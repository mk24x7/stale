import SwiftUI
import StaleCore

struct ScanningView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if let progress = state.inspectProgress, progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(maxWidth: 300)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .scaleEffect(1.5)
            }

            VStack(spacing: 6) {
                if let progress = state.inspectProgress {
                    Text("Inspecting repositories...")
                        .font(.headline)
                    Text("\(progress.completed) / \(progress.total)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Looking for repositories...")
                        .font(.headline)
                    Text(state.scanProgress)
                        .font(.caption)
                        .foregroundColor(Theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320)
                    Text("Found \(state.foundCount) \(state.foundCount == 1 ? "repository" : "repositories")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button("Cancel") {
                state.cancelScan()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
