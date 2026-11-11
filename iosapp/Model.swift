// The app's one source of truth: the shared Finder on a real network, or the made-up devices of the demo, never both.
// Everything the screens do goes through here, so a demo write only ever changes a made-up device.
import Network
import SwiftUI
import UIKit

extension Device: Identifiable { var id: String { key } }

// what the list shows where the devices would be, when there are none to show
enum ListState: String { case list, looking, nothing, blocked, noWiFi }

struct Note: Equatable { let text: String; let warn: Bool }

final class FindModel: ObservableObject {
    @Published private(set) var devices: [Device] = []
    @Published private(set) var note: Note?
    @Published private(set) var scanning = false
    @Published private(set) var demo = false
    @Published private(set) var onNetwork = true
    @Published private(set) var blocked = false
    @Published private(set) var now = Date()
    @Published var path: [String] = []                // the device screens open, by key
    @Published var browsing: Browse?                  // a device's page in the in-app browser
    @Published private(set) var blinking: Set<String> = []
    @Published private(set) var held: [String: Held] = [:]   // a brightness just sent, until the light reports it
    @Published private(set) var toast: String?
    private(set) var started = Date()
    private var finder: Finder?
    private let netPath = NWPathMonitor()
    private var clock: Timer?
    private var running = false, away = false

    #if DEBUG
    // test hooks, Debug only: DOWNSTAGE_STATE=looking|nothing|blocked|noWiFi opens that state without a network,
    // DOWNSTAGE_SEARCH=text opens the list searched, DOWNSTAGE_DEMO=1 (or -demo YES) starts in the demo,
    // DOWNSTAGE_OPEN=<key> opens that device's screen, DOWNSTAGE_BROWSE=<key> its Settings in the browser sheet
    let env = ProcessInfo.processInfo.environment
    var forced: ListState? { env["DOWNSTAGE_STATE"].flatMap(ListState.init(rawValue:)) }
    var startSearch: String { env["DOWNSTAGE_SEARCH"] ?? "" }
    #else
    var forced: ListState? { nil }
    var startSearch: String { "" }
    #endif

