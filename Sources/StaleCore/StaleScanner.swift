import Foundation

public struct ScanOptions: Sendable {
    public var root: URL
    /// Also report repositories nested inside other repositories.
    public var nested: Bool
    public var maxDepth: Int
    public var home: URL
    /// Repositories inspected at the same time.
    public var concurrency: Int

    public static let defaultConcurrency = 8

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser,
                nested: Bool = false,
                maxDepth: Int = DiscoveryRules.defaultMaxDepth,
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                concurrency: Int = ScanOptions.defaultConcurrency) {
        self.root = root
        self.nested = nested
        self.maxDepth = maxDepth
        self.home = home
        self.concurrency = concurrency
    }
}

public enum ScanProgress: Sendable {
    /// Walking the tree; `path` is the directory being listed.
    case discovering(path: String, found: Int)
    /// Walk finished with `total` repositories to inspect.
    case discovered(total: Int)
    /// `completed` of `total` repositories inspected.
    case inspected(completed: Int, total: Int)
}

/// Finds repositories under a root and reports the work that exists only on
/// this disk. Never modifies anything.
public struct StaleScanner: Sendable {
    public let git: GitRunner

    public init(git: GitRunner = GitRunner()) {
        self.git = git
    }

    /// Throws `StaleError` for a missing git or an invalid root, and
    /// `CancellationError` when the calling task is cancelled.
    public func scan(_ options: ScanOptions,
                     onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) async throws -> ScanResult {
        let started = Date()
        let requested = options.root.standardizedFileURL
        guard FileKind.of(requested) == .directory || Self.isDirectoryFollowingLinks(requested) else {
            throw StaleError.notADirectory(requested.path)
        }
        // Canonical so report paths and the root agree (/tmp vs /private/tmp).
        let root = URL(fileURLWithPath: PathFormat.canonical(requested.path), isDirectory: true)
        try await git.verify()

        var rules = DiscoveryRules.default
        rules.maxDepth = options.maxDepth
        let discovery = RepoDiscovery(rules: rules, nested: options.nested, home: options.home)
        let found = discovery.discover(root: root) { path, count in
            onProgress(.discovering(path: path, found: count))
        }
        if found.cancelled { throw CancellationError() }
        try Task.checkCancellation()

        let candidates = found.candidates
        onProgress(.discovered(total: candidates.count))
        var reports = try await inspectAll(candidates, concurrency: max(1, options.concurrency), onProgress: onProgress)
        reports = Self.attributeWorktrees(reports)
        reports.sort(by: RepoReport.riskOrder)

        return ScanResult(
            root: root,
            reports: reports,
            scannedDirectories: found.scannedDirectories,
            deniedCount: found.deniedCount,
            deniedDirectories: found.deniedDirectories,
            duration: Date().timeIntervalSince(started)
        )
    }

    private func inspectAll(_ candidates: [RepoCandidate], concurrency: Int,
                            onProgress: @escaping @Sendable (ScanProgress) -> Void) async throws -> [RepoReport] {
        let inspector = RepoInspector(git: git)
        let total = candidates.count
        return try await withThrowingTaskGroup(of: RepoReport.self) { group in
            var results: [RepoReport] = []
            results.reserveCapacity(total)
            var next = 0
            func addNext() {
                guard next < candidates.count else { return }
                let candidate = candidates[next]
                next += 1
                group.addTask { try await inspector.inspect(candidate) }
            }
            for _ in 0..<min(concurrency, candidates.count) { addNext() }
            while let report = try await group.next() {
                results.append(report)
                onProgress(.inspected(completed: results.count, total: total))
                try Task.checkCancellation()
                addNext()
            }
            return results
        }
    }

    /// Branches, stashes and remotes are shared by every worktree of a
    /// repository. When the main working tree was scanned too, linked
    /// worktrees keep only their own working-tree findings so nothing is
    /// counted twice.
    static func attributeWorktrees(_ reports: [RepoReport]) -> [RepoReport] {
        let scanned = Set(reports.map { PathFormat.canonical($0.path.path) })
        return reports.map { report in
            guard report.state.isWorktree, let main = report.state.mainWorktreePath,
                  scanned.contains(PathFormat.canonical(main))
            else { return report }
            var trimmed = report
            trimmed.findings = report.findings.filter { !FindingDeriver.refKinds.contains($0.kind) }
            return trimmed
        }
    }

    static func isDirectoryFollowingLinks(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
