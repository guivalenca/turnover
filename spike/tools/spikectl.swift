// spikectl: test driver for the spike. Run it from a shell that is trusted for Accessibility and
// event posting (NOT from the spike app). It finds Finder items with the AX API and plays short
// bursts of synthesized input.
//
//   spikectl find <name> [windowTitle]        centre + frame of Finder elements named <name>
//   spikectl at <x> <y>                       AX element (and ancestors) at a screen point
//   spikectl selected [windowTitle]           names of selected items in a Finder window
//   spikectl window <title> <x> <y> <w> <h>   move/resize a Finder window and bring it to front
//   spikectl menus                            items of Finder's open (context) menus
//   spikectl dump [windowTitle] [depth]       AX tree, for debugging
//   spikectl mouse                            current cursor position
//   spikectl run <step>...                    synthesized input; steps:
//       expect:x,y,text   abort unless the AX element at x,y (or an ancestor) mentions text
//       move:x,y[,n,ms]   down:x,y   drag:x,y[,n,ms]   up   click:x,y   rclick:x,y
//       shift:down|up     key:esc|down|up|left|right|return    sleep:ms   shot:path   log:text
// Screen coordinates are global, origin top-left (CGEvent and AX use the same space).

import AppKit
import ApplicationServices
import CoreGraphics

setvbuf(stdout, nil, _IOLBF, 0)

// MARK: - AX helpers

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}

func string(_ e: AXUIElement, _ name: String) -> String? {
    if let s = attr(e, name) as? String { return s }
    if let u = attr(e, name) as? URL { return u.path }
    return nil
}

func frame(_ e: AXUIElement) -> CGRect? {
    guard let p = attr(e, kAXPositionAttribute), let s = attr(e, kAXSizeAttribute) else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &point)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: point, size: size)
}

func children(_ e: AXUIElement) -> [AXUIElement] {
    (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func names(_ e: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, "AXFilename", kAXIdentifierAttribute]
        .compactMap { string(e, $0) }.filter { !$0.isEmpty }
}

func describe(_ e: AXUIElement) -> String {
    let role = string(e, kAXRoleAttribute) ?? "?"
    let f = frame(e).map { "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))" } ?? ""
    return "\(role) \(names(e)) \(f)"
}

func finder() -> AXUIElement {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
        fail("Finder is not running")
    }
    return AXUIElementCreateApplication(app.processIdentifier)
}

func windows(_ title: String?) -> [AXUIElement] {
    let all = (attr(finder(), kAXWindowsAttribute) as? [AXUIElement]) ?? []
    guard let title else { return all }
    return all.filter { string($0, kAXTitleAttribute) == title }
}

func walk(_ e: AXUIElement, depth: Int = 0, max: Int = 30, _ visit: (AXUIElement, Int) -> Void) {
    visit(e, depth)
    guard depth < max else { return }
    for c in children(e) { walk(c, depth: depth + 1, max: max, visit) }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

func elementAt(_ x: Double, _ y: Double) -> AXUIElement? {
    var element: AXUIElement?
    let r = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(x), Float(y), &element)
    return r == .success ? element : nil
}

func ancestry(_ e: AXUIElement, levels: Int = 4) -> [AXUIElement] {
    var out = [e]
    var current = e
    for _ in 0..<levels {
        guard let p = attr(current, kAXParentAttribute) else { break }
        current = p as! AXUIElement
        out.append(current)
    }
    return out
}

// MARK: - Input synthesis

let source = CGEventSource(stateID: .hidSystemState)!
var flags: CGEventFlags = []
var position = CGEvent(source: nil)!.location

func post(_ e: CGEvent) {
    e.post(tap: .cghidEventTap)
    usleep(2_000)
}

func mouse(_ type: CGEventType, _ p: CGPoint, button: CGMouseButton = .left) {
    let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button)!
    e.flags = flags
    e.setIntegerValueField(.mouseEventClickState, value: 1)
    post(e)
    position = p
}

func glide(_ type: CGEventType, to target: CGPoint, steps: Int, ms: Int) {
    let start = position
    for i in 1...max(steps, 1) {
        let t = Double(i) / Double(max(steps, 1))
        mouse(type, CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t))
        usleep(useconds_t(ms * 1000 / max(steps, 1)))
    }
}

func key(_ code: CGKeyCode, down: Bool) {
    let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
    e.flags = flags
    post(e)
}

let keyCodes: [String: CGKeyCode] = ["esc": 53, "down": 125, "up": 126, "left": 123, "right": 124, "return": 36]

func stamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

func numbers(_ s: Substring) -> [Double] { s.split(separator: ",").compactMap { Double($0) } }

/// If the real cursor is not where we last put it, a human is using the mouse: cancel and stop.
func abortIfUserMoved() {
    var now = CGEvent(source: nil)!.location
    // Posted events reach the window server asynchronously: allow ~150 ms for the cursor to catch up.
    for _ in 0..<10 where hypot(now.x - position.x, now.y - position.y) > 3 {
        usleep(15_000)
        now = CGEvent(source: nil)!.location
    }
    guard hypot(now.x - position.x, now.y - position.y) > 3 else { return }
    print("\(stamp()) ABORT: cursor moved by someone else (\(now) vs \(position)); cancelling")
    key(53, down: true); key(53, down: false)            // Esc cancels any drag in progress
    let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: now, mouseButton: .left)!
    up.post(tap: .cghidEventTap)
    if flags.contains(.maskShift) { flags.remove(.maskShift); key(56, down: false) }
    exit(3)
}

