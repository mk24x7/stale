import AppKit
import SwiftUI
import StaleCore

/// Hidden snapshot mode used to regenerate the README screenshot without
/// screen recording permission:
///
///     scripts/snapshot.sh
///
/// which builds a throwaway fixture of demo repositories and runs
///
///     STALE_SNAPSHOT_DIR=/tmp/stale-shots STALE_SNAPSHOT_ROOT=<fixture>/Code \
///         dist/Stale.app/Contents/MacOS/Stale
///
/// It scans STALE_SNAPSHOT_ROOT only (it refuses to run without it, so the
/// real home folder is never scanned), shortens paths against the parent of
/// that folder so they read as ~/Code/..., renders the window content offscreen
/// at 2x into landing.png and results.png, and quits. It never touches a
/// repository and never changes a saved preference.
enum Snapshot {
    static let size = NSSize(width: 780, height: 640)
    static let scale: CGFloat = 2

    static var directory: URL? {
        guard let path = ProcessInfo.processInfo.environment["STALE_SNAPSHOT_DIR"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    static var root: URL? {
        guard let path = ProcessInfo.processInfo.environment["STALE_SNAPSHOT_ROOT"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    @MainActor
    static func run(state: AppState) async {
        guard let dir = directory else { return }
        guard let root = root.map(resolved) else {
            fail("STALE_SNAPSHOT_ROOT is not set; refusing to scan the real home folder")
            return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        state.home = root.deletingLastPathComponent()
        state.setScanRoot(root)

        await render(state: state, to: dir.appendingPathComponent("landing.png"))

        state.startScan()
        let deadline = Date().addingTimeInterval(120)
        while state.phase == .scanning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard state.phase == .results else {
            fail("scan did not finish (\(state.alertMessage ?? "timeout"))")
            return
        }
        await render(state: state, to: dir.appendingPathComponent("results.png"))
        NSApp.terminate(nil)
    }

    /// realpath, so /var and /private/var match the paths the scanner reports.
    private static func resolved(_ url: URL) -> URL {
        guard let real = realpath(url.path, nil) else { return url }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real), isDirectory: true)
    }

    @MainActor
    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("snapshot: \(message)\n".utf8))
        NSApp.terminate(nil)
    }

    /// Hosts the window content in a borderless window of the default window
    /// size and captures it. The title bar is hidden in the real window too, so
    /// the content view (with its own "Stale" title strip) is the whole window.
    @MainActor
    private static func render(state: AppState, to url: URL) async {
        let content = ContentView()
            .environmentObject(state)
            .preferredColorScheme(.dark)
            .frame(width: size.width, height: size.height)

        let window = KeyableWindow(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        // Keep the regular app window out of the way so it cannot take key
        // status back and grey out the prominent button in the capture.
        for other in NSApp.windows where !(other is KeyableWindow) { other.orderOut(nil) }
        let host = NSHostingView(rootView: content)
        window.contentView = host
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        // Another app can take focus while the scan runs; wait until this
        // window is key in the active app again so controls draw active.
        for _ in 0..<20 where !(NSApp.isActive && window.isKeyWindow) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        host.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        window.orderOut(nil)
    }
}

/// Borderless windows cannot become key by default, which renders prominent
/// buttons in their inactive grey; the snapshot should show the active look.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
