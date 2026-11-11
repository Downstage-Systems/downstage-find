// Downstage Find for iPhone and iPad, native (2026-11-11, Rob: "Rebuild natively"). The finding is shared with the
// Mac app (shared/Finder.swift); the Mac keeps its page, this app draws everything itself in SwiftUI, to
// downstage-clients/docs/ios-app-standard.md.
import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// The brand in iOS shapes: dark only, Run Green tint, pale pills
enum Theme {
    static let ground = Color(hex: 0x0B0D10), panel = Color(hex: 0x12161B), raised = Color(hex: 0x181D23), edge = Color(hex: 0x232A32)
    static let text = Color(hex: 0xE8ECEF), dim = Color(hex: 0xA3ADB6), meta = Color(hex: 0x7C8791)
    static let green = Color(hex: 0x2FD97B), onGreen = Color(hex: 0x06140C)
    static let uiGround = UIColor(red: 0x0B / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0, alpha: 1)
    static let uiText = UIColor(red: 0xE8 / 255.0, green: 0xEC / 255.0, blue: 0xEF / 255.0, alpha: 1)
}

extension Font {
    // Rajdhani 700 is for names and figures only; it grows with Dynamic Type from the text style it stands in for
    static func name(_ size: CGFloat = 18, _ style: Font.TextStyle = .headline) -> Font { .custom("Rajdhani-Bold", size: size, relativeTo: style) }
}

func tapFeel() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }

// what the app says it is, for support: "what version are you on?"
let versionText = "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")"
let thisDevice = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"

@main
struct FindApp: App {
    @StateObject private var model = FindModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.green)
                .onAppear { model.start() }
        }
        .onChange(of: phase) { p in
            if p == .active { model.cameForward() } else if p == .background { model.wentAway() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: FindModel
    var body: some View {
        Group {
            if split {
                // iPad: the list on the left, the device on the right; NavigationSplitView folds itself into one
                // column in a narrow window
                NavigationSplitView {
                    DeviceList(split: true)
                        .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
                } detail: {
                    NavigationStack(path: $model.path) {
                        Group {
                            if let k = model.selected { DeviceScreen(key: k).id(k) }
                            else { ChooseDevice() }
                        }
                        .navigationDestination(for: String.self) { key in DeviceScreen(key: key) }
                    }
                }
                .navigationSplitViewStyle(.balanced)
                .onChange(of: model.selected) { _ in model.path = [] }
            } else {
                NavigationStack(path: $model.path) {
                    DeviceList()
                }
            }
        }
        .background(Theme.ground.ignoresSafeArea())
        // a device's page opens over the app, and Done comes back to it
        .sheet(item: $model.browsing) { b in
            if b.demo { DemoPage(browse: b) } else { SafariView(url: b.url).ignoresSafeArea() }
        }
    }
}

// The iPad's detail column before a device is chosen
struct ChooseDevice: View {
    @EnvironmentObject private var model: FindModel
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.left").font(.largeTitle).foregroundColor(Theme.meta).accessibilityHidden(true)
            Text(model.devices.isEmpty ? "Your devices appear on the left." : "Choose a device.")
                .font(.title3.weight(.semibold)).foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground.ignoresSafeArea())
    }
}

// The one filled green button a screen has: Run Green, dark text, 50 pt or more
struct GreenButton: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .foregroundColor(Theme.onGreen)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.green.opacity(c.isPressed ? 0.8 : 1)))
            .contentShape(Rectangle())
    }
}
