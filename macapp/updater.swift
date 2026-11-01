// Updates from GitHub Releases: check, download, verify, swap the app, relaunch.
// The page draws the update strip; this does the work and tells it what's happening.
import Cocoa
import WebKit

final class Updater: NSObject, WKScriptMessageHandler {
    static let repo = "Downstage-Systems/downstage-find"
    weak var web: WKWebView?
    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    var state: [String: Any] = ["status": "idle"]
    var assetURL: URL?
    var latest = ""
    var busy = false

    var feed: URL {
        #if UPDATE_TEST
        if let s = ProcessInfo.processInfo.environment["DOWNSTAGE_UPDATE_FEED"], let u = URL(string: s) { return u }
        #endif
        return URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!
    }

    // 2026.10.30.1 is newer than 2026.10.30
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    func publish(_ s: [String: Any]) {
        state = s
        var out = s; out["version"] = current
        guard let data = try? JSONSerialization.data(withJSONObject: out), let json = String(data: data, encoding: .utf8) else { return }
        #if UPDATE_TEST
        print("update", json); fflush(stdout)
        #endif
        DispatchQueue.main.async { self.web?.evaluateJavaScript("window.updateState && window.updateState(\(json))") }
    }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        switch m.body as? String {
        case "ready": publish(state); if (state["status"] as? String) == "idle" { check() }
        case "check": check()
        case "install": install()
        default: break
        }
    }

    func fail(_ msg: String) { busy = false; publish(["status": "error", "message": msg]) }

    func check() {
        if busy { return }
        busy = true; publish(["status": "checking"])
        var req = URLRequest(url: feed); req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Downstage-Find", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            self.busy = false
            if err != nil { self.fail("Can't reach GitHub. Check this Mac's internet connection."); return }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { self.publish(["status": "current", "message": "No releases published yet."]); return }
            guard code == 200, let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let tag = j["tag_name"] as? String else { self.fail("GitHub answered, but not with a release (\(code))."); return }
            let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            guard Updater.isNewer(v, than: self.current) else { self.publish(["status": "current"]); return }
            let zip = (j["assets"] as? [[String: Any]] ?? []).first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
            guard let s = zip?["browser_download_url"] as? String, let u = URL(string: s) else {
                self.fail("Version \(v) is out, but it has no zip attached yet."); return }
            self.assetURL = u; self.latest = v
            self.publish(["status": "available", "latest": v, "notes": j["body"] as? String ?? ""])
            #if UPDATE_TEST
            if ProcessInfo.processInfo.environment["DOWNSTAGE_UPDATE_AUTO"] != nil { self.install() }
            #endif
        }.resume()
    }

    func install() {
        guard !busy, let url = assetURL else { return }
        let app = Bundle.main.bundleURL
        if app.path.contains("/AppTranslocation/") { fail("Drag the app into Applications first, then open it from there."); return }
        if !FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) {
            fail("This Mac won't let the app replace itself where it is. Move it to Applications and try again."); return }
        busy = true; publish(["status": "downloading", "latest": latest])
        URLSession.shared.downloadTask(with: url) { file, resp, err in
            guard err == nil, let file = file, ((resp as? HTTPURLResponse)?.statusCode ?? 200) == 200 else {
                self.fail("The download didn't finish. Nothing changed."); return }
            do { try self.swap(zip: file) } catch { self.fail("\(error.localizedDescription) Nothing changed.") }
        }.resume()
    }

    func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func refuse(_ why: String) -> NSError { NSError(domain: "update", code: 1, userInfo: [NSLocalizedDescriptionKey: why]) }

    func swap(zip: URL) throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("downstage-find-update-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let z = dir.appendingPathComponent("update.zip"); try fm.moveItem(at: zip, to: z)
        let out = dir.appendingPathComponent("new"); try fm.createDirectory(at: out, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", z.path, out.path]) else { throw refuse("The download isn't a readable zip.") }
        let items = try fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
        guard items.count == 1, let new = Bundle(url: items[0]) else { throw refuse("The download has no app in it.") }
        guard new.bundleIdentifier == Bundle.main.bundleIdentifier else { throw refuse("The download is a different app.") }
        guard let v = new.infoDictionary?["CFBundleShortVersionString"] as? String, Updater.isNewer(v, than: current) else {
            throw refuse("The download isn't newer than this version.") }
        // A signed app only takes an update signed by a team it lists (signing.conf). An unsigned one, or a test build, lists none
        var verify = ["--verify", "--deep", "--strict"]
        let teams = Bundle.main.infoDictionary?["DownstageAllowedTeams"] as? [String] ?? []
        if !teams.isEmpty { verify.append("-R=anchor apple generic and (" + teams.map { "certificate leaf[subject.OU] = \"\($0)\"" }.joined(separator: " or ") + ")") }
        guard run("/usr/bin/codesign", verify + [items[0].path]) else { throw refuse("The download failed its signature check.") }
        // the swap happens after this app has quit; a failed move puts the old app back
        let script = dir.appendingPathComponent("swap.sh")
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let app = Bundle.main.bundleURL.path
        try """
        #!/bin/bash
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        if mv \(q(app)) \(q(dir.appendingPathComponent("old.app").path)); then
          mv \(q(items[0].path)) \(q(app)) || mv \(q(dir.appendingPathComponent("old.app").path)) \(q(app))
        fi
        open \(q(app))
        """.write(to: script, atomically: true, encoding: .utf8)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = [script.path]
        try p.run()
        publish(["status": "installing", "latest": v])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }
}
