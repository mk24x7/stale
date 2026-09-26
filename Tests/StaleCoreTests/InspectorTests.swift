import XCTest
@testable import StaleCore

/// Per-repository detection against real repositories built with git.
final class InspectorTests: XCTestCase {
    func testCleanPushedRepoReportsNothing() async throws {
        let tree = try TempTree()
        try GitFixture.pushedRepo(tree.url("work/app"), remote: tree.url("remotes/app.git"))

        let report = try await GitFixture.inspect(tree.url("work/app"))

        XCTAssertEqual(report.findings, [])
        XCTAssertEqual(report.risk, .none)
        XCTAssertEqual(report.branch, "main")
        XCTAssertEqual(report.state.remotes, ["origin"])
        XCTAssertNotNil(report.lastActivity)
        XCTAssertNil(report.error)
    }

    func testUnpushedCommitsAreCounted() async throws {
        let tree = try TempTree()
        let repo = tree.url("app")
        try GitFixture.pushedRepo(repo, remote: tree.url("app.git"))
        try GitFixture.commit(repo, message: "one")
        try GitFixture.commit(repo, message: "two")

        let report = try await GitFixture.inspect(repo)

        let unpushed = try XCTUnwrap(report.finding(.unpushed))
        XCTAssertEqual(unpushed.count, 2)
        XCTAssertEqual(unpushed.branches, [BranchFinding(name: "main", commits: 2, upstream: "origin/main")])
        XCTAssertEqual(unpushed.summary, "2 unpushed commits on main")
        XCTAssertEqual(report.risk, .high)
    }

    func testUnpushedCommitsAcrossTwoBranches() async throws {
        let tree = try TempTree()
        let repo = tree.url("app")
        try GitFixture.pushedRepo(repo, remote: tree.url("app.git"))
        try GitFixture.git(["switch", "-q", "-c", "dev"], in: repo)
        try GitFixture.git(["push", "-q", "-u", "origin", "dev"], in: repo)
        try GitFixture.commit(repo, message: "dev work")
        try GitFixture.git(["switch", "-q", "main"], in: repo)
        try GitFixture.commit(repo, message: "main work")

        let report = try await GitFixture.inspect(repo)

        let unpushed = try XCTUnwrap(report.finding(.unpushed))
        XCTAssertEqual(unpushed.count, 2)
        XCTAssertEqual(Set(unpushed.branches.map(\.name)), ["dev", "main"])
        XCTAssertEqual(unpushed.summary, "2 unpushed commits on 2 branches")
    }

    func testBranchWithNoUpstreamAndUniqueCommits() async throws {
        let tree = try TempTree()
        let repo = tree.url("app")
        try GitFixture.pushedRepo(repo, remote: tree.url("app.git"))
        try GitFixture.git(["switch", "-q", "-c", "feature"], in: repo)
        try GitFixture.commit(repo, message: "feature work")

        let report = try await GitFixture.inspect(repo)

        let orphan = try XCTUnwrap(report.finding(.noUpstream))
        XCTAssertEqual(orphan.count, 1)
        XCTAssertEqual(orphan.branches, [BranchFinding(name: "feature", commits: 1)])
        XCTAssertEqual(orphan.summary, "feature: 1 commit with no upstream")
        XCTAssertNil(report.finding(.unpushed))
        XCTAssertEqual(report.branch, "feature")
    }

    func testBranchWithNoUpstreamButAlreadyOnRemoteIsNotReported() async throws {
        let tree = try TempTree()
        let repo = tree.url("app")
        try GitFixture.pushedRepo(repo, remote: tree.url("app.git"))
        // Points at a commit origin/main already has, so nothing would be lost.
        try GitFixture.git(["branch", "copy-of-main"], in: repo)

        let report = try await GitFixture.inspect(repo)

        XCTAssertEqual(report.findings, [])
        XCTAssertEqual(report.state.branches.first { $0.name == "copy-of-main" }?.uniqueCommits, 0)
    }

