// One device: its art, name and state, then only what that device has today (web/find.html detail()): brightness
// for a light that reports it, Blink for a light or Relay, what it's linked to, its address and serial, a One's
// Companion and OnTime and its pages. Open Settings stays under the thumb and opens inside the app.
import SafariServices
import SwiftUI

struct DeviceScreen: View {
    @EnvironmentObject private var model: FindModel
    let key: String

    var body: some View {
        Group {
            if let d = model.device(key) { content(d) }
            else {
                // forgotten while open, or gone from a look: say so rather than a blank screen
                Text("This device is no longer in the list.").foregroundColor(Theme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.ground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ d: Device) -> some View {
        let all = model.devices, s = statusOf(d, in: all, now: model.now), parts = brightOf(d)
        return List {
            Section {
                VStack(spacing: 6) {
                    DeviceArt(device: d).frame(width: 92, height: 78).opacity(d.gone ? 0.5 : 1).padding(.bottom, 6)
                    Text(d.name).font(.name(30, .largeTitle)).foregroundColor(Theme.text).multilineTextAlignment(.center)
                    Text(kindName(d) + (d.version.isEmpty ? "" : " · " + d.version)).font(.subheadline).foregroundColor(Theme.dim)
                    PillView(pill: s).padding(.top, 4)
                    if s.text != s.short && s.text != "On the network" {
                        Text(s.text).font(.footnote).foregroundColor(Theme.meta).multilineTextAlignment(.center).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)

            if let n = model.note, !model.blocked {
                Section { Text(n.text).font(.subheadline).foregroundColor(n.warn ? Color(hex: 0xF7C066) : Theme.dim) }
                    .listRowBackground(n.warn ? Color(hex: 0x33270F) : Theme.panel)
            }

            if !parts.isEmpty || (canBlink(d) && !d.gone) {
                Section {
                    ForEach(parts) { p in BrightRow(device: d, part: p).listRowBackground(Theme.panel) }
                    if canBlink(d) && !d.gone {
                        let on = model.blinking.contains(d.key)
                        Button { model.blink(d) } label: {
                            Label(on ? "Blinking…" : "Blink this " + (d.kind == "relay" ? "Relay" : "light"), systemImage: "lightbulb.max")
                                .frame(minHeight: 44)
                        }
                        .disabled(on)
                        .listRowBackground(Theme.panel)
                        .accessibilityHint("Blinks it for a few seconds so you can see which one it is.")
                    }
                } footer: {
                    if parts.contains(where: { $0.locked }) { Text("Cue PIN set: change its brightness in Settings.") }
                }
            }

            Section {
                ForEach(rows(d), id: \.label) { r in
                    if let k = r.link {
                        NavigationLink(value: k) { LabeledContent(r.label, value: r.value) }
                            .listRowBackground(Theme.panel)
                    } else {
                        LabeledContent(r.label) {
                            Text(r.value).font(r.mono ? .body.monospaced() : .body).foregroundColor(Theme.dim).multilineTextAlignment(.trailing)
                        }
                        .listRowBackground(Theme.panel)
                        .contextMenu {
                            if let what = r.copy { Button { model.copy(r.value, what) } label: { Label("Copy " + what.lowercased(), systemImage: "doc.on.doc") } }
                        }
                        .accessibilityHint(r.copy == nil ? "" : "Hold to copy.")
                    }
                }
            } header: {
                Text("About").font(.footnote.weight(.semibold)).foregroundColor(Theme.dim).textCase(nil)
            } footer: {
                if rows(d).contains(where: { $0.copy != nil }) { Text("Hold an address or serial to copy it.") }
            }

            let ways = d.gone ? [] : Array(waysOf(d).dropFirst())
            if !ways.isEmpty {
                Section {
                    ForEach(ways, id: \.self) { w in
                        Button { model.open(w, of: d) } label: {
                            HStack { Text(w.name).foregroundColor(Theme.text); Spacer(); Image(systemName: "arrow.up.forward.square").foregroundColor(Theme.meta) }
                                .frame(minHeight: 44)
                        }
                        .listRowBackground(Theme.panel)
                    }
                } header: {
                    Text("Pages").font(.footnote.weight(.semibold)).foregroundColor(Theme.dim).textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowSeparatorTint(Theme.edge)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu { DeviceMenu(device: d, settings: false) } label: { Image(systemName: "ellipsis").accessibilityLabel("More") }
            }
        }
        // the main action under the thumb: Settings for a device that's here, Forget for one that isn't
        .safeAreaInset(edge: .bottom) {
            VStack {
                if d.gone {
                    Button(role: .destructive) { model.forget(d) } label: {
                        Text("Forget this device").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else if let w = waysOf(d).first {
                    Button { model.open(w, of: d) } label: {
                        Text("Open Settings").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(GreenButton())
                }
            }
            .frame(maxWidth: 560)                 // the iPad's wide detail column keeps a button, not a bar
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(Theme.ground.ignoresSafeArea())
        }
        .overlay(alignment: .bottom) { Toast() }
    }

    struct Row { let label: String; let value: String; var mono = false; var copy: String? = nil; var link: String? = nil }

    // the page's detail rows, in its order, each only when the device has it
    private func rows(_ d: Device) -> [Row] {
        let h = d.health, all = model.devices
        var r: [Row] = []
        if isLight(d), !d.gone {
            if (h["relayed"] as? NSNumber)?.boolValue ?? false, let via = h["via"] as? String {
                let o = all.first { $0.key == via }
                r.append(Row(label: "Linked to", value: o?.name ?? "its Relay", link: o?.key))
            } else if let ssid = h["ssid"] as? String {
                let rssi = (h["rssi"] as? NSNumber)?.intValue
                r.append(Row(label: "Network", value: ssid + (rssi.map { " · " + signalWord($0) } ?? "")))
            }
            let cw = companionWord(h["companion"] as? String ?? "")
            if !cw.isEmpty, !((h["relayed"] as? NSNumber)?.boolValue ?? false) { r.append(Row(label: "Companion", value: cw)) }
        }
        if d.kind == "relay", !d.gone, let showing = h["showing"] as? String { r.append(Row(label: "Lights", value: showing)) }
        if d.kind == "one", !d.gone {
            r.append(Row(label: "Companion", value: d.companion ? "Running" : "Not running"))
            r.append(Row(label: "OnTime", value: d.ontime ? "Running" : "Not running"))
        }
        if !d.host.isEmpty { r.append(Row(label: "Address", value: addressOf(d), mono: true, copy: "Address")) }
        if d.gone, let t = d.lastSeen { r.append(Row(label: "Last seen", value: ago(t, now: model.now))) }
        if !d.serial.isEmpty || isLight(d) || d.kind == "relay" { r.append(Row(label: "Serial", value: d.serial.isEmpty ? d.key : d.serial, mono: true, copy: "Serial")) }
        return r
    }
}

// A light's brightness: the number follows the finger, the light hears once, when the slider is let go
struct BrightRow: View {
    @EnvironmentObject private var model: FindModel
    let device: Device
    let part: BrightPart
    @State private var value: Double = 50
    @State private var editing = false

    var body: some View {
        let reported = model.shown(device, part)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(part.label).foregroundColor(part.locked ? Theme.meta : Theme.text)
                Spacer()
                Text("\(Int(editing ? value : Double(reported)))%").monospacedDigit().foregroundColor(part.locked ? Theme.meta : Theme.dim)
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.min").foregroundColor(Theme.meta).accessibilityHidden(true)
                Slider(value: $value, in: 1...100, step: 1) { e in
                    editing = e
                    if !e { model.bright(device, part: part.part, pct: Int(value)) }
                }
                .disabled(part.locked)
                .tint(part.locked ? Theme.meta : Theme.green)
                .accessibilityLabel(part.label)
                .accessibilityValue("\(Int(value)) percent")
                Image(systemName: "sun.max").foregroundColor(Theme.meta).accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .onAppear { value = Double(reported) }
        .onChange(of: reported) { v in if !editing { value = Double(v) } }
    }
}

// The hold-down menu, the same for a row and for the ··· on a device's screen
struct DeviceMenu: View {
    @EnvironmentObject private var model: FindModel
    let device: Device
    var settings = true
    var body: some View {
        let d = device, ways = d.gone ? [] : waysOf(d)
        if settings, let w = ways.first { Button { model.open(w, of: d) } label: { Label("Open Settings", systemImage: "gearshape") } }
        ForEach(ways.dropFirst(), id: \.self) { w in Button { model.open(w, of: d) } label: { Label(w.name, systemImage: "arrow.up.forward.square") } }
        if canBlink(d) && !d.gone {
            Button { model.blink(d) } label: { Label("Blink", systemImage: "lightbulb.max") }.disabled(model.blinking.contains(d.key))
        }
        if !d.host.isEmpty { Button { model.copy(addressOf(d), "Address") } label: { Label("Copy address", systemImage: "doc.on.doc") } }
        if !d.serial.isEmpty { Button { model.copy(d.serial, "Serial") } label: { Label("Copy serial", systemImage: "number") } }
        Divider()
        Button(role: .destructive) { model.forget(d) } label: { Label("Forget this device", systemImage: "trash") }
            .tint(.red)
    }
}

// "Address copied": a word that comes and goes, above the bottom button
struct Toast: View {
    @EnvironmentObject private var model: FindModel
    var body: some View {
        if let t = model.toast {
            Text(t).font(.subheadline.weight(.medium)).foregroundColor(Theme.text)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Theme.raised))
                .overlay(Capsule().stroke(Theme.edge))
                .padding(.bottom, 84)
                .transition(.opacity)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

// A device's page inside the app, in the system browser sheet; Done comes back to Find
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController.Configuration()
        c.entersReaderIfAvailable = false
        let v = SFSafariViewController(url: url, configuration: c)
        v.preferredControlTintColor = UIColor(red: 0x2F / 255.0, green: 0xD9 / 255.0, blue: 0x7B / 255.0, alpha: 1)
        v.preferredBarTintColor = Theme.uiGround
        v.dismissButtonStyle = .done
        return v
    }
    func updateUIViewController(_ v: SFSafariViewController, context: Context) {}
}

// The demo has no device to open: say where its page would be, rather than a browser that can't load
struct DemoPage: View {
    let browse: Browse
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "safari").font(.largeTitle).foregroundColor(Theme.dim).accessibilityHidden(true)
            Text(browse.device + " · " + browse.title).font(.title3.weight(.semibold)).foregroundColor(Theme.text)
            Text("These are demo devices. On a real network, a device's \(browse.title) page opens here, inside the app.")
                .font(.subheadline).foregroundColor(Theme.dim).multilineTextAlignment(.center)
            Text(browse.url.absoluteString).font(.footnote.monospaced()).foregroundColor(Theme.meta)
            Button { dismiss() } label: { Text("Done").font(.body.weight(.semibold)).frame(maxWidth: 320, minHeight: 50) }
                .buttonStyle(GreenButton())
                .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