func run(_ steps: [String]) {
    var started = false
    for step in steps {
        if started { abortIfUserMoved() }
        if step.hasPrefix("down:") || step.hasPrefix("click:") || step.hasPrefix("rclick:") || step.hasPrefix("move:") { started = true }
        let parts = step.split(separator: ":", maxSplits: 1)
        let verb = String(parts[0])
        let arg = parts.count > 1 ? parts[1] : ""
        print("\(stamp()) \(step)")
        switch verb {
        case "expect":
            let bits = arg.split(separator: ",", maxSplits: 2)
            let x = Double(bits[0])!, y = Double(bits[1])!, text = String(bits[2])
            guard let e = elementAt(x, y) else { fail("expect: nothing at \(x),\(y)") }
            let chain = ancestry(e, levels: 10)
            guard chain.contains(where: { names($0).contains { $0.contains(text) } }) else {
                fail("expect: \(text) not at \(x),\(y): \(chain.map(describe))")
            }
        case "move":
            let n = numbers(arg)
            glide(.mouseMoved, to: CGPoint(x: n[0], y: n[1]), steps: n.count > 2 ? Int(n[2]) : 1, ms: n.count > 3 ? Int(n[3]) : 0)
        case "down":
            let n = numbers(arg)
            mouse(.leftMouseDown, CGPoint(x: n[0], y: n[1]))
        case "drag":
            let n = numbers(arg)
            glide(.leftMouseDragged, to: CGPoint(x: n[0], y: n[1]), steps: n.count > 2 ? Int(n[2]) : 10, ms: n.count > 3 ? Int(n[3]) : 150)
        case "up":
            mouse(.leftMouseUp, position)
        case "click":
            let n = numbers(arg)
            mouse(.leftMouseDown, CGPoint(x: n[0], y: n[1]))
            usleep(40_000)
            mouse(.leftMouseUp, CGPoint(x: n[0], y: n[1]))
        case "rclick":
            let n = numbers(arg)
            mouse(.rightMouseDown, CGPoint(x: n[0], y: n[1]), button: .right)
            usleep(40_000)
            mouse(.rightMouseUp, CGPoint(x: n[0], y: n[1]), button: .right)
        case "shift":
            if arg == "down" { flags.insert(.maskShift); key(56, down: true) } else { flags.remove(.maskShift); key(56, down: false) }
        case "key":
            guard let code = keyCodes[String(arg)] else { fail("unknown key \(arg)") }
            key(code, down: true)
            usleep(30_000)
            key(code, down: false)
        case "sleep":
            usleep(useconds_t(Int(arg)! * 1000))
        case "shot":
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", String(arg)]
            try! p.run()
            p.waitUntilExit()
        case "log":
            break
        default:
            fail("unknown step \(step)")
        }
    }
}

// MARK: - Commands

let args = Array(CommandLine.arguments.dropFirst())
guard AXIsProcessTrusted() else { fail("this process is not trusted for Accessibility") }

switch args.first {
case "find":
    let name = args[1]
    for w in windows(args.count > 2 ? args[2] : nil) {
        walk(w) { e, _ in
            guard names(e).contains(name), let f = frame(e), f.width > 0 else { return }
            print("\(Int(f.midX)) \(Int(f.midY)) \(string(e, kAXRoleAttribute) ?? "?") \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))")
        }
    }
case "at":
    guard let e = elementAt(Double(args[1])!, Double(args[2])!) else { fail("nothing there") }
    for a in ancestry(e, levels: 6) { print(describe(a)) }
case "selected":
    for w in windows(args.count > 1 ? args[1] : nil) {
        walk(w) { e, _ in
            if let rows = attr(e, kAXSelectedRowsAttribute) as? [AXUIElement], !rows.isEmpty {
                for r in rows {
                    var label: [String] = []
                    walk(r, max: 3) { c, _ in label += names(c) }
                    print("row: \(label.joined(separator: " | "))")
                }
            }
            if let kids = attr(e, kAXSelectedChildrenAttribute) as? [AXUIElement], !kids.isEmpty {
                for k in kids { print("child: \(names(k).first ?? describe(k))") }
            }
        }
    }
case "window":
    guard let w = windows(args[1]).first else { fail("no window titled \(args[1])") }
    var p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    var s = CGSize(width: Double(args[4])!, height: Double(args[5])!)
    AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(finder(), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    print(describe(w))
case "menus":
    walk(finder(), max: 12) { e, depth in
        let role = string(e, kAXRoleAttribute)
        if role == kAXMenuItemRole || role == kAXMenuRole {
            let enabled = (attr(e, kAXEnabledAttribute) as? Bool) ?? false
            let f = frame(e).map { "\(Int($0.midX)) \(Int($0.midY))" } ?? "-"
            print("\(String(repeating: "  ", count: depth))\(role!) \"\(string(e, kAXTitleAttribute) ?? "")\" centre=\(f) enabled=\(enabled)")
        }
    }
case "dump":
    let depth = args.count > 2 ? Int(args[2])! : 8
    for w in windows(args.count > 1 ? args[1] : nil) {
        walk(w, max: depth) { e, d in print(String(repeating: "  ", count: d) + describe(e)) }
    }
case "mouse":
    let p = CGEvent(source: nil)!.location
    print("\(Int(p.x)) \(Int(p.y))")
case "front":
    print(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
case "activate":
    // Give focus back to the app the human was using (AX works under cooperative activation).
    AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid_t(args[1])!), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
case "run":
    run(Array(args.dropFirst()))
default:
    fail("usage: see the header of spikectl.swift")
}
