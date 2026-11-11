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
    var body: some View {
        NavigationStack {
            DeviceList()
        }
        .background(Theme.ground.ignoresSafeArea())
    }
}
