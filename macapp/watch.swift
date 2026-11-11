// What the menu bar item and the alerts know about each device: its one-word state, worded like the page's pill
// (find.html statusOf and healthOf), and the three alerts with their rules. Plain Foundation, so it can be tested
// from Terminal with made-up states.
import Foundation

enum Level { case ok, warn, off }

// The row's pill in one place for the native side: green when it's fine, amber when it needs a look, grey when it
// isn't answering. Kept to the page's words; the page stays the one that writes the full line
func statusOf(_ d: Device) -> (level: Level, text: String) {
    if d.gone { return (.off, "Not seen") }
    let h = d.health
    if d.kind == "relay" {
        guard let ok = h["health_ok"] as? Bool else { return (.ok, "Online") }   // a Relay from before 0.186.45
        if ok { return (.ok, "Live") }
        let why = (h["health_why"] as? String ?? "").components(separatedBy: " · ").first ?? ""
        return (.warn, why.isEmpty ? "Needs a look" : why)
    }
    if d.kind == "one" || d.kind == "view" || h.isEmpty { return (.ok, "Online") }
    let c = h["companion"] as? String ?? ""
    let battery = h["battery"] as? Int, charging = h["charging"] as? Bool ?? false
    var warn: String?
    if h["setup"] as? Bool ?? false { warn = "In setup" }
    else if let why = h["why"] as? String, !why.isEmpty { warn = "Needs a look" }
    else if h["relayed"] as? Bool ?? false || c.hasPrefix("live") { warn = nil }
    else if c.contains("no Companion host") { warn = "No Companion set" }
    else if c.contains("its Cue") { warn = "Waiting for its Cue" }
    else if c.contains("network") { warn = "No network" }
    else { warn = "Finding Companion" }
    if warn == nil {
        let weak = h["weak"] as? Int ?? 0, rssi = h["rssi"] as? Int ?? 0
        if weak == 1 { warn = "Dropping packets" }
        else if weak == 2 { warn = "CueLink dropping packets" }
        else if !(h["relayed"] as? Bool ?? false), h["ssid"] != nil, rssi < -75 { warn = "Weak signal" }
        else if let b = battery, b < 20, !charging { warn = "Battery \(b)%" }
    }
    if let w = warn { return (.warn, w) }
    return (.ok, battery.map { "\($0)%" } ?? "Live")
}

let kindNames = ["one": "Downstage One", "view": "Downstage View", "relay": "Cue Relay", "cue": "Cue", "tally": "Cue",
                 "lite": "Cue Lite", "mini": "Cue Mini", "360": "Cue 360"]

// The alerts, once each per event, never once a poll:
//   a battery light under 20% and not charging (again only after it has charged or come back above 20%),
//   a device that was here and has not answered for 60 s,
//   and that device coming back (only after its "not answering" alert went out).
// A device remembered from another day and not here at launch never alerts: it was never here this time.
final class Alerts {
    var post: (_ title: String, _ body: String) -> Void = { _, _ in }
    var now: () -> Date = { Date() }
    static let goneAfter: TimeInterval = 60
    private var lowSent = Set<String>()
    private var goneSince: [String: Date] = [:]
    private var goneSent = Set<String>()
    private var wasHere = Set<String>()

    func check(_ devices: [String: Device]) {
        let t = now()
        for (key, d) in devices {
            let kind = kindNames[d.kind] ?? "Cue"
            if !d.gone { wasHere.insert(key) }
            // battery
            if !d.gone, let b = d.health["battery"] as? Int {
                let low = b < 20 && !(d.health["charging"] as? Bool ?? false)
                if low && !lowSent.contains(key) { lowSent.insert(key); post("\(d.name) is at \(b)% battery", "\(kind) · not charging.") }
                if !low { lowSent.remove(key) }
            }
            // gone and back
            if d.gone {
                guard wasHere.contains(key) else { continue }
                let since = goneSince[key] ?? t
                goneSince[key] = since
                if t.timeIntervalSince(since) >= Alerts.goneAfter && !goneSent.contains(key) {
                    goneSent.insert(key)
                    post("\(d.name) isn't answering", "\(kind) · not seen for a minute.")
                }
            } else {
                goneSince.removeValue(forKey: key)
                if goneSent.remove(key) != nil { post("\(d.name) is back", "\(kind)" + (d.host.isEmpty ? "." : " · \(d.host)")) }
            }
        }
        // forgotten devices take their state with them
        for k in wasHere where devices[k] == nil { wasHere.remove(k); goneSince.removeValue(forKey: k); goneSent.remove(k); lowSent.remove(k) }
    }
}
