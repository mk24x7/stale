import SwiftUI
import StaleCore

struct LandingView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer().frame(height: 24)

                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(Theme.accent)

                VStack(spacing: 4) {
                    Text("Stale")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Find the git work on your Mac that exists nowhere else")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Folder to scan")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: browse) {
                        HStack {
                            Text(state.scanRootDisplay)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Toggle("Include nested repos", isOn: $state.includeNested)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .help("Also report repositories that live inside another repository's working tree")
                }
                .frame(maxWidth: 480)

                Divider().frame(maxWidth: 480)

                VStack(alignment: .leading, spacing: 8) {
                    Text("WHAT IT LOOKS FOR")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.tertiary)
                    ForEach(Self.kinds, id: \.kind) { item in
                        HStack(spacing: 8) {
                            Image(systemName: Theme.icon(for: item.kind))
                                .font(.system(size: 11))
                                .foregroundColor(Theme.color(for: item.kind.risk))
                                .frame(width: 16)
                            Text(item.text)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    Text("Read-only: Stale only runs git status, for-each-ref, stash list, remote and rev-list. It never commits, pushes, fetches or deletes anything.")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .frame(maxWidth: 480, alignment: .leading)

                Button(action: { state.startScan() }) {
                    Text("Scan")
                        .frame(maxWidth: 280)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.return, modifiers: [])

                Text("v\(AppVersion.short)")
                    .font(.system(size: 9))
                    .foregroundColor(Theme.tertiary)

                Spacer().frame(height: 8)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let kinds: [(kind: FindingKind, text: String)] = [
        (.noRemote, "Repositories with commits but no remote"),
        (.unpushed, "Branches ahead of their upstream"),
        (.noUpstream, "Branches with no upstream holding commits no remote has"),
        (.uncommitted, "Modified, staged or conflicted files"),
        (.stash, "Stash entries"),
        (.untracked, "Untracked files that are not ignored"),
    ]

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = state.scanRoot
        panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            state.setScanRoot(url)
        }
    }
}
