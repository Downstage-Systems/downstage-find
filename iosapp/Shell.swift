// The iOS window: the same web page the Mac app shows, in a WKWebView, with phone-sized controls added here so the shared page stays as it is.
import SafariServices
import UIKit
import WebKit

let groundColor = UIColor(red: 0x0B / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0, alpha: 1)

// Inputs under 16 px make iOS zoom the page on focus; a finger needs a bigger target than a mouse
private let mobileStyle = """
:root { --sa-t: 0px; --sa-r: 0px; --sa-b: 0px; --sa-l: 0px; --win-t: 0px; --win-l: 0px; }
  input, select, button, a.btn { min-height: 44px !important; font-size: 16px !important; }
  html { -webkit-text-size-adjust: 100%; }
  * { -webkit-tap-highlight-color: transparent; -webkit-touch-callout: none; }
"""

class ShellController: UIViewController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var web: WKWebView!
    var loaded = false
    var lastSize = CGSize.zero

    func configure(_ c: WKUserContentController) {}
    var appStyle: String { "" }
    var pageURL: URL { Bundle.main.resourceURL! }
    var pageRoot: URL { Bundle.main.resourceURL!.appendingPathComponent("web") }
    func pageReady() {}
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {}

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = groundColor
        let config = WKWebViewConfiguration()
        let who = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let css = (mobileStyle + appStyle).replacingOccurrences(of: "\n", with: " ")
        let flag = "window.downstageMobile = '\(who)';"
        // JSON, so a quote mark in the CSS can't break the script around it
        let cssData = (try? JSONSerialization.data(withJSONObject: [css])) ?? Data()
        let cssText = String(String(decoding: cssData, as: UTF8.self).dropFirst().dropLast())
        let style = "(function () { var s = document.createElement('style'); s.textContent = \(cssText); document.documentElement.appendChild(s); })();"
        config.userContentController.addUserScript(WKUserScript(source: flag + style, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configure(config.userContentController)
        #if DEBUG
        if let js = ProcessInfo.processInfo.environment["DOWNSTAGE_TEST_JS"] {
            config.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            config.userContentController.add(self, name: "testlog")
        }
        #endif
        web = WKWebView(frame: .zero, configuration: config)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.bounces = false
        web.scrollView.isScrollEnabled = false
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        // the page draws to every edge, so its header reaches the sides, and keeps its controls clear using --sa-* below
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.topAnchor), web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor), web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        #if DEBUG
        // a test lays the page out at an exact window size, like one side of an iPad split
        if let parts = ProcessInfo.processInfo.environment["DOWNSTAGE_TEST_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), parts.count == 2 {
            testWindowed = true
            view.constraints.filter { ($0.firstItem as? WKWebView) == web && ($0.firstAttribute == .trailing || $0.firstAttribute == .bottom) }.forEach { $0.isActive = false }
            NSLayoutConstraint.activate([web.widthAnchor.constraint(equalToConstant: parts[0]), web.heightAnchor.constraint(equalToConstant: parts[1])])
        }
        #endif
        web.loadFileURL(pageURL, allowingReadAccessTo: pageRoot)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true; tellInsets(); pageReady() }
    override func viewSafeAreaInsetsDidChange() { super.viewSafeAreaInsetsDidChange(); tellInsets() }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if view.bounds.size != lastSize { lastSize = view.bounds.size; tellInsets() }
    }
    // An iPad app in a window has the red, yellow and green window buttons over its top left corner
    var windowed: Bool {
        #if DEBUG
        if testWindowed { return true }
        #endif
        guard UIDevice.current.userInterfaceIdiom == .pad, let screen = view.window?.windowScene?.screen.bounds.size else { return false }
        return abs(view.bounds.width - screen.width) > 1 || abs(view.bounds.height - screen.height) > 1
    }
    // the notch, island, home bar and window buttons, for the page's CSS
    func tellInsets() {
        let i = view.safeAreaInsets
        call("(function (s) { s.setProperty('--win-t', '\(windowed ? 46 : 0)px'); s.setProperty('--win-l', '\(windowed ? 62 : 0)px'); })(document.documentElement.style)")
        call("(function (s) { s.setProperty('--sa-t', '\(i.top)px'); s.setProperty('--sa-r', '\(i.right)px'); s.setProperty('--sa-b', '\(i.bottom)px'); s.setProperty('--sa-l', '\(i.left)px'); })(document.documentElement.style)")
    }
    #if DEBUG
    var testWindowed = false
    func testLine(_ line: String) {
        // in the app's own Documents, where a test reads it with simctl get_app_container
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first, let d = (line + "\n").data(using: .utf8) else { return }
        let path = dir.appendingPathComponent("test.log").path
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(d); h.closeFile() } else { FileManager.default.createFile(atPath: path, contents: d) }
    }
    var testOrientation: UIInterfaceOrientationMask? {
        switch ProcessInfo.processInfo.environment["DOWNSTAGE_TEST_ORIENT"] {
        case "portrait": return .portrait
        case "upside": return .portraitUpsideDown
        case "left": return .landscapeLeft
        case "right": return .landscapeRight
        default: return nil
        }
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { testOrientation ?? super.supportedInterfaceOrientations }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let o = testOrientation { view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: o)) }
    }
    #endif
    func call(_ js: String) { if loaded { web.evaluateJavaScript(js, completionHandler: nil) } }

    // a device's pages open over the app, and Done comes back to it
    func show(_ url: URL) {
        guard url.scheme == "http" || url.scheme == "https", presentedViewController == nil else { return }
        present(SFSafariViewController(url: url), animated: true)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { show(url) }
        return nil
    }
    // the page's confirm(): first paragraph is the title. The first word of the title is the button, like Scan
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let parts = message.components(separatedBy: "\n\n")
        let title = parts.first ?? ""
        let a = UIAlertController(title: title, message: parts.dropFirst().joined(separator: "\n\n"), preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: title.split(separator: " ").first.map(String.init) ?? "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }
    func cameForward() {}
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var shell: ShellController?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let s = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: s)
        w.overrideUserInterfaceStyle = .dark
        let c = makeShell()
        shell = c
        w.rootViewController = c
        w.makeKeyAndVisible()
        window = w
    }
    func sceneWillEnterForeground(_ scene: UIScene) { shell?.cameForward() }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ a: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = SceneDelegate.self
        return c
    }
}