    func testUpstreamGoneWithUnmergedCommits() async throws {
        let tree = try TempTree()
        let repo = tree.url("app")
        try GitFixture.pushedRepo(repo, remote: tree.url("app.git"))
        try GitFixture.git(["switch", "-q", "-c", "topic"], in: repo)
        try GitFixture.commit(repo, message: "topic 1")
        try GitFixture.git(["push", "-q", "-u", "origin", "topic"], in: repo)
        try GitFixture.commit(repo, message: "topic 2")
        // Someone deletes the remote branch; after a prune the upstream is gone.
        try GitFixture.git(["push", "-q", "origin", "--delete", "topic"], in: repo)

        let report = try await GitFixture.inspect(repo)

        let orphan = try XCTUnwrap(report.finding(.noUpstream))
        XCTAssertEqual(orphan.branches.count, 1)
        XCTAssertEqual(orphan.branches[0].name, "topic")
        XCTAssertTrue(orphan.branches[0].upstreamGone)
        XCTAssertEqual(orphan.branches[0].commits, 2)
        XCTAssertEqual(orphan.summary, "topic: 2 commits with upstream gone")
    }

    func testDirtyAndStagedCounts() async throws {
        let tree = try TempTree()
        let repo = tree.url("app")
        try GitFixture.pushedRepo(repo, remote: tree.url("app.git"))
        try GitFixture.commit(repo, file: "a.txt", contents: "a")
        try GitFixture.commit(repo, file: "b.txt", contents: "b")
        try GitFixture.git(["push", "-q"], in: repo)
        try tree.write("app/a.txt", "changed")          // unstaged
        try tree.write("app/b.txt", "changed")
        try GitFixture.git(["add", "b.txt"], in: repo)   // staged
        try tree.write("app/new.txt", "new")
        try GitFixture.git(["add", "new.txt"], in: repo) // staged addition

        let report = try await GitFixture.inspect(repo)

        let dirty = try XCTUnwrap(report.finding(.uncommitted))
        XCTAssertEqual(dirty.count, 3)
        XCTAssertEqual(report.state.staged, 2)
        XCTAssertEqual(report.state.unstaged, 1)
        XCTAssertEqual(dirty.summary, "3 uncommitted (2 staged)")
        XCTAssertNil(report.finding(.untracked))
        XCTAssertEqual(report.risk, .medium)
    }

    func testUntrackedOnlyIsLowRisk() async throws {
        let tree = try TempTree()
        let repo = tree.url("app")
        try GitFixture.pushedRepo(repo, remote: tree.url("app.git"))
        try tree.write("app/notes.md", "todo")
        try tree.write("app/scratch/one.txt", "1")
        try tree.write("app/scratch/two.txt", "2")
        try tree.write("app/.gitignore", "ignored.log\n")
        try tree.write("app/ignored.log", "noise")

        let report = try await GitFixture.inspect(repo)

        // notes.md, .gitignore and the scratch/ directory (collapsed by git).
        XCTAssertEqual(report.kinds, [.untracked])
        XCTAssertEqual(report.finding(.untracked)?.count, 3)
        XCTAssertEqual(report.risk, .low)
    }

    func testStashesAreDetected() async throws {
        let tree = try TempTree()
        let repo = tree.url("app")
        try GitFixture.pushedRepo(repo, remote: tree.url("app.git"))
        try tree.write("app/file.txt", "wip 1")
        try GitFixture.git(["stash", "-q"], in: repo)
        try tree.write("app/file.txt", "wip 2")
        try GitFixture.git(["stash", "-q"], in: repo)

        let report = try await GitFixture.inspect(repo)

        XCTAssertEqual(report.kinds, [.stash])
        XCTAssertEqual(report.finding(.stash)?.count, 2)
        XCTAssertEqual(report.finding(.stash)?.summary, "2 stashes")
    }

