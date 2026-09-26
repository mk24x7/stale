import Foundation

// MARK: - Risk

/// How much would be lost if the disk died. Ordered: none < low < medium < high.
public enum Risk: Int, Comparable, CaseIterable, Codable, Sendable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    public static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Lowercase name used in JSON and on the command line.
    public var name: String {
        switch self {
        case .none: return "none"
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }

    public init?(name: String) {
        guard let match = Risk.allCases.first(where: { $0.name == name.lowercased() }) else { return nil }
        self = match
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Risk(name: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown risk \(raw)"))
        }
        self = value
    }
}

// MARK: - Findings

/// One kind of work that exists only on this disk.
public enum FindingKind: String, CaseIterable, Codable, Sendable {
    /// The repository has commits but no remote at all.
    case noRemote = "noremote"
    /// A branch is ahead of its upstream.
    case unpushed
    /// A branch has no upstream (or its upstream is gone) and holds commits
    /// that no remote-tracking branch contains.
    case noUpstream = "noupstream"
    /// Modified, staged, deleted, renamed or conflicted tracked files.
    case uncommitted
    /// Files git does not track and does not ignore.
    case untracked
    /// Entries in `git stash list`.
    case stash
    /// git could not read the repository (corrupt, dangling .git file, timeout).
    case unreadable

    /// Risk carried by this kind of finding.
    public var risk: Risk {
        switch self {
        case .noRemote, .unpushed, .noUpstream: return .high
        case .uncommitted, .stash, .unreadable: return .medium
        case .untracked: return .low
        }
    }

    /// Ordering weight used to sort repositories. Follows the documented
    /// order: no remote, unpushed commits, uncommitted changes, stashes,
    /// untracked files.
    public var weight: Int {
        switch self {
        case .noRemote: return 60
        case .unpushed, .noUpstream: return 50
        case .uncommitted: return 40
        case .unreadable: return 35
        case .stash: return 30
        case .untracked: return 10
        }
    }

    /// Short label for badges.
    public var label: String {
        switch self {
        case .noRemote: return "no remote"
        case .unpushed: return "unpushed"
        case .noUpstream: return "no upstream"
        case .uncommitted: return "uncommitted"
        case .untracked: return "untracked"
        case .stash: return "stash"
        case .unreadable: return "unreadable"
        }
    }
}

/// A branch that contributes to an `unpushed` or `noUpstream` finding.
public struct BranchFinding: Codable, Equatable, Sendable {
    public let name: String
    /// Commits on this branch that the upstream (unpushed) or every
    /// remote-tracking branch (noUpstream) does not contain.
    public let commits: Int
    /// Upstream as configured, for example "origin/main". Nil when none.
    public let upstream: String?
    /// True when the configured upstream no longer exists.
    public let upstreamGone: Bool

    public init(name: String, commits: Int, upstream: String? = nil, upstreamGone: Bool = false) {
        self.name = name
        self.commits = commits
        self.upstream = upstream
        self.upstreamGone = upstreamGone
    }
}

public struct Finding: Codable, Equatable, Sendable {
    public let kind: FindingKind
    /// Commits (noRemote, unpushed, noUpstream), files (uncommitted,
    /// untracked) or entries (stash). Zero for unreadable.
    public let count: Int
    /// Branches involved, for unpushed and noUpstream.
    public let branches: [BranchFinding]
    /// Human-readable one-line summary, ASCII only.
    public let summary: String

    public init(kind: FindingKind, count: Int, branches: [BranchFinding] = [], summary: String) {
        self.kind = kind
        self.count = count
        self.branches = branches
        self.summary = summary
    }

    public var risk: Risk { kind.risk }
}

// MARK: - Raw repository state

/// A local branch as reported by `git for-each-ref refs/heads`.
public struct BranchState: Codable, Equatable, Sendable {
    public var name: String
    /// Full upstream ref, for example "refs/remotes/origin/main". Nil when unset.
    public var upstreamRef: String?
    public var ahead: Int
    public var behind: Int
    public var upstreamGone: Bool
    public var committerDate: Date?
    /// Commits reachable from this branch but from no remote-tracking ref.
    /// Only computed for branches without a usable upstream.
    public var uniqueCommits: Int?

    public init(name: String, upstreamRef: String? = nil, ahead: Int = 0, behind: Int = 0,
                upstreamGone: Bool = false, committerDate: Date? = nil, uniqueCommits: Int? = nil) {
        self.name = name
        self.upstreamRef = upstreamRef
        self.ahead = ahead
        self.behind = behind
        self.upstreamGone = upstreamGone
        self.committerDate = committerDate
        self.uniqueCommits = uniqueCommits
    }

