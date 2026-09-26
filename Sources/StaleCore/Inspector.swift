import Foundation

/// Reads one repository with read-only git commands and builds its report.
public struct RepoInspector: Sendable {
    public let git: GitRunner

    public init(git: GitRunner = GitRunner()) {
        self.git = git
    }

    public func inspect(_ candidate: RepoCandidate) async throws -> RepoReport {
        let url = candidate.url
        do {
            let state = try await readState(url)
            let findings = FindingDeriver.findings(for: state)
            let lastActivity = state.branches.compactMap(\.committerDate).max()
            return RepoReport(path: url, branch: state.currentBranch, findings: findings,
                              lastActivity: lastActivity, state: state)
        } catch let failure as InspectionFailure {
            var state = RepoState()
            state.isBare = candidate.layout == .bare
            return RepoReport(path: url, branch: nil, findings: [FindingDeriver.unreadable(failure.reason)],
                              lastActivity: nil, state: state, error: failure.reason)
        }
    }

    struct InspectionFailure: Error {
        let reason: String
    }

    private func required(_ arguments: [String], in url: URL) async throws -> GitOutput {
        let output = try await git.run(arguments, in: url)
        if output.timedOut {
            let name = arguments.first ?? "git"
            throw InspectionFailure(reason: "git \(name) timed out after \(Int(git.timeout)) s")
        }
        guard output.status == 0 else { throw InspectionFailure(reason: Self.clean(output.errorLine)) }
        return output
    }

    func readState(_ url: URL) async throws -> RepoState {
        var state = RepoState()

        // Validates the repository and tells bare from linked worktree.
        let probe = try await required(
            ["rev-parse", "--is-bare-repository", "--absolute-git-dir", "--git-common-dir"], in: url)
        let probeLines = probe.lines
        guard probeLines.count >= 3 else {
            throw InspectionFailure(reason: "unexpected git rev-parse output")
        }
        state.isBare = probeLines[0] == "true"
        let gitDir = Self.resolve(probeLines[1], relativeTo: url)
        let commonDir = Self.resolve(probeLines[2], relativeTo: url)
        if !state.isBare && gitDir != commonDir {
            state.isWorktree = true
            let common = URL(fileURLWithPath: commonDir)
            if common.lastPathComponent == ".git" {
                state.mainWorktreePath = common.deletingLastPathComponent().path
            }
        }

        if !state.isBare {
            let status = try await required(["status", "--porcelain=v2", "--branch", "--untracked-files=normal"], in: url)
            let parsed = GitParsers.parseStatus(status.stdout)
            state.currentBranch = parsed.branchHead
            state.headUnborn = parsed.headUnborn
            state.changedFiles = parsed.changedFiles
            state.staged = parsed.staged
            state.unstaged = parsed.unstaged
            state.conflicted = parsed.conflicted
            state.untracked = parsed.untracked
        }

        let refs = try await required(["for-each-ref", "--format=\(GitParsers.refFormat)", "refs/heads"], in: url)
        state.branches = refs.lines.compactMap(GitParsers.parseRefLine)

        if !state.isBare {
            let stash = try await required(["stash", "list", "--format=%gd"], in: url)
            state.stashes = stash.lines.count
        }

        let remotes = try await required(["remote"], in: url)
        state.remotes = remotes.lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let detached = state.currentBranch == RepoState.detachedName && !state.headUnborn
        if state.remotes.isEmpty {
            if !state.branches.isEmpty || detached {
                var args = ["rev-list", "--count", "--branches"]
                if detached { args.append("HEAD") }
                let count = try await required(args, in: url)
                state.localOnlyCommits = Int(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }
        } else {
            if detached {
                // Commits made on a detached HEAD that no branch or remote holds.
                let count = try await required(["rev-list", "--count", "HEAD", "--not", "--branches", "--remotes"], in: url)
                state.detachedCommits = Int(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }
            // A branch without a usable upstream only matters if it holds
            // commits that no remote-tracking branch has.
            for index in state.branches.indices where !state.branches[index].hasRemoteUpstream {
                try Task.checkCancellation()
                let ref = "refs/heads/" + state.branches[index].name
                let count = try await required(["rev-list", "--count", ref, "--not", "--remotes"], in: url)
                state.branches[index].uniqueCommits =
                    Int(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            }
        }
        return state
    }

    static func resolve(_ path: String, relativeTo base: URL) -> String {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
        return PathFormat.canonical(url.path)
    }

    /// Strip git's "fatal: " prefix for display.
    static func clean(_ line: String) -> String {
        for prefix in ["fatal: ", "error: "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return line
    }
}
