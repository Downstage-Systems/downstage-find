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
    var body: some View {
        VStack(spacing: 10) {
            switch state {
            case .looking:
                ProgressView().tint(Theme.dim).padding(.bottom, 4)
                Text("Looking…").font(.name(24, .title2)).foregroundColor(Theme.text)
                Text("Asking the network for Downstage devices.").foregroundColor(Theme.dim)
            case .nothing:
                Text("Nothing found yet").font(.name(24, .title2)).foregroundColor(Theme.text)
                Text("Check this \(thisDevice) is on the same Wi-Fi as your devices. Some networks hide devices from each other.")
                    .foregroundColor(Theme.dim)
            case .blocked:
                Image(systemName: "network.slash").font(.title).foregroundColor(Color(hex: 0xF7C066)).padding(.bottom, 2)
                Text("Local Network is off").font(.name(24, .title2)).foregroundColor(Theme.text)
                Text("Downstage Find needs Local Network to see your devices. Turn it on in Settings.").foregroundColor(Theme.dim)
                Button { openAppSettings() } label: { Text("Open \(thisDevice) Settings").frame(minHeight: 44) }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
            case .noWiFi:
                Image(systemName: "wifi.slash").font(.title).foregroundColor(Theme.dim).padding(.bottom, 2)
                Text("Not on Wi-Fi").font(.name(24, .title2)).foregroundColor(Theme.text)
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
}

func openAppSettings() {
    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
}

struct DeviceList: View {
    @EnvironmentObject private var model: FindModel
    @State private var query = ""
    @State private var taps: [Date] = []

    var body: some View {
        let all = model.devices
        let shown = all.filter { matches($0, query) }
        let state = model.state
        List {
            banners
            if state != .list {
                Section { StateView(state: state) }
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
                                    .listRowBackground(Theme.panel)
                            }
                        } header: {
                            Text(groups[gi].title).font(.footnote.weight(.semibold)).foregroundColor(Theme.dim).textCase(nil)
                        }
                    }
                }
            }
            foot(all: all, state: state)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .listRowSeparatorTint(Theme.edge)
        .navigationTitle("Devices")
        .searchable(text: $query, prompt: "Search")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .refreshable { await model.lookAgain() }
        .navigationDestination(for: String.self) { key in DeviceScreen(key: key) }
        .onAppear { if query.isEmpty { query = model.startSearch } }
    }

    // A word from the finder (a typed address being asked, a scan), and Local Network when devices are listed but
    // none of them answers
    @ViewBuilder private var banners: some View {
        if model.nothingAnswers {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing is answering. Check Local Network is on for Downstage Find in Settings.")
                        .foregroundColor(Color(hex: 0xF7C066))
                    Button("Open \(thisDevice) Settings") { openAppSettings() }
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            }
            .listRowBackground(Color(hex: 0x33270F))
        } else if let n = model.note, !model.blocked {
            Section {
                Text(n.text).font(.subheadline).foregroundColor(n.warn ? Color(hex: 0xF7C066) : Theme.dim)
            }
            .listRowBackground(n.warn ? Color(hex: 0x33270F) : Theme.panel)
        }
    }

    // The foot: the count, the version, and the way into the demo (five taps on the version, for App Review)
    private func foot(all: [Device], state: ListState) -> some View {
        Section {
            VStack(spacing: 6) {
                if state == .list { Text(countLine(all)); Text("Pull down to look again.") }
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

// The device's own screen comes in step 2; for now its name, kind and state, so a row has somewhere to go
struct DeviceScreen: View {
    @EnvironmentObject private var model: FindModel
    let key: String
    var body: some View {
        let all = model.devices
        ScrollView {
            if let d = all.first(where: { $0.key == key }) {
                VStack(spacing: 8) {
                    DeviceArt(device: d).frame(width: 96, height: 82).padding(.top, 12)
                    Text(d.name).font(.name(30, .largeTitle)).foregroundColor(Theme.text)
                    Text(kindName(d) + (d.version.isEmpty ? "" : " · " + d.version)).font(.subheadline).foregroundColor(Theme.dim)
                    PillView(pill: statusOf(d, in: all, now: model.now))
                    Text(statusOf(d, in: all, now: model.now).text).font(.footnote).foregroundColor(Theme.meta).multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.ground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
