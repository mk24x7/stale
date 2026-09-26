import Foundation

/// A directory that looks like a git repository.
public struct RepoCandidate: Equatable, Hashable, Sendable {
    public enum Layout: String, Sendable {
        /// Working tree with a `.git` directory.
        case workTree
        /// Working tree with a `.git` file (linked worktree, submodule, or a
        /// dangling pointer).
        case gitFile
        /// Bare repository: HEAD, objects and refs directly inside.
        case bare
    }

    public let url: URL
    public let layout: Layout

    public init(url: URL, layout: Layout) {
        self.url = url
        self.layout = layout
    }
}

public struct DiscoveryRules: Sendable {
    /// Skipped only when they sit directly in the home folder.
    public var skipUnderHome: Set<String>
    /// Skipped at any depth.
    public var skipAnywhere: Set<String>
    /// Directory name suffixes (lowercase) that are never entered.
    public var skipPackageExtensions: [String]
    /// Root is depth 0; repositories are found at depth <= maxDepth.
    public var maxDepth: Int

    public static let defaultMaxDepth = 10

    public static let `default` = DiscoveryRules(
        skipUnderHome: [
            "Library", "Applications", ".Trash", "Pictures", "Movies", "Music",
            // Tool caches full of clean upstream clones (registries, plugin managers).
            ".cache", ".npm", ".yarn", ".pnpm-store", ".bun", ".cargo", ".rustup", ".gradle", ".m2",
            ".cocoapods", ".nvm", ".pyenv", ".rbenv", ".gem", ".docker", ".ollama", ".conda",
            ".vscode", ".cursor", ".windsurf", ".zsh_sessions",
        ],
        skipAnywhere: [
            "node_modules", ".build", "target", "vendor", "Pods", "venv", ".venv", "__pycache__",
            "DerivedData", ".git", ".Trash", ".Trashes", ".Spotlight-V100", ".fseventsd",
        ],
        skipPackageExtensions: [".app", ".xcodeproj", ".xcworkspace", ".photoslibrary", ".framework", ".appex", ".bundle"],
        maxDepth: defaultMaxDepth
    )

    public init(skipUnderHome: Set<String>, skipAnywhere: Set<String>, skipPackageExtensions: [String], maxDepth: Int) {
        self.skipUnderHome = skipUnderHome
        self.skipAnywhere = skipAnywhere
        self.skipPackageExtensions = skipPackageExtensions
        self.maxDepth = maxDepth
    }
}

public struct DiscoveryResult: Sendable {
    public var candidates: [RepoCandidate] = []
    public var scannedDirectories = 0
    public var deniedCount = 0
    public var deniedDirectories: [URL] = []
    public var cancelled = false

    public init() {}
}

/// Iterative depth-first walk that finds repositories.
///
/// - A directory containing `.git` (directory or file) is a repository. The
///   walk does not descend into it unless `nested` is set.
/// - A directory holding `HEAD`, `objects/` and `refs/` is a bare repository;
///   the walk never descends into it.
/// - Symlinks are never followed; package bundles (.app, ...) are never entered.
/// - `skipUnderHome` names are skipped directly under `home`, `skipAnywhere`
///   names at any depth. Hidden directories are walked (dotfile repositories
///   matter) except the listed tool caches.
/// - Cancellation is checked continuously; partial results are returned with
///   `cancelled` set.
public struct RepoDiscovery: Sendable {
    public static let deniedDirectoryCap = 50

    public var rules: DiscoveryRules
    public var nested: Bool
    public var home: URL

    public init(rules: DiscoveryRules = .default, nested: Bool = false,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.rules = rules
        self.nested = nested
        self.home = home
    }

    public func discover(root: URL, onProgress: (String, Int) -> Void = { _, _ in }) -> DiscoveryResult {
        var result = DiscoveryResult()
        let fm = FileManager.default
        let homePath = home.standardizedFileURL.path
        let packageSuffixes = rules.skipPackageExtensions.map { $0.lowercased() }

        // The root itself may be a repository.
        if let layout = Self.layout(of: root) {
            result.candidates.append(RepoCandidate(url: root, layout: layout))
            if layout == .bare || !nested { return result }
        }

        var stack: [(URL, Int)] = [(root, 0)]
        var lastProgress = Date.timeIntervalSinceReferenceDate

        while let (dirURL, depth) = stack.popLast() {
            if Task.isCancelled { result.cancelled = true; return result }
            if depth >= rules.maxDepth { continue }

            let now = Date.timeIntervalSinceReferenceDate
            if now - lastProgress > 0.1 {
                onProgress(dirURL.path, result.candidates.count)
                lastProgress = now
            }

            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: [])
            } catch {
                if error.isPermissionError {
                    result.deniedCount += 1
                    if result.deniedDirectories.count < Self.deniedDirectoryCap {
                        result.deniedDirectories.append(dirURL)
                    }
                }
                continue
            }
            result.scannedDirectories += 1
            let dirIsHome = dirURL.standardizedFileURL.path == homePath

            // Push in reverse name order so the walk visits children alphabetically.
            var children: [URL] = []
            for (index, itemURL) in contents.enumerated() {
                if index & 63 == 63, Task.isCancelled { result.cancelled = true; return result }
                guard FileKind.of(itemURL) == .directory else { continue }
                let name = itemURL.lastPathComponent
                if rules.skipAnywhere.contains(name) { continue }
                if dirIsHome && rules.skipUnderHome.contains(name) { continue }
                let lowered = name.lowercased()
                if packageSuffixes.contains(where: { lowered.hasSuffix($0) }) { continue }

                if let layout = Self.layout(of: itemURL) {
                    result.candidates.append(RepoCandidate(url: itemURL, layout: layout))
                    if layout == .bare || !nested { continue }
                }
                children.append(itemURL)
            }
            for child in children.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                stack.append((child, depth + 1))
            }
        }
        return result
    }

    /// How `dir` looks as a repository, or nil if it does not.
    public static func layout(of dir: URL) -> RepoCandidate.Layout? {
        let dotGit = dir.appendingPathComponent(".git")
        switch FileKind.of(dotGit) {
        case .directory: return .workTree
        case .regularFile: return .gitFile
        default: break
        }
        if FileKind.of(dir.appendingPathComponent("HEAD")) == .regularFile,
           FileKind.of(dir.appendingPathComponent("objects")) == .directory,
           FileKind.of(dir.appendingPathComponent("refs")) == .directory {
            return .bare
        }
        return nil
    }
}
