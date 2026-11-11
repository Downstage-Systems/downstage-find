// The finding itself, shared by the Mac and iOS apps: Bonjour first, then a typed address or a scan the person asks for.
import Foundation

#if os(iOS)
let blockedSearchHelp = "iOS blocked the search. In Settings, open Downstage Find and turn on Local Network."
let notOnNetwork = "This device isn't on a network."
#else
let blockedSearchHelp = "macOS blocked the search. In System Settings, open Privacy & Security, then Local Network, and turn on Downstage Find."
let notOnNetwork = "This Mac isn't on a network."
#endif

struct Device {
    var key: String
    var kind: String
    var name: String
    var host: String
    var port: Int
    var serial = ""
    var version = ""
    var companion = false
    var ontime = false
    var hasApps = false
    var hasShow = false
    var gone = false
    var health: [String: Any] = [:]   // a light's or a Relay's own report, worded by the page
    var lastSeen: Date?               // the last time it answered
    var heard = false                 // Bonjour told us of it this session
    var answered = false              // its /status answered this session
    var json: [String: Any] {
        ["key": key, "kind": kind, "name": name, "host": host, "port": port, "serial": serial, "version": version,
         "companion": companion, "ontime": ontime, "hasApps": hasApps, "hasShow": hasShow, "gone": gone, "health": health,
         "lastSeen": lastSeen.map { $0.timeIntervalSince1970 * 1000 } ?? NSNull(), "heard": heard, "answered": answered]
    }
}

func getJSON(_ url: String, timeout: TimeInterval, done: @escaping ([String: Any]?) -> Void) {
    guard let u = URL(string: url) else { return done(nil) }
    var r = URLRequest(url: u); r.timeoutInterval = timeout
    URLSession.shared.dataTask(with: r) { data, resp, _ in
        guard let data = data, (resp as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return DispatchQueue.main.async { done(nil) } }
        DispatchQueue.main.async { done(o) }
    }.resume()
}

func exists(_ url: String, done: @escaping (Bool) -> Void) {
    guard let u = URL(string: url) else { return done(false) }
    var r = URLRequest(url: u); r.httpMethod = "HEAD"; r.timeoutInterval = 3
    URLSession.shared.dataTask(with: r) { _, resp, _ in
        DispatchQueue.main.async { done((resp as? HTTPURLResponse)?.statusCode == 200) }
    }.resume()
}

// What a device's /status says it is: a One or View has os_version, a light or Relay has firmware. Anything else isn't ours
func identify(_ s: [String: Any], host: String, port: Int) -> Device? {
    if s["os_version"] != nil {
        let serial = s["serial"] as? String ?? ""
        let view = !serial.hasPrefix("DS1-") && s["companion_installed"] == nil
        var d = Device(key: serial.isEmpty ? host : serial, kind: view ? "view" : "one", name: s["name"] as? String ?? (serial.isEmpty ? host : serial), host: host, port: port)
        update(&d, s)
        return d
    }
    // a light says firmware; a Relay since 0.186.4x says version (its one-system /status keys)
    if let fw = (s["firmware"] ?? s["version"]) as? String, s["id"] != nil || s["serial"] != nil {
        let id = s["id"] as? String ?? s["serial"] as? String ?? host
        let model = (s["model"] as? String ?? "").lowercased()
        let kind = model.contains("relay") ? "relay" : model.contains("lite") ? "lite" : model.contains("mini") ? "mini" : model.contains("360") ? "360" : "cue"
        return Device(key: id, kind: kind, name: s["label"] as? String ?? id, host: host, port: port, serial: s["serial"] as? String ?? "", version: fw)
    }
    return nil
}

func update(_ d: inout Device, _ s: [String: Any]) {
    if let n = s["name"] as? String, !n.isEmpty { d.name = n }
    if let v = s["os_version"] as? String { d.version = v }
    d.companion = s["companion_running"] as? Bool ?? false
    d.ontime = s["ontime_running"] as? Bool ?? false
}

