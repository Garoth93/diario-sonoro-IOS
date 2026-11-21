import SwiftUI
import UserNotifications
import AppIntents
import SonoroCore

/// Registers the background task and handles notification taps.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundBuilder.register()
        UNUserNotificationCenter.current().delegate = self
        MainActor.assumeIsolated { _ = AppModel.shared }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let link = (response.notification.request.content.userInfo["link"] as? String).flatMap(URL.init(string:))
        Task { @MainActor in
            if let link { AppModel.shared.handle(url: link) }
            completionHandler()
        }
    }
}

@main
struct DiarioSonoroApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ThemedRoot()
                .environment(model)
                .environment(model.player)
                .onOpenURL { model.handle(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.setActive(true)
            case .background:
                model.setActive(false)
                model.lockIfNeeded()
            default:
                break
            }
        }
    }
}

/// Builds the Material palette for the current light/dark appearance.
private struct ThemedRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var systemScheme

    private var scheme: ColorScheme {
        switch model.settings.appearance {
        case .system: return systemScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        let theme = M3Theme(seed: Palette.defaultAccent, dark: scheme == .dark)
        Group {
            if LaunchOptions.screen == "widgets" {
                WidgetGalleryView()
            } else {
                RootView()
            }
        }
        .environment(\.m3, theme)
        .tint(theme.primary)
        .preferredColorScheme(model.settings.appearance == .system ? nil : scheme)
    }
}

/// Siri / Spotlight / Action button phrases.
struct DiarioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordClipIntent(),
            phrases: [
                "Registra con \(.applicationName)",
                "Registra un suono con \(.applicationName)",
                "Apri \(.applicationName) e registra"
            ],
            shortTitle: "Registra un suono",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: OpenTodaySoundtrackIntent(),
            phrases: [
                "Colonna sonora di oggi su \(.applicationName)",
                "Ascolta la giornata con \(.applicationName)"
            ],
            shortTitle: "Colonna sonora di oggi",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: OpenAnniversaryIntent(),
            phrases: [
                "Un anno fa oggi su \(.applicationName)",
                "Cosa ho registrato un anno fa con \(.applicationName)"
            ],
            shortTitle: "Un anno fa oggi",
            systemImageName: "clock.arrow.circlepath"
        )
    }
}
