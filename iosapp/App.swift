// Downstage Find for iPhone and iPad: finds Downstage devices and opens their pages. The finding is shared with the Mac app.
import UIKit
import WebKit

func makeShell() -> ShellController { FindController() }

final class FindController: ShellController {
    let finder = Finder()
    override var pageURL: URL { pageRoot.appendingPathComponent("find.html") }

    override var appStyle: String { """
      header { padding: calc(10px + var(--sa-t)) calc(14px + var(--sa-r)) 10px calc(14px + var(--sa-l) + var(--win-l)) !important; }
      #say { padding-left: calc(14px + var(--sa-l)) !important; padding-right: calc(14px + var(--sa-r)) !important; }
      main { padding: 14px calc(14px + var(--sa-r)) calc(14px + var(--sa-b)) calc(14px + var(--sa-l)) !important; }
    """ }
    override func configure(_ c: WKUserContentController) {
        c.add(self, name: "find")
        // the version sits at the foot of the list
        c.addUserScript(WKUserScript(source: "(function () { const v = document.createElement('div'); v.style.cssText = 'margin-top: 18px; text-align: center; font-size: 12px; color: var(--muted);'; v.textContent = '\(versionText)'; document.querySelector('main').appendChild(v); })();",
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
        case "bright": if let k = m["key"] as? String, let p = m["pct"] as? Int { finder.bright(k, part: m["part"] as? String ?? "light", pct: p) }
        default: break
        }
    }
}

func quoted(_ s: String) -> String {
    let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data()
    return String(String(decoding: d, as: UTF8.self).dropFirst().dropLast())
}
