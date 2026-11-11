// Made-up devices for the demo: App Review, screenshots and tests. No network at all; the names are generic and the
// addresses are a made-up 192.168.1.x. Their reports are shaped like the real /status answers (Finder.lightHealth,
// relayHealth), so every row and pill is drawn by the same code as a real device's.
import Foundation

enum Demo {
    static func devices(now: Date = Date()) -> [Device] {
        #if DEBUG
        // DOWNSTAGE_DEMO=empty: a demo network with nothing Downstage on it, for the empty states and "found nothing"
        if ProcessInfo.processInfo.environment["DOWNSTAGE_DEMO"] == "empty" { return [] }
        #endif
        var out: [Device] = []
        func add(_ d: Device, _ health: [String: Any] = [:], seen: TimeInterval = 0) {
            var d = d
            d.health = health
            d.heard = !d.gone; d.answered = !d.gone
            d.lastSeen = now.addingTimeInterval(-seen)
            out.append(d)
        }
        var foh = Device(key: "DS1-DEMO-0001", kind: "one", name: "FOH", host: "192.168.1.20", port: 8080, serial: "DS1-DEMO-0001", version: "1.8.2")
        foh.companion = true; foh.ontime = true; foh.hasApps = true; foh.hasShow = true
        add(foh)
        add(Device(key: "DSR-DEMO-07", kind: "relay", name: "RELAY", host: "192.168.1.31", port: 80, serial: "DSR-DEMO-07", version: "0.186.48"),
            ["health_ok": true, "showing": "2 of 3 linked"])
        add(Device(key: "DSC-DEMO-11", kind: "cue", name: "CAM 1", host: "192.168.1.41", port: 80, serial: "DSC-DEMO-11", version: "0.186.49"),
            ["companion": "live", "relayed": true, "via": "DSR-DEMO-07", "brightpct": 80, "weak": 0])
        add(Device(key: "DSL-DEMO-42", kind: "lite", name: "CAM 2", host: "192.168.1.42", port: 80, serial: "DSL-DEMO-42", version: "0.186.49"),
            ["companion": "live", "ssid": "SHOW", "rssi": -58, "battery": 18, "charging": false, "brightpct": 64, "weak": 0])
        add(Device(key: "DS3-DEMO-03", kind: "360", name: "CAM 3", host: "192.168.1.43", port: 80, serial: "DS3-DEMO-03", version: "0.186.49"),
            ["companion": "no Companion host set", "ssid": "SHOW", "rssi": -64, "brightpct": 100, "hexBright": 70, "weak": 0])
        add(Device(key: "DSM-DEMO-05", kind: "mini", name: "STAGE RIGHT", host: "192.168.1.45", port: 80, serial: "DSM-DEMO-05", version: "0.186.49"),
            ["companion": "live", "relayed": true, "via": "DSR-DEMO-07", "brightpct": 50, "tokenSet": true, "weak": 2])
        var left = Device(key: "DSM-DEMO-04", kind: "mini", name: "STAGE LEFT", host: "", port: 0, serial: "DSM-DEMO-04", version: "0.186.40")
        left.gone = true
        add(left, seen: 26 * 3600)
        var lobby = Device(key: "DSV-DEMO-02", kind: "view", name: "LOBBY", host: "192.168.1.60", port: 8080, serial: "DSV-DEMO-02", version: "1.8.2")
        lobby.companion = false
        add(lobby)
        return out
    }
}
