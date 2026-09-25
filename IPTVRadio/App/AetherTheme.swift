import SwiftUI

/// Colors sampled from the supplied SiriusXM reference screenshot.
enum AetherTheme {
    static let topBlue = Color(red: 0.0 / 255, green: 48.0 / 255, blue: 97.0 / 255)
    static let primaryText = Color(red: 242.0 / 255, green: 245.0 / 255, blue: 250.0 / 255)
    // Representative foreground pixels sampled from the supplied JPEG:
    // supporting copy #B6BDCD, muted outline controls #7F8BA6.
    static let secondaryText = Color(red: 182.0 / 255, green: 189.0 / 255, blue: 205.0 / 255)
    static let mutedIcon = Color(red: 127.0 / 255, green: 139.0 / 255, blue: 166.0 / 255)
    static let coral = Color(red: 255.0 / 255, green: 107.0 / 255, blue: 88.0 / 255)
    static let tabBar = Color(red: 7.0 / 255, green: 10.0 / 255, blue: 17.0 / 255)
    static let raisedSurface = Color(red: 10.0 / 255, green: 14.0 / 255, blue: 23.0 / 255)
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
