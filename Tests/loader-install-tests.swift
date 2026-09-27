import Foundation
import CryptoKit

let files = FileManager.default
let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEST_LOADER_ROOT"]!).resolvingSymlinksInPath()
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: ProcessInfo.processInfo.environment["TEST_LOADER_PRIVATE"]!)!)
func rejects(_ label: String, _ body: () throws -> Void) {
    do { try body(); fatalError("Accepted: \(label)") } catch {}
}
let parent = root.appendingPathComponent("Apps with spaces")
try files.createDirectory(at: parent, withIntermediateDirectories: true)
let target = parent.appendingPathComponent("Search Mod Preview.app")
let profile = root.appendingPathComponent("profile-sentinel")
try "saved tabs and mods".write(to: profile, atomically: true, encoding: .utf8)
let fixture = root.appendingPathComponent("fixture.swift")
try """
import Foundation
if let path=ProcessInfo.processInfo.environment["SEARCH_PROBE"] {
    try? "reopened".write(toFile: path, atomically: true, encoding: .utf8)
}
""".write(to: fixture, atomically: true, encoding: .utf8)
let executable = root.appendingPathComponent("fixture")
try LoaderInstallCore.run("/usr/bin/xcrun", ["swiftc", "-target", "arm64-apple-macos14.0", fixture.path, "-o", executable.path])
func app(_ at: URL, build: Int, identifier: String = LoaderInstallCore.identifier) throws {
    try files.createDirectory(at: at.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    try files.copyItem(at: executable, to: at.appendingPathComponent("Contents/MacOS/SearchModPreview"))
    let info: [String: Any] = ["CFBundleIdentifier":identifier,"CFBundleExecutable":"SearchModPreview", "CFBundlePackageType":"APPL", "CFBundleName":"Loader Update Test", "LSUIElement":true,"CFBundleShortVersionString":"0.4.0", "CFBundleVersion":String(build),"SearchUpstreamVersion":"v1.0.4","LSMinimumSystemVersion":"14.0"]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: at.appendingPathComponent("Contents/Info.plist"))
    try LoaderInstallCore.run("/usr/bin/codesign", ["--force","--sign","-",at.path])
}
try app(target, build: 6)
let package = root.appendingPathComponent("Search Appearance Mod Loader")
try app(package.appendingPathComponent("Search Mod Preview.app"), build: 7)
let archive = root.appendingPathComponent("good.zip")
try LoaderInstallCore.run("/usr/bin/ditto", ["-c","-k","--keepParent",package.path,archive.path])
let hash = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
let base = "https://github.com/haon-v2/search-appearance-mods/releases/"
var manifest: [String: Any] = ["schemaVersion":1,"version":"0.4.0","build":7,"upstreamVersion":"v1.0.4","minimumSystemVersion":"14.0","architecture":"arm64","sha256":hash,"archive":base+"download/appearance-mods-v0.4.0/"+LoaderRelease.archiveName,"releaseURL":base+"tag/appearance-mods-v0.4.0"]
let data = try JSONSerialization.data(withJSONObject: manifest)
let sig = try key.signature(for: data)
let release = try LoaderInstallCore.authenticated(data, signature: sig)
assert(release.build == 7)
rejects("unsigned manifest") { _ = try LoaderInstallCore.authenticated(data, signature: Data()) }
rejects("changed manifest") { _ = try LoaderInstallCore.authenticated(data + Data([32]), signature: sig) }
rejects("foreign signing key") { _ = try LoaderInstallCore.authenticated(data, signature: Curve25519.Signing.PrivateKey().signature(for: data)) }
rejects("wrong target build") { try LoaderInstallCore.target(target, build: 5) }
let official = parent.appendingPathComponent("Search.app")
try app(official, build: 6, identifier:"com.officecommun.search")
rejects("official Search") { try LoaderInstallCore.target(official, build: 6) }
let link = parent.appendingPathComponent("Link.app")
try files.createSymbolicLink(at: link, withDestinationURL: target)
rejects("symlink target") { try LoaderInstallCore.target(link, build: 6) }
let badArchive = root.appendingPathComponent("corrupt.zip")
try Data("broken".utf8).write(to: badArchive)
rejects("corrupt archive") { _ = try LoaderInstallCore.prepare(archive: badArchive,data:data,signature:sig,app:target,currentBuild:6) }
assert(try! LoaderInstallCore.info(target)["CFBundleVersion"] as? String == "6")
func stage() throws -> URL { try LoaderInstallCore.prepare(archive: archive,data:data,signature:sig,app:target,currentBuild:6) }
let rollback = try stage()
rejects("failed launch") {
    try LoaderInstallCore.install(stage: rollback, app: target, currentBuild: 6) { _ in throw LoaderInstallCore.reject("Simulated launch failure") }
}
assert(try! LoaderInstallCore.info(target)["CFBundleVersion"] as? String == "6")
let tampered = try stage()
try Data("bad".utf8).write(to: tampered.appendingPathComponent("update.zip"))
rejects("archive changed after preparation") { try LoaderInstallCore.install(stage:tampered,app:target,currentBuild:6) { _ in fatalError("Launched unverified app") } }
let wrongApp = package.appendingPathComponent("Search Mod Preview.app")
try "changed".write(to: wrongApp.appendingPathComponent("Contents/MacOS/SearchModPreview"), atomically:true,encoding:.utf8)
rejects("broken app signature") { try LoaderInstallCore.verify(wrongApp, release: release) }
// The real helper must leave the old bundle untouched while its parent runs.
let prepared = try stage()
let oldProcess = Process();oldProcess.executableURL=URL(fileURLWithPath:"/bin/sleep");oldProcess.arguments=["60"];try oldProcess.run()
let reopened = root.appendingPathComponent("reopened")
let helper = Process();helper.executableURL=URL(fileURLWithPath:ProcessInfo.processInfo.environment["TEST_LOADER_HELPER"]!)
helper.arguments=[prepared.path,target.path,String(oldProcess.processIdentifier),"6"]
helper.environment=ProcessInfo.processInfo.environment.merging(["SEARCH_PROBE":reopened.path]) { _, new in new }
try helper.run()
for _ in 0..<100 {
    if files.fileExists(atPath:prepared.appendingPathComponent("ready").path) { break }
    Thread.sleep(forTimeInterval:0.05)
}
assert(files.fileExists(atPath:prepared.appendingPathComponent("ready").path))
Thread.sleep(forTimeInterval:0.3)
assert(try! LoaderInstallCore.info(target)["CFBundleVersion"] as? String == "6")
assert(!files.fileExists(atPath:reopened.path))
oldProcess.terminate();oldProcess.waitUntilExit()
for _ in 0..<200 { if !helper.isRunning { break };Thread.sleep(forTimeInterval:0.05) }
if helper.isRunning { helper.terminate();fatalError("Installer helper timed out") }
assert(helper.terminationStatus==0)
for _ in 0..<100 { if files.fileExists(atPath:reopened.path) { break };Thread.sleep(forTimeInterval:0.1) }
assert(files.fileExists(atPath:reopened.path),"Updated app did not relaunch")
assert(try! LoaderInstallCore.info(target)["CFBundleVersion"] as? String == "7")
assert(try! String(contentsOf:profile,encoding:.utf8)=="saved tabs and mods")
rejects("downgrade") { _ = try LoaderInstallCore.prepare(archive:archive,data:data,signature:sig,app:target,currentBuild:7) }
assert(files.fileExists(atPath:prepared.appendingPathComponent("Previous.app").path))
print("PASS: authentication, tampering, target identity, downgrade prevention, rollback, quit wait, relaunch and profile isolation")
