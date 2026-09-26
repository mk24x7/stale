import Foundation

/// Parsed `git status --porcelain=v2 --branch` output.
public struct StatusSummary: Equatable, Sendable {
    public var branchHead: String?
    public var headUnborn = false
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var changedFiles = 0
    public var staged = 0
    public var unstaged = 0
    public var conflicted = 0
    public var untracked = 0

    public init() {}
}

public enum GitParsers {
    /// Parse porcelain v2 status. Lines:
    ///   # branch.oid <sha> | (initial)
    ///   # branch.head <name> | (detached)
    ///   # branch.upstream <upstream>
    ///   # branch.ab +<ahead> -<behind>
    ///   1 XY ...   ordinary change
    ///   2 XY ...   rename or copy
    ///   u XY ...   unmerged
    ///   ? <path>   untracked
    ///   ! <path>   ignored (not requested)
    /// X is the index (staged) state, Y the worktree state; "." means unchanged.
    public static func parseStatus(_ text: String) -> StatusSummary {
        var summary = StatusSummary()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = Substring(rawLine)
            if line.hasPrefix("# ") {
                let parts = line.dropFirst(2).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let value = String(parts[1])
                switch parts[0] {
                case "branch.oid":
                    summary.headUnborn = value == "(initial)"
                case "branch.head":
                    summary.branchHead = value == "(detached)" ? RepoState.detachedName : value
                case "branch.upstream":
                    summary.upstream = value
                case "branch.ab":
                    for token in value.split(separator: " ") {
                        if token.hasPrefix("+") { summary.ahead = Int(token.dropFirst()) ?? 0 }
                        if token.hasPrefix("-") { summary.behind = Int(token.dropFirst()) ?? 0 }
                    }
                default:
                    break
                }
                continue
            }
            guard let tag = line.first else { continue }
            switch tag {
            case "1", "2":
                let xy = line.dropFirst(2).prefix(2)
                guard xy.count == 2 else { continue }
                summary.changedFiles += 1
                if xy.first != "." { summary.staged += 1 }
                if xy.last != "." { summary.unstaged += 1 }
            case "u":
                summary.changedFiles += 1
                summary.conflicted += 1
            case "?":
                summary.untracked += 1
            default:
                break
            }
        }
        return summary
    }

    /// Format string passed to `git for-each-ref`. Tab separated:
    /// short branch name, full upstream ref, upstream track, committer date.
    /// The full upstream ref (rather than `upstream:short`) distinguishes a
    /// remote-tracking upstream from a local branch used as upstream.
    public static let refFormat = "%(refname:short)%09%(upstream)%09%(upstream:track)%09%(committerdate:iso8601-strict)"

    /// Parse one `for-each-ref` line produced with `refFormat`.
    public static func parseRefLine(_ line: String) -> BranchState? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 4, !fields[0].isEmpty else { return nil }
        let track = parseTrack(fields[2])
        return BranchState(
            name: fields[0],
            upstreamRef: fields[1].isEmpty ? nil : fields[1],
            ahead: track.ahead,
            behind: track.behind,
            upstreamGone: track.gone,
            committerDate: parseDate(fields[3])
        )
    }

    /// Parse `%(upstream:track)`: "", "[ahead 2]", "[behind 1]",
    /// "[ahead 2, behind 1]" or "[gone]".
    public static func parseTrack(_ text: String) -> (ahead: Int, behind: Int, gone: Bool) {
        let inner = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        if inner == "gone" { return (0, 0, true) }
        var ahead = 0
        var behind = 0
        for part in inner.split(separator: ",") {
            let words = part.split(separator: " ")
            guard words.count == 2, let n = Int(words[1]) else { continue }
            if words[0] == "ahead" { ahead = n }
            if words[0] == "behind" { behind = n }
        }
        return (ahead, behind, false)
    }

    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }
}
