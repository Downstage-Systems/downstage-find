// Downstage Find: a native window that finds Downstage devices and opens their apps in the browser.
// A web page can't ask the network who is there, so this does it: Bonjour first, since one question finds
// everything without sweeping (a sweep tripped UniFi's threat protection at a venue), then a typed address or a
// scan the person asks for, for networks that hide devices from each other.
// The window follows downstage-clients/docs/mac-app-standard.md: the page's toolbar is the title bar, the menus
// carry every command, and Find's own Settings live in their own window.
import Cocoa
import WebKit

let ground = NSColor(srgbRed: 0x0B / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0, alpha: 1)   // brand Ground: no white flash
let toolbarHeight: CGFloat = 52                     // the page's toolbar is the window's title bar
let helpURL = "https://downstage.systems/support/apps/downstage-find/"

// The page draws the title bar, so the web view moves the window: a press on the toolbar's empty space drags it,
// a double-click zooms or minimizes as System Settings says. The page reports where its controls are.
final class DragWebView: WKWebView {
    var barHeight: CGFloat = toolbarHeight          // in the page's own pixels
    var controls: [NSRect] = []                     // the toolbar's buttons and fields, top-left origin, page pixels
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        let z = max(pageZoom, 0.1)
        let x = p.x / z, y = (isFlipped ? p.y : bounds.height - p.y) / z
        if let w = window, y < barHeight, !controls.contains(where: { $0.contains(NSPoint(x: x, y: y)) }) {
            if e.clickCount == 2 {
                let act = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
                if act == "Minimize" { w.performMiniaturize(nil) } else if act != "None" { w.performZoom(nil) }
            } else {
                w.performDrag(with: e)
            }
            return
        }
        super.mouseDown(with: e)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation,
                         WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: DragWebView!
    let finder = Finder()
    let updater = Updater()
    let settings = SettingsWindow()
    var loaded = false
    var state: [String: Bool] = [:]       // the page's detail pane, for the View menu

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMenu()
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "find")
        config.userContentController.add(updater, name: "updates")
        // the page leaves room for the traffic lights in its toolbar, and knows it is in the Mac app
        config.userContentController.addUserScript(WKUserScript(source: "window.downstageMac = true; document.documentElement.style.setProperty('--tb-l', '66px');",
                                                                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = DragWebView(frame: .zero, configuration: config)
        updater.web = web
        web.uiDelegate = self
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")    // the window's Ground shows until the page paints
        let z = UserDefaults.standard.double(forKey: "zoom")
        if z >= 0.5 && z <= 2 { web.pageZoom = CGFloat(z) }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Downstage Find"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        if #available(macOS 11.0, *) { window.titlebarSeparatorStyle = .none }
        window.minSize = NSSize(width: 520, height: 360)
        window.backgroundColor = ground
        window.isMovableByWindowBackground = false
        window.contentView = web
        window.delegate = self
        window.setFrameAutosaveName("DownstageFindMain")
        if !window.setFrameUsingName("DownstageFindMain") { window.center() }
        placeLights()
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

    // the traffic lights sit in the middle of the page's 52 pt toolbar, not in a 28 pt strip above it
    func placeLights() {
        guard let close = window.standardWindowButton(.closeButton), let bar = close.superview?.superview,
              !window.styleMask.contains(.fullScreen) else { return }
        var f = bar.frame; f.size.height = toolbarHeight; f.origin.y = window.frame.height - toolbarHeight; bar.frame = f
        for (i, t) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let b = window.standardWindowButton(t) else { continue }
            b.setFrameOrigin(NSPoint(x: 20 + CGFloat(i) * 20, y: (toolbarHeight - b.frame.height) / 2))
        }
    }
    func windowDidResize(_ n: Notification) { placeLights() }
    func windowDidEndLiveResize(_ n: Notification) { placeLights() }
    func windowWillEnterFullScreen(_ n: Notification) { call("document.body.classList.add('macfs')") }
    func windowDidExitFullScreen(_ n: Notification) { call("document.body.classList.remove('macfs')"); placeLights() }

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
        case "forget": if let k = m["key"] as? String { finder.forget(k) }
        case "copy":
            if let t = m["text"] as? String { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string) }
        case "bright": if let k = m["key"] as? String, let p = m["pct"] as? Int { finder.bright(k, part: m["part"] as? String ?? "light", pct: p) }
        case "dragzone":
            web.barHeight = CGFloat(m["height"] as? Double ?? Double(toolbarHeight))
            web.controls = (m["rects"] as? [[Double]] ?? []).filter { $0.count == 4 }.map { NSRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
        case "state":
            for (k, v) in m where k != "action" { if let on = v as? Bool { state[k] = on } }
        default: break
        }
    }

    // alerts drop down from the window as sheets; before the window is up, a plain panel
    func sheet(_ a: NSAlert, _ done: @escaping (NSApplication.ModalResponse) -> Void) {
        if let w = window, w.isVisible, w.attachedSheet == nil { a.beginSheetModal(for: w, completionHandler: done) }
        else { done(a.runModal()) }
    }
    func webView(_ w: WKWebView, runJavaScriptAlertPanelWithMessage m: String, initiatedByFrame f: WKFrameInfo, completionHandler done: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = m; a.addButton(withTitle: "OK"); sheet(a) { _ in done() }
    }
    func webView(_ w: WKWebView, runJavaScriptConfirmPanelWithMessage m: String, initiatedByFrame f: WKFrameInfo, completionHandler done: @escaping (Bool) -> Void) {
        let parts = m.components(separatedBy: "\n\n")
        let a = NSAlert(); a.messageText = parts.first ?? ""; a.informativeText = parts.dropFirst().joined(separator: "\n\n")
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        sheet(a) { done($0 == .alertFirstButtonReturn) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    // ---- menus: each item asks the page to do what its own controls do
    func page(_ cmd: String) { call("window.findCmd && window.findCmd('\(cmd)')") }
    @objc func addCmd() { page("add") }
    @objc func scanCmd() { page("scan") }
    @objc func lookCmd() { page("look") }
    @objc func searchCmd() { page("search") }
    @objc func detailCmd() { page("detail") }
    @objc func zoomIn() { setZoom(web.pageZoom + 0.1) }
    @objc func zoomOut() { setZoom(web.pageZoom - 0.1) }
    @objc func zoomReset() { setZoom(1) }
    func setZoom(_ z: CGFloat) {
        let v = min(2, max(0.5, (z * 10).rounded() / 10))
        web.pageZoom = v
        UserDefaults.standard.set(Double(v), forKey: "zoom")
    }
    @objc func showSettings() { settings.show() }
    @objc func link(_ s: NSMenuItem) { if let u = s.representedObject as? URL { NSWorkspace.shared.open(u) } }
    @objc func checkForUpdates() {
        web.evaluateJavaScript("window.updAsked = true") { _, _ in self.updater.check() }
    }
    @objc func about() {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let credits = NSAttributedString(string: "Built by Rob Spradling, Downstage Systems LLC.\nFinds Downstage devices on your network and opens their Settings.",
                                         attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: p])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(detailCmd):
            item.title = (state["detail"] ?? false) ? "Hide Details" : "Show Details"
            return loaded && (state["selected"] ?? false)
        case #selector(addCmd), #selector(lookCmd), #selector(searchCmd): return loaded
        case #selector(scanCmd): return loaded && !(state["scanning"] ?? false)
        case #selector(zoomIn): return web.pageZoom < 2
        case #selector(zoomOut): return web.pageZoom > 0.5
        default: return true
        }
    }

    func buildMenu() {
        func item(_ title: String, _ sel: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: key); i.target = self; i.keyEquivalentModifierMask = mods; return i
        }
        func linkItem(_ title: String, _ url: String) -> NSMenuItem {
            let i = item(title, #selector(link(_:))); i.representedObject = URL(string: url); return i
        }
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(item("About Downstage Find", #selector(about)))
        appMenu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(showSettings), ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Downstage Find", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]; appMenu.addItem(others)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Downstage Find", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(item("Add by Address…", #selector(addCmd), "n"))
        file.addItem(item("Scan Network…", #selector(scanCmd)))
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = file

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(item("Find…", #selector(searchCmd), "f"))
        editItem.submenu = edit

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.addItem(item("Look Again", #selector(lookCmd), "r"))
        view.addItem(item("Show Details", #selector(detailCmd), "i", [.command, .option]))
        view.addItem(.separator())
        view.addItem(item("Zoom In", #selector(zoomIn), "+"))
        view.addItem(item("Zoom Out", #selector(zoomOut), "-"))
        view.addItem(item("Actual Size", #selector(zoomReset), "0"))
        view.addItem(.separator())
        let fs = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]; view.addItem(fs)
        viewItem.submenu = view

        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        winItem.submenu = win
        NSApp.windowsMenu = win

        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(linkItem("Downstage Find Help", helpURL))
        help.addItem(.separator())
        help.addItem(linkItem("Suggest a Feature…", "mailto:hello@downstage.systems?subject=Downstage%20Find%20idea"))
        help.addItem(linkItem("Email Us", "mailto:hello@downstage.systems?subject=Downstage%20Find"))
        help.addItem(.separator())
        help.addItem(linkItem("downstage.systems", "https://downstage.systems/"))
        helpItem.submenu = help
        NSApp.helpMenu = help
        NSApp.mainMenu = main
    }
}

// Find's own Settings (⌘,): a small native window. It holds the switches for remembered devices, the menu bar and
// alerts as they arrive (steps 3 and 4 of the 2026-11-10 brief), and nothing else.
final class SettingsWindow: NSObject, NSWindowDelegate {
    var window: NSWindow?
    func show() {
        if window == nil { build() }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 160), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Settings"
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(srgbRed: 0x12 / 255.0, green: 0x16 / 255.0, blue: 0x1B / 255.0, alpha: 1)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        let head = NSTextField(labelWithString: "Downstage Find")
        head.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString: "Nothing to set yet. Remembered devices, the menu bar and alerts are switched on and off here.")
        body.font = NSFont.systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = 392
        stack.addArrangedSubview(head)
        stack.addArrangedSubview(body)
        w.contentView = stack
        w.delegate = self
        window = w
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
