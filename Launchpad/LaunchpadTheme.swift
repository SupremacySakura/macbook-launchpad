import AppKit
import SwiftUI

enum LaunchpadAppearanceMode: String, CaseIterable {
    case light
    case dark
    case system

    private static let defaultsKey = "launchpad.appearanceMode"

    static func loadSaved(userDefaults: UserDefaults = .standard) -> LaunchpadAppearanceMode {
        guard let raw = userDefaults.string(forKey: defaultsKey),
              let mode = LaunchpadAppearanceMode(rawValue: raw) else {
            return .light
        }
        return mode
    }

    func save(userDefaults: UserDefaults = .standard) {
        userDefaults.set(rawValue, forKey: Self.defaultsKey)
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .system:
            return nil
        }
    }

    var iconName: String {
        switch self {
        case .light:
            return "sun.max"
        case .dark:
            return "moon.stars"
        case .system:
            return "circle.lefthalf.filled"
        }
    }

    var label: String {
        switch self {
        case .light:
            return "清透浅色"
        case .dark:
            return "静谧深色"
        case .system:
            return "跟随系统"
        }
    }

    var next: LaunchpadAppearanceMode {
        switch self {
        case .light:
            return .dark
        case .dark:
            return .system
        case .system:
            return .light
        }
    }
}

struct LaunchpadTheme: Equatable {
    let isDark: Bool

    init(colorScheme: ColorScheme) {
        self.isDark = colorScheme == .dark
    }

    // MARK: - Backdrop
    var backdropTop: Color {
        isDark
            ? Color(red: 0.06, green: 0.09, blue: 0.13).opacity(0.62)
            : Color(red: 0.955, green: 0.972, blue: 0.985).opacity(0.60)
    }

    var backdropMid: Color {
        isDark
            ? Color(red: 0.055, green: 0.085, blue: 0.125).opacity(0.68)
            : Color(red: 0.945, green: 0.968, blue: 0.982).opacity(0.64)
    }

    var backdropBottom: Color {
        isDark
            ? Color(red: 0.045, green: 0.072, blue: 0.112).opacity(0.72)
            : Color(red: 0.935, green: 0.962, blue: 0.978).opacity(0.68)
    }

    var ambientGlowPrimary: Color {
        isDark
            ? Color(red: 0.35, green: 0.84, blue: 0.78).opacity(0.11)
            : Color(red: 0.56, green: 0.86, blue: 0.80).opacity(0.14)
    }

    var ambientGlowSecondary: Color {
        isDark
            ? Color(red: 0.38, green: 0.62, blue: 0.92).opacity(0.10)
            : Color(red: 0.66, green: 0.82, blue: 0.96).opacity(0.12)
    }

    // MARK: - Accent
    var accent: Color {
        isDark
            ? Color(red: 0.35, green: 0.84, blue: 0.78)
            : Color(red: 0.12, green: 0.62, blue: 0.58)
    }

    // MARK: - Stage Glass
    var stageFillTop: Color {
        isDark
            ? Color.white.opacity(0.055)
            : Color.white.opacity(0.36)
    }

    var stageFillBottom: Color {
        isDark
            ? Color.white.opacity(0.025)
            : Color.white.opacity(0.20)
    }

    var stageBorderTop: Color {
        isDark
            ? Color.white.opacity(0.14)
            : Color.white.opacity(0.72)
    }

    var stageBorderBottom: Color {
        isDark
            ? Color.white.opacity(0.04)
            : Color.white.opacity(0.22)
    }

    var stageShadow: Color {
        isDark
            ? Color.black.opacity(0.24)
            : Color(red: 0.10, green: 0.18, blue: 0.28).opacity(0.06)
    }

