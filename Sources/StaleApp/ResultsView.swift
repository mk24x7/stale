import SwiftUI
import StaleCore

struct ResultsView: View {
    @EnvironmentObject var state: AppState
    @State private var showClean = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if state.atRisk.isEmpty {
                allClearView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(state.groups, id: \.risk) { group in
                            Section {
                                ForEach(group.reports) { report in
                                    RepoRowView(report: report)
                                    Divider().padding(.leading, 14)
                                }
                            } header: {
                                RiskHeader(risk: group.risk, count: group.reports.count)
                            }
                        }
                        if !state.clean.isEmpty {
                            cleanSection
                        }
                    }
                }
            }

            Divider()

            if let result = state.result, result.deniedCount > 0 {
                DeniedNotice(count: result.deniedCount, examples: result.deniedDirectories)
                Divider()
            }

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.atRisk.isEmpty ? "Nothing at risk" : "\(state.atRisk.count) \(state.atRisk.count == 1 ? "repository has" : "repositories have") work that exists only on this Mac")
                    .font(.system(size: 13, weight: .semibold))
                Text(state.scanRootDisplay)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            ForEach(state.groups, id: \.risk) { group in
                CountPill(text: "\(group.reports.count) \(Theme.title(for: group.risk).lowercased())",
                          color: Theme.color(for: group.risk))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var allClearView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 36))
                .foregroundColor(Theme.color(for: .none))
            Text("Every repository found is committed and pushed")
                .font(.headline)
            Text("\(state.clean.count) \(state.clean.count == 1 ? "repository" : "repositories") checked")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var cleanSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { showClean.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: showClean ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("\(state.clean.count) clean \(state.clean.count == 1 ? "repository" : "repositories")")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(Theme.tertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showClean {
                ForEach(state.clean) { report in
                    HStack {
                        Text(report.name)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(PathFormat.shorten(report.path.path, home: state.home.path))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 3)
                }
                Spacer().frame(height: 8)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let result = state.result {
                Text(TextReport.footer(result, shown: result.atRisk.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("v\(AppVersion.short)")
                .font(.system(size: 9))
                .foregroundColor(Theme.tertiary)
            Button("New Scan") { state.reset() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(action: { state.copyReport() }) {
                Text(state.copiedAt == nil ? "Copy Report" : "Copied")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Copy a plain-text summary to the clipboard")
            Button("Rescan") { state.rescan() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)
                .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

struct RiskHeader: View {
    let risk: Risk
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.color(for: risk))
                .frame(width: 7, height: 7)
            Text(Theme.title(for: risk))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Theme.color(for: risk))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            Text(Theme.explanation(for: risk))
                .font(.system(size: 10))
                .foregroundColor(Theme.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.background.opacity(0.96))
    }
}

struct RepoRowView: View {
    @EnvironmentObject var state: AppState
    let report: RepoReport
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(report.name)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)
                    if let branch = report.branch {
                        Text(branch)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(3)
                            .lineLimit(1)
                    } else if report.state.isBare {
                        Text("bare")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if report.state.isWorktree {
                        Text("worktree")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.tertiary)
                    }
                }
                Text(PathFormat.shorten(report.path.path, home: state.home.path))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                FlowBadges(findings: report.findings)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let date = report.lastActivity {
                    Text(PathFormat.age(date))
                        .font(.system(size: 10))
                        .foregroundColor(Theme.tertiary)
                        .help("Most recent commit on any local branch")
                }
                HStack(spacing: 6) {
                    Button(action: { state.reveal(report) }) {
                        Label("Finder", systemImage: "folder")
                    }
                    .help("Reveal in Finder")
                    Button(action: { state.openInTerminal(report) }) {
                        Label("Terminal", systemImage: "terminal")
                    }
                    .help("Open in Terminal")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(hovering ? Color.white.opacity(0.03) : Color.clear)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Reveal in Finder") { state.reveal(report) }
            Button("Open in Terminal") { state.openInTerminal(report) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report.path.path, forType: .string)
            }
        }
    }
}

/// Finding badges, wrapping onto a second line when the row is narrow.
struct FlowBadges: View {
    let findings: [Finding]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) { badges }
            VStack(alignment: .leading, spacing: 4) { badges }
        }
    }

    @ViewBuilder private var badges: some View {
        ForEach(findings, id: \.kind) { finding in
            FindingBadge(finding: finding)
        }
    }
}

struct FindingBadge: View {
    let finding: Finding

    private var color: Color { Theme.color(for: finding.risk) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: Theme.icon(for: finding.kind))
                .font(.system(size: 9, weight: .semibold))
            Text(finding.summary)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .cornerRadius(4)
        .help(detail)
    }

    private var detail: String {
        guard !finding.branches.isEmpty else { return finding.summary }
        return finding.branches.map { branch in
            var line = "\(branch.name): \(branch.commits) \(branch.commits == 1 ? "commit" : "commits")"
            if let upstream = branch.upstream { line += " vs \(upstream)" }
            if branch.upstreamGone { line += " (upstream gone)" }
            return line
        }.joined(separator: "\n")
    }
}

struct CountPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(8)
    }
}

/// Shown when the scan hit folders it was not allowed to read.
struct DeniedNotice: View {
    let count: Int
    let examples: [URL]

    static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            Text("\(count) \(count == 1 ? "folder" : "folders") could not be read")
                .font(.caption)
                .foregroundColor(.secondary)
                .help(examples.prefix(10).map { PathFormat.shorten($0.path) }.joined(separator: "\n"))
            Spacer()
            Button("Open Privacy Settings") {
                NSWorkspace.shared.open(Self.privacySettingsURL)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}
