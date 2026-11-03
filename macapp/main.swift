// Downstage Find: a native window that finds Downstage devices and opens their apps in the browser.
// A web page can't ask the network who is there, so this does it: Bonjour first, since one question finds
// everything without sweeping (a sweep tripped UniFi's threat protection at a venue), then a typed address or a
// scan the person asks for, for networks that hide devices from each other.
import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!
    let finder = Finder()
    let updater = Updater()
    var loaded = false

    func applicationDidFinishLaunching(_ note: Notification) {
        buildMenu()
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "find")
        config.userContentController.add(updater, name: "updates")
        web = WKWebView(frame: .zero, configuration: config)
        updater.web = web
        web.uiDelegate = self
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Downstage Find"
        window.minSize = NSSize(width: 380, height: 300)
        window.backgroundColor = NSColor(red: 0x0B / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0, alpha: 1)
        window.contentView = web
        window.center()
        window.setFrameAutosaveName("DownstageFind")
        window.makeKeyAndOrderFront(nil)
        let root = Bundle.main.resourceURL!.appendingPathComponent("web")
        web.loadFileURL(root.appendingPathComponent("find.html"), allowingReadAccessTo: root)
        finder.changed = { [weak self] in self?.tell() }
        finder.say = { [weak self] text, warn in self?.call("window.findSay(\(self?.quoted(text) ?? "''"), \(warn))") }
        finder.scanState = { [weak self] running in self?.call("window.scanState(\(running))") }
        finder.start()
        #if UPDATE_TEST
        if let h = ProcessInfo.processInfo.environment["DOWNSTAGE_TEST_ADD"] { finder.add(h) }
        #endif
    }
    func quoted(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
        return String(String(decoding: d, as: UTF8.self).dropFirst().dropLast())
    }
    func call(_ js: String) { if loaded { web.evaluateJavaScript(js, completionHandler: nil) } }
    func tell() {
        guard let data = try? JSONSerialization.data(withJSONObject: finder.devices.values.map { $0.json }) else { return }
        #if UPDATE_TEST
        if ProcessInfo.processInfo.environment["DOWNSTAGE_TEST_LOG"] != nil { print(String(decoding: data, as: UTF8.self)); fflush(stdout) }
        #endif
        call("window.devices(\(String(decoding: data, as: UTF8.self)))")
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; tell() }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let action = m["action"] as? String else { return }
        switch action {
        case "open":
            // only our own http pages on the local network: the page gives the address, never a file or another scheme
            if let s = m["url"] as? String, let u = URL(string: s), u.scheme == "http" { NSWorkspace.shared.open(u) }
        case "refresh": finder.refresh()
        case "scan": finder.scan()
        case "add": if let h = m["host"] as? String { finder.add(h) }
        case "identify": if let k = m["key"] as? String { finder.blink(k) }
        case "bright": if let k = m["key"] as? String, let p = m["pct"] as? Int { finder.bright(k, part: m["part"] as? String ?? "light", pct: p) }
        default: break
        }
    }
    // the page's confirm() for the scan
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let parts = message.components(separatedBy: "\n\n")
        let a = NSAlert()
        a.messageText = parts.first ?? ""
        a.informativeText = parts.dropFirst().joined(separator: "\n\n")
        a.addButton(withTitle: "Scan")
        a.addButton(withTitle: "Cancel")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }
    @objc func checkForUpdates() {
        web.evaluateJavaScript("window.updAsked = true") { _, _ in self.updater.check() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Downstage Find", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Downstage Find", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
