import XCTest
@testable import StaleCore

/// Whole scans over trees of real repositories.
final class ScannerTests: XCTestCase {
    func testNestedRepoIgnoredByDefaultAndFoundWithNested() async throws {
        let tree = try TempTree()
        try GitFixture.pushedRepo(tree.url("scan/outer"), remote: tree.url("remotes/outer.git"))
        try tree.write("scan/outer/.gitignore", "inner/\n")
        try GitFixture.git(["add", ".gitignore"], in: tree.url("scan/outer"))
        try GitFixture.git(["commit", "-q", "-m", "ignore inner"], in: tree.url("scan/outer"))
        try GitFixture.git(["push", "-q"], in: tree.url("scan/outer"))
        try GitFixture.initRepo(tree.url("scan/outer/inner"))
        try GitFixture.commit(tree.url("scan/outer/inner"))

        let flat = try await GitFixture.scan(tree.url("scan"))
        XCTAssertEqual(flat.reports.map { tree.relative($0.path) }, ["scan/outer"])
        XCTAssertEqual(flat.atRisk.count, 0)

        let nested = try await GitFixture.scan(tree.url("scan"), nested: true)
        XCTAssertEqual(Set(nested.reports.map { tree.relative($0.path) }), ["scan/outer", "scan/outer/inner"])
        XCTAssertEqual(nested.atRisk.map { tree.relative($0.path) }, ["scan/outer/inner"])
        XCTAssertEqual(nested.atRisk.first?.kinds, [.noRemote])
    }

    func testWorktreeReportsOnlyItsWorkingTreeWhenMainIsScanned() async throws {
        let tree = try TempTree()
        let main = tree.url("scan/main")
        try GitFixture.initRepo(main)
        try GitFixture.commit(main)
        try GitFixture.git(["worktree", "add", "-q", "-b", "wt-branch", tree.path("scan/linked")], in: main)
        try tree.write("scan/linked/file.txt", "edited in the worktree")

        let result = try await GitFixture.scan(tree.url("scan"))
        let byPath = Dictionary(uniqueKeysWithValues: result.reports.map { (tree.relative($0.path), $0) })

        let linked = try XCTUnwrap(byPath["scan/linked"])
        XCTAssertTrue(linked.state.isWorktree)
        XCTAssertEqual(linked.branch, "wt-branch")
        XCTAssertEqual(linked.kinds, [.uncommitted], "ref findings belong to the main repository")

        let mainReport = try XCTUnwrap(byPath["scan/main"])
        XCTAssertFalse(mainReport.state.isWorktree)
        XCTAssertEqual(mainReport.kinds, [.noRemote])
    }

    func testWorktreeKeepsRefFindingsWhenMainIsOutsideTheRoot() async throws {
        let tree = try TempTree()
        let main = tree.url("elsewhere/main")
        try GitFixture.initRepo(main)
        try GitFixture.commit(main)
        try GitFixture.git(["worktree", "add", "-q", "-b", "wt", tree.path("scan/linked")], in: main)

        let result = try await GitFixture.scan(tree.url("scan"))

        XCTAssertEqual(result.reports.count, 1)
        XCTAssertEqual(result.reports.first?.kinds, [.noRemote])
        XCTAssertEqual(result.reports.first?.state.mainWorktreePath, main.path)
    }

    func testReportsAreSortedByRisk() async throws {
        let tree = try TempTree()
        let remotes = tree.url("remotes")
        let scan = tree.url("scan")

        try GitFixture.pushedRepo(scan.appendingPathComponent("a-untracked"), remote: remotes.appendingPathComponent("a.git"))
        try tree.write("scan/a-untracked/new.txt", "x")

        try GitFixture.pushedRepo(scan.appendingPathComponent("b-stash"), remote: remotes.appendingPathComponent("b.git"))
        try tree.write("scan/b-stash/file.txt", "wip")
        try GitFixture.git(["stash", "-q"], in: scan.appendingPathComponent("b-stash"))

        try GitFixture.pushedRepo(scan.appendingPathComponent("c-dirty"), remote: remotes.appendingPathComponent("c.git"))
        try tree.write("scan/c-dirty/file.txt", "edit")

        try GitFixture.pushedRepo(scan.appendingPathComponent("d-unpushed"), remote: remotes.appendingPathComponent("d.git"))
        try GitFixture.commit(scan.appendingPathComponent("d-unpushed"))

        try GitFixture.initRepo(scan.appendingPathComponent("e-local"))
        try GitFixture.commit(scan.appendingPathComponent("e-local"))

        try GitFixture.pushedRepo(scan.appendingPathComponent("f-clean"), remote: remotes.appendingPathComponent("f.git"))

        let result = try await GitFixture.scan(scan)

        XCTAssertEqual(result.reports.map(\.name), ["e-local", "d-unpushed", "c-dirty", "b-stash", "a-untracked", "f-clean"])
        XCTAssertEqual(result.atRisk.count, 5)
        XCTAssertEqual(result.clean.map(\.name), ["f-clean"])
        XCTAssertGreaterThan(result.scannedDirectories, 0)
        XCTAssertGreaterThan(result.duration, 0)
    }

    func testScanIsReadOnly() async throws {
        let tree = try TempTree()
        let repo = tree.url("scan/app")
        try GitFixture.pushedRepo(repo, remote: tree.url("app.git"))
        try tree.write("scan/app/file.txt", "dirty")
        try tree.write("scan/app/untracked.txt", "new")
        let before = try Self.snapshot(repo.appendingPathComponent(".git"))

        _ = try await GitFixture.scan(tree.url("scan"))

        let after = try Self.snapshot(repo.appendingPathComponent(".git"))
        XCTAssertEqual(before, after, "the scan must not change anything inside .git")
    }

    func testMissingGitBinaryIsAClearError() async throws {
        let tree = try TempTree(["repo/.git": .dir])
        let scanner = StaleScanner(git: GitRunner(executable: URL(fileURLWithPath: "/nonexistent/bin/git")))

        do {
            _ = try await scanner.scan(ScanOptions(root: tree.root))
            XCTFail("expected gitNotFound")
        } catch let error as StaleError {
            guard case .gitNotFound(let path, _) = error else { return XCTFail("unexpected \(error)") }
            XCTAssertEqual(path, "/nonexistent/bin/git")
            XCTAssertTrue(error.localizedDescription.contains("xcode-select --install"))
        }
    }

    func testMissingRootIsAClearError() async throws {
        do {
            _ = try await GitFixture.scan(URL(fileURLWithPath: "/nonexistent/stale-root"))
            XCTFail("expected notADirectory")
        } catch let error as StaleError {
            XCTAssertEqual(error, .notADirectory("/nonexistent/stale-root"))
        }
    }

    func testCancelledScanThrowsCancellationError() async throws {
        let tree = try TempTree()
        for i in 0..<12 {
            let repo = tree.url("scan/r\(i)")
            try GitFixture.initRepo(repo)
            try GitFixture.commit(repo)
        }
        let root = tree.url("scan")

        let task = Task { try await GitFixture.scan(root) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // expected
        }
    }

    /// Relative path -> (size, modification time) for every file under `dir`.
    static func snapshot(_ dir: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        let fm = FileManager.default
        guard let walker = fm.enumerator(atPath: dir.path) else { return result }
        while let relative = walker.nextObject() as? String {
            let attributes = try fm.attributesOfItem(atPath: dir.appendingPathComponent(relative).path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? -1
            let date = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            result[relative] = "\(size)@\(date)"
        }
        return result
    }
}
