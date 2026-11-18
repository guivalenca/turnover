import Foundation
import Testing
import TurnoverAppCore

/// Where an image dragged out of a web page is saved, by what the ring was dropped over: the
/// Desktop, a Finder window's folder, or Downloads, copied too when that is another app.
@Suite struct SaveDestinationTests {
    let levels = DragSource.Levels(normal: 0, dragging: 500)
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let browser: Int32 = 501, chat: Int32 = 502, finder: Int32 = 400, dock: Int32 = 300
    let drop = CGPoint(x: 1500, y: 300)

    /// What `CGWindowListCopyWindowInfo` lists over the Desktop: the wallpaper's windows, far
    /// below the normal level.
    var wallpaper: [DragSource.Window] {
        [.init(isFinder: false, layer: -2_147_483_622, frame: screen, owner: dock),
         .init(isFinder: false, layer: -2_147_483_626, frame: screen, owner: dock)]
    }
    var browserWindow: DragSource.Window { .init(isFinder: false, layer: 0, frame: CGRect(x: 40, y: 60, width: 900, height: 700), owner: browser) }

    func destination(at point: CGPoint, over windows: [DragSource.Window], from source: Int32? = 501) -> SaveDestination {
        SaveDestination(droppedAt: point, draggedFrom: source, windows: windows + wallpaper, levels: levels, screens: [screen])
    }

    @Test func overTheBareDesktopItLandsWhereItWasDropped() {
        #expect(destination(at: drop, over: [browserWindow]) == .desktop(drop: drop))
    }

    /// Where Finder's window of Desktop icons is listed, it is the Desktop too.
    @Test func findersDesktopIconsAreTheDesktop() {
        let icons = DragSource.Window(isFinder: true, layer: -2_147_483_603, frame: screen, owner: finder)

        #expect(destination(at: drop, over: [browserWindow, icons]) == .desktop(drop: drop))
    }

    @Test func overAFinderWindowItGoesToThatWindowsFolder() {
        let folder = DragSource.Window(isFinder: true, layer: 0, frame: CGRect(x: 1000, y: 100, width: 600, height: 400), owner: finder)

        #expect(destination(at: drop, over: [browserWindow, folder]) == .finderWindow(drop: drop, frame: folder.frame))
    }

    @Test func overTheBrowserItCameFromItIsOnlySavedToDownloads() {
        #expect(destination(at: CGPoint(x: 400, y: 400), over: [browserWindow]) == .downloads(copied: false))
    }

    @Test func overAnotherAppItIsSavedToDownloadsAndCopied() {
        let chatWindow = DragSource.Window(isFinder: false, layer: 0, frame: CGRect(x: 1100, y: 200, width: 500, height: 500), owner: chat)

        #expect(destination(at: drop, over: [chatWindow, browserWindow]) == .downloads(copied: true))
    }

    @Test func theFrontmostWindowUnderTheDropDecides() {
        let chatWindow = DragSource.Window(isFinder: false, layer: 0, frame: CGRect(x: 300, y: 300, width: 500, height: 300), owner: chat)
        let point = CGPoint(x: 400, y: 400)

        #expect(destination(at: point, over: [chatWindow, browserWindow]) == .downloads(copied: true))
        #expect(destination(at: point, over: [browserWindow, chatWindow]) == .downloads(copied: false))
    }

    /// The Dock and the menu bar are above the normal level: nothing pastes there.
    @Test func overTheDockOrTheMenuBarItIsOnlySavedToDownloads() {
        let dockBar = DragSource.Window(isFinder: false, layer: 20, frame: CGRect(x: 400, y: 1040, width: 900, height: 77), owner: dock)
        let menuBar = DragSource.Window(isFinder: false, layer: 24, frame: CGRect(x: 0, y: 0, width: 1728, height: 33), owner: 200)

        #expect(destination(at: CGPoint(x: 800, y: 1080), over: [dockBar, menuBar]) == .downloads(copied: false))
        #expect(destination(at: CGPoint(x: 800, y: 10), over: [dockBar, menuBar]) == .downloads(copied: false))
    }

    /// The drag image and the Dock's full-screen overlay during a drag are seen through.
    @Test func theDragImageAndFullScreenOverlaysAreSeenThrough() {
        let dragImage = DragSource.Window(isFinder: false, layer: 500, frame: CGRect(x: 1450, y: 250, width: 100, height: 100), owner: browser)
        let overlay = DragSource.Window(isFinder: false, layer: 20, frame: screen, owner: dock)

        #expect(destination(at: drop, over: [dragImage, overlay, browserWindow]) == .desktop(drop: drop))
    }

    @Test func whenWhereItCameFromIsUnknownAnyAppIsAnotherApp() {
        #expect(destination(at: CGPoint(x: 400, y: 400), over: [browserWindow], from: nil) == .downloads(copied: true))
    }
}
