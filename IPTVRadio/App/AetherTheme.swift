import SwiftUI

/// One visual language in two appearances. Dynamic system colors let SwiftUI
/// and UIKit follow the selected appearance without rebuilding the tab bars.
enum AetherTheme {
    private static func rgb(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in AetherTheme.rgb(traits.userInterfaceStyle == .dark ? dark : light) }
    }

    static let uiNavigationSurface = adaptive(light: 0xEDF0E8, dark: 0x1B281F)
    static let uiPrimaryText = adaptive(light: 0x222B25, dark: 0xF2F0E7)
    static let uiMutedIcon = adaptive(light: 0x5E705F, dark: 0xAEBFAE)
    static let uiAccent = adaptive(light: 0x2B664C, dark: 0xB5D4B3)

    static let canvas = Color(uiColor: adaptive(light: 0xF5F3EC, dark: 0x111A14))
    static let surface = Color(uiColor: adaptive(light: 0xFFFEF9, dark: 0x1B271E))
    static let navigationSurface = Color(uiColor: uiNavigationSurface)
    static let primaryText = Color(uiColor: uiPrimaryText)
    static let secondaryText = Color(uiColor: adaptive(light: 0x576359, dark: 0xC3CDC0))
    static let mutedIcon = Color(uiColor: uiMutedIcon)
    static let accent = Color(uiColor: uiAccent)
    static let onAccent = Color(uiColor: adaptive(light: 0xFFFFFF, dark: 0x17281C))
    static let accentSoft = Color(uiColor: adaptive(light: 0xD8E8DA, dark: 0x304938))
    static let destructive = Color(uiColor: adaptive(light: 0x8F4036, dark: 0xF0A99D))
    static let border = Color(uiColor: adaptive(light: 0xD0D9CE, dark: 0x3B4C3E))
    static let tabBar = navigationSurface
    static let raisedSurface = surface

    static let background = LinearGradient(
        stops: [
            .init(color: Color(uiColor: adaptive(light: 0xE6ECE2, dark: 0x203126)), location: 0),
            .init(color: canvas, location: 0.38),
            .init(color: canvas, location: 1)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let playerVeil = LinearGradient(
        colors: [
            Color(uiColor: adaptive(light: 0xF5F3EC, dark: 0x07110B)).opacity(0.58),
            Color(uiColor: adaptive(light: 0xF5F3EC, dark: 0x07110B)).opacity(0.70),
            Color(uiColor: adaptive(light: 0xF5F3EC, dark: 0x07110B)).opacity(0.90)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let logoShadow = Color(uiColor: adaptive(light: 0x233027, dark: 0xDCE8DA)).opacity(0.48)

    static let displayFont = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let sectionFont = Font.system(.title2, design: .serif).weight(.semibold)
}