    func testRepoWithoutRemoteIsHighestRisk() async throws {
        let tree = try TempTree()
        let repo = tree.url("local")
        try GitFixture.initRepo(repo)
        try GitFixture.commit(repo, message: "one")
        try GitFixture.commit(repo, message: "two")
        try GitFixture.git(["branch", "side"], in: repo)

        let report = try await GitFixture.inspect(repo)

        let noRemote = try XCTUnwrap(report.finding(.noRemote))
        XCTAssertEqual(noRemote.count, 2)
        XCTAssertEqual(noRemote.summary, "no remote (2 commits)")
        XCTAssertNil(report.finding(.noUpstream), "no remote already covers every branch")
        XCTAssertEqual(report.risk, .high)
        XCTAssertEqual(report.riskScore, FindingKind.noRemote.weight)
    }

    func testFreshRepoWithoutCommitsReportsOnlyUntracked() async throws {
        let tree = try TempTree()
        let repo = tree.url("fresh")
        try GitFixture.initRepo(repo)
        try tree.write("fresh/draft.txt", "draft")

        let report = try await GitFixture.inspect(repo)

        XCTAssertEqual(report.kinds, [.untracked])
        XCTAssertTrue(report.state.headUnborn)
        XCTAssertNil(report.lastActivity)
    }

    func testEmptyFreshRepoReportsNothing() async throws {
        let tree = try TempTree()
        try GitFixture.initRepo(tree.url("empty"))

        let report = try await GitFixture.inspect(tree.url("empty"))

        XCTAssertEqual(report.findings, [])
    }

    func testDetachedHeadCommitsAreReported() async throws {
        let tree = try TempTree()
        let repo = tree.url("app")
        try GitFixture.pushedRepo(repo, remote: tree.url("app.git"))
        try GitFixture.git(["switch", "-q", "--detach"], in: repo)
        try GitFixture.commit(repo, message: "experiment")

        let report = try await GitFixture.inspect(repo)

        XCTAssertEqual(report.branch, RepoState.detachedName)
        let orphan = try XCTUnwrap(report.finding(.noUpstream))
        XCTAssertEqual(orphan.branches, [BranchFinding(name: RepoState.detachedName, commits: 1)])
    }

    func testBareRepoWithoutRemote() async throws {
        let tree = try TempTree()
        let bare = tree.url("backup.git")
        let work = tree.url("work")
        try GitFixture.initRepo(bare, bare: true)
        try GitFixture.initRepo(work)
        try GitFixture.commit(work)
        try GitFixture.git(["push", "-q", bare.path, "main"], in: work)

        let report = try await GitFixture.inspect(bare)

        XCTAssertTrue(report.state.isBare)
        XCTAssertNil(report.branch)
        XCTAssertEqual(report.finding(.noRemote)?.count, 1)
    }

    func testDanglingGitFileIsUnreadable() async throws {
        let tree = try TempTree(["broken/.git": .file("gitdir: /nonexistent/stale/worktree\n"),
                                 "broken/file.txt": .file("x")])

        let report = try await GitFixture.inspect(tree.url("broken"))

        XCTAssertEqual(report.kinds, [.unreadable])
        XCTAssertNotNil(report.error)
        XCTAssertEqual(report.risk, .medium)
    }

    func testCorruptGitDirectoryInsideAnotherRepoIsUnreadable() async throws {
        let tree = try TempTree()
        try GitFixture.pushedRepo(tree.url("outer"), remote: tree.url("outer.git"))
        // An empty .git directory is not a repository. Without the ceiling
        // git would silently report the enclosing repository instead.
        try tree.add(["outer/inner/.git": .dir, "outer/inner/code.txt": .file("x")])

        let report = try await GitFixture.inspect(tree.url("outer/inner"))

        XCTAssertEqual(report.kinds, [.unreadable])
    }

    func testTimeoutIsReportedAsUnreadable() async throws {
        let tree = try TempTree(["bin/git": .file("#!/bin/sh\nexec sleep 30\n"), "app/.git": .dir])
        tree.chmod("bin/git", 0o755)
        let runner = GitRunner(executable: tree.url("bin/git"), timeout: 0.3)

        let started = Date()
        let report = try await RepoInspector(git: runner).inspect(RepoCandidate(url: tree.url("app"), layout: .workTree))

        XCTAssertEqual(report.kinds, [.unreadable])
        XCTAssertTrue(report.error?.contains("timed out") ?? false, report.error ?? "nil")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
}
