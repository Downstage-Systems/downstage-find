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
    private(set) var started = Date()
    private var finder: Finder?
    private let path = NWPathMonitor()
    private var clock: Timer?
    private var running = false, away = false

    #if DEBUG
    // test hooks, Debug only: DOWNSTAGE_STATE=looking|nothing|blocked|noWiFi opens that state without a network,
    // DOWNSTAGE_SEARCH=text opens the list searched, DOWNSTAGE_DEMO=1 (or -demo YES) starts in the demo
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
        path.pathUpdateHandler = { [weak self] p in
            let on = p.status == .satisfied && (p.usesInterfaceType(.wifi) || p.usesInterfaceType(.wiredEthernet) || !p.usesInterfaceType(.cellular))
            DispatchQueue.main.async { self?.onNetwork = on }
        }
        path.start(queue: .main)
        // once a second while the first look is on (Looking turns into Nothing found at 5 s), then every 30 s for "last seen"
        clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let t = Date()
            if t.timeIntervalSince(self.started) < 12 || t.timeIntervalSince(self.now) >= 30 { self.now = t }
        }
        if demo { devices = Demo.devices() } else { startFinder() }
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
            if demo { devices = Demo.devices() } else { finder?.refresh() }
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
        if on { stopFinder(); devices = Demo.devices(); started = Date() }
        else { devices = []; blocked = false; startFinder() }
    }
}
