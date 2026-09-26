import Foundation
import XCTest
@testable import StaleCore

/// Builds real git repositories for tests with the system git, isolated from
/// the user's global and system configuration (no signing, no hooks, fixed
/// identity and default branch).
enum GitFixture {
    static let isolatedEnvironment: [String: String] = [
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Stale Test",
        "GIT_AUTHOR_EMAIL": "test@example.com",
        "GIT_COMMITTER_NAME": "Stale Test",
        "GIT_COMMITTER_EMAIL": "test@example.com",
        "GIT_TERMINAL_PROMPT": "0",
    ]

    /// GitRunner for the code under test, also isolated from user config.
    static var runner: GitRunner { GitRunner(extraEnvironment: isolatedEnvironment) }

    static var scanner: StaleScanner { StaleScanner(git: runner) }

    /// Run git synchronously and fail the test on a non-zero exit.
    @discardableResult
    static func git(_ args: [String], in dir: URL, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let process = Process()
        process.executableURL = GitRunner.defaultExecutable
        process.arguments = ["-C", dir.path] + args
        var env = ProcessInfo.processInfo.environment
        for key in GitRunner.scrubbedVariables { env.removeValue(forKey: key) }
        for (key, value) in isolatedEnvironment { env[key] = value }
        process.environment = env
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let stdout = String(decoding: outData, as: UTF8.self)
        if process.terminationStatus != 0 {
            let message = "git \(args.joined(separator: " ")) failed: \(String(decoding: errData, as: UTF8.self))"
            XCTFail(message, file: file, line: line)
            throw NSError(domain: "GitFixture", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        return stdout
    }

    /// `git init -b main` at `dir` (created if needed).
    static func initRepo(_ dir: URL, bare: Bool = false) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var args = ["init", "-q", "-b", "main"]
        if bare { args.append("--bare") }
        try git(args, in: dir)
    }

    /// Write a file and commit it.
    static func commit(_ dir: URL, file name: String = "file.txt", contents: String? = nil,
                       message: String = "change") throws {
        let target = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = contents ?? UUID().uuidString
        try Data(body.utf8).write(to: target)
        try git(["add", "--", name], in: dir)
        try git(["commit", "-q", "-m", message], in: dir)
    }

    /// A repository at `dir` with one commit pushed to a bare `origin` at
    /// `remote`, with main tracking origin/main.
    static func pushedRepo(_ dir: URL, remote: URL) throws {
        try initRepo(remote, bare: true)
        try initRepo(dir)
        try commit(dir, message: "initial")
        try git(["remote", "add", "origin", remote.path], in: dir)
        try git(["push", "-q", "-u", "origin", "main"], in: dir)
    }

    static func scan(_ root: URL, nested: Bool = false, maxDepth: Int = 10, home: URL? = nil) async throws -> ScanResult {
        let options = ScanOptions(root: root, nested: nested, maxDepth: maxDepth,
                                  home: home ?? URL(fileURLWithPath: "/nonexistent-home"))
        return try await scanner.scan(options)
    }

    static func inspect(_ dir: URL) async throws -> RepoReport {
        guard let layout = RepoDiscovery.layout(of: dir) else {
            throw NSError(domain: "GitFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "not a repo: \(dir.path)"])
        }
        return try await RepoInspector(git: runner).inspect(RepoCandidate(url: dir, layout: layout))
    }
}

extension RepoReport {
    func finding(_ kind: FindingKind) -> Finding? { findings.first { $0.kind == kind } }
    var kinds: [FindingKind] { findings.map(\.kind) }
}
