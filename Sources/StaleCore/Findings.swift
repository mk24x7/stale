import Foundation

/// Turns raw repository state into findings. Pure, so it is tested without git.
public enum FindingDeriver {
    public static func findings(for state: RepoState) -> [Finding] {
        var findings: [Finding] = []

        if state.remotes.isEmpty {
            if state.localOnlyCommits > 0 {
                findings.append(Finding(
                    kind: .noRemote,
                    count: state.localOnlyCommits,
                    summary: "no remote (\(PathFormat.plural(state.localOnlyCommits, "commit")))"
                ))
            }
        } else {
            let unpushed = state.branches
                .filter { $0.hasRemoteUpstream && $0.ahead > 0 }
                .map { BranchFinding(name: $0.name, commits: $0.ahead, upstream: $0.upstreamShort) }
            if !unpushed.isEmpty {
                let total = unpushed.reduce(0) { $0 + $1.commits }
                let summary = unpushed.count == 1
                    ? "\(PathFormat.plural(total, "unpushed commit")) on \(unpushed[0].name)"
                    : "\(PathFormat.plural(total, "unpushed commit")) on \(unpushed.count) branches"
                findings.append(Finding(kind: .unpushed, count: total, branches: unpushed, summary: summary))
            }

            var orphaned = state.branches
                .filter { !$0.hasRemoteUpstream && ($0.uniqueCommits ?? 0) > 0 }
                .map {
                    BranchFinding(name: $0.name, commits: $0.uniqueCommits ?? 0,
                                  upstream: $0.upstreamShort, upstreamGone: $0.upstreamGone)
                }
            if state.detachedCommits > 0 {
                orphaned.append(BranchFinding(name: RepoState.detachedName, commits: state.detachedCommits))
            }
            if !orphaned.isEmpty {
                let total = orphaned.reduce(0) { $0 + $1.commits }
                let summary: String
                if orphaned.count == 1 {
                    let branch = orphaned[0]
                    let why = branch.upstreamGone ? "upstream gone" : "no upstream"
                    summary = "\(branch.name): \(PathFormat.plural(total, "commit")) with \(why)"
                } else {
                    summary = "\(orphaned.count) branches without upstream (\(PathFormat.plural(total, "commit")))"
                }
                findings.append(Finding(kind: .noUpstream, count: total, branches: orphaned, summary: summary))
            }
        }

        if state.changedFiles > 0 {
            var summary = "\(state.changedFiles) uncommitted"
            var extras: [String] = []
            if state.staged > 0 { extras.append("\(state.staged) staged") }
            if state.conflicted > 0 { extras.append("\(state.conflicted) conflicted") }
            if !extras.isEmpty { summary += " (" + extras.joined(separator: ", ") + ")" }
            findings.append(Finding(kind: .uncommitted, count: state.changedFiles, summary: summary))
        }

        if state.stashes > 0 {
            findings.append(Finding(kind: .stash, count: state.stashes,
                                    summary: PathFormat.plural(state.stashes, "stash", "stashes")))
        }

        if state.untracked > 0 {
            findings.append(Finding(kind: .untracked, count: state.untracked,
                                    summary: "\(state.untracked) untracked"))
        }

        return findings.sorted { $0.kind.weight > $1.kind.weight }
    }

    /// Finding for a repository git could not read.
    public static func unreadable(_ reason: String) -> Finding {
        Finding(kind: .unreadable, count: 0, summary: "unreadable: \(reason)")
    }

    /// Findings that describe refs (branches, stashes, remotes) and therefore
    /// belong to the main repository rather than to each linked worktree.
    public static let refKinds: Set<FindingKind> = [.noRemote, .unpushed, .noUpstream, .stash]
}
