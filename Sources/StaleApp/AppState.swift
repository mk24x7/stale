import AppKit
import Foundation
import StaleCore
import SwiftUI

enum AppPhase {
    case idle, scanning, results
}

@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .idle

    // Configuration
    @Published var scanRoot: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var scanRootDisplay: String = "~"
    @Published var includeNested: Bool = UserDefaults.standard.bool(forKey: AppState.includeNestedKey) {
        didSet { UserDefaults.standard.set(includeNested, forKey: Self.includeNestedKey) }
    }

    nonisolated static let includeNestedKey = "includeNested"

    // Scanning
    @Published var scanProgress: String = ""
    @Published var foundCount: Int = 0
    @Published var inspectProgress: (completed: Int, total: Int)?

    // Results
    @Published var result: ScanResult?
    @Published var copiedAt: Date?

    // Errors
    @Published var alertTitle: String = ""
    @Published var alertMessage: String?

    private var scanTask: Task<Void, Never>?
    /// Home folder used to shorten paths to "~". Only snapshot mode changes it,
    /// so the screenshot shows fixture paths as if they were under a home folder.
    var home = FileManager.default.homeDirectoryForCurrentUser

    var atRisk: [RepoReport] { result?.atRisk ?? [] }
    var clean: [RepoReport] { result?.clean ?? [] }

    /// At-risk repositories grouped by risk, highest first, empty groups dropped.
    var groups: [(risk: Risk, reports: [RepoReport])] {
        [Risk.high, .medium, .low].compactMap { risk in
            let reports = atRisk.filter { $0.risk == risk }
            return reports.isEmpty ? nil : (risk, reports)
        }
    }

    func setScanRoot(_ url: URL) {
        scanRoot = url
        scanRootDisplay = PathFormat.shorten(url.path, home: home.path)
    }

    func startScan() {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: scanRoot.path, isDirectory: &isDir), isDir.boolValue else {
            showAlert("Cannot scan this folder", "\(scanRoot.path) is not an existing folder. Choose another folder to scan.")
            phase = .idle
            return
        }

        scanTask?.cancel()
        phase = .scanning
        scanProgress = ""
        foundCount = 0
        inspectProgress = nil
        result = nil
        copiedAt = nil

        let options = ScanOptions(root: scanRoot, nested: includeNested, home: home)

        // Progress events arrive on background threads; an AsyncStream hands
        // them to the main actor without sharing self across threads.
        var progressContinuation: AsyncStream<ScanProgress>.Continuation?
        let progressStream = AsyncStream<ScanProgress>(bufferingPolicy: .bufferingNewest(32)) {
            progressContinuation = $0
        }
        let continuation = progressContinuation

        scanTask = Task { [weak self] in
            let progressTask = Task { [weak self] in
                for await event in progressStream {
                    self?.apply(event)
                }
            }
            defer {
                continuation?.finish()
                progressTask.cancel()
            }
            do {
                let result = try await StaleScanner().scan(options) { event in
                    continuation?.yield(event)
                }
                guard let self, !Task.isCancelled, self.phase == .scanning else { return }
                self.result = result
                self.phase = .results
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.phase == .scanning else { return }
                self.phase = .idle
                self.showAlert("Scan failed", error.localizedDescription)
            }
        }
    }

    private func apply(_ event: ScanProgress) {
        guard phase == .scanning else { return }
        switch event {
        case .discovering(let path, let found):
            scanProgress = PathFormat.shorten(path, home: home.path)
            foundCount = found
        case .discovered(let total):
            foundCount = total
            inspectProgress = (0, total)
        case .inspected(let completed, let total):
            inspectProgress = (completed, total)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        phase = .idle
        scanProgress = ""
        foundCount = 0
        inspectProgress = nil
    }

    /// Back to the landing screen to pick another folder.
    func reset() {
        cancelScan()
        result = nil
    }

    func rescan() {
        startScan()
    }

    // MARK: - Row actions (all read-only)

    func reveal(_ report: RepoReport) {
        NSWorkspace.shared.activateFileViewerSelecting([report.path])
    }

    func openInTerminal(_ report: RepoReport) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            showAlert("Terminal not found", "Terminal.app could not be located.")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([report.path], withApplicationAt: terminal, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.showAlert("Could not open Terminal", error.localizedDescription)
                }
            }
        }
    }

    /// Put the plain-text report (the same text the CLI prints) on the pasteboard.
    func copyReport() {
        guard let result else { return }
        let text = TextReport.render(result, header: true, home: home.path)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedAt = Date()
    }

    private func showAlert(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
    }
}
