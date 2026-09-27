import AppKit
import Combine
import SwiftUI

@MainActor
final class LoaderUpdater: ObservableObject {
    static let shared = LoaderUpdater()
    static var isPreview: Bool { Bundle.main.bundleIdentifier == "local.noah.search.mod-preview" }
    static var upstream: String { Bundle.main.object(forInfoDictionaryKey: "SearchUpstreamVersion") as? String ?? "unknown" }
    enum State: Equatable {
        case unchecked, checking, current, available(LoaderRelease), incompatible(LoaderRelease), failed
        case downloading(LoaderRelease, Int), installing(LoaderRelease), installFailed(String)
    }
    @Published private(set) var state: State = .unchecked
    @Published private(set) var lastChecked: Date?
    private var clock: Timer?
    private var authenticatedRelease: (release: LoaderRelease, data: Data, signature: Data)?
    private var installation: Task<Void, Never>?
    private let pendingKey = "appearance.loader.update.pendingStage"
    var busy: Bool {
        switch state { case .checking, .downloading, .installing: return true; default: return false }
    }
    private var say: ((String) -> Void)?
    private let lastKey = "appearance.loader.update.lastAttempt"

    func start(then announce: @escaping (String) -> Void) {
        guard Self.isPreview, !Store.testing else { return }
        say = announce
        finishPendingInstall()
        if clock == nil {
            clock = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkIfDue() }
            }
            clock?.tolerance = 300
        }
        if case .installFailed = state { return }
        checkIfDue()
    }

    private func checkIfDue() {
        let last = Store.settings.object(forKey: lastKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= 20 * 3600 { check() }
    }

    func openPanel() {
        Store.settings.set("about", forKey: "settings.page")
        Browsers.front?.tuning = true
        NotificationCenter.default.post(name: Self.showPanel, object: nil)
        check()
    }
    static let showPanel = Notification.Name("SearchPreviewShowUpdates")

    func check() {
        guard Self.isPreview, !busy else { return }
        state = .checking
        Store.settings.set(Date(), forKey: lastKey)
        Task {
            do {
                let url = URL(string: "https://api.github.com/repos/\(LoaderRelease.repository)/releases?per_page=30")!
                let data = try await Self.read(url, limit: 2_000_000)
                let releases = try JSONDecoder().decode([LoaderGitHubRelease].self, from: data)
                // GitHub includes prereleases here. /releases/latest would omit our previews.
                guard let entry = releases.first(where: { $0.manifest != nil }), let manifest = entry.manifest else {
                    throw LoaderRelease.Invalid.manifest
                }
                let payload = try await Self.read(manifest, limit: 32_768)
                let signatureURL = manifest.deletingLastPathComponent().appendingPathComponent("loader-update.sig")
                let signature = try await Self.read(signatureURL, limit: 64)
                let next = try LoaderInstallCore.authenticated(payload, signature: signature).validated(tag: entry.tag_name)
                authenticatedRelease = (next, payload, signature)
                lastChecked = Date()
                if next.build <= Updater.build {
                    state = .current
                } else if next.runs(on: ProcessInfo.processInfo.operatingSystemVersion, architecture: Self.architecture) {
                    state = .available(next)
                    say?("Appearance loader \(next.version) is available in Settings → About")
                } else {
                    state = .incompatible(next)
                }
            } catch {
                // An offline, malformed or unavailable feed must never claim "up to date".
                state = .failed
            }
        }
    }

    private static var architecture: String { LoaderInstallCore.architecture }

    private func finishPendingInstall() {
        guard let path = Store.settings.string(forKey: pendingKey) else { return }
        let stage = URL(fileURLWithPath: path).standardizedFileURL
        guard LoaderInstallCore.validStage(stage, app: Bundle.main.bundleURL.standardizedFileURL) else {
            Store.settings.removeObject(forKey: pendingKey); return
        }
        let result = (try? String(contentsOf: stage.appendingPathComponent("result"), encoding: .utf8)) ?? ""
        if result == "installed",
           let data = try? Data(contentsOf: stage.appendingPathComponent("manifest.json")),
           let sig = try? Data(contentsOf: stage.appendingPathComponent("manifest.sig")),
           let release = try? LoaderInstallCore.authenticated(data, signature: sig), release.build == Updater.build {
            try? FileManager.default.removeItem(at: stage)
            Store.settings.removeObject(forKey: pendingKey)
            say?("Updated to appearance loader \(Updater.version)")
        } else if result.hasPrefix("failed:") {
            state = .installFailed(result)
            say?("The update could not be installed. See Settings → About.")
            // Keep the previous bundle if rollback itself failed; never delete the only copy.
            if !FileManager.default.fileExists(atPath: stage.appendingPathComponent("Previous.app").path) {
                try? FileManager.default.removeItem(at: stage)
                Store.settings.removeObject(forKey: pendingKey)
            }
        }
    }

    func cancelDownload() { installation?.cancel() }

    func install() {
        guard case .available(let next) = state, let verified = authenticatedRelease,
              verified.release == next, Self.isPreview else { return }
        state = .downloading(next, 0)
        installation = Task {
            var stage: URL?
            let archive = FileManager.default.temporaryDirectory.appendingPathComponent("loader-download-\(UUID().uuidString).zip")
            defer { try? FileManager.default.removeItem(at: archive); installation = nil }
            do {
                let app = Bundle.main.bundleURL.standardizedFileURL
                try LoaderInstallCore.target(app, build: Updater.build)
                let data = try await Self.read(next.archive, limit: LoaderInstallCore.maximumArchiveBytes) { count in
                    Task { @MainActor in
                        if case .downloading = self.state { self.state = .downloading(next, count) }
                    }
                }
                try Task.checkCancellation()
                try data.write(to: archive, options: .atomic)
                state = .installing(next)
                let prepared = try await Task.detached(priority: .utility) {
                    try LoaderInstallCore.prepare(archive: archive, data: verified.data, signature: verified.signature,
                                                  app: app, currentBuild: Updater.build)
                }.value
                stage = prepared
                try Task.checkCancellation()
                let helper = prepared.appendingPathComponent("LoaderInstallHelper")
                try FileManager.default.copyItem(at: app.appendingPathComponent("Contents/MacOS/LoaderInstallHelper"), to: helper)
                let process = Process()
                process.executableURL = helper
                process.arguments = [prepared.path, app.path, String(ProcessInfo.processInfo.processIdentifier), String(Updater.build)]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                // Quit only after the helper has started and validated the installation location.
                for _ in 0..<100 {
                    if FileManager.default.fileExists(atPath: prepared.appendingPathComponent("ready").path) { break }
                    guard process.isRunning else { throw LoaderInstallCore.reject("The update helper could not start. Nothing was replaced.") }
                    try await Task.sleep(for: .milliseconds(50))
                }
                guard FileManager.default.fileExists(atPath: prepared.appendingPathComponent("ready").path) else {
                    process.terminate()
                    throw LoaderInstallCore.reject("The update helper did not become ready. Nothing was replaced.")
                }
                Store.settings.set(prepared.path, forKey: pendingKey)
                Store.settings.synchronize()
                // Uses the normal quit path: all windows and pending disk writes are saved.
                NSApp.terminate(nil)
            } catch {
                if let stage { try? FileManager.default.removeItem(at: stage) }
                if Task.isCancelled { state = .available(next) }
                else { state = .installFailed(error.localizedDescription) }
            }
        }
    }

    nonisolated private static func read(_ url: URL, limit: Int, progress: (@Sendable (Int) -> Void)? = nil) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Search-Appearance-Mod-Loader", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https", response.expectedContentLength <= limit else {
            throw LoaderRelease.Invalid.manifest
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { throw LoaderRelease.Invalid.manifest }
            data.append(byte)
            if data.count % 65536 == 0 { progress?(data.count) }
        }
        return data
    }
}

