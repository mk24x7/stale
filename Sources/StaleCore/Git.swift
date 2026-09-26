import Foundation

public enum StaleError: Error, Equatable, LocalizedError, Sendable {
    /// The git executable is missing or does not run.
    case gitNotFound(path: String, detail: String)
    /// The scan root does not exist or is not a directory.
    case notADirectory(String)

    public var errorDescription: String? {
        switch self {
        case .gitNotFound(let path, let detail):
            var text = "git was not found or could not run at \(path)."
            if !detail.isEmpty { text += " " + detail }
            text += " Install the Xcode Command Line Tools with: xcode-select --install"
            return text
        case .notADirectory(let path):
            return "\(path) is not an existing folder."
        }
    }
}

/// Output of one git invocation.
public struct GitOutput: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public var succeeded: Bool { status == 0 && !timedOut }

    /// First non-empty stderr line, trimmed, for error messages.
    public var errorLine: String {
        if timedOut { return "git timed out" }
        let line = stderr.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line ?? "git exited with status \(status)"
    }

    public var lines: [String] {
        stdout.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}

/// Runs git read-only commands. Every call:
/// - uses an argv array (never a shell),
/// - runs `git -C <repo>` with GIT_OPTIONAL_LOCKS=0 so status never rewrites the index,
/// - sets GIT_CEILING_DIRECTORIES to the repository's parent so a broken
///   repository is never silently replaced by an enclosing one,
/// - disables fsmonitor, the pager and terminal prompts,
/// - is terminated after `timeout` seconds or when the calling task is cancelled.
public struct GitRunner: Sendable {
    public static let defaultExecutable = URL(fileURLWithPath: "/usr/bin/git")
    public static let defaultTimeout: TimeInterval = 20

    public let executable: URL
    public let timeout: TimeInterval
    /// Added to (and overriding) the inherited environment.
    public let extraEnvironment: [String: String]

    public init(executable: URL = GitRunner.defaultExecutable,
                timeout: TimeInterval = GitRunner.defaultTimeout,
                extraEnvironment: [String: String] = [:]) {
        self.executable = executable
        self.timeout = timeout
        self.extraEnvironment = extraEnvironment
    }

    /// Variables that would redirect git away from the `-C` directory.
    static let scrubbedVariables = [
        "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_PREFIX", "GIT_CEILING_DIRECTORIES",
        "GIT_DISCOVERY_ACROSS_FILESYSTEM", "GIT_PAGER", "PAGER",
    ]

    func environment(ceiling: String?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in Self.scrubbedVariables { env.removeValue(forKey: key) }
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["LC_ALL"] = "C"
        if let ceiling { env["GIT_CEILING_DIRECTORIES"] = ceiling }
        for (key, value) in extraEnvironment { env[key] = value }
        return env
    }

    /// Check that git exists and runs. Throws `StaleError.gitNotFound`.
    public func verify() async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw StaleError.gitNotFound(path: executable.path, detail: "")
        }
        let output: GitOutput
        do {
            output = try await launch(["--version"], ceiling: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StaleError.gitNotFound(path: executable.path, detail: error.localizedDescription)
        }
        guard output.succeeded, output.stdout.hasPrefix("git version") else {
            throw StaleError.gitNotFound(path: executable.path, detail: output.errorLine)
        }
    }

    /// Run `git -C <repo> <arguments>`.
    public func run(_ arguments: [String], in repo: URL) async throws -> GitOutput {
        let args = ["--no-pager", "-C", repo.path, "-c", "core.fsmonitor=false", "-c", "color.ui=false"]
            + arguments
        return try await launch(args, ceiling: repo.deletingLastPathComponent().path)
    }

    private func launch(_ arguments: [String], ceiling: String?) async throws -> GitOutput {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment(ceiling: ceiling)
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let box = ProcessBox(process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GitOutput, Error>) in
                let group = DispatchGroup()
                let collected = OutputBox()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    collected.setStdout(outPipe.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    collected.setStderr(errPipe.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                group.enter()
                process.terminationHandler = { _ in group.leave() }

                do {
                    try process.run()
                } catch {
                    // Nothing was launched: close our write ends so the readers finish.
                    try? outPipe.fileHandleForWriting.close()
                    try? errPipe.fileHandleForWriting.close()
                    process.terminationHandler = nil
                    group.leave()
                    group.notify(queue: .global()) { continuation.resume(throwing: error) }
                    return
                }
                box.started()

                let deadline = timeout
                DispatchQueue.global().asyncAfter(deadline: .now() + deadline) {
                    if box.terminateIfRunning() {
                        collected.markTimedOut()
                    }
                }

                group.notify(queue: .global()) {
                    let result = GitOutput(
                        status: process.terminationStatus,
                        stdout: String(decoding: collected.stdout, as: UTF8.self),
                        stderr: String(decoding: collected.stderr, as: UTF8.self),
                        timedOut: collected.timedOut
                    )
                    if box.wasCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(returning: result)
                    }
                }
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// Thread-safe holder for the process so timeout and cancellation can stop it.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var isStarted = false
    private var cancelled = false

    init(_ process: Process) { self.process = process }

    func started() {
        lock.lock()
        isStarted = true
        let cancelNow = cancelled
        lock.unlock()
        if cancelNow { _ = terminateIfRunning() }
    }

    var wasCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = isStarted
        lock.unlock()
        if running { _ = terminateIfRunning() }
    }

    /// SIGTERM now, SIGKILL two seconds later if git is still running.
    func terminateIfRunning() -> Bool {
        lock.lock()
        let running = isStarted && process.isRunning
        let pid = process.processIdentifier
        lock.unlock()
        guard running else { return false }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
        return true
    }
}

private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()
    private var didTimeOut = false

    func setStdout(_ data: Data) { lock.lock(); out = data; lock.unlock() }
    func setStderr(_ data: Data) { lock.lock(); err = data; lock.unlock() }
    func markTimedOut() { lock.lock(); didTimeOut = true; lock.unlock() }
    var stdout: Data { lock.lock(); defer { lock.unlock() }; return out }
    var stderr: Data { lock.lock(); defer { lock.unlock() }; return err }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return didTimeOut }
}
