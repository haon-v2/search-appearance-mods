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
    }
    @Published private(set) var state: State = .unchecked
    @Published private(set) var lastChecked: Date?
    private var clock: Timer?
    private var say: ((String) -> Void)?
    private let lastKey = "appearance.loader.update.lastAttempt"

    func start(then announce: @escaping (String) -> Void) {
        guard Self.isPreview, !Store.testing else { return }
        say = announce
        if clock == nil {
            clock = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkIfDue() }
            }
            clock?.tolerance = 300
        }
        checkIfDue()
    }

    private func checkIfDue() {
        let last = Store.settings.object(forKey: lastKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= 20 * 3600 { check() }
    }

    func check() {
        guard Self.isPreview, state != .checking else { return }
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
                let next = try JSONDecoder().decode(LoaderRelease.self, from: payload).validated(tag: entry.tag_name)
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

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    private static func read(_ url: URL, limit: Int) async throws -> Data {
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
            guard data.count < limit else { throw LoaderRelease.Invalid.manifest }
            data.append(byte)
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
                    .disabled(updates.state == .checking)
            }
            Rule()
            Line(title, detail) {
                if case .available(let next) = updates.state {
                    Pill("Download update", filled: true) {
                        browser.tuning = false
                        browser.open(next.releaseURL, foreground: true)
                    }
                }
            }
            Rule()
            Line("Preview updates", "Checked daily through GitHub. Download, quit, and replace Search Mod Preview.app; its profile and mods stay in place. Official Search uses a separate update channel.") {
                Pill("Release history") {
                    browser.tuning = false
                    browser.open(URL(string: "https://github.com/haon-v2/search-appearance-mods/releases")!, foreground: true)
                }
            }
        }
    }
    private var title: String {
        switch updates.state {
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
        case .available(let next): return "Includes Search \(next.upstreamVersion). Downloading an official Search build would remove the loader."
        case .incompatible(let next): return "Loader \(next.version) needs macOS \(next.minimumSystemVersion)+ on \(next.architecture). Keep this build for now."
        case .failed: return "Check your connection and try again. No update has been installed."
        case .current: return "Future Search releases are checked before a compatible preview is published. Compatibility work may delay an update."
        default: return "Includes tested Search updates while preserving appearance-mod support."
        }
    }
}
