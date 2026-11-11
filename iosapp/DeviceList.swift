// The first screen: every Downstage device here, grouped Ones, lights, Relays, Views, with the system's own search and
// pull to refresh. Where there are no devices to show, the list says why in one sentence, in the place they would be.
import SwiftUI
import UIKit

struct DeviceArt: View {
    let device: Device
    var body: some View {
        Image(artName(device))
            .resizable()
            .scaledToFit()
            // the art is dark on dark: the page's faint outline, so its edge reads on the panel
            .shadow(color: Color(hex: 0xCFD6DC).opacity(0.55), radius: 0.4)
            .accessibilityHidden(true)
    }
}

struct PillView: View {
    let pill: Pill
    var body: some View {
        let (bg, fg): (Color, Color) = {
            switch pill.tone {
            case .ok: return (Color(hex: 0x10301D), Color(hex: 0x74E8A8))
            case .warn: return (Color(hex: 0x33270F), Color(hex: 0xF7C066))
            case .off: return (Theme.raised, Theme.meta)
            }
        }()
        Text(pill.short)
            .font(.footnote.weight(.medium))
            .foregroundColor(fg)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(bg))
    }
}

struct DeviceRow: View {
    let device: Device
    let all: [Device]
    let now: Date
    @Environment(\.dynamicTypeSize) private var type

    var body: some View {
        let pill = statusOf(device, in: all, now: now)
        let name = Text(device.name).font(.name(18, .headline)).foregroundColor(Theme.text)
        let sub = Text(subOf(device, in: all, now: now)).font(.footnote).foregroundColor(Theme.meta)
        let art = DeviceArt(device: device).frame(width: 44, height: 38).opacity(device.gone ? 0.5 : 1)
        Group {
            if type.isAccessibilitySize {
                // the biggest sizes: words and pill stacked, no art, nothing cut off
                VStack(alignment: .leading, spacing: 6) { name; sub; PillView(pill: pill) }
            } else {
                // the pill on the name's line, the description under both; a name and pill too long for one line
                // stack, so a name is never cut short
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        art
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                name.lineLimit(1).fixedSize(horizontal: true, vertical: false)
                                Spacer(minLength: 4)
                                PillView(pill: pill)
                            }
                            sub.lineLimit(2)
                        }
                    }
                    HStack(spacing: 12) {
                        art
                        VStack(alignment: .leading, spacing: 3) {
                            name.lineLimit(2)
                            sub.lineLimit(2)
                            PillView(pill: pill).padding(.top, 3)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .opacity(device.gone ? 0.85 : 1)
        .padding(.vertical, 2)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(device.name), \(subOf(device, in: all, now: now))")
        .accessibilityValue(pill.text)
    }
}

// A state in the list's place: one sentence, and the one thing to do about it
struct StateView: View {
    let state: ListState
    var add: () -> Void = {}
    var scan: () -> Void = {}
    var scanning = false
    var body: some View {
        VStack(spacing: 10) {
            switch state {
            case .looking:
                ProgressView().tint(Theme.dim).padding(.bottom, 4).accessibilityHidden(true)
                Text("Looking…").font(.title3.weight(.semibold)).foregroundColor(Theme.text)
                Text("Asking the network for Downstage devices.").foregroundColor(Theme.dim)
            case .nothing:
                Text("Nothing found yet").font(.title3.weight(.semibold)).foregroundColor(Theme.text)
                Text("Check this \(thisDevice) is on the same Wi-Fi as your devices. Some networks hide devices from each other: add one by its address, or scan the network.")
                    .foregroundColor(Theme.dim)
                ViewThatFits {
                    HStack(spacing: 10) { offers }
                    VStack(spacing: 10) { offers }
                }
                .padding(.top, 8)
            case .blocked:
                Image(systemName: "network.slash").font(.title).foregroundColor(Color(hex: 0xF7C066)).padding(.bottom, 2).accessibilityHidden(true)
                Text("Local Network is off").font(.title3.weight(.semibold)).foregroundColor(Theme.text)
                Text("Downstage Find needs Local Network to see your devices. Turn it on in Settings.").foregroundColor(Theme.dim)
                Button { tapFeel(); openAppSettings() } label: {
                    Text("Open \(thisDevice) Settings").font(.body.weight(.semibold)).frame(maxWidth: 320, minHeight: 50)
                }
                .buttonStyle(GreenButton())
                .padding(.top, 8)
            case .noWiFi:
                Image(systemName: "wifi.slash").font(.title).foregroundColor(Theme.dim).padding(.bottom, 2).accessibilityHidden(true)
                Text("Not on Wi-Fi").font(.title3.weight(.semibold)).foregroundColor(Theme.text)
                Text("Join the show's Wi-Fi on this \(thisDevice) to find your devices.").foregroundColor(Theme.dim)
            case .list:
                EmptyView()
            }
        }
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 12)
    }
    @ViewBuilder private var offers: some View {
        Button(action: add) { Text("Add by address…").frame(minHeight: 44).padding(.horizontal, 6) }
            .buttonStyle(.bordered)
        Button(action: scan) { Text(scanning ? "Scanning…" : "Scan this network…").frame(minHeight: 44).padding(.horizontal, 6) }
            .buttonStyle(.bordered)
            .disabled(scanning)
    }
}

