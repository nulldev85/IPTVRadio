import SwiftUI
import UIKit

/// The app's visual language, in one place.
///
/// Graphite and brass: a near-black neutral base, three flat surface steps above
/// it, warm off-white type, and a single muted brass accent (the asset catalog's
/// `AccentColor`). Colour is rationed: brass means interactive, sage means live,
/// terracotta means broken, and nothing else in the app is coloured at all — so
/// a colour here always says something.
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
    /// The page. Near-black but neutral-warm rather than pure black, so surfaces
    /// above it are visible without anything having to glow.
    static let appBackground = UIColor(red: 0.063, green: 0.063, blue: 0.075, alpha: 1)
    /// Rows, cards, bars: one step up from the page.
    static let appSurface = UIColor(red: 0.090, green: 0.090, blue: 0.106, alpha: 1)
    /// Controls and input fields: two steps up.
    static let appElevated = UIColor(red: 0.125, green: 0.125, blue: 0.145, alpha: 1)
    /// Separators and borders. A hairline does the work a shadow would.
    static let appHairline = UIColor(white: 1, alpha: 0.09)

    /// Warm off-white. Pure white on graphite reads cold and clinical.
    static let appTextPrimary = UIColor(red: 0.949, green: 0.941, blue: 0.922, alpha: 1)
    static let appTextSecondary = UIColor(red: 0.647, green: 0.639, blue: 0.627, alpha: 1)
    static let appTextTertiary = UIColor(red: 0.424, green: 0.416, blue: 0.404, alpha: 1)

    /// Read from the asset catalog so the accent has exactly one definition.
    static let appAccent = UIColor(named: "AccentColor")
        ?? UIColor(red: 0.788, green: 0.631, blue: 0.416, alpha: 1)
    /// Type and glyphs drawn *on* the accent.
    static let appAccentContrast = UIColor(red: 0.075, green: 0.071, blue: 0.063, alpha: 1)

    /// Live playback. Muted sage: present without shouting.
    static let appLive = UIColor(red: 0.561, green: 0.682, blue: 0.541, alpha: 1)
    /// Failures and warnings. Terracotta instead of system red.
    static let appAlert = UIColor(red: 0.769, green: 0.471, blue: 0.369, alpha: 1)
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

/// The one emphasised button: solid brass, near-black label, no gradient and no
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

/// The quiet counterpart: an elevated surface with a brass label and a hairline
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

    /// Station and settings rows: transparent over the page, hairline separator
    /// in the theme's colour rather than the system's.
    func appListRow() -> some View {
        listRowBackground(Color.appBackground)
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