// Only what the card's health line needs from a light's /status: its Companion state, its own reason when it can't work,
// how its WiFi or CueLink is doing, and a battery if it has one. Its brightness and its Hex's (0.186.38) ride along for
// the sliders, with whether a Cue PIN guards them
func lightHealth(_ s: [String: Any]) -> [String: Any] {
    var h: [String: Any] = [:]
    for k in ["setup", "companion", "why", "rssi", "ssid", "battery", "charging", "brightpct", "tokenSet"] { if let v = s[k] { h[k] = v } }
    if let l = s["loss"] as? [String: Any] { h["weak"] = l["weak"] }
    if let l = s["link"] as? [String: Any] { h["relayed"] = l["relayed"]; h["via"] = l["via"] }
    if let x = s["hex"] as? [String: Any] { h["hexBright"] = x["bright"] }
    return h
}

// A Relay's own verdict (2026-11-09, one-system-ui.md): health_ok, and health_why worst first; showing is "3 of 8 linked"
func relayHealth(_ s: [String: Any]) -> [String: Any] {
    var h: [String: Any] = [:]
    for k in ["health_ok", "health_why", "showing"] { if let v = s[k] { h[k] = v } }
    return h
}

final class Finder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var browser = NetServiceBrowser()
    var services: [NetService] = []
    var devices: [String: Device] = [:]
    var changed: () -> Void = {}
    var say: (String, Bool) -> Void = { _, _ in }
    var scanState: (Bool) -> Void = { _ in }
    var timer: Timer?

    // heard: Bonjour has answered at least once, so Local Network is allowed. blocked: the warning is up
    var heard = false, blocked = false, retries = 0

    // The Mac remembers each device it has seen, by its key (serial or id): its name, kind and serial and when it
    // was last seen, nothing about the network it was on. One missing now stays in the list, dimmed, and drops off
    // 30 days after it was last seen
    var remembers = false
    static let keepFor: TimeInterval = 30 * 24 * 3600
    let store = "rememberedDevices"
    var savedAt = Date.distantPast
    func loadRemembered() {
        guard remembers, let saved = UserDefaults.standard.dictionary(forKey: store) as? [String: [String: Any]] else { return }
        let now = Date().timeIntervalSince1970
        for (key, r) in saved where devices[key] == nil {
            guard let t = r["seen"] as? Double, now - t < Finder.keepFor else { continue }
            var d = Device(key: key, kind: r["kind"] as? String ?? "cue", name: r["name"] as? String ?? key, host: "", port: 0, serial: r["serial"] as? String ?? "")
            d.gone = true
            d.lastSeen = Date(timeIntervalSince1970: t)
            devices[key] = d
        }
    }
    func saveRemembered() {
        guard remembers else { return }
        var out: [String: [String: Any]] = [:]
        for d in devices.values {
            guard let t = d.lastSeen, Date().timeIntervalSince(t) < Finder.keepFor else { continue }
            out[d.key] = ["name": d.name, "kind": d.kind, "serial": d.serial, "seen": t.timeIntervalSince1970]
        }
        UserDefaults.standard.set(out, forKey: store)
        savedAt = Date()
    }
    func expire() {
        // only what was last seen more than 30 days ago: one heard this session but never answering stays
        devices = devices.filter { !$0.value.gone || ($0.value.lastSeen.map { Date().timeIntervalSince($0) < Finder.keepFor } ?? true) }
    }
    var rememberedCount: Int { devices.values.filter { $0.gone && $0.lastSeen != nil }.count }
    // Settings' Forget All: every device that isn't here now; one that is stays, and is remembered again
    func forgetAll() {
        devices = devices.filter { !$0.value.gone }
        UserDefaults.standard.removeObject(forKey: store)
        saveRemembered()
        changed()
    }

    func start() {
        loadRemembered()
        changed()
        search()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.check() }
    }
    func search() {
        browser.stop()
        services = []
        browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_downstage._tcp.", inDomain: "local.")
    }
    func refresh() {
        retries = 0
        // a remembered device stays, dimmed; without remembering (the iPhone) one that's gone drops off
        if remembers { expire() } else { devices = devices.filter { !$0.value.gone } }
        changed()
        search()
        check()
    }
    // A search also stops when iOS puts the app in the background, so a failure only means "blocked" until Bonjour has
    // answered once. Either way it tries again a few times on its own
    func netServiceBrowser(_ b: NetServiceBrowser, didNotSearch err: [String: NSNumber]) {
        guard b === browser else { return }
        if !heard { blocked = true; say(blockedSearchHelp, true) }
        guard retries < 3 else { return }
        retries += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.search() }
    }
    func netServiceBrowser(_ b: NetServiceBrowser, didFind s: NetService, moreComing: Bool) {
        heard = true; retries = 0
        if blocked { blocked = false; say("", false) }
        services.append(s)
        s.delegate = self
        s.resolve(withTimeout: 5)
    }
    func netServiceBrowser(_ b: NetServiceBrowser, didRemove s: NetService, moreComing: Bool) {
        services.removeAll { $0 == s }
        for (k, d) in devices where d.key == s.name || d.name == s.name { devices[k]?.gone = true }
        check()
    }
    func netServiceDidResolveAddress(_ s: NetService) {
        guard let host = ipv4(s) else { return }
        let txt = s.txtRecordData().map { NetService.dictionary(fromTXTRecord: $0).mapValues { String(decoding: $0, as: UTF8.self) } } ?? [:]
        let serial = txt["serial"] ?? ""
        let kind = txt["kind"]?.lowercased() ?? (serial.hasPrefix("DS1-") ? "one" : serial.isEmpty ? "cue" : "view")
        let key = txt["id"] ?? (serial.isEmpty ? s.name : serial)
        var d = devices[key] ?? Device(key: key, kind: kind, name: txt["name"] ?? s.name, host: host, port: s.port, serial: serial, version: txt["fw"] ?? "")
        d.host = host; d.port = s.port; d.gone = false; d.heard = true
        devices[key] = d
        changed()
        look(key)
    }
    func ipv4(_ s: NetService) -> String? {
        for a in s.addresses ?? [] {
            let found: String? = a.withUnsafeBytes { raw in
                guard let sa = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self), sa.pointee.sa_family == UInt8(AF_INET) else { return nil }
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(sa, socklen_t(a.count), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
                return String(cString: buf)
            }
            if let found = found, !found.hasPrefix("169.254.") { return found }
        }
        return nil
    }
    // Keep each card true: is it there, and for a One, which of its apps are running
    func look(_ key: String) {
        guard let d = devices[key], !d.host.isEmpty else { return }   // remembered, not heard of yet here
        getJSON("http://\(d.host):\(d.port)/status", timeout: 3) { [weak self] s in
            guard let self = self, self.devices[key] != nil else { return }
            self.devices[key]!.gone = s == nil
            if s != nil { self.devices[key]!.answered = true; self.devices[key]!.lastSeen = Date() }
            if let s = s, d.kind == "one" || d.kind == "view" { update(&self.devices[key]!, s) }
            else if let s = s, d.kind == "relay" { self.devices[key]!.health = relayHealth(s) }
            else if let s = s { self.devices[key]!.health = lightHealth(s) }
            self.changed()
        }
        if d.kind == "one" {
            exists("http://\(d.host):\(d.port)/static/apps/virtual-deck.html") { [weak self] yes in
                self?.devices[key]?.hasApps = yes
                self?.changed()
            }
            // Show mode came with the One's show-mode pages: only offer it on a One that has it
            exists("http://\(d.host):\(d.port)/show") { [weak self] yes in
                self?.devices[key]?.hasShow = yes
                self?.changed()
            }
        }
    }
    func check() {
        devices.keys.forEach(look)
        // gentle on the disk too: the last-seen times are written at most once a minute
        if remembers && Date().timeIntervalSince(savedAt) > 60 { expire(); saveRemembered() }
    }

    func add(_ host: String) {
        say("Asking \(host)…", false)
        probe(host, ports: [8080, 80], timeout: 3) { [weak self] found in
            guard let self = self else { return }
            if let d = found { self.keep(d); self.say("", false) }
            else { self.say("Nothing Downstage answered at \(host).", true) }
        }
    }
    // "Which light is this?": a light blinks white for 5 s, a Relay flashes its LED for 6 s. No PIN, nothing else changes
    func blink(_ key: String) {
        guard let d = devices[key], d.kind != "one", d.kind != "view", let u = URL(string: "http://\(d.host):\(d.port)/identify") else { return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = 3
        URLSession.shared.dataTask(with: r) { [weak self] _, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { if !ok { self?.say("\(d.name) didn't answer.", true) } }
        }.resume()
    }
    // A light's brightness, or its Hex's, as a percent 1-100: live on the light, no restart, kept. The page sends it once,
    // when the slider is let go, because each change is written to the light's flash. No answer at all gets one more try:
    // the same value twice changes nothing (one in eight went unanswered on the bench Mini)
    func bright(_ key: String, part: String, pct: Int, again: Bool = true) {
        guard let d = devices[key], (1...100).contains(pct) else { return }
        let hex = part == "hex"
        guard let u = URL(string: "http://\(d.host):\(d.port)" + (hex ? "/follow" : "/api/v1/brightness")) else { return }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = 3
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = (hex ? "part=hex&bright=\(pct)" : "pct=\(pct)").data(using: .utf8)
        URLSession.shared.dataTask(with: r) { [weak self] _, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                guard let self = self else { return }
                if code == nil && again {
                    return DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.bright(key, part: part, pct: pct, again: false) }
                }
                if code == 200 {
                    self.devices[key]?.health[hex ? "hexBright" : "brightpct"] = pct
                    self.changed()
                } else if code == 401 {
                    self.say("\(d.name) has a Cue PIN. Change its brightness in Settings.", true)
                } else {
                    self.say("\(d.name) didn't take the brightness.", true)
                }
                self.look(key)
            }
        }.resume()
    }
    // Off the list until it's heard of again: Bonjour or a look brings it back
    func forget(_ key: String) {
        devices.removeValue(forKey: key)
        saveRemembered()
        changed()
    }
    func probe(_ host: String, ports: [Int], timeout: TimeInterval, done: @escaping (Device?) -> Void) {
        guard let port = ports.first else { return done(nil) }
        getJSON("http://\(host):\(port)/status", timeout: timeout) { [weak self] s in
            if let s = s, let d = identify(s, host: host, port: port) { done(d) }
            else { self?.probe(host, ports: Array(ports.dropFirst()), timeout: timeout, done: done) }
        }
    }
    func keep(_ d: Device) {
        devices[d.key] = d
        changed()
        look(d.key)
    }
    // Only when asked: every address on each network this machine is on, a few at a time
    func scan() {
        let ips = localNets().flatMap { n in (1...254).map { "\(n).\($0)" } }
        guard !ips.isEmpty else { return say(notOnNetwork, true) }
        scanState(true)
        say("Scanning \(ips.count) addresses…", false)
        var queue = ips[...], left = ips.count, foundCount = 0
        func next() {
            guard let ip = queue.popFirst() else { return }
            probe(ip, ports: [8080, 80], timeout: 0.8) { [weak self] d in
                guard let self = self else { return }
                if let d = d { foundCount += 1; if self.devices[d.key]?.gone ?? true { self.keep(d) } }
                left -= 1
                if left == 0 {
                    self.scanState(false)
                    self.say(foundCount == 0 ? "The scan found nothing Downstage on this network." : "", foundCount == 0)
                } else { next() }
            }
        }
        for _ in 0..<12 { next() }
    }
    func localNets() -> [String] {
        var out: [String] = [], head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return out }
        defer { freeifaddrs(head) }
        var p = head
        while let i = p {
            defer { p = i.pointee.ifa_next }
            guard let a = i.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET), i.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            #if os(iOS)
            // Wi-Fi, Ethernet or a hotspot only: an iPhone's cellular address is the carrier's network, never scan that
            let ifname = String(cString: i.pointee.ifa_name)
            guard ifname.hasPrefix("en") || ifname.hasPrefix("bridge") else { continue }
            #endif
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(a, socklen_t(a.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: buf)
            if ip.hasPrefix("169.254.") { continue }
            let net = ip.split(separator: ".").prefix(3).joined(separator: ".")
            if !out.contains(net) { out.append(net) }
        }
        return out
    }
}
