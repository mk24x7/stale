import XCTest
@testable import StaleCore

/// The filesystem walk, without running git (layouts are faked with plain files).
final class DiscoveryTests: XCTestCase {
    private func found(_ tree: TempTree, nested: Bool = false, maxDepth: Int = 10, home: URL? = nil) -> [String] {
        var rules = DiscoveryRules.default
        rules.maxDepth = maxDepth
        let discovery = RepoDiscovery(rules: rules, nested: nested, home: home ?? URL(fileURLWithPath: "/nonexistent-home"))
        return discovery.discover(root: tree.root).candidates.map { tree.relative($0.url) }.sorted()
    }

    func testFindsWorkTreeGitFileAndBareLayouts() throws {
        let tree = try TempTree([
            "a/.git/HEAD": .file("ref: refs/heads/main\n"),
            "b/.git": .file("gitdir: ../a/.git/worktrees/b\n"),
            "c.git/HEAD": .file("ref: refs/heads/main\n"),
            "c.git/objects": .dir,
            "c.git/refs": .dir,
            "plain/readme.txt": .file("x"),
        ])
        let discovery = RepoDiscovery(home: URL(fileURLWithPath: "/nonexistent-home"))
        let result = discovery.discover(root: tree.root)
        let layouts = Dictionary(uniqueKeysWithValues: result.candidates.map { (tree.relative($0.url), $0.layout) })

        XCTAssertEqual(layouts, ["a": .workTree, "b": .gitFile, "c.git": .bare])
    }

    func testSkipsDependencyAndBuildFoldersAnywhere() throws {
        var spec: [String: TreeNode] = ["real/.git": .dir]
        for name in ["node_modules", ".build", "target", "vendor", "Pods", "venv", ".venv", "__pycache__", "DerivedData"] {
            spec["proj/\(name)/dep/.git"] = .dir
        }
        let tree = try TempTree(spec)

        XCTAssertEqual(found(tree), ["real"])
    }

    func testSkipsHomeOnlyFoldersOnlyDirectlyUnderHome() throws {
        let tree = try TempTree([
            "Library/tool/.git": .dir,
            "Music/band/.git": .dir,
            ".cargo/registry/index/.git": .dir,
            "code/Library/.git": .dir,
            "code/Music/.git": .dir,
            ".dotfiles/.git": .dir,
        ])

        XCTAssertEqual(found(tree, home: tree.root), [".dotfiles", "code/Library", "code/Music"])
    }

    func testDoesNotFollowSymlinksOrEnterAppBundles() throws {
        let tree = try TempTree([
            "outside/repo/.git": .dir,
            "scan/link": .symlink("../outside"),
            "scan/Tool.app/Contents/.git": .dir,
            "scan/own/.git": .dir,
        ])
        let discovery = RepoDiscovery(home: URL(fileURLWithPath: "/nonexistent-home"))
        let result = discovery.discover(root: tree.url("scan"))

        XCTAssertEqual(result.candidates.map { tree.relative($0.url) }, ["scan/own"])
    }

    func testMaxDepthIsInclusive() throws {
        let tree = try TempTree([
            "one/.git": .dir,
            "a/two/.git": .dir,
            "a/b/three/.git": .dir,
        ])

        XCTAssertEqual(found(tree, maxDepth: 1), ["one"])
        XCTAssertEqual(found(tree, maxDepth: 2), ["a/two", "one"])
        XCTAssertEqual(found(tree, maxDepth: 3), ["a/b/three", "a/two", "one"])
    }

    func testRootThatIsARepositoryIsReported() throws {
        let tree = try TempTree([".git": .dir, "sub/inner/.git": .dir])

        XCTAssertEqual(found(tree), [""])
        XCTAssertEqual(found(tree, nested: true), ["", "sub/inner"])
    }

    func testDeniedDirectoriesAreCounted() throws {
        try XCTSkipIf(isRunningAsRoot, "root can read everything")
        let tree = try TempTree(["locked/secret/.git": .dir, "open/.git": .dir])
        tree.chmod("locked", 0o000)
        let discovery = RepoDiscovery(home: URL(fileURLWithPath: "/nonexistent-home"))

        let result = discovery.discover(root: tree.root)

        XCTAssertEqual(result.candidates.map { tree.relative($0.url) }, ["open"])
        XCTAssertEqual(result.deniedCount, 1)
        XCTAssertEqual(result.deniedDirectories.map { tree.relative($0) }, ["locked"])
    }

    func testCancelledWalkStopsEarly() async throws {
        var spec: [String: TreeNode] = [:]
        for i in 0..<200 { spec["d\(i)/x/.git"] = .dir }
        let tree = try TempTree(spec)
        let root = tree.root

        let task = Task.detached { () -> DiscoveryResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return RepoDiscovery(home: URL(fileURLWithPath: "/nonexistent-home")).discover(root: root)
        }
        let result = await task.value

        XCTAssertTrue(result.cancelled)
        XCTAssertLessThan(result.candidates.count, 200)
    }
}
