import AppKit
import SwiftUI
import TurnoverKit

/// The Turnover window: what Turnover does, the setup checklist, the two settings, and Quit.
struct TurnoverView: View {
    @Bindable var model: WindowModel

    var body: some View {
        Form {
            Section {
                Header()
            }

            Section("Setup") {
                SetupRow(
                    "Finder extension", detail: "Adds Turnover to the right-click menu",
                    status: model.finderExtensionIsOn ? "On" : nil,
                    button: "Open Settings…", action: { model.openFinderExtensionSettings() })
                SetupRow(
                    "Notifications", detail: "Tells you when longer conversions finish",
                    status: model.notifications == .allowed ? "Allowed" : nil,
                    button: model.notifications == .notAsked ? "Allow…" : "Open Settings…",
                    action: { model.turnOnNotifications() })
                .disabled(model.notifications == nil)
            }

            Section("Settings") {
                Picker(selection: $model.jpegQuality) {
                    ForEach(JPEGQuality.allCases, id: \.self) { quality in
                        Text("\(quality.name) (\(quality.percent)%)").tag(quality)
                    }
                } label: {
                    Text("JPEG quality")
                    Text("Hold ⌥ over the ring to choose just once")
                }
                // A label with a second line doesn't reach Accessibility by itself.
                .accessibilityLabel("JPEG quality")
                Toggle(isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) })) {
                    Text("Open at login")
                    Text("Turnover needs to be running to show the ring")
                }
                .accessibilityLabel("Open at login")
            }

            Section {
            } footer: {
                Footer()
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Header: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("Turnover")
                .font(.title2.weight(.semibold))
            Text("Drag a file, press ⇧, choose a format.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// One setup step: a checkmark and what it's for, then "On" once done, or a button that leads
/// to the setting.
private struct SetupRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    /// Shown, with a checkmark, once the step is done.
    let status: LocalizedStringKey?
    let button: LocalizedStringKey
    let action: () -> Void

    init(
        _ title: LocalizedStringKey, detail: LocalizedStringKey, status: LocalizedStringKey?,
        button: LocalizedStringKey, action: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.status = status
        self.button = button
        self.action = action
    }

    var body: some View {
        LabeledContent {
            if let status {
                Text(status)
            } else {
                Button(button, action: action)
            }
        } label: {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                Image(systemName: status == nil ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(status == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.green))
                    .imageScale(.large)
                    // The row already says "On" or offers its button.
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct Footer: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        HStack {
            Text("Version \(version) · MIT License")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit Turnover") { NSApp.terminate(nil) }
        }
    }
}