    /// Upstream in short form ("origin/main"), or nil.
    public var upstreamShort: String? {
        guard let ref = upstreamRef else { return nil }
        for prefix in ["refs/remotes/", "refs/heads/"] where ref.hasPrefix(prefix) {
            return String(ref.dropFirst(prefix.count))
        }
        return ref
    }

    /// True when the upstream is a remote-tracking branch that still exists,
    /// so the ahead count means "commits not pushed".
    public var hasRemoteUpstream: Bool {
        guard let ref = upstreamRef, !upstreamGone else { return false }
        return ref.hasPrefix("refs/remotes/")
    }
}

/// Everything read from git for one repository, before interpretation.
public struct RepoState: Codable, Equatable, Sendable {
    /// `currentBranch` value for a detached HEAD.
    public static let detachedName = "HEAD (detached)"

    public var isBare: Bool = false
    public var isWorktree: Bool = false
    /// Current branch name, "HEAD (detached)", or nil for bare repositories.
    public var currentBranch: String?
    /// True when HEAD has no commit yet (freshly initialised repository).
    public var headUnborn: Bool = false
    public var staged: Int = 0
    public var unstaged: Int = 0
    /// Tracked files with a change in the index, the worktree, or both.
    public var changedFiles: Int = 0
    public var conflicted: Int = 0
    public var untracked: Int = 0
    public var stashes: Int = 0
    public var remotes: [String] = []
    public var branches: [BranchState] = []
    /// Commits on local branches (and a detached HEAD) when the repository has no remote.
    public var localOnlyCommits: Int = 0
    /// Commits reachable only from a detached HEAD, when the repository has a remote.
    public var detachedCommits: Int = 0
    /// Absolute path of the main working tree for a linked worktree.
    public var mainWorktreePath: String?

    public init() {}
}

// MARK: - Reports

public struct RepoReport: Codable, Equatable, Identifiable, Sendable {
    public let path: URL
    public let name: String
    public let branch: String?
    public var findings: [Finding]
    public var lastActivity: Date?
    public var state: RepoState
    /// Why git could not read the repository, when `unreadable`.
    public var error: String?

    public var id: URL { path }

    public init(path: URL, name: String? = nil, branch: String?, findings: [Finding],
                lastActivity: Date?, state: RepoState, error: String? = nil) {
        self.path = path
        self.name = name ?? path.lastPathComponent
        self.branch = branch
        self.findings = findings
        self.lastActivity = lastActivity
        self.state = state
        self.error = error
    }

    /// Highest risk among the findings; `.none` when there are none.
    public var risk: Risk { findings.map(\.risk).max() ?? .none }

    /// Sort key: the heaviest finding kind present.
    public var riskScore: Int { findings.map(\.kind.weight).max() ?? 0 }

    public var isAtRisk: Bool { !findings.isEmpty }

    /// Comma-separated summaries of every finding.
    public var summary: String {
        findings.isEmpty ? "nothing at risk" : findings.map(\.summary).joined(separator: ", ")
    }

    public func has(_ kind: FindingKind) -> Bool { findings.contains { $0.kind == kind } }

    /// Sum of all finding counts, a tie-breaker when sorting.
    var magnitude: Int { findings.reduce(0) { $0 + $1.count } }

    /// Highest risk first, then more work first, then path.
    public static func riskOrder(_ a: RepoReport, _ b: RepoReport) -> Bool {
        if a.riskScore != b.riskScore { return a.riskScore > b.riskScore }
        if a.risk != b.risk { return a.risk > b.risk }
        if a.magnitude != b.magnitude { return a.magnitude > b.magnitude }
        return a.path.path < b.path.path
    }
}

public struct ScanResult: Sendable {
    public var root: URL
    /// Every repository found, sorted by risk (highest first). Clean
    /// repositories are included with no findings.
    public var reports: [RepoReport]
    /// Number of directories whose contents were listed.
    public var scannedDirectories: Int
    /// Total number of directories that could not be read.
    public var deniedCount: Int
    /// First `RepoDiscovery.deniedDirectoryCap` directories that could not be read.
    public var deniedDirectories: [URL]
    public var duration: TimeInterval

    public init(root: URL, reports: [RepoReport] = [], scannedDirectories: Int = 0, deniedCount: Int = 0,
                deniedDirectories: [URL] = [], duration: TimeInterval = 0) {
        self.root = root
        self.reports = reports
        self.scannedDirectories = scannedDirectories
        self.deniedCount = deniedCount
        self.deniedDirectories = deniedDirectories
        self.duration = duration
    }

    public var atRisk: [RepoReport] { reports.filter(\.isAtRisk) }
    public var clean: [RepoReport] { reports.filter { !$0.isAtRisk } }
}
