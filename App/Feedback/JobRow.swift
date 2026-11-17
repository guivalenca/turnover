import SwiftUI
import TurnoverKit

/// One conversion in the menu bar item's menu: the file, how far along it is, and a ✕ that stops
/// it. The row stays put while the menu is open and shows how the job ended.
struct JobRow: View {
    let job: Job

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.source.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(status)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                // A stopped or failed job's bar stays where it got to, greyed.
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(job.isFinished && job.result == nil ? .secondary : .accentColor)
            }
            Button {
                job.cancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Stop converting \(job.source.lastPathComponent)")
            .accessibilityLabel("Stop converting \(job.source.lastPathComponent)")
            .opacity(job.isFinished ? 0 : 1)
            .disabled(job.isFinished)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(width: 280)
    }

    private var status: String {
        switch job.state {
        case .waiting: "Waiting"
        case .running: percent(job.progress)
        case .converted: "Done"
        case .cancelled: "Stopped"
        case .failed: "Failed"
        case .skipped: "Skipped"
        }
    }
}

/// "42%", rounded down so that 100% means done.
func percent(_ fraction: Double) -> String {
    ((fraction * 100).rounded(.down) / 100).formatted(.percent.precision(.fractionLength(0)))
}
