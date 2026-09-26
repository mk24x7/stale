import Foundation
import StaleCore

/// stale: list git work that exists only on this disk. Read-only.

func writeError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

/// Transient one-line progress on stderr, only when stderr is a terminal.
final class ProgressLine: @unchecked Sendable {
    private let enabled: Bool
    private let lock = NSLock()
    private var last = Date.distantPast

    init(enabled: Bool) { self.enabled = enabled }

    func show(_ text: String, force: Bool = false) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard force || now.timeIntervalSince(last) > 0.1 else { return }
        last = now
        let columns = 78
        let clipped = text.count > columns ? String(text.prefix(columns - 3)) + "..." : text
        FileHandle.standardError.write(Data("\r\u{1B}[K\(clipped)".utf8))
    }

    func clear() {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
    }
}

func run() async -> Int32 {
    let options: CommandLineOptions
    do {
        options = try CommandLineParser.parse(Array(CommandLine.arguments.dropFirst()))
    } catch let error as UsageError {
        writeError("stale: \(error.message)")
        writeError("Run 'stale --help' for usage.")
        return ExitCode.usage
    } catch {
        writeError("stale: \(error.localizedDescription)")
        return ExitCode.usage
    }

    if options.showHelp {
        print(CommandLineParser.usage, terminator: "")
        return ExitCode.clean
    }
    if options.showVersion {
        print("stale \(StaleVersion.current)")
        return ExitCode.clean
    }

    let home = FileManager.default.homeDirectoryForCurrentUser
    let rootPath = PathFormat.expandTilde(options.path ?? home.path, home: home.path)
    let root = URL(fileURLWithPath: rootPath).standardizedFileURL
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
        writeError("stale: \(root.path) is not an existing folder")
        return ExitCode.usage
    }

    let environment = ProcessInfo.processInfo.environment
    let stdoutIsTTY = isatty(STDOUT_FILENO) == 1
    let useColor = options.color && stdoutIsTTY && environment["NO_COLOR"] == nil && environment["TERM"] != "dumb"
    let progress = ProgressLine(enabled: !options.json && isatty(STDERR_FILENO) == 1)

    let scanOptions = ScanOptions(root: root, nested: options.nested, maxDepth: options.maxDepth, home: home)
    let result: ScanResult
    do {
        result = try await StaleScanner().scan(scanOptions) { event in
            switch event {
            case .discovering(let path, let found):
                progress.show("Scanning \(PathFormat.shorten(path, home: home.path))  (\(found) repos)")
            case .discovered(let total):
                progress.show("Found \(total) repos, inspecting...", force: true)
            case .inspected(let completed, let total):
                progress.show("Inspecting repos \(completed)/\(total)")
            }
        }
    } catch {
        progress.clear()
        writeError("stale: \(error.localizedDescription)")
        return ExitCode.failure
    }
    progress.clear()

    let shown = options.filter.apply(result.reports)
    if options.json {
        do {
            print(try JSONReport(result: result, filter: options.filter).encoded(), terminator: "")
        } catch {
            writeError("stale: could not encode JSON: \(error.localizedDescription)")
            return ExitCode.failure
        }
    } else {
        print(TextReport.render(result, filter: options.filter, style: TextStyle(enabled: useColor),
                                home: home.path), terminator: "")
    }
    return shown.isEmpty ? ExitCode.clean : ExitCode.atRisk
}

exit(await run())