struct LoaderUpdatePanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var updates = LoaderUpdater.shared
    var body: some View {
        Card {
            Line("Appearance loader \(Updater.version)", "Based on Search \(LoaderUpdater.upstream) by Drice Roland / Office Commun. Mod support by Noah Helms.") {
                Pill(updates.state == .checking ? "Checking…" : "Check now") { updates.check() }
                    .disabled(updates.busy)
            }
            Rule()
            Line(title, detail) {
                if case .available = updates.state {
                    Pill("Download and Restart", filled: true) { updates.install() }
                } else if case .downloading = updates.state {
                    Pill("Cancel") { updates.cancelDownload() }
                } else if case .installFailed = updates.state {
                    Pill("Try again") { updates.check() }
                }
            }
            Rule()
            Line("Preview updates", "Checked daily through GitHub. Download and Restart verifies and installs the update, then reopens your saved tabs. Save unfinished forms first. Your profile and mods stay in place.") {
                Pill("Release history") {
                    browser.tuning = false
                    browser.open(URL(string: "https://github.com/haon-v2/search-appearance-mods/releases")!, foreground: true)
                }
            }
        }
    }
    private var title: String {
        switch updates.state {
        case .downloading: return "Downloading the update…"
        case .installing: return "Verifying and preparing to restart…"
        case .installFailed: return "Couldn’t install the update"
        case .unchecked: return "Compatible loader releases"
        case .checking: return "Checking for an update…"
        case .current: return "You have the latest compatible loader release"
        case .available(let next): return "Loader \(next.version) is available"
        case .incompatible: return "A newer loader requires a different system"
        case .failed: return "Couldn’t check for updates"
        }
    }
    private var detail: String {
        switch updates.state {
        case .available(let next): return "Includes Search \(next.upstreamVersion). Restarting restores saved tabs; save any unfinished forms first."
        case .downloading(_, let count): return String(format: "%.1f MB downloaded. Your browser stays open until verification finishes.", Double(count) / 1_000_000)
        case .installing: return "Checking the signed release, download and app before restarting."
        case .installFailed(let reason): return reason
        case .incompatible(let next): return "Loader \(next.version) needs macOS \(next.minimumSystemVersion)+ on \(next.architecture). Keep this build for now."
        case .failed: return "Check your connection and try again. No update has been installed."
        case .current: return "Future Search releases are checked before a compatible preview is published. Compatibility work may delay an update."
        default: return "Includes tested Search updates while preserving appearance-mod support."
        }
    }
}