    func start() {
        guard !running else { return }
        running = true
        #if DEBUG
        demo = env["DOWNSTAGE_DEMO"] == "1" || UserDefaults.standard.bool(forKey: "demo")
        if forced != nil { return }
        #endif
        // a phone on cellular only isn't on the show's network; Wi-Fi or a wired adapter is
        netPath.pathUpdateHandler = { [weak self] p in
            let on = p.status == .satisfied && (p.usesInterfaceType(.wifi) || p.usesInterfaceType(.wiredEthernet) || !p.usesInterfaceType(.cellular))
            DispatchQueue.main.async { self?.onNetwork = on }
        }
        netPath.start(queue: .main)
        // once a second while the first look is on (Looking turns into Nothing found at 5 s), then every 30 s for "last seen"
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let t = Date()
            if t.timeIntervalSince(self.started) < 12 || t.timeIntervalSince(self.now) >= 30 { self.now = t }
        }
        if demo { devices = Demo.devices() } else { startFinder() }
        #if DEBUG
        if let k = env["DOWNSTAGE_OPEN"] { path = [k] }
        if let k = env["DOWNSTAGE_BROWSE"], let d = devices.first(where: { $0.key == k }), let w = waysOf(d).first { open(w, of: d) }
        #endif
    }

    private func startFinder() {
        let f = Finder()
        f.changed = { [weak self, weak f] in
            guard let self = self, let f = f, self.finder === f else { return }
            self.devices = Array(f.devices.values)
            self.blocked = f.blocked
        }
        f.say = { [weak self, weak f] text, warn in
            guard let self = self, let f = f, self.finder === f else { return }
            self.note = text.isEmpty ? nil : Note(text: text, warn: warn)
            self.blocked = f.blocked
        }
        f.scanState = { [weak self] on in self?.scanning = on }
        finder = f
        started = Date(); now = started
        f.start()
    }
    private func stopFinder() {
        finder?.timer?.invalidate()
        finder?.browser.stop()
        finder = nil
    }

    // Nothing answering at all, though Bonjour lists devices: most often Local Network turned off for the app
    var nothingAnswers: Bool {
        !demo && devices.contains { $0.heard } && !devices.contains { $0.answered } && now.timeIntervalSince(started) > 8
    }

    var state: ListState {
        if let f = forced { return f }
        if !devices.isEmpty { return .list }
        if demo { return .nothing }
        if !onNetwork { return .noWiFi }
        if blocked { return .blocked }
        return now.timeIntervalSince(started) < 5 ? .looking : .nothing
    }

    // ── what the screens ask for ──
    func lookAgain() async {
        await MainActor.run {
            started = Date(); now = started
            note = nil
            // the demo keeps what was changed and brings back what was forgotten, as a real look would
            if demo { devices += Demo.devices().filter { d in !devices.contains { $0.key == d.key } } } else { finder?.refresh() }
        }
        // the spinner stays long enough to read as a look, and the first answers come back inside it
        try? await Task.sleep(nanoseconds: 1_200_000_000)
    }
    func cameForward() {
        guard away else { return }
        away = false
        if !demo { finder?.refresh() }
    }
    func wentAway() { away = true }

    // the demo for App Review and screenshots: five taps on the version line, in any build
    func setDemo(_ on: Bool) {
        guard on != demo else { return }
        demo = on
        note = nil
        path = []
        if on { stopFinder(); devices = Demo.devices(); started = Date() }
        else { devices = []; blocked = false; startFinder() }
    }

    // ── a device's actions: on a real network through the Finder, in the demo on the made-up devices only ──
    func device(_ key: String) -> Device? { devices.first { $0.key == key } }

    func open(_ w: Way, of d: Device) {
        tapFeel()
        testLog("open \(d.key) \(w.url.absoluteString) demo=\(demo)")
        browsing = Browse(url: w.url, title: w.name, device: d.name, demo: demo)
    }
    // "Which light is this?": a light blinks white for about 5 s, a Relay flashes its LED; the button rests that long
    func blink(_ d: Device) {
        guard canBlink(d), !d.gone, !blinking.contains(d.key) else { return }
        tapFeel()
        testLog("blink \(d.key) demo=\(demo)")
        if !demo { finder?.blink(d.key) }
        blinking.insert(d.key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.blinking.remove(d.key) }
    }
    // one write when the slider is let go: each change goes to the light's flash. A Cue PIN light is never written
    func bright(_ d: Device, part: String, pct: Int) {
        let pct = max(1, min(100, pct))
        guard let p = brightOf(d).first(where: { $0.part == part }), !p.locked else { return }
        tapFeel()
        testLog("bright \(d.key) \(part) \(pct) demo=\(demo)")
        held[d.key + ":" + part] = Held(pct: pct, until: Date().addingTimeInterval(5))
        if demo {
            if let i = devices.firstIndex(where: { $0.key == d.key }) { devices[i].health[part == "hex" ? "hexBright" : "brightpct"] = pct }
        } else {
            finder?.bright(d.key, part: part, pct: pct)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) { [weak self] in self?.held[d.key + ":" + part] = nil }
    }
    // the slider shows what was just sent until the light reports it, so it doesn't jump back mid-look
    func shown(_ d: Device, _ p: BrightPart) -> Int {
        guard let h = held[d.key + ":" + p.part], h.pct != p.pct, Date() < h.until else { return p.pct }
        return h.pct
    }
    func forget(_ d: Device) {
        tapFeel()
        testLog("forget \(d.key) demo=\(demo)")
        path.removeAll { $0 == d.key }
        if demo { devices.removeAll { $0.key == d.key } } else { finder?.forget(d.key) }
    }
    func copy(_ text: String, _ what: String) {
        UIPasteboard.general.string = text
        testLog("copy \(what) \(text)")
        tapFeel()
        say(what + " copied")
    }
    func say(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in if self?.toast == text { self?.toast = nil } }
    }
}

// Debug only: each action a test can't see from outside, one line each in the app's Documents/test.log, read with
// simctl get_app_container
func testLog(_ line: String) {
    #if DEBUG
    guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
          let d = (line + "\n").data(using: .utf8) else { return }
    let path = dir.appendingPathComponent("test.log").path
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(d); h.closeFile() } else { FileManager.default.createFile(atPath: path, contents: d) }
    #endif
}

struct Held: Equatable { let pct: Int; let until: Date }
struct Browse: Identifiable { let url: URL; let title: String; let device: String; let demo: Bool; var id: URL { url } }
