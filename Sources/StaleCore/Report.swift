import Foundation

/// Which findings to show. Empty `kinds` means every kind.
public struct ReportFilter: Equatable, Sendable {
    public var kinds: Set<FindingKind>
    public var minRisk: Risk

    public init(kinds: Set<FindingKind> = [], minRisk: Risk = .low) {
        self.kinds = kinds
        self.minRisk = minRisk
    }

    public static let all = ReportFilter()

    public func accepts(_ finding: Finding) -> Bool {
        (kinds.isEmpty || kinds.contains(finding.kind)) && finding.risk >= minRisk
    }

    /// Reports with at least one accepted finding, keeping only accepted
    /// findings, in risk order.
    public func apply(_ reports: [RepoReport]) -> [RepoReport] {
        reports.compactMap { report in
            let kept = report.findings.filter(accepts)
            guard !kept.isEmpty else { return nil }
            var copy = report
            copy.findings = kept
            return copy
        }
        .sorted(by: RepoReport.riskOrder)
    }
}

/// ANSI styling, active only when `enabled`.
public struct TextStyle: Sendable {
    public var enabled: Bool

    public init(enabled: Bool) { self.enabled = enabled }

    public static let plain = TextStyle(enabled: false)

    func wrap(_ text: String, _ code: String) -> String {
        enabled ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }

    public func bold(_ text: String) -> String { wrap(text, "1") }
    public func dim(_ text: String) -> String { wrap(text, "2") }

    public func risk(_ text: String, _ risk: Risk) -> String {
        switch risk {
        case .high: return wrap(text, "1;31")
        case .medium: return wrap(text, "33")
        case .low: return wrap(text, "36")
        case .none: return wrap(text, "32")
        }
    }
}

public enum TextReport {
    public static func label(_ risk: Risk) -> String {
        switch risk {
        case .high: return "HIGH"
        case .medium: return "MED "
        case .low: return "LOW "
        case .none: return "OK  "
        }
    }

    /// One line: risk label, path, branch, findings summary.
    public static func line(_ report: RepoReport, style: TextStyle = .plain, home: String? = nil) -> String {
        let path = home.map { PathFormat.shorten(report.path.path, home: $0) } ?? PathFormat.shorten(report.path.path)
        var text = style.risk(label(report.risk), report.risk) + "  " + style.bold(path)
        if let branch = report.branch {
            text += " " + style.dim("[\(branch)]")
        } else if report.state.isBare {
            text += " " + style.dim("[bare]")
        }
        text += "  " + report.summary
        return text
    }

    public static func footer(_ result: ScanResult, shown: Int) -> String {
        let seconds = String(format: "%.1f", result.duration)
        return "\(PathFormat.plural(result.reports.count, "repo")), \(shown) with unbacked work, "
            + "\(PathFormat.plural(result.deniedCount, "denied folder")) (\(seconds) s)"
    }

    /// Lines for each shown report, a blank line and the footer. Used by the
    /// CLI (with colour) and by the app's "Copy report" (plain).
    public static func render(_ result: ScanResult, filter: ReportFilter = .all,
                              style: TextStyle = .plain, header: Bool = false, home: String? = nil) -> String {
        let shown = filter.apply(result.reports)
        var lines: [String] = []
        if header {
            let root = home.map { PathFormat.shorten(result.root.path, home: $0) } ?? PathFormat.shorten(result.root.path)
            lines.append("Stale \(StaleVersion.current) report for \(root)")
            lines.append("")
        }
        if shown.isEmpty {
            lines.append("Nothing at risk: every repository found is committed and pushed.")
        } else {
            lines.append(contentsOf: shown.map { line($0, style: style, home: home) })
        }
        lines.append("")
        lines.append(footer(result, shown: shown.count))
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - JSON

public struct JSONReport: Codable, Sendable {
    public struct Summary: Codable, Sendable {
        public var repositories: Int
        public var atRisk: Int
        public var scannedDirectories: Int
        public var deniedDirectories: Int
    }

    public struct Repository: Codable, Sendable {
        public var path: String
        public var name: String
        public var branch: String?
        public var risk: Risk
        public var riskScore: Int
        public var lastActivity: Date?
        public var bare: Bool
        public var worktree: Bool
        public var remotes: [String]
        public var error: String?
        public var findings: [Finding]
    }

    public var version: String
    public var root: String
    public var durationSeconds: Double
    public var summary: Summary
    /// Repositories with findings that pass the filter, highest risk first.
    public var repositories: [Repository]
    /// Paths of repositories with nothing at risk.
    public var clean: [String]
    /// Up to 50 folders that could not be read.
    public var denied: [String]

    public init(result: ScanResult, filter: ReportFilter = .all) {
        let shown = filter.apply(result.reports)
        version = StaleVersion.current
        root = result.root.path
        durationSeconds = (result.duration * 1000).rounded() / 1000
        summary = Summary(repositories: result.reports.count, atRisk: shown.count,
                          scannedDirectories: result.scannedDirectories, deniedDirectories: result.deniedCount)
        repositories = shown.map {
            Repository(path: $0.path.path, name: $0.name, branch: $0.branch, risk: $0.risk, riskScore: $0.riskScore,
                       lastActivity: $0.lastActivity, bare: $0.state.isBare, worktree: $0.state.isWorktree,
                       remotes: $0.state.remotes, error: $0.error, findings: $0.findings)
        }
        clean = result.clean.map(\.path.path).sorted()
        denied = result.deniedDirectories.map(\.path)
    }

    public func encoded() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
