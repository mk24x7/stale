import Foundation

/// Small display helpers shared by the CLI, the app and the text report.
public enum PathFormat {
    /// Replace the home directory prefix with "~".
    public static func shorten(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String {
        let trimmedHome = home.hasSuffix("/") && home.count > 1 ? String(home.dropLast()) : home
        if path == trimmedHome { return "~" }
        if path.hasPrefix(trimmedHome + "/") {
            return "~" + path.dropFirst(trimmedHome.count)
        }
        return path
    }

    /// Expand a leading "~" or "~/" to the home directory.
    public static func expandTilde(_ path: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst(1) }
        return path
    }

    /// "today", "3 days ago", "2 months ago", "1 year ago".
    public static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        let days = max(0, seconds / 86400)
        let weeks = days / 7
        let months = days / 30
        let years = days / 365
        if years > 0 { return "\(years) year\(years > 1 ? "s" : "") ago" }
        if months > 0 { return "\(months) month\(months > 1 ? "s" : "") ago" }
        if weeks > 0 { return "\(weeks) week\(weeks > 1 ? "s" : "") ago" }
        if days > 0 { return "\(days) day\(days > 1 ? "s" : "") ago" }
        return "today"
    }

    /// realpath(3) of `path`, or the standardised path when it does not exist.
    /// (URL.resolvingSymlinksInPath maps /private/var back to /var, which
    /// would make the same directory compare unequal.)
    public static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func plural(_ count: Int, _ singular: String, _ pluralForm: String? = nil) -> String {
        "\(count) " + (count == 1 ? singular : (pluralForm ?? singular + "s"))
    }
}
