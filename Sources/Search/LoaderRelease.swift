import Foundation

/// The community channel is separate from Office Commun's signed appcast.
/// Only a release with completed compatibility checks gets this manifest.
struct LoaderRelease: Decodable, Equatable {
    static let repository = "haon-v2/search-appearance-mods"
    static let archiveName = "Search-Appearance-Mod-Loader-macOS-arm64.zip"
    let schemaVersion: Int
    let version: String
    let build: Int
    let upstreamVersion: String
    let minimumSystemVersion: String
    let architecture: String
    let archive: URL
    let sha256: String
    let releaseURL: URL

    enum Invalid: Error { case manifest }
    func validated(tag: String) throws -> Self {
        let base = "https://github.com/\(Self.repository)/releases/"
        guard schemaVersion == 1, build > 0,
              version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              tag == "appearance-mods-v\(version)",
              upstreamVersion.range(of: #"^v?\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              minimumSystemVersion.range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              architecture == "arm64",
              sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
              releaseURL.absoluteString == base + "tag/" + tag,
              archive.absoluteString == base + "download/" + tag + "/" + Self.archiveName
        else { throw Invalid.manifest }
        return self
    }

    func runs(on system: OperatingSystemVersion, architecture host: String) -> Bool {
        let parts = minimumSystemVersion.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2, architecture == host else { return false }
        let current = [system.majorVersion, system.minorVersion, system.patchVersion]
        let minimum = [parts[0], parts[1], parts.count > 2 ? parts[2] : 0]
        return !current.lexicographicallyPrecedes(minimum)
    }
}

struct LoaderGitHubRelease: Decodable {
    let tag_name: String
    let draft: Bool
    let assets: [Asset]
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
    }
    var manifest: URL? {
        guard !draft, tag_name.range(of: #"^appearance-mods-v\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              assets.contains(where: { $0.name == LoaderRelease.archiveName }),
              let asset = assets.first(where: { $0.name == "loader-update.json" }),
              asset.browser_download_url.absoluteString == "https://github.com/\(LoaderRelease.repository)/releases/download/\(tag_name)/loader-update.json"
        else { return nil }
        return asset.browser_download_url
    }
}
