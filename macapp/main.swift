// Downstage Find: a native window that finds Downstage devices and opens their apps in the browser.
// A web page can't ask the network who is there, so this does it: Bonjour first, since one question finds
// everything without sweeping (a sweep tripped UniFi's threat protection at a venue), then a typed address or a
// scan the person asks for, for networks that hide devices from each other.
// The window follows downstage-clients/docs/mac-app-standard.md: the page's toolbar is the title bar, the menus
// carry every command, and Find's own Settings live in their own window.
import Cocoa
import WebKit
import UserNotifications
import ServiceManagement

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
                         WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, UNUserNotificationCenterDelegate {
    var window: NSWindow!
    var web: DragWebView!
    let finder = Finder()
    let updater = Updater()
    let settings = SettingsWindow()
    var loaded = false
    var state: [String: Bool] = [:]       // the page's detail pane, for the View menu
    let alerts = Alerts()
    var bar: MenuBar?                     // only while "Show in menu bar" is on
    var alertTimer: Timer?

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
        finder.changed = { [weak self] in self?.tell(); self?.watch() }
        finder.say = { [weak self] text, warn in self?.call("window.findSay(\(self?.quoted(text) ?? "''"), \(warn))") }
        finder.scanState = { [weak self] running in self?.call("window.scanState(\(running))") }
        finder.remembers = true
        settings.finder = finder
        settings.app = self
        window.isReleasedWhenClosed = false
        alerts.post = { [weak self] title, body in self?.notify(title, body) }
        UNUserNotificationCenter.current().delegate = self
        if UserDefaults.standard.bool(forKey: "menuBar") { setMenuBar(true, save: false) }
        if UserDefaults.standard.bool(forKey: "alerts") { startAlerts() }
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

    // With Find in the menu bar, closing the window leaves it running there (and out of the Dock); without, it quits
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { bar == nil }
    func windowWillClose(_ n: Notification) {
        if (n.object as? NSWindow) === window && bar != nil { NSApp.setActivationPolicy(.accessory) }
    }
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool { showMain(); return true }
    @objc func showMain() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // ---- the menu bar item and alerts, both off until switched on in Settings
    func setMenuBar(_ on: Bool, save: Bool = true) {
        if save { UserDefaults.standard.set(on, forKey: "menuBar") }
        if on, bar == nil { bar = MenuBar(app: self); bar?.update() }
        if !on, bar != nil {
            bar = nil
            if !window.isVisible { showMain() }   // nothing left to reach Find by
        }
    }
    func watch() {
        bar?.update()
        if UserDefaults.standard.bool(forKey: "alerts") { alerts.check(finder.devices) }
    }
    // the 60 s rule needs a clock even when nothing changes
    func startAlerts() {
        alertTimer?.invalidate()
        alertTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.watch() }
        watch()
    }
    // The first time alerts go on, macOS asks the person; that answer is theirs. Off in System Settings: say so
    func setAlerts(_ on: Bool, done: @escaping (Bool, String?) -> Void) {
        guard on else {
            UserDefaults.standard.set(false, forKey: "alerts"); alertTimer?.invalidate(); alertTimer = nil
            return done(false, nil)
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    UserDefaults.standard.set(true, forKey: "alerts"); self.startAlerts(); done(true, nil)
                } else {
                    UserDefaults.standard.set(false, forKey: "alerts")
                    done(false, "Notifications are off for Downstage Find. Turn them on in System Settings, Notifications.")
                }
            }
        }
    }
    func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
    // a click on an alert brings the window up
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        showMain(); done()
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(macOS 11.0, *) { done([.banner, .sound]) } else { done([.alert, .sound]) }
    }

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

