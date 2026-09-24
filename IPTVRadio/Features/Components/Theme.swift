import SwiftUI
import UIKit

/// The app's visual language, in one place.
///
/// Three values and nothing else: a dark grey base, light grey for secondary
/// text and quiet glyphs, and white for what matters — type you read first, and
/// anything interactive (the asset catalog's `AccentColor`).
///
/// There are no hues at all, so emphasis has to come from weight and brightness
/// rather than colour. That is the point: a palette with nothing to clash makes
/// whatever album art is on screen the only colour in the app.
///
/// Deliberately matte. No blur materials, no gloss gradients, no shadows, no
/// saturated system colours. Depth comes from the surface steps and hairlines,
/// which stay stable on OLED and never shift with whatever artwork is on screen.
///
/// Tokens are defined once as `UIColor` because the UIKit appearance proxies
/// (tab bar, navigation bar) need them too; the `Color` values are derived from
/// the same constants so SwiftUI and UIKit can never drift apart.
enum AppTheme {
    /// Applies the tokens to the UIKit chrome SwiftUI does not reach: the tab
    /// bar and the navigation bars. Both are configured opaque, which replaces
    /// the system's translucent blur with a flat surface and a hairline.
    @MainActor
    static func applyChromeAppearance() {
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = .appBackground
        navigation.shadowColor = .appHairline
        navigation.titleTextAttributes = [.foregroundColor: UIColor.appTextPrimary]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor.appTextPrimary]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        // One step up from the page so the dock the mini player shares with the
        // tab bar reads as a single solid surface.
        tab.backgroundColor = .appSurface
        tab.shadowColor = .appHairline
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = .appTextTertiary
            item.normal.titleTextAttributes = [.foregroundColor: UIColor.appTextTertiary]
            item.selected.iconColor = .appAccent
            item.selected.titleTextAttributes = [.foregroundColor: UIColor.appAccent]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // The sign-in method picker. Left alone it is a light grey pill on a
        // lighter track, which is the loudest thing on that screen.
        let segmented = UISegmentedControl.appearance()
        segmented.backgroundColor = .appSurface
        segmented.selectedSegmentTintColor = .appElevated
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.appTextSecondary], for: .normal)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.appTextPrimary], for: .selected)
    }

    /// Corner radius for cards and controls. One value, used everywhere.
    static let corner: CGFloat = 12
    /// Corner radius for small square things (artwork tiles, placeholders).
    static let smallCorner: CGFloat = 10
}

extension UIColor {
    /// The page: dark grey, not black. Surfaces above it are then visible as
    /// steps rather than needing a border to be found.
    static let appBackground = UIColor(red: 0.102, green: 0.102, blue: 0.110, alpha: 1)
    /// Rows, cards, bars: one step up from the page.
    static let appSurface = UIColor(red: 0.137, green: 0.137, blue: 0.149, alpha: 1)
    /// Controls and input fields: two steps up.
    static let appElevated = UIColor(red: 0.176, green: 0.176, blue: 0.192, alpha: 1)
    /// Separators and borders. A hairline does the work a shadow would.
    static let appHairline = UIColor(white: 1, alpha: 0.10)

    /// White: the first thing read on any screen.
    static let appTextPrimary = UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)
    /// Light grey: everything explanatory.
    static let appTextSecondary = UIColor(red: 0.678, green: 0.678, blue: 0.698, alpha: 1)
    /// Dimmer grey, for glyphs and labels that should recede entirely.
    static let appTextTertiary = UIColor(red: 0.463, green: 0.463, blue: 0.486, alpha: 1)

    /// Read from the asset catalog so the accent has exactly one definition.
    static let appAccent = UIColor(named: "AccentColor") ?? UIColor.white
    /// Type and glyphs drawn *on* the accent, which is white — so, the page.
    static let appAccentContrast = UIColor(red: 0.102, green: 0.102, blue: 0.110, alpha: 1)

    /// Live playback. White, like everything else that matters: with no hues in
    /// the palette, a state is told by its label and its glyph.
    static let appLive = UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)
    /// Failures and warnings — white as well, carried by the warning glyph and
    /// the wording rather than by being red.
    static let appAlert = UIColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)
}

extension Color {
    static let appBackground = Color(uiColor: .appBackground)
    static let appSurface = Color(uiColor: .appSurface)
    static let appElevated = Color(uiColor: .appElevated)
    static let appHairline = Color(uiColor: .appHairline)

    static let appTextPrimary = Color(uiColor: .appTextPrimary)
    static let appTextSecondary = Color(uiColor: .appTextSecondary)
    static let appTextTertiary = Color(uiColor: .appTextTertiary)

    /// The accent, named explicitly rather than via `Color.accentColor`: that
    /// resolves the environment tint, which a local `.tint(…)` can change.
    static let appAccent = Color(uiColor: .appAccent)
    static let appAccentContrast = Color(uiColor: .appAccentContrast)

    static let appLive = Color(uiColor: .appLive)
    static let appAlert = Color(uiColor: .appAlert)
}

// MARK: - Controls

/// The one emphasised button: solid white, dark grey label, no gradient and no
/// shadow. Pressing dims it rather than scaling it.
struct AppProminentButtonStyle: ButtonStyle {
    /// Sign-in style buttons stretch; inline ones size to their label.
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.appAccentContrast)
            .padding(.horizontal, 24)
            .frame(maxWidth: fullWidth ? CGFloat.infinity : nil, minHeight: 46)
            .background(Color.appAccent.opacity(configuration.isPressed ? 0.72 : 1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous))
    }
}

/// The quiet counterpart: an elevated surface with a white label and a hairline
/// border. Used where a button is an option rather than the point of the screen.
struct AppQuietButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.appAccent)
            .padding(.horizontal, 24)
            .frame(maxWidth: fullWidth ? CGFloat.infinity : nil, minHeight: 46)
            .background(Color.appElevated.opacity(configuration.isPressed ? 0.6 : 1))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                    .strokeBorder(Color.appHairline, lineWidth: 1)
            )
    }
}

extension View {
    /// Puts the app's base colour behind a `List`, `Form` or `ScrollView`,
    /// replacing the system's grouped greys.
    func appScrollBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
    }

    /// A flat card: surface fill, hairline border, shared corner radius.
    func appCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                    .strokeBorder(Color.appHairline, lineWidth: 1)
            )
    }

    /// Text-field chrome. Replaces `.roundedBorder`, whose bezel is the one
    /// genuinely shiny control iOS still ships.
    func appFieldBackground() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.appElevated)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.corner, style: .continuous)
                    .strokeBorder(Color.appHairline, lineWidth: 1)
            )
    }

    /// Station and settings rows: flush with the page, hairline separator in
    /// the theme's colour rather than the system's.
    ///
    /// `highlighted` lifts a row onto the surface step. With no hues to spend,
    /// that step is how "this is the one playing" is said — a brighter label
    /// would be indistinguishable from an ordinary one.
    func appListRow(highlighted: Bool = false) -> some View {
        listRowBackground(highlighted ? Color.appSurface : Color.appBackground)
            .listRowSeparatorTint(Color.appHairline)
    }

    /// Section chrome for a `Form`: rows on the surface step, theme hairlines
    /// between them, applied to a whole `Section` at once.
    func appFormSection() -> some View {
        listRowBackground(Color.appSurface)
            .listRowSeparatorTint(Color.appHairline)
    }

    /// A one-pixel rule along the top edge, used where a bar meets content.
    func appTopHairline() -> some View {
        overlay(alignment: .top) {
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 0.5)
        }
    }
}
