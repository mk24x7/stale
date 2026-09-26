import Foundation

/// Parsed `stale` command line. Hand-written parser, no dependencies.
public struct CommandLineOptions: Equatable, Sendable {
    public var path: String?
    public var json = false
    public var kinds: Set<FindingKind> = []
    public var minRisk: Risk = .low
    public var nested = false
    public var maxDepth = DiscoveryRules.defaultMaxDepth
    public var color = true
    public var showVersion = false
    public var showHelp = false

    public init() {}

    public var filter: ReportFilter { ReportFilter(kinds: kinds, minRisk: minRisk) }
}

public struct UsageError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public enum ExitCode {
    public static let clean: Int32 = 0
    public static let failure: Int32 = 1
    public static let usage: Int32 = 2
    public static let atRisk: Int32 = 3
}

public enum CommandLineParser {
    /// Values accepted by `--only`. "unreadable" is accepted as well.
    public static let onlyValues = ["unpushed", "uncommitted", "untracked", "stash", "noremote", "noupstream", "unreadable"]

    public static let usage = """
    Usage: stale [path] [options]

    Find git work on this Mac that exists nowhere else: uncommitted changes,
    untracked files, unpushed commits, branches with no upstream, stashes and
    repositories with no remote. Read-only: stale never modifies a repository.

    Arguments:
      path                  Folder to scan (default: your home folder)

    Options:
      --json                Print one JSON document instead of text
      --only <list>         Comma-separated finding types to report:
                            unpushed, uncommitted, untracked, stash,
                            noremote, noupstream
      --min-risk <level>    Only report findings at or above: low, medium, high
                            (default: low)
      --nested              Also report repositories nested inside other repositories
      --max-depth <n>       Maximum folder depth below path (default: 10)
      --no-color            Disable colours (NO_COLOR is also honoured)
      -V, --version         Show the version
      -h, --help            Show this help

    Exit codes:
      0  nothing at risk
      1  runtime error
      2  usage error
      3  at-risk work found

    """

    public static func parse(_ arguments: [String]) throws -> CommandLineOptions {
        var options = CommandLineOptions()
        var index = 0
        var positionalOnly = false

        func value(for flag: String, inline: String?) throws -> String {
            if let inline {
                guard !inline.isEmpty else { throw UsageError("\(flag) needs a value") }
                return inline
            }
            index += 1
            guard index < arguments.count else { throw UsageError("\(flag) needs a value") }
            let next = arguments[index]
            if next.hasPrefix("-") && next != "-" { throw UsageError("\(flag) needs a value") }
            return next
        }

        while index < arguments.count {
            let argument = arguments[index]
            if positionalOnly || !argument.hasPrefix("-") || argument == "-" {
                guard options.path == nil else {
                    throw UsageError("unexpected argument '\(argument)'; only one path can be scanned")
                }
                options.path = argument
                index += 1
                continue
            }
            if argument == "--" {
                positionalOnly = true
                index += 1
                continue
            }

            var flag = argument
            var inline: String?
            if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
                flag = String(argument[..<equals])
                inline = String(argument[argument.index(after: equals)...])
            }

            switch flag {
            case "--json":
                try noValue(flag, inline)
                options.json = true
            case "--nested":
                try noValue(flag, inline)
                options.nested = true
            case "--no-color", "--no-colour":
                try noValue(flag, inline)
                options.color = false
            case "-V", "--version":
                try noValue(flag, inline)
                options.showVersion = true
            case "-h", "--help":
                try noValue(flag, inline)
                options.showHelp = true
            case "--only":
                let raw = try value(for: flag, inline: inline)
                var kinds = Set<FindingKind>()
                for item in raw.split(separator: ",", omittingEmptySubsequences: false) {
                    let name = item.trimmingCharacters(in: .whitespaces).lowercased()
                    guard let kind = FindingKind(rawValue: name) else {
                        throw UsageError("unknown finding type '\(name)' for --only; expected one of: "
                            + onlyValues.dropLast().joined(separator: ", "))
                    }
                    kinds.insert(kind)
                }
                options.kinds = kinds
            case "--min-risk":
                let raw = try value(for: flag, inline: inline)
                guard let risk = Risk(name: raw), risk != .none else {
                    throw UsageError("unknown risk level '\(raw)' for --min-risk; expected low, medium or high")
                }
                options.minRisk = risk
            case "--max-depth":
                let raw = try value(for: flag, inline: inline)
                guard let depth = Int(raw), depth >= 1, depth <= 100 else {
                    throw UsageError("--max-depth needs a whole number from 1 to 100, got '\(raw)'")
                }
                options.maxDepth = depth
            default:
                throw UsageError("unknown option '\(argument)'")
            }
            index += 1
        }
        return options
    }

    private static func noValue(_ flag: String, _ inline: String?) throws {
        if inline != nil { throw UsageError("\(flag) does not take a value") }
    }
}
