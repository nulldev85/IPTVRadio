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
                .environmentObject(environment.settings)
                .environmentObject(environment.favorites)
                .environmentObject(environment.history)
                .environmentObject(environment.connectivity)
                .tint(Color.accentColor)
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
