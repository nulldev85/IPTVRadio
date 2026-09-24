import SwiftUI

@main
struct IPTVRadioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment: AppEnvironment

    init() {
        let env = AppEnvironmentFactory.makeEnvironment(processArguments: ProcessInfo.processInfo.arguments)
        _environment = StateObject(wrappedValue: env)
        AppLogger.app.info("App started")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.playback)
                .environmentObject(environment.library)
                .environmentObject(environment.auth)
                .environmentObject(environment.settings)
                .environmentObject(environment.favorites)
                .environmentObject(environment.history)
                .environmentObject(environment.connectivity)
                .tint(Color.appAccent)
                // The app has one appearance: the graphite theme. Locking it
                // here (and in Info.plist, for UIKit's own chrome) is what
                // lets every screen be designed for a dark base instead of
                // hedging between two.
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Tab bar and navigation bars are UIKit, so the theme has to be
        // pushed into their appearance proxies before the first view is
        // built. Audio session configuration happens in PlaybackEngine when
        // playback starts.
        AppTheme.applyChromeAppearance()
        return true
    }
}
