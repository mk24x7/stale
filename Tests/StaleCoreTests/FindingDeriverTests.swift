import XCTest
@testable import StaleCore

final class FindingDeriverTests: XCTestCase {
    func testRiskLevelsPerKind() {
        XCTAssertEqual(FindingKind.noRemote.risk, .high)
        XCTAssertEqual(FindingKind.unpushed.risk, .high)
        XCTAssertEqual(FindingKind.noUpstream.risk, .high)
        XCTAssertEqual(FindingKind.uncommitted.risk, .medium)
        XCTAssertEqual(FindingKind.stash.risk, .medium)
        XCTAssertEqual(FindingKind.untracked.risk, .low)
        let order: [FindingKind] = [.noRemote, .unpushed, .uncommitted, .stash, .untracked]
        XCTAssertEqual(order.map(\.weight), order.map(\.weight).sorted(by: >))
    }

    func testFindingsAreOrderedHeaviestFirst() {
        var state = RepoState()
        state.remotes = ["origin"]
        state.untracked = 1
        state.stashes = 1
        state.changedFiles = 2
        state.unstaged = 2
        state.branches = [BranchState(name: "main", upstreamRef: "refs/remotes/origin/main", ahead: 4)]

        let kinds = FindingDeriver.findings(for: state).map(\.kind)

        XCTAssertEqual(kinds, [.unpushed, .uncommitted, .stash, .untracked])
    }

    func testNoRemoteWithoutCommitsIsNotAFinding() {
        var state = RepoState()
        state.headUnborn = true
        XCTAssertEqual(FindingDeriver.findings(for: state), [])
    }

    func testBehindOnlyIsNotAFinding() {
        var state = RepoState()
        state.remotes = ["origin"]
        state.branches = [BranchState(name: "main", upstreamRef: "refs/remotes/origin/main", behind: 9)]
        XCTAssertEqual(FindingDeriver.findings(for: state), [])
    }

    func testSummariesUseSingularAndPlural() {
        var state = RepoState()
        state.remotes = ["origin"]
        state.stashes = 1
        state.changedFiles = 1
        state.conflicted = 1
        state.branches = [
            BranchState(name: "a", uniqueCommits: 1),
            BranchState(name: "b", uniqueCommits: 2),
        ]

        let summaries = FindingDeriver.findings(for: state).map(\.summary)

        XCTAssertEqual(summaries, ["2 branches without upstream (3 commits)", "1 uncommitted (1 conflicted)", "1 stash"])
    }

    func testReportRiskOrderingTieBreaksOnMagnitudeThenPath() {
        func report(_ path: String, _ findings: [Finding]) -> RepoReport {
            RepoReport(path: URL(fileURLWithPath: path), branch: "main", findings: findings, lastActivity: nil, state: RepoState())
        }
        let small = report("/b", [Finding(kind: .uncommitted, count: 1, summary: "")])
        let big = report("/c", [Finding(kind: .uncommitted, count: 9, summary: "")])
        let sameAsSmall = report("/a", [Finding(kind: .uncommitted, count: 1, summary: "")])
        let clean = report("/0", [])

        let sorted = [small, clean, big, sameAsSmall].sorted(by: RepoReport.riskOrder).map(\.path.path)

        XCTAssertEqual(sorted, ["/c", "/a", "/b", "/0"])
    }
}
