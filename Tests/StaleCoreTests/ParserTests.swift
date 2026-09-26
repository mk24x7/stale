import XCTest
@testable import StaleCore

final class ParserTests: XCTestCase {
    func testParsesPorcelainV2Status() {
        let text = """
        # branch.oid 1234567890abcdef1234567890abcdef12345678
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +3 -1
        1 .M N... 100644 100644 100644 abc abc src/a.swift
        1 M. N... 100644 100644 100644 abc def src/b.swift
        1 MM N... 100644 100644 100644 abc def src/c.swift
        2 R. N... 100644 100644 100644 abc abc R100 new.swift\told.swift
        u UU N... 100644 100644 100644 100644 abc def ghi conflict.swift
        ? notes.md
        ? "name with\\nnewline"
        ! ignored.log

        """
        let status = GitParsers.parseStatus(text)

        XCTAssertEqual(status.branchHead, "main")
        XCTAssertFalse(status.headUnborn)
        XCTAssertEqual(status.upstream, "origin/main")
        XCTAssertEqual(status.ahead, 3)
        XCTAssertEqual(status.behind, 1)
        XCTAssertEqual(status.changedFiles, 5)
        XCTAssertEqual(status.staged, 3)
        XCTAssertEqual(status.unstaged, 2)
        XCTAssertEqual(status.conflicted, 1)
        XCTAssertEqual(status.untracked, 2)
    }

    func testParsesInitialAndDetachedHeads() {
        let initial = GitParsers.parseStatus("# branch.oid (initial)\n# branch.head main\n")
        XCTAssertTrue(initial.headUnborn)
        XCTAssertEqual(initial.branchHead, "main")

        let detached = GitParsers.parseStatus("# branch.oid abc\n# branch.head (detached)\n")
        XCTAssertEqual(detached.branchHead, RepoState.detachedName)
        XCTAssertFalse(detached.headUnborn)
    }

    func testParsesUpstreamTrack() {
        XCTAssertTrue(GitParsers.parseTrack("") == (0, 0, false))
        XCTAssertTrue(GitParsers.parseTrack("[ahead 2]") == (2, 0, false))
        XCTAssertTrue(GitParsers.parseTrack("[behind 7]") == (0, 7, false))
        XCTAssertTrue(GitParsers.parseTrack("[ahead 12, behind 3]") == (12, 3, false))
        XCTAssertTrue(GitParsers.parseTrack("[gone]") == (0, 0, true))
    }

    func testParsesForEachRefLines() throws {
        let tracked = try XCTUnwrap(GitParsers.parseRefLine(
            "main\trefs/remotes/origin/main\t[ahead 1]\t2026-09-01T10:20:30+05:30"))
        XCTAssertEqual(tracked.name, "main")
        XCTAssertEqual(tracked.upstreamShort, "origin/main")
        XCTAssertEqual(tracked.ahead, 1)
        XCTAssertTrue(tracked.hasRemoteUpstream)
        XCTAssertEqual(tracked.committerDate, ISO8601DateFormatter().date(from: "2026-09-01T04:50:30Z"))

        let local = try XCTUnwrap(GitParsers.parseRefLine("feature/x\t\t\t2026-09-01T10:20:30Z"))
        XCTAssertNil(local.upstreamRef)
        XCTAssertFalse(local.hasRemoteUpstream)

        let localUpstream = try XCTUnwrap(GitParsers.parseRefLine("topic\trefs/heads/main\t[ahead 4]\t2026-09-01T10:20:30Z"))
        XCTAssertFalse(localUpstream.hasRemoteUpstream, "a local branch as upstream is not a backup")

        let gone = try XCTUnwrap(GitParsers.parseRefLine("old\trefs/remotes/origin/old\t[gone]\t2026-09-01T10:20:30Z"))
        XCTAssertTrue(gone.upstreamGone)
        XCTAssertFalse(gone.hasRemoteUpstream)

        XCTAssertNil(GitParsers.parseRefLine("garbage"))
    }
}