func openAppSettings() {
    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
}

struct DeviceList: View {
    @EnvironmentObject private var model: FindModel
    var split = false                       // the iPad's sidebar: rows select, the detail column shows the device
    @State private var query = ""
    @State private var taps: [Date] = []
    @State private var asking = false
    @State private var address = ""
    @State private var scanAsk = false
    @State private var allBright = false
    @State private var forgetAsk = false

    var body: some View {
        let all = model.devices
        let shown = all.filter { matches($0, query) }
        let state = model.state
        list(all: all, shown: shown, state: state)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .listRowSeparatorTint(Theme.edge)
            .navigationTitle("Devices")
            .searchable(text: $query, prompt: "Search")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .refreshable { await model.lookAgain() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { address = ""; asking = true } label: { Label("Add by address…", systemImage: "plus.magnifyingglass") }
                        Button { scanAsk = true } label: { Label(model.scanning ? "Scanning…" : "Scan this network…", systemImage: "dot.radiowaves.left.and.right") }
                            .disabled(model.scanning)
                    } label: {
                        Image(systemName: "plus").accessibilityLabel("Add a device")
                    }
                }
            }
            // For a network that hides devices from each other: a typed address joins the list like any other
            .alert("Add by address", isPresented: $asking) {
                TextField("192.168.1.50", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Add") { model.add(address) }
            } message: {
                Text("For a network that hides devices from each other. Type the device's address and it joins the list like any other.")
            }
            .alert("Scan this network?", isPresented: $scanAsk) {
                Button("Cancel", role: .cancel) {}
                Button("Scan") { model.scan() }
            } message: {
                Text("This knocks on every address on your network. It takes a few seconds, but some venue networks treat it as an attack, so ask first if it isn't your network.")
            }
            .sheet(isPresented: $allBright) { AllBrightSheet() }
            .onAppear { if query.isEmpty { query = model.startSearch } }
            .overlay(alignment: .bottom) { Toast() }
            .modifier(Destination(on: !split))
    }

    @ViewBuilder private func list(all: [Device], shown: [Device], state: ListState) -> some View {
        if split {
            List(selection: $model.selected) { content(all: all, shown: shown, state: state) }
        } else {
            List { content(all: all, shown: shown, state: state) }
        }
    }

    @ViewBuilder private func content(all: [Device], shown: [Device], state: ListState) -> some View {
        banners
        if state != .list {
            Section { StateView(state: state, add: { address = ""; asking = true }, scan: { scanAsk = true }, scanning: model.scanning) }
                .listRowBackground(Color.clear)
        } else if shown.isEmpty {
            Section {
                Text("No device matches “\(query.trimmingCharacters(in: .whitespaces))”.")
                    .foregroundColor(Theme.meta)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
            .listRowBackground(Color.clear)
        } else {
            ForEach(groups.indices, id: \.self) { gi in
                let rows = ordered(shown.filter { groupOf($0) == gi })
                if !rows.isEmpty {
                    Section {
                        ForEach(rows) { d in
                            NavigationLink(value: d.key) { DeviceRow(device: d, all: all, now: model.now) }
                                .tag(d.key)
                                .listRowBackground(split && model.selected == d.key ? Theme.raised : Theme.panel)
                                .contextMenu { DeviceMenu(device: d) }
                                // swipe left: Settings for a device that's here, Forget for one that isn't
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if d.gone {
                                        Button(role: .destructive) { model.forget(d) } label: { Label("Forget", systemImage: "trash") }
                                    } else if let w = waysOf(d).first {
                                        Button { model.open(w, of: d) } label: { Label("Settings", systemImage: "gearshape") }
                                            .tint(Theme.green)
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Text(groups[gi].title)
                            Spacer()
                            // one slider for every light, where two or more report a brightness (the Mac's offer)
                            if groups[gi].title == "Lights" && model.allLights.count >= 2 {
                                Button { allBright = true } label: { Text("Brightness for all").frame(minHeight: 30) }
                                    .foregroundColor(Theme.green)
                                    .accessibilityHint("One slider for every light here.")
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Theme.dim)
                        .textCase(nil)
                    }
                }
            }
        }
        foot(all: all, state: state)
    }

    // A word from the finder (a typed address being asked, a scan, Brightness for all), and what's in the way when
    // devices are listed: Local Network off, nothing answering, or this phone off Wi-Fi
    @ViewBuilder private var banners: some View {
        if !model.devices.isEmpty && !model.demo && (model.blocked || model.nothingAnswers) {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.blocked ? "Local Network is off for Downstage Find, so it can't see your devices. Turn it on in Settings."
                                       : "Nothing is answering. Check Local Network is on for Downstage Find in Settings.")
                        .foregroundColor(Color(hex: 0xF7C066))
                    Button("Open \(thisDevice) Settings") { tapFeel(); openAppSettings() }
                        .frame(minHeight: 44)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
            .listRowBackground(Color(hex: 0x33270F))
        } else if !model.devices.isEmpty && !model.demo && !model.onNetwork {
            Section {
                Label("Not on Wi-Fi: join the show's Wi-Fi on this \(thisDevice) to reach your devices.", systemImage: "wifi.slash")
                    .font(.subheadline).foregroundColor(Color(hex: 0xF7C066))
            }
            .listRowBackground(Color(hex: 0x33270F))
        } else if let n = model.note, !model.blocked {
            Section {
                HStack(spacing: 10) {
                    if model.scanning { ProgressView().tint(Theme.dim) }
                    Text(n.text).font(.subheadline).foregroundColor(n.warn ? Color(hex: 0xF7C066) : Theme.dim)
                }
            }
            .listRowBackground(n.warn ? Color(hex: 0x33270F) : Theme.panel)
        }
    }

    // The foot: the count, Forget All when some are remembered, the version, and the way into the demo (five taps on
    // the version, for App Review)
    private func foot(all: [Device], state: ListState) -> some View {
        Section {
            VStack(spacing: 6) {
                if state == .list { Text(countLine(all)); Text("Pull down to look again.") }
                if model.rememberedCount > 0 {
                    Button { forgetAsk = true } label: {
                        Text(model.rememberedCount == 1 ? "Forget the 1 not seen…" : "Forget the \(model.rememberedCount) not seen…").frame(minHeight: 44)
                    }
                    .foregroundColor(Theme.dim)
                    .accessibilityHint("Devices this \(thisDevice) remembers stay for 30 days after they were last seen.")
                    // anchored on the button, so the iPad's popover points at it
                    .confirmationDialog(model.rememberedCount == 1 ? "Forget 1 device?" : "Forget \(model.rememberedCount) devices?",
                                        isPresented: $forgetAsk, titleVisibility: .visible) {
                        Button("Forget All", role: .destructive) { model.forgetAll() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Devices that aren't here now come off the list. Any that come back are found again as new.")
                    }
                }
                Text(model.demo ? versionText + " · demo devices" : versionText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { tappedVersion() }
                    .accessibilityAddTraits(.isStaticText)
            }
            .font(.footnote)
            .foregroundColor(Theme.meta)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    private func tappedVersion() {
        let t = Date()
        taps = taps.filter { t.timeIntervalSince($0) < 3 } + [t]
        if taps.count >= 5 {
            taps = []
            tapFeel()
            model.setDemo(!model.demo)
        }
    }
}

// On the iPhone the list pushes a device's screen; on the iPad the detail column does that instead
struct Destination: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.navigationDestination(for: String.self) { key in DeviceScreen(key: key) } } else { content }
    }
}

// Brightness for all: one slider for every light here that has one. Each light gets one write, when it's let go;
// a light with a Cue PIN is skipped and counted
struct AllBrightSheet: View {
    @EnvironmentObject private var model: FindModel
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 50
    @State private var editing = false
    @State private var started = false

    var body: some View {
        let ls = model.allLights, open = ls.filter { !(brightOf($0).first?.locked ?? false) }, pinned = ls.count - open.count
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("All lights").foregroundColor(open.isEmpty ? Theme.meta : Theme.text)
                    Spacer()
                    Text("\(Int(value))%").monospacedDigit().foregroundColor(Theme.dim)
                }
                HStack(spacing: 10) {
                    Image(systemName: "sun.min").foregroundColor(Theme.meta).accessibilityHidden(true)
                    Slider(value: $value, in: 1...100, step: 1) { e in
                        editing = e
                        if !e { model.brightAll(Int(value)) }
                    }
                    .disabled(open.isEmpty)
                    .tint(open.isEmpty ? Theme.meta : Theme.green)
                    .accessibilityLabel("Brightness for all lights")
                    .accessibilityValue("\(Int(value)) percent")
                    Image(systemName: "sun.max").foregroundColor(Theme.meta).accessibilityHidden(true)
                }
                Text((open.isEmpty ? "Every light here has a Cue PIN." : "Sets \(open.count) " + (open.count == 1 ? "light" : "lights") + " when you let go.") +
                     (pinned > 0 ? " \(pinned) with a Cue PIN " + (pinned == 1 ? "is" : "are") + " skipped: change " + (pinned == 1 ? "it" : "those") + " in Settings." : ""))
                    .font(.footnote).foregroundColor(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
                if let n = model.note, n.text.hasPrefix("Brightness ") {
                    Label(n.text, systemImage: "checkmark.circle").font(.footnote).foregroundColor(Color(hex: 0x74E8A8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Brightness for all")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // starts at the lights' average, like the Mac
            guard !started else { return }
            started = true
            let ps = open.compactMap { brightOf($0).first?.pct }
            value = ps.isEmpty ? 50 : Double(Int((Double(ps.reduce(0, +)) / Double(ps.count)).rounded()))
        }
    }
}
