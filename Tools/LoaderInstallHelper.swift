import AppKit
import Foundation

@main
struct LoaderInstallHelper {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 5, let pid = Int32(args[3]), pid > 1, let build = Int(args[4]) else { exit(2) }
        let stage = URL(fileURLWithPath: args[1]).standardizedFileURL
        let app = URL(fileURLWithPath: args[2]).standardizedFileURL
        guard LoaderInstallCore.validStage(stage, app: app) else { exit(2) }
        do {
            try LoaderInstallCore.target(app, build: build)
            try "ready".write(to: stage.appendingPathComponent("ready"), atomically: true, encoding: .utf8)
            let deadline = Date().addingTimeInterval(120)
            while kill(pid, 0) == 0 {
                guard Date() < deadline else { throw LoaderInstallCore.reject("The browser did not quit. Nothing was replaced; please try again.") }
                Thread.sleep(forTimeInterval: 0.2)
            }
            try LoaderInstallCore.install(stage: stage, app: app, currentBuild: build) { app in
                var arguments = ["-n"]
                if let probe = ProcessInfo.processInfo.environment["SEARCH_PROBE"] {
                    arguments += ["--env", "SEARCH_PROBE=\(probe)"]
                }
                try LoaderInstallCore.run("/usr/bin/open", arguments + [app.path])
            }
        } catch {
            try? ("failed: " + error.localizedDescription).write(to: stage.appendingPathComponent("result"), atomically: true, encoding: .utf8)
            // Relaunch the old app only if it actually quit and is back in place.
            if kill(pid, 0) != 0, (try? LoaderInstallCore.target(app, build: build)) != nil {
                var arguments = ["-n"]
                if let probe = ProcessInfo.processInfo.environment["SEARCH_PROBE"] { arguments += ["--env", "SEARCH_PROBE=\(probe)"] }
                try? LoaderInstallCore.run("/usr/bin/open", arguments + [app.path])
            }
            exit(1)
        }
    }
}
