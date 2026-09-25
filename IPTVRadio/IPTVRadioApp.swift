import SwiftUI

@main
struct IPTVRadioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment: AppEnvironment

    init() {
        let env = AppEnvironmentFactory.makeEnvironment(processArguments: ProcessInfo.processInfo.arguments)
        _environment = StateObject(wrappedValue: env)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(red: 7.0 / 255, green: 10.0 / 255, blue: 17.0 / 255, alpha: 1)
        let inactive = UIColor(red: 127.0 / 255, green: 139.0 / 255, blue: 166.0 / 255, alpha: 1)
        let active = UIColor(red: 242.0 / 255, green: 245.0 / 255, blue: 250.0 / 255, alpha: 1)
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

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        AppLogger.app.info("App started")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .foregroundStyle(AetherTheme.primaryText)
                .environmentObject(environment)
                .environmentObject(environment.playback)
                .environmentObject(environment.library)
                .environmentObject(environment.auth)
                .environmentObject(environment.settings)
                .environmentObject(environment.favorites)
                .environmentObject(environment.history)
                .environmentObject(environment.connectivity)
                .tint(AetherTheme.coral)
                .preferredColorScheme(.dark)
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
