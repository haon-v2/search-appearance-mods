import Foundation
import CryptoKit
import Security

/// Shared with the small post-exit helper. No profile files are read or moved.
enum LoaderInstallCore {
    static let identifier = "local.noah.search.mod-preview"
    static let maximumArchiveBytes = 64 * 1024 * 1024
    static let stagePrefix = ".search-loader-update-"
    // Generated once; the corresponding private key lives only in GitHub Actions secrets.
    static let publicKey = "TGrb5k2b5lT3G8oQQQ/pL464B5DsGwQIORzodhxzkTA="

    enum Failure: LocalizedError {
        case refused(String)
        var errorDescription: String? { if case .refused(let message) = self { return message }; return nil }
    }
    static func reject(_ message: String) -> Failure { .refused(message) }

    static func authenticated(_ data: Data, signature: Data, key: String = publicKey) throws -> LoaderRelease {
        guard data.count <= 32768, signature.count == 64,
              let raw = Data(base64Encoded: key),
              let signingKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              signingKey.isValidSignature(signature, for: data) else {
            throw reject("The update’s release signature could not be verified.")
        }
        let release = try JSONDecoder().decode(LoaderRelease.self, from: data)
        return try release.validated(tag: "appearance-mods-v\(release.version)")
    }

    static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw reject("The update step \(URL(fileURLWithPath: tool).lastPathComponent) failed (\(process.terminationStatus)).") }
    }

    static func info(_ app: URL) throws -> [String: Any] {
        let file = app.appendingPathComponent("Contents/Info.plist")
        guard let dictionary = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any] else {
            throw reject("The update is not a valid application.")
        }
        return dictionary
    }

    static func target(_ app: URL, build: Int) throws {
        let files = FileManager.default
        let canonical = app.standardizedFileURL.resolvingSymlinksInPath()
        guard canonical == app.standardizedFileURL, app.pathExtension == "app",
              !app.path.contains("/AppTranslocation/"), !app.path.hasPrefix("/Volumes/"),
              files.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            throw reject("Move Search Mod Preview to a writable Applications folder, then try again. This copy cannot be updated here.")
        }
        let metadata = try info(app)
        guard metadata["CFBundleIdentifier"] as? String == identifier,
              Int(metadata["CFBundleVersion"] as? String ?? "") == build else {
            throw reject("This app has changed since the update started. Reopen it and check again.")
        }
    }

    static func verify(_ app: URL, release: LoaderRelease) throws {
        let metadata = try info(app)
        guard metadata["CFBundleIdentifier"] as? String == identifier,
              metadata["CFBundleExecutable"] as? String == "SearchModPreview",
              metadata["CFBundleShortVersionString"] as? String == release.version,
              Int(metadata["CFBundleVersion"] as? String ?? "") == release.build,
              metadata["SearchUpstreamVersion"] as? String == release.upstreamVersion,
              metadata["LSMinimumSystemVersion"] as? String == release.minimumSystemVersion else {
            throw reject("The downloaded app does not match the signed release.")
        }
        var code: SecStaticCode?
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess,
              let code, SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
            throw reject("The downloaded app’s code signature is invalid.")
        }
        // Inspect the ARM64 Mach-O header without requiring Xcode command-line tools.
        let executable = try FileHandle(forReadingFrom: app.appendingPathComponent("Contents/MacOS/SearchModPreview"))
        defer { try? executable.close() }
        guard try executable.read(upToCount: 8) == Data([0xcf, 0xfa, 0xed, 0xfe, 0x0c, 0x00, 0x00, 0x01]) else {
            throw reject("The update executable is not an ARM64 Mac app.")
        }
    }

    static func unpack(_ stage: URL, release: LoaderRelease) throws -> URL {
        let archive = stage.appendingPathComponent("update.zip")
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard data.count <= maximumArchiveBytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == release.sha256 else {
            throw reject("The update download is incomplete or has changed.")
        }
        // Only a pinned-key authenticated archive reaches the system extractor.
        let output = stage.appendingPathComponent("unpacked")
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, output.path])
        let fresh = output.appendingPathComponent("Search Appearance Mod Loader/Search Mod Preview.app")
        guard fresh.resolvingSymlinksInPath() == fresh else { throw reject("The update contains an unexpected link.") }
        try verify(fresh, release: release)
        return fresh
    }

    static func prepare(archive: URL, data: Data, signature: Data, app: URL, currentBuild: Int) throws -> URL {
        let release = try authenticated(data, signature: signature)
        guard release.build > currentBuild,
              release.runs(on: ProcessInfo.processInfo.operatingSystemVersion, architecture: architecture) else {
            throw reject("This update is older than the installed app or is incompatible with this Mac.")
        }
        try target(app, build: currentBuild)
        let files = FileManager.default
        let stage = app.deletingLastPathComponent().appendingPathComponent(stagePrefix + UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try files.copyItem(at: archive, to: stage.appendingPathComponent("update.zip"))
            try data.write(to: stage.appendingPathComponent("manifest.json"))
            try signature.write(to: stage.appendingPathComponent("manifest.sig"))
            _ = try unpack(stage, release: release)
            return stage
        } catch {
            try? files.removeItem(at: stage)
            throw error
        }
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    static func validStage(_ stage: URL, app: URL) -> Bool {
        stage.deletingLastPathComponent() == app.deletingLastPathComponent()
            && stage.resolvingSymlinksInPath() == stage
            && stage.lastPathComponent.hasPrefix(stagePrefix)
            && UUID(uuidString: String(stage.lastPathComponent.dropFirst(stagePrefix.count))) != nil
    }

    /// Swaps only after the old process exits. The old bundle stays available
    /// until the new app starts and acknowledges success. A failed launch rolls back.
    static func install(stage: URL, app: URL, currentBuild: Int, launch: (URL) throws -> Void) throws {
        guard validStage(stage, app: app) else { throw reject("Invalid update staging folder.") }
        let release = try authenticated(Data(contentsOf: stage.appendingPathComponent("manifest.json")),
                                        signature: Data(contentsOf: stage.appendingPathComponent("manifest.sig")))
        guard release.build > currentBuild,
              release.runs(on: ProcessInfo.processInfo.operatingSystemVersion, architecture: architecture) else {
            throw reject("Refusing an older or incompatible update.")
        }
        try target(app, build: currentBuild)
        // Re-extract and verify after quitting; don't trust the previously unpacked copy.
        let fresh = try unpack(stage, release: release)
        let files = FileManager.default
        let backup = stage.appendingPathComponent("Previous.app")
        guard !files.fileExists(atPath: backup.path) else { throw reject("An earlier update is still awaiting recovery.") }
        try files.moveItem(at: app, to: backup)
        do {
            try files.moveItem(at: fresh, to: app)
            try "installed".write(to: stage.appendingPathComponent("result"), atomically: true, encoding: .utf8)
            try launch(app)
        } catch {
            if files.fileExists(atPath: app.path) { try files.removeItem(at: app) }
            try files.moveItem(at: backup, to: app)
            throw error
        }
    }
}
