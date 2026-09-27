import Foundation

let tag = "appearance-mods-v0.2.0"
let base = "https://github.com/haon-v2/search-appearance-mods/releases/"
let good: [String: Any] = ["schemaVersion":1, "version":"0.2.0", "build":3, "upstreamVersion":"v1.0.3", "minimumSystemVersion":"14.0", "architecture":"arm64", "archive":base+"download/"+tag+"/"+LoaderRelease.archiveName, "sha256":String(repeating:"a",count:64), "releaseURL":base+"tag/"+tag]
func decode(_ input: [String: Any]) throws -> LoaderRelease {
    try JSONDecoder().decode(LoaderRelease.self, from: JSONSerialization.data(withJSONObject: input)).validated(tag: tag)
}
let release = try decode(good)
assert(release.build == 3)
assert(release.runs(on: .init(majorVersion:14,minorVersion:0,patchVersion:0), architecture:"arm64"))
assert(release.runs(on: .init(majorVersion:26,minorVersion:0,patchVersion:0), architecture:"arm64"))
assert(!release.runs(on: .init(majorVersion:13,minorVersion:9,patchVersion:9), architecture:"arm64"))
assert(!release.runs(on: .init(majorVersion:26,minorVersion:0,patchVersion:0), architecture:"x86_64"))
for (key,value) in [("schemaVersion",2 as Any),("build",0),("version","1.0.0"),("version","0.2.0/evil"),("upstreamVersion","garbage"),("minimumSystemVersion","14.x"),("architecture","anything"),("sha256","bad"),("archive","http://github.com/unsafe.zip"),("releaseURL","https://github.com/driceroland/Search/releases/tag/v1.0.3")] {
    var bad=good;bad[key]=value
    do { _ = try decode(bad); fatalError("Accepted invalid \(key)") } catch {}
}
for key in good.keys {
    var bad=good;bad.removeValue(forKey:key)
    do { _ = try decode(bad); fatalError("Accepted missing \(key)") } catch {}
}
let assetURL = base+"download/"+tag+"/loader-update.json"
func candidate(draft: Bool=false, manifest: String=assetURL, archive: Bool=true) throws -> LoaderGitHubRelease {
    var assets: [[String:String]] = [["name":"loader-update.json","browser_download_url":manifest]]
    if archive { assets.append(["name":LoaderRelease.archiveName,"browser_download_url":good["archive"] as! String]) }
    let json: [String:Any] = ["tag_name":tag,"draft":draft,"prerelease":true,"assets":assets]
    return try JSONDecoder().decode(LoaderGitHubRelease.self,from:JSONSerialization.data(withJSONObject:json))
}
let preview = try candidate();assert(preview.manifest != nil)
let draft = try candidate(draft:true);assert(draft.manifest == nil)
let incomplete = try candidate(archive:false);assert(incomplete.manifest == nil)
let foreign = try candidate(manifest:"https://example.com/loader-update.json");assert(foreign.manifest == nil)
print("PASS: loader feed identity, mandatory metadata, compatibility, prereleases and incomplete-release rejection")
