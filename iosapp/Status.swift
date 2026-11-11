// What a device's row and screen say about it, worded exactly as the Mac's page words it (web/find.html: statusOf,
// healthOf, relayOf, subOf, ago, countLine). Keep the two in step: a change of words there is a change here.
import Foundation

let kindNames = ["one": "Downstage One", "view": "Downstage View", "relay": "Cue Relay", "cue": "Cue", "tally": "Cue",
                 "lite": "Cue Lite", "mini": "Cue Mini", "360": "Cue 360"]
func kindName(_ d: Device) -> String { kindNames[d.kind] ?? "Cue" }
// the art: an unknown kind is a light, drawn as a Cue, as on the page
func artName(_ d: Device) -> String { ["one", "view", "relay", "lite", "mini", "360"].contains(d.kind) ? "dev-\(d.kind)" : "dev-cue" }
func isLight(_ d: Device) -> Bool { !["one", "view", "relay"].contains(d.kind) }
func canBlink(_ d: Device) -> Bool { d.kind != "one" && d.kind != "view" }

// The sections in the Mac page's order, so the two apps agree: Ones, Views, Relays, Lights. An unknown kind is a light
let groups: [(title: String, kinds: [String])] = [("Ones", ["one"]), ("Views", ["view"]), ("Relays", ["relay"]),
                                                  ("Lights", ["cue", "tally", "lite", "mini", "360"])]
func groupOf(_ d: Device) -> Int { groups.firstIndex { $0.kinds.contains(d.kind) } ?? groups.count - 1 }

enum Tone { case ok, warn, off }
struct Pill { let tone: Tone; let short: String; let text: String }

private func num(_ v: Any?) -> Int? { (v as? NSNumber).map { $0.intValue } ?? v as? Int }
private func flag(_ v: Any?) -> Bool { (v as? NSNumber)?.boolValue ?? v as? Bool ?? false }
private func nameOf(_ key: Any?, in all: [Device]) -> String { all.first { $0.key == key as? String }?.name ?? "its Relay" }

// A light's health: the full line for its screen, and a short one for the row's pill. weak is the light's own packet
// loss to its gateway or its Cue, so it can be high at a strong signal
func healthOf(_ d: Device, in all: [Device]) -> (warn: Bool, text: String, short: String)? {
    let h = d.health
    if h.isEmpty { return nil }
    let c = h["companion"] as? String ?? ""
    var warn = true, text = "", short = ""
    if flag(h["setup"]) { text = "In setup: join its hotspot to choose a network"; short = "In setup" }
    else if let why = h["why"] as? String, !why.isEmpty { text = why; short = "Needs a look" }
    else if flag(h["relayed"]) { warn = false; text = "Live, linked to " + nameOf(h["via"], in: all) }
    else if c.hasPrefix("live") { warn = false; text = "Live on Companion" }
    else if c.contains("no Companion host") { text = "No Companion set"; short = text }
    else if c.contains("its Cue") { text = "Waiting for the Cue it is linked to"; short = "Waiting for its Cue" }
    else if c.contains("network") { text = "Waiting for a network"; short = "No network" }
    else { text = "Finding Companion"; short = text }
    // the pill keeps the first reason it found: the light's own state, then packet loss, signal, battery
    var more: [String] = []
    func add(_ t: String, _ s: String, _ w: Bool) { more.append(t); if w { if !warn { short = s }; warn = true } }
    let weak = num(h["weak"]) ?? 0, rssi = num(h["rssi"])
    if weak == 1 { add("WiFi dropping packets", "Dropping packets", true) }
    if weak == 2 { add("CueLink dropping packets", "CueLink dropping packets", true) }
    if !flag(h["relayed"]), h["ssid"] != nil, let r = rssi, r < -75 { add("Weak WiFi signal (\(r) dBm)", "Weak signal", true) }
    let battery = num(h["battery"]), charging = flag(h["charging"])
    if let b = battery {
        let low = b < 20 && !charging
        add("Battery \(b)%" + (charging ? ", charging" : low ? ", not charging" : ""), "Battery \(b)%", low)
    }
    if !warn { short = "Live" + (battery.map { " · \($0)%" } ?? "") }
    return (warn, ([text] + more).joined(separator: " · "), short)
}

