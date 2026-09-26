import XCTest
@testable import StaleCore

final class ReportTests: XCTestCase {
    private func sampleResult() -> ScanResult {
        var dirty = RepoState()
        dirty.remotes = ["origin"]
        dirty.changedFiles = 2
        dirty.unstaged = 2
        dirty.untracked = 1
        let dirtyReport = RepoReport(path: URL(fileURLWithPath: "/home/me/code/dirty"), branch: "main",
                                     findings: FindingDeriver.findings(for: dirty), lastActivity: nil, state: dirty)
        var local = RepoState()
        local.localOnlyCommits = 5
        let localReport = RepoReport(path: URL(fileURLWithPath: "/home/me/code/local"), branch: "main",
                                     findings: FindingDeriver.findings(for: local), lastActivity: nil, state: local)
        let cleanReport = RepoReport(path: URL(fileURLWithPath: "/home/me/code/clean"), branch: "main",
                                     findings: [], lastActivity: nil, state: RepoState())
        return ScanResult(root: URL(fileURLWithPath: "/home/me/code"),
                          reports: [localReport, dirtyReport, cleanReport].sorted(by: RepoReport.riskOrder),
                          scannedDirectories: 10, deniedCount: 2, deniedDirectories: [], duration: 1.25)
    }

    func testPlainTextReport() {
        let text = TextReport.render(sampleResult(), home: "/home/me")

        XCTAssertEqual(text, """
        HIGH  ~/code/local [main]  no remote (5 commits)
        MED   ~/code/dirty [main]  2 uncommitted, 1 untracked

        3 repos, 2 with unbacked work, 2 denied folders (1.2 s)

        """)
        XCTAssertTrue(text.unicodeScalars.allSatisfy(\.isASCII))
    }

    func testFilterByKindAndRisk() {
        let result = sampleResult()

        let onlyUntracked = ReportFilter(kinds: [.untracked]).apply(result.reports)
        XCTAssertEqual(onlyUntracked.map(\.name), ["dirty"])
        XCTAssertEqual(onlyUntracked.first?.kinds, [.untracked])

        let highOnly = ReportFilter(minRisk: .high).apply(result.reports)
        XCTAssertEqual(highOnly.map(\.name), ["local"])

        let text = TextReport.render(result, filter: ReportFilter(kinds: [.stash]), home: "/home/me")
        XCTAssertTrue(text.hasPrefix("Nothing at risk"))
        XCTAssertTrue(text.contains("3 repos, 0 with unbacked work"))
    }

    func testColourOnlyWhenEnabled() {
        let report = sampleResult().reports[0]
        XCTAssertFalse(TextReport.line(report, style: .plain, home: "/home/me").contains("\u{1B}["))
        XCTAssertTrue(TextReport.line(report, style: TextStyle(enabled: true), home: "/home/me").contains("\u{1B}[1;31m"))
    }

    func testJSONDocument() throws {
        let json = try JSONReport(result: sampleResult()).encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])

        XCTAssertEqual(object["version"] as? String, StaleVersion.current)
        XCTAssertEqual(object["root"] as? String, "/home/me/code")
        let summary = try XCTUnwrap(object["summary"] as? [String: Any])
        XCTAssertEqual(summary["repositories"] as? Int, 3)
        XCTAssertEqual(summary["atRisk"] as? Int, 2)
        XCTAssertEqual(summary["deniedDirectories"] as? Int, 2)
        XCTAssertEqual(object["clean"] as? [String], ["/home/me/code/clean"])
        let repos = try XCTUnwrap(object["repositories"] as? [[String: Any]])
        XCTAssertEqual(repos.map { $0["name"] as? String }, ["local", "dirty"])
        XCTAssertEqual(repos.first?["risk"] as? String, "high")
        let findings = try XCTUnwrap(repos.first?["findings"] as? [[String: Any]])
        XCTAssertEqual(findings.first?["kind"] as? String, "noremote")
        XCTAssertEqual(findings.first?["count"] as? Int, 5)
    }

    func testPathHelpers() {
        XCTAssertEqual(PathFormat.shorten("/home/me/x", home: "/home/me"), "~/x")
        XCTAssertEqual(PathFormat.shorten("/home/me", home: "/home/me"), "~")
        XCTAssertEqual(PathFormat.shorten("/home/meow", home: "/home/me"), "/home/meow")
        XCTAssertEqual(PathFormat.expandTilde("~/x", home: "/home/me"), "/home/me/x")
        XCTAssertEqual(PathFormat.expandTilde("~", home: "/home/me"), "/home/me")
        let now = Date()
        XCTAssertEqual(PathFormat.age(now, now: now), "today")
        XCTAssertEqual(PathFormat.age(now.addingTimeInterval(-3 * 86400), now: now), "3 days ago")
        XCTAssertEqual(PathFormat.age(now.addingTimeInterval(-400 * 86400), now: now), "1 year ago")
    }
}
