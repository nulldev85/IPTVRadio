import SwiftUI

/// Aether's browsing identity: warm paper, deep green ink and a restrained
/// mineral accent. Album artwork supplies the saturated color.
enum AetherTheme {
    static let canvas = Color(red: 245 / 255, green: 243 / 255, blue: 236 / 255)
    static let surface = Color(red: 255 / 255, green: 254 / 255, blue: 249 / 255)
    static let navigationSurface = Color(red: 237 / 255, green: 240 / 255, blue: 232 / 255)
    static let primaryText = Color(red: 34 / 255, green: 43 / 255, blue: 37 / 255)
    static let secondaryText = Color(red: 87 / 255, green: 99 / 255, blue: 89 / 255)
    static let mutedIcon = Color(red: 94 / 255, green: 112 / 255, blue: 95 / 255)
    static let accent = Color(red: 43 / 255, green: 102 / 255, blue: 76 / 255)
    static let accentSoft = Color(red: 216 / 255, green: 232 / 255, blue: 218 / 255)
    static let destructive = Color(red: 143 / 255, green: 64 / 255, blue: 54 / 255)
    static let logoWell = Color(red: 29 / 255, green: 50 / 255, blue: 38 / 255)
    static let tabBar = navigationSurface
    static let raisedSurface = surface
    static let border = Color(red: 208 / 255, green: 217 / 255, blue: 206 / 255)

    static let background = LinearGradient(
        stops: [
            .init(color: Color(red: 230 / 255, green: 236 / 255, blue: 226 / 255), location: 0),
            .init(color: canvas, location: 0.38),
            .init(color: canvas, location: 1)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let displayFont = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let sectionFont = Font.system(.title2, design: .serif).weight(.semibold)

    /// The vinyl, fullscreen player and preview bar retain their established
    /// visual treatment independently of the browsing theme.
    enum Player {
        static let topBlue = Color(red: 0.0 / 255, green: 48.0 / 255, blue: 97.0 / 255)
        static let primaryText = Color(red: 242.0 / 255, green: 245.0 / 255, blue: 250.0 / 255)
        static let secondaryText = Color(red: 182.0 / 255, green: 189.0 / 255, blue: 205.0 / 255)
        static let mutedIcon = Color(red: 127.0 / 255, green: 139.0 / 255, blue: 166.0 / 255)
        static let tabBar = Color(red: 7.0 / 255, green: 10.0 / 255, blue: 17.0 / 255)
        static let border = Color(red: 57.0 / 255, green: 65.0 / 255, blue: 82.0 / 255)
        static let background = LinearGradient(
            stops: [
                .init(color: topBlue, location: 0),
                .init(color: Color(red: 0.0 / 255, green: 33.0 / 255, blue: 71.0 / 255), location: 0.18),
                .init(color: Color(red: 0.0 / 255, green: 21.0 / 255, blue: 42.0 / 255), location: 0.34),
                .init(color: Color(red: 0.0 / 255, green: 11.0 / 255, blue: 25.0 / 255), location: 0.50),
                .init(color: Color(red: 0.0 / 255, green: 2.0 / 255, blue: 9.0 / 255), location: 0.68),
                .init(color: .black, location: 0.78)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // Kept for the existing vinyl center detail.
    static let topBlue = Player.topBlue
}