// A Relay's own verdict (health_ok, health_why worst first, joined by " · "), worded like a light's line
func relayOf(_ d: Device) -> Pill? {
    let h = d.health
    guard let ok = h["health_ok"] as? Bool else { return nil }   // a Relay from before 0.186.45
    let linked = (h["showing"] as? String).map { " · " + $0 } ?? ""
    if ok { return Pill(tone: .ok, short: "Live", text: "Live on Companion" + linked) }
    let why = (h["health_why"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Needs a look"
    return Pill(tone: .warn, short: why.components(separatedBy: " · ").first ?? why, text: why + linked)
}

// The one pill a row shows: green when it's fine, amber when it needs a look, grey when it isn't answering
func statusOf(_ d: Device, in all: [Device], now: Date = Date()) -> Pill {
    if d.gone {
        return Pill(tone: .off, short: "Not seen",
                    text: (d.lastSeen.map { "Last seen " + ago($0, now: now) + ". " } ?? "Not answering. ") + "It may be unplugged, or off this network.")
    }
    if d.kind == "relay", let r = relayOf(d) { return r }
    if isLight(d), let h = healthOf(d, in: all) { return Pill(tone: h.warn ? .warn : .ok, short: h.short, text: h.text) }
    return Pill(tone: .ok, short: "Online", text: "On the network")
}

func subOf(_ d: Device, in all: [Device], now: Date = Date()) -> String {
    if d.gone, let t = d.lastSeen { return kindName(d) + " · last seen " + ago(t, now: now) }
    if isLight(d), flag(d.health["relayed"]), !d.gone { return kindName(d) + " · linked to " + nameOf(d.health["via"], in: all) }
    return kindName(d) + (d.host.isEmpty ? "" : " · " + d.host)
}

func ago(_ t: Date, now: Date = Date()) -> String {
    let s = max(0, now.timeIntervalSince(t))
    let m = Int((s / 60).rounded()), h = Int((s / 3600).rounded()), d = Int((s / 86400).rounded())
    return s < 60 ? "just now" : m < 60 ? "\(m) min ago" : h < 24 ? "\(h) " + (h == 1 ? "hour ago" : "hours ago") : "\(d) " + (d == 1 ? "day ago" : "days ago")
}

func matches(_ d: Device, _ q: String) -> Bool {
    let q = q.trimmingCharacters(in: .whitespaces).lowercased()
    return q.isEmpty || [d.name, kindName(d), d.host, d.serial, d.key].contains { $0.lowercased().contains(q) }
}

// the order inside a section: here before not seen, then by name, numbers counted as numbers (CAM 2 before CAM 10)
func ordered(_ ds: [Device]) -> [Device] {
    ds.sorted { a, b in
        if a.gone != b.gone { return !a.gone }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}

func countLine(_ all: [Device]) -> String {
    let look = all.filter { !$0.gone && statusOf($0, in: all).tone == .warn }.count, gone = all.filter { $0.gone }.count
    return [all.count == 1 ? "1 device" : "\(all.count) devices",
            look == 0 ? "" : look == 1 ? "1 needs a look" : "\(look) need a look",
            gone == 0 ? "" : "\(gone) not seen"].filter { !$0.isEmpty }.joined(separator: " · ")
}

// A device's pages, as the page's appsOf: the first is its Settings. A One's plain / follows that browser's last
// choice (Touch or Show mode), so Settings asks for Full setup, which opens on its Dashboard
struct Way: Hashable { let name: String; let url: URL }
func waysOf(_ d: Device) -> [Way] {
    let base = "http://" + d.host, page = base + ":\(d.port)"
    func w(_ n: String, _ u: String) -> Way? { URL(string: u).map { Way(name: n, url: $0) } }
    if d.kind != "one" { return [w("Settings", page + "/")].compactMap { $0 } }
    var a = [w("Settings", page + "/?browser=1")]
    if d.hasShow { a.append(w("Show mode", page + "/show")) }
    a.append(w("Touch", page + "/touch"))
    if d.hasApps { a.append(w("Apps", page + "/?browser=1&tab=apps")) }
    if d.companion { a.append(w("Companion", base + ":8000/")) }
    if d.ontime { a.append(w("OnTime", base + ":4001/editor/")) }
    return a.compactMap { $0 }
}

func companionWord(_ c: String) -> String {
    c.hasPrefix("live") ? (c.contains("locked") ? "Live, locked" : "Live") : c.contains("no Companion host") ? "No Companion set"
        : c.contains("its Cue") ? "Waiting for its Cue" : c.contains("network") ? "Waiting for a network" : c.isEmpty ? "" : "Finding Companion"
}
func signalWord(_ rssi: Int) -> String { rssi >= -60 ? "good signal" : rssi >= -72 ? "fair signal" : "weak signal" }
func addressOf(_ d: Device) -> String { d.host.isEmpty ? "" : d.host + (d.port != 0 && d.port != 80 ? ":\(d.port)" : "") }

// A light's brightness and its Hex's, where its /status has them (0.186.38): a percent, 1-100, locked by a Cue PIN
struct BrightPart: Identifiable { let part: String; let label: String; let pct: Int; let locked: Bool; var id: String { part } }
func brightOf(_ d: Device) -> [BrightPart] {
    guard !d.gone else { return [] }
    let h = d.health, locked = (h["tokenSet"] as? NSNumber)?.boolValue ?? h["tokenSet"] as? Bool ?? false
    var out: [BrightPart] = []
    if let v = (h["brightpct"] as? NSNumber)?.intValue { out.append(BrightPart(part: "light", label: "Brightness", pct: v, locked: locked)) }
    if let v = (h["hexBright"] as? NSNumber)?.intValue { out.append(BrightPart(part: "hex", label: "Hex", pct: v, locked: locked)) }
    return out
}
