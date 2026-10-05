import SwiftUI

@main
struct IPTVRadioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment: AppEnvironment

    init() {
        let env = AppEnvironmentFactory.makeEnvironment(processArguments: ProcessInfo.processInfo.arguments)
        _environment = StateObject(wrappedValue: env)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundColor = AetherTheme.uiNavigationSurface.withAlphaComponent(0.94)
        let inactive = AetherTheme.uiMutedIcon
        let active = AetherTheme.uiAccent
        for itemAppearance in [
            tabAppearance.stackedLayoutAppearance,
            tabAppearance.inlineLayoutAppearance,
            tabAppearance.compactInlineLayoutAppearance
        ] {
            itemAppearance.normal.iconColor = inactive
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: inactive]
            itemAppearance.selected.iconColor = active
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: active]
        }
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        // Match the system tab bar and the optional flat navigation bar.
        UITabBar.appearance().tintColor = active
        UITabBar.appearance().unselectedItemTintColor = inactive

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithTransparentBackground()
        navigationAppearance.titleTextAttributes = [.foregroundColor: AetherTheme.uiPrimaryText]
        var largeTitleAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: AetherTheme.uiPrimaryText]
        let titleFont = UIFont.systemFont(ofSize: 35, weight: .semibold)
        if let descriptor = titleFont.fontDescriptor.withDesign(.serif) {
            largeTitleAttributes[.font] = UIFont(descriptor: descriptor, size: 35)
        }
        navigationAppearance.largeTitleTextAttributes = largeTitleAttributes
        navigationAppearance.buttonAppearance.normal.titleTextAttributes = [.foregroundColor: active]
        navigationAppearance.doneButtonAppearance.normal.titleTextAttributes = [.foregroundColor: active]
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = active
        AppLogger.app.info("App started")
    }

    var body: some Scene {
        WindowGroup {
            ThemedRootView()
                .foregroundStyle(AetherTheme.primaryText)
                .environmentObject(environment)
                .environmentObject(environment.playback)
                .environmentObject(environment.library)
                .environmentObject(environment.auth)
                .environmentObject(environment.settings)
                .environmentObject(environment.favorites)
                .environmentObject(environment.history)
                .environmentObject(environment.manualStations)
                .environmentObject(environment.connectivity)
                .tint(AetherTheme.accent)
        }
    }
}

private struct ThemedRootView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        RootView()
            .preferredColorScheme(settings.appearance.colorScheme)
    }
}

private extension SettingsStore.Appearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Audio session configuration happens in PlaybackEngine when playback starts.
        return true
    }
}
