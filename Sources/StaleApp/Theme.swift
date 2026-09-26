import SwiftUI
import StaleCore

/// Colours shared by every screen. The accent is the coral of the app icon.
enum Theme {
    static let background = Color(nsColor: NSColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1))
    static let accent = Color(red: 0xE0 / 255, green: 0x7A / 255, blue: 0x5F / 255)
    static let ring = Color(red: 0xFF / 255, green: 0xE0 / 255, blue: 0x66 / 255)
    static let tertiary = Color(nsColor: .tertiaryLabelColor)

    static func color(for risk: Risk) -> Color {
        switch risk {
        case .high: return Color(red: 0.95, green: 0.35, blue: 0.32)
        case .medium: return Color(red: 0.95, green: 0.7, blue: 0.2)
        case .low: return Color(red: 0.35, green: 0.7, blue: 0.95)
        case .none: return Color(red: 0.2, green: 0.8, blue: 0.5)
        }
    }

    static func title(for risk: Risk) -> String {
        switch risk {
        case .high: return "HIGH RISK"
        case .medium: return "MEDIUM RISK"
        case .low: return "LOW RISK"
        case .none: return "CLEAN"
        }
    }

    static func explanation(for risk: Risk) -> String {
        switch risk {
        case .high: return "Commits that exist on no remote"
        case .medium: return "Uncommitted changes, stashes, or repositories git could not read"
        case .low: return "Untracked files only"
        case .none: return "Committed and pushed"
        }
    }

    static func icon(for kind: FindingKind) -> String {
        switch kind {
        case .noRemote: return "icloud.slash"
        case .unpushed: return "arrow.up.circle"
        case .noUpstream: return "arrow.triangle.branch"
        case .uncommitted: return "pencil"
        case .untracked: return "questionmark.folder"
        case .stash: return "tray.full"
        case .unreadable: return "exclamationmark.triangle"
        }
    }
}