    // MARK: - Search Bar
    var searchFill: Color {
        isDark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.56)
    }

    var searchBorder: Color {
        isDark
            ? Color.white.opacity(0.15)
            : Color.white.opacity(0.78)
    }

    var searchFocusedBorder: Color {
        accent.opacity(isDark ? 0.62 : 0.52)
    }

    var searchFocusedHalo: Color {
        accent.opacity(isDark ? 0.18 : 0.14)
    }

    var searchIcon: Color {
        isDark
            ? Color.white.opacity(0.58)
            : Color(red: 0.32, green: 0.40, blue: 0.48)
    }

    var searchText: Color {
        isDark
            ? Color.white.opacity(0.94)
            : Color(red: 0.10, green: 0.14, blue: 0.20)
    }

    var searchPlaceholder: Color {
        isDark
            ? Color.white.opacity(0.46)
            : Color(red: 0.32, green: 0.40, blue: 0.48).opacity(0.85)
    }

    var searchBadgeFill: Color {
        isDark
            ? Color.white.opacity(0.10)
            : Color(red: 0.10, green: 0.14, blue: 0.20).opacity(0.07)
    }

    var searchBadgeText: Color {
        isDark
            ? Color.white.opacity(0.74)
            : Color(red: 0.25, green: 0.33, blue: 0.42)
    }

    // MARK: - App Item
    var itemHoverFill: Color {
        isDark
            ? Color.white.opacity(0.09)
            : Color.white.opacity(0.52)
    }

    var itemHoverBorder: Color {
        isDark
            ? Color.white.opacity(0.16)
            : Color.white.opacity(0.84)
    }

    var itemPrimaryMatchFill: Color {
        accent.opacity(isDark ? 0.12 : 0.08)
    }

    var itemPrimaryMatchBorder: Color {
        accent.opacity(isDark ? 0.44 : 0.34)
    }

    var itemLabel: Color {
        isDark
            ? Color.white.opacity(0.94)
            : Color(red: 0.10, green: 0.14, blue: 0.20)
    }

    var itemLabelShadow: Color {
        isDark ? Color.black.opacity(0.28) : Color.clear
    }

    var placeholderFill: Color {
        isDark
            ? Color.white.opacity(0.07)
            : Color.white.opacity(0.45)
    }

    var placeholderBorder: Color {
        isDark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.65)
    }

    // MARK: - Page Indicator
    var indicatorPillFill: Color {
        isDark
            ? Color.white.opacity(0.07)
            : Color.white.opacity(0.46)
    }

    var indicatorPillBorder: Color {
        isDark
            ? Color.white.opacity(0.12)
            : Color.white.opacity(0.70)
    }

    var indicatorActive: Color {
        accent
    }

    var indicatorInactive: Color {
        isDark
            ? Color.white.opacity(0.28)
            : Color(red: 0.20, green: 0.28, blue: 0.38).opacity(0.24)
    }

    var indicatorHover: Color {
        isDark
            ? Color.white.opacity(0.52)
            : Color(red: 0.20, green: 0.28, blue: 0.38).opacity(0.48)
    }

    // MARK: - Context Menu
    var menuFill: Color {
        isDark
            ? Color(red: 0.11, green: 0.15, blue: 0.20).opacity(0.86)
            : Color.white.opacity(0.86)
    }

    var menuBorder: Color {
        isDark
            ? Color.white.opacity(0.16)
            : Color.white.opacity(0.90)
    }

    var menuShadow: Color {
        isDark
            ? Color.black.opacity(0.36)
            : Color(red: 0.10, green: 0.18, blue: 0.28).opacity(0.14)
    }

    var menuText: Color {
        isDark
            ? Color.white.opacity(0.92)
            : Color(red: 0.10, green: 0.14, blue: 0.20)
    }

    var menuSecondaryText: Color {
        isDark
            ? Color.white.opacity(0.54)
            : Color(red: 0.32, green: 0.40, blue: 0.48)
    }

    var menuHoverFill: Color {
        isDark
            ? Color.white.opacity(0.10)
            : Color(red: 0.10, green: 0.14, blue: 0.20).opacity(0.06)
    }

    var menuDestructive: Color {
        isDark
            ? Color(red: 1.0, green: 0.42, blue: 0.42)
            : Color(red: 0.84, green: 0.20, blue: 0.22)
    }

    var menuDestructiveHoverFill: Color {
        menuDestructive.opacity(isDark ? 0.16 : 0.10)
    }

    var menuDivider: Color {
        isDark
            ? Color.white.opacity(0.10)
            : Color(red: 0.10, green: 0.14, blue: 0.20).opacity(0.08)
    }

    // MARK: - Corner Utility Button
    var utilityFill: Color {
        isDark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.50)
    }

    var utilityBorder: Color {
        isDark
            ? Color.white.opacity(0.14)
            : Color.white.opacity(0.75)
    }

    var utilityIcon: Color {
        isDark
            ? Color.white.opacity(0.78)
            : Color(red: 0.22, green: 0.30, blue: 0.38)
    }
}

struct LaunchpadBackdropView: View {
    let theme: LaunchpadTheme
    let appearance: NSAppearance?

    var body: some View {
        ZStack {
            VisualEffectBackground(appearance: appearance)

            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: theme.backdropTop, location: 0),
                        .init(color: theme.backdropMid, location: 0.5),
                        .init(color: theme.backdropBottom, location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [theme.ambientGlowPrimary, .clear],
                    center: UnitPoint(x: 0.86, y: 0.10),
                    startRadius: 0,
                    endRadius: 880
                )

                RadialGradient(
                    colors: [theme.ambientGlowSecondary, .clear],
                    center: UnitPoint(x: 0.08, y: 0.90),
                    startRadius: 0,
                    endRadius: 760
                )
            }
            .drawingGroup()
        }
        .ignoresSafeArea()
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    let appearance: NSAppearance?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = appearance
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.appearance !== appearance {
            nsView.appearance = appearance
        }
    }
}
