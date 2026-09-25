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
        let active = UIColor(red: 182.0 / 255, green: 189.0 / 255, blue: 205.0 / 255, alpha: 1)
        for itemAppearance in [
            tabAppearance.stackedLayoutAppearance,
            tabAppearance.inlineLayoutAppearance,
            tabAppearance.compactInlineLayoutAppearance
        ] {
            itemAppearance.normal.iconColor = inactive
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: inactive]
            itemAppearance.selected.iconColor = inactive
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: active]
        }
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        // SwiftUI's TabView tint can override the item's selected appearance.
        // Set the UIKit tint as well so the selected symbol stays blue-gray.
        UITabBar.appearance().tintColor = inactive
        UITabBar.appearance().unselectedItemTintColor = inactive

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithTransparentBackground()
        navigationAppearance.titleTextAttributes = [.foregroundColor: active]
        navigationAppearance.largeTitleTextAttributes = [.foregroundColor: active]
        navigationAppearance.buttonAppearance.normal.titleTextAttributes = [.foregroundColor: inactive]
        navigationAppearance.doneButtonAppearance.normal.titleTextAttributes = [.foregroundColor: inactive]
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = inactive
        AppLogger.app.info("App started")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .foregroundStyle(AetherTheme.secondaryText)
                .environmentObject(environment)
                .environmentObject(environment.playback)
                .environmentObject(environment.library)
                .environmentObject(environment.auth)
                .environmentObject(environment.settings)
                .environmentObject(environment.favorites)
                .environmentObject(environment.history)
                .environmentObject(environment.manualStations)
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