// Find's own Settings (⌘,): a small native window with the switches for remembered devices, the menu bar and alerts
// (steps 3 and 4 of the 2026-11-10 brief), and nothing else. Every switch starts off.
final class SettingsWindow: NSObject, NSWindowDelegate {
    var window: NSWindow?
    weak var finder: Finder?
    weak var app: AppDelegate?
    let forgetButton = NSButton(title: "Forget All…", target: nil, action: nil)
    let countLabel = NSTextField(labelWithString: "")
    let menuBarSwitch = NSSwitch(), loginSwitch = NSSwitch(), alertSwitch = NSSwitch()
    let alertNote = NSTextField(wrappingLabelWithString: "")
    func show() {
        if window == nil { build() }
        refresh()
        if window?.isVisible == false { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func refresh() {
        let n = finder?.rememberedCount ?? 0
        countLabel.stringValue = n == 0 ? "No devices are remembered that aren't here now." : (n == 1 ? "1 remembered device isn't here now." : "\(n) remembered devices aren't here now.")
        forgetButton.isEnabled = n > 0
        menuBarSwitch.state = UserDefaults.standard.bool(forKey: "menuBar") ? .on : .off
        alertSwitch.state = UserDefaults.standard.bool(forKey: "alerts") ? .on : .off
        if #available(macOS 13.0, *) { loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off }
        else { loginSwitch.isEnabled = false }
    }
    func windowDidBecomeKey(_ n: Notification) { refresh() }
    func label(_ t: String, _ size: CGFloat = 12, _ weight: NSFont.Weight = .regular, dim: Bool = false) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: t)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = dim ? .secondaryLabelColor : .labelColor
        l.preferredMaxLayoutWidth = 412
        return l
    }
    func switchRow(_ sw: NSSwitch, _ title: String, _ action: Selector) -> NSStackView {
        sw.target = self; sw.action = action; sw.controlSize = .small
        let l = label(title, 13)
        l.preferredMaxLayoutWidth = 360
        let row = NSStackView(views: [l, NSView(), sw])
        row.orientation = .horizontal
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }
    func rule() -> NSBox { let b = NSBox(); b.boxType = .separator; return b }
    func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Settings"
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(srgbRed: 0x12 / 255.0, green: 0x16 / 255.0, blue: 0x1B / 255.0, alpha: 1)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        // remembered devices
        stack.addArrangedSubview(label("Remembered devices", 13, .semibold))
        stack.addArrangedSubview(label("A device this Mac has seen stays in the list, dimmed, while it's away, and drops off 30 days after it was last seen. Only its name, kind and serial are kept, nothing about the network.", dim: true))
        countLabel.font = NSFont.systemFont(ofSize: 12)
        forgetButton.target = self
        forgetButton.action = #selector(forgetAll)
        forgetButton.bezelStyle = .rounded
        let row = NSStackView(views: [countLabel, forgetButton])
        row.orientation = .horizontal
        row.spacing = 12
        stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(row)
        stack.setCustomSpacing(18, after: row)
        // menu bar
        let r1 = rule(); stack.addArrangedSubview(r1); stack.setCustomSpacing(16, after: r1)
        let mb = switchRow(menuBarSwitch, "Show in menu bar", #selector(menuBarChanged))
        stack.addArrangedSubview(mb)
        stack.addArrangedSubview(label("Every device and its state, one click away. Its edge turns amber when a device needs a look. Closing the window leaves Find running there.", dim: true))
        let lg = switchRow(loginSwitch, "Open at login", #selector(loginChanged))
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(lg)
        // alerts
        let r2 = rule(); stack.setCustomSpacing(18, after: lg); stack.addArrangedSubview(r2); stack.setCustomSpacing(16, after: r2)
        let al = switchRow(alertSwitch, "Alerts", #selector(alertsChanged))
        stack.addArrangedSubview(al)
        stack.addArrangedSubview(label("A notification when a light's battery drops under 20% and isn't charging, when a device hasn't answered for a minute, and when it comes back. One for each, never a repeat.", dim: true))
        alertNote.font = NSFont.systemFont(ofSize: 12)
        alertNote.textColor = NSColor(srgbRed: 0xF7 / 255.0, green: 0xC0 / 255.0, blue: 0x66 / 255.0, alpha: 1)
        alertNote.preferredMaxLayoutWidth = 412
        alertNote.isHidden = true
        stack.addArrangedSubview(alertNote)
        for v in [mb, lg, al, r1, r2] { v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true }
        w.contentView = stack
        w.setContentSize(stack.fittingSize)
        w.delegate = self
        window = w
    }
    @objc func menuBarChanged() { app?.setMenuBar(menuBarSwitch.state == .on) }
    @objc func loginChanged() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if loginSwitch.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }
    @objc func alertsChanged() {
        alertNote.isHidden = true
        app?.setAlerts(alertSwitch.state == .on) { on, note in
            self.alertSwitch.state = on ? .on : .off
            if let n = note { self.alertNote.stringValue = n; self.alertNote.isHidden = false }
        }
    }
    // a sheet on the Settings window: how many, and that it can't be undone
    @objc func forgetAll() {
        guard let w = window, let f = finder else { return }
        let n = f.rememberedCount
        let a = NSAlert()
        a.messageText = n == 1 ? "Forget 1 device?" : "Forget \(n) devices?"
        a.informativeText = "Devices that aren't here now come off the list. Any that come back are found again as new."
        a.addButton(withTitle: "Forget All")
        a.addButton(withTitle: "Cancel")
        a.beginSheetModal(for: w) { r in
            if r == .alertFirstButtonReturn { f.forgetAll(); self.refresh() }
        }
    }
}

// Find in the menu bar: the mark, its bottom edge amber when a device needs a look. A click lists every device with
// a status dot and its state; picking one opens its Settings. Open Downstage Find and Look Again at the foot.
final class MenuBar: NSObject, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    weak var app: AppDelegate?
    var warn = false
    init(app: AppDelegate) {
        self.app = app
        super.init()
        let m = NSMenu(); m.delegate = self; m.autoenablesItems = false
        item.menu = m
        item.button?.toolTip = "Downstage Find"
        draw()
    }
    deinit { NSStatusBar.system.removeStatusItem(item) }
    func devices() -> [Device] {
        let order = ["one", "view", "relay"]
        func g(_ d: Device) -> Int { order.firstIndex(of: d.kind) ?? 3 }
        return (app?.finder.devices.values.map { $0 } ?? []).sorted {
            (g($0), $0.gone ? 1 : 0) != (g($1), $1.gone ? 1 : 0) ? (g($0), $0.gone ? 1 : 0) < (g($1), $1.gone ? 1 : 0)
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    func update() {
        let w = devices().contains { statusOf($0).level == .warn }
        if w != warn { warn = w; draw() }
    }
    // the mark at 18 x 14: a rounded screen and its edge; the outline follows the menu bar, the edge goes amber
    func draw() {
        let amber = warn
        let img = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            let fg = NSColor.controlTextColor
            let screen = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 10), xRadius: 2.5, yRadius: 2.5)
            screen.lineWidth = 1.5; fg.setStroke(); screen.stroke()
            (amber ? NSColor(srgbRed: 0xF5 / 255.0, green: 0xA5 / 255.0, blue: 0x24 / 255.0, alpha: 1) : fg).setFill()
            NSBezierPath(roundedRect: NSRect(x: 4, y: 13, width: 10, height: 2), xRadius: 1, yRadius: 1).fill()
            return true
        }
        img.isTemplate = !amber
        item.button?.image = img
    }
    func dot(_ l: Level) -> NSImage {
        let c: NSColor = l == .ok ? NSColor(srgbRed: 0x2F / 255.0, green: 0xD9 / 255.0, blue: 0x7B / 255.0, alpha: 1)
            : l == .warn ? NSColor(srgbRed: 0xF5 / 255.0, green: 0xA5 / 255.0, blue: 0x24 / 255.0, alpha: 1) : NSColor(white: 0.45, alpha: 1)
        return NSImage(size: NSSize(width: 8, height: 8), flipped: false) { r in c.setFill(); NSBezierPath(ovalIn: r).fill(); return true }
    }
    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        let ds = devices()
        let look = ds.filter { statusOf($0).level == .warn }.count, gone = ds.filter { $0.gone }.count
        let head = [ds.count == 1 ? "1 device" : "\(ds.count) devices", look == 0 ? "" : (look == 1 ? "1 needs a look" : "\(look) need a look"),
                    gone == 0 ? "" : "\(gone) not seen"].filter { !$0.isEmpty }.joined(separator: " · ")
        let h = NSMenuItem(title: ds.isEmpty ? "Nothing found yet" : head, action: nil, keyEquivalent: ""); h.isEnabled = false; m.addItem(h)
        let tab = NSMutableParagraphStyle(); tab.tabStops = [NSTextTab(textAlignment: .right, location: 300)]
        for d in ds {
            let st = statusOf(d)
            let t = NSMutableAttributedString(string: d.name, attributes: [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: tab])
            let tint: NSColor = st.level == .warn ? NSColor(srgbRed: 0xF7 / 255.0, green: 0xC0 / 255.0, blue: 0x66 / 255.0, alpha: 1) : .secondaryLabelColor
            t.append(NSAttributedString(string: "\t" + st.text, attributes: [.font: NSFont.menuFont(ofSize: 12), .foregroundColor: tint, .paragraphStyle: tab]))
            let i = NSMenuItem(title: d.name, action: #selector(openDevice(_:)), keyEquivalent: "")
            i.attributedTitle = t; i.image = dot(st.level); i.target = self; i.representedObject = d.key
            i.isEnabled = !d.gone && !d.host.isEmpty
            m.addItem(i)
        }
        m.addItem(.separator())
        let o = NSMenuItem(title: "Open Downstage Find", action: #selector(openFind), keyEquivalent: ""); o.target = self; m.addItem(o)
        let l = NSMenuItem(title: "Look Again", action: #selector(lookAgain), keyEquivalent: ""); l.target = self; m.addItem(l)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit Downstage Find", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }
    // a device's own page is its Settings; a One's is Full setup (find.html appsOf)
    @objc func openDevice(_ s: NSMenuItem) {
        guard let k = s.representedObject as? String, let d = app?.finder.devices[k], !d.host.isEmpty else { return }
        if let u = URL(string: "http://\(d.host):\(d.port)/" + (d.kind == "one" ? "?browser=1" : "")) { NSWorkspace.shared.open(u) }
    }
    @objc func openFind() { app?.showMain() }
    @objc func lookAgain() { app?.finder.refresh() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
