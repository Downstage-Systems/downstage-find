// Downstage Find for iPhone and iPad: finds Downstage devices and opens their pages. The finding is shared with the Mac app.
import UIKit
import WebKit

func makeShell() -> ShellController { FindController() }

final class FindController: ShellController {
    let finder = Finder()
    override var pageURL: URL { pageRoot.appendingPathComponent("find.html") }

    // the page keeps itself clear of the notch and the home bar with the --sa-* insets the shell sets
    override func configure(_ c: WKUserContentController) {
        c.add(self, name: "find")
        // the version sits at the foot of the list
        c.addUserScript(WKUserScript(source: "(function () { const v = document.createElement('div'); v.style.cssText = 'margin-top: 18px; text-align: center; font-size: 12px; color: var(--meta);'; v.textContent = '\(versionText)'; document.querySelector('main').appendChild(v); })();",
                                     injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        finder.changed = { [weak self] in self?.tell() }
        finder.say = { [weak self] text, warn in self?.call("window.findSay(\(quoted(text)), \(warn))") }
        finder.scanState = { [weak self] running in self?.call("window.scanState(\(running))") }
        finder.start()
    }
    func tell() {
        guard let data = try? JSONSerialization.data(withJSONObject: finder.devices.values.map { $0.json }) else { return }
        call("window.devices(\(String(decoding: data, as: UTF8.self)))")
    }
    override func pageReady() { tell() }
    override func cameForward() { finder.refresh() }
    override func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        #if DEBUG
        if message.name == "testlog", let line = message.body as? String { return testLine(line) }
        #endif
        guard let m = message.body as? [String: Any], let action = m["action"] as? String else { return }
        switch action {
        case "open":
            // only our own http pages on the local network: the page gives the address, never a file or another scheme
            if let s = m["url"] as? String, let u = URL(string: s), u.scheme == "http" { show(u) }
        case "refresh": finder.refresh()
        case "scan": finder.scan()
        case "add": if let h = m["host"] as? String { finder.add(h) }
        case "identify": if let k = m["key"] as? String { finder.blink(k) }
        case "forget": if let k = m["key"] as? String { finder.forget(k) }
        case "copy": if let t = m["text"] as? String { UIPasteboard.general.string = t }
        case "bright": if let k = m["key"] as? String, let p = m["pct"] as? Int { finder.bright(k, part: m["part"] as? String ?? "light", pct: p) }
        default: break
        }
    }
}

func quoted(_ s: String) -> String {
    let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
    return String(String(decoding: d, as: UTF8.self).dropFirst().dropLast())
}
