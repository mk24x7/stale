import XCTest
@testable import StaleCore

final class CommandLineTests: XCTestCase {
    func testDefaults() throws {
        let options = try CommandLineParser.parse([])
        XCTAssertNil(options.path)
        XCTAssertFalse(options.json)
        XCTAssertEqual(options.kinds, [])
        XCTAssertEqual(options.minRisk, .low)
        XCTAssertFalse(options.nested)
        XCTAssertEqual(options.maxDepth, 10)
        XCTAssertTrue(options.color)
    }

    func testParsesEveryFlag() throws {
        let options = try CommandLineParser.parse([
            "~/code", "--json", "--only", "unpushed,noremote", "--min-risk", "high",
            "--nested", "--max-depth", "4", "--no-color",
        ])
        XCTAssertEqual(options.path, "~/code")
        XCTAssertTrue(options.json)
        XCTAssertEqual(options.kinds, [.unpushed, .noRemote])
        XCTAssertEqual(options.minRisk, .high)
        XCTAssertTrue(options.nested)
        XCTAssertEqual(options.maxDepth, 4)
        XCTAssertFalse(options.color)
    }

    func testAcceptsInlineValuesAndAllOnlyNames() throws {
        let options = try CommandLineParser.parse(["--only=uncommitted,untracked,stash,noupstream", "--max-depth=2"])
        XCTAssertEqual(options.kinds, [.uncommitted, .untracked, .stash, .noUpstream])
        XCTAssertEqual(options.maxDepth, 2)
    }

    func testVersionAndHelpFlags() throws {
        XCTAssertTrue(try CommandLineParser.parse(["--version"]).showVersion)
        XCTAssertTrue(try CommandLineParser.parse(["-V"]).showVersion)
        XCTAssertTrue(try CommandLineParser.parse(["-h"]).showHelp)
        XCTAssertTrue(try CommandLineParser.parse(["--help"]).showHelp)
    }

    func testRejectsBadInput() {
        let bad: [[String]] = [
            ["--bogus"],
            ["--only", "everything"],
            ["--only"],
            ["--min-risk", "extreme"],
            ["--min-risk", "none"],
            ["--max-depth", "0"],
            ["--max-depth", "ten"],
            ["--max-depth", "--json"],
            ["--json=yes"],
            ["one", "two"],
        ]
        for args in bad {
            XCTAssertThrowsError(try CommandLineParser.parse(args), "\(args)") { error in
                XCTAssertTrue(error is UsageError, "\(args): \(error)")
            }
        }
    }

    func testDoubleDashAllowsDashPath() throws {
        XCTAssertEqual(try CommandLineParser.parse(["--", "-weird"]).path, "-weird")
    }

    func testUsageTextIsASCII() {
        XCTAssertTrue(CommandLineParser.usage.unicodeScalars.allSatisfy(\.isASCII))
        XCTAssertTrue(CommandLineParser.usage.contains("--min-risk"))
    }
}
