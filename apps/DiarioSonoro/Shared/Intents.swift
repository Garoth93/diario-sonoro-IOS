import AppIntents
import Foundation
import SonoroCore

// Shared by the app and the widget extension (compiled in both targets).
// In the widget extension (`WIDGET_EXTENSION`) the intent leaves a pending
// link in the App Group; the app reads it as soon as it becomes active.

@MainActor
private func open(_ link: DeepLink) {
    #if WIDGET_EXTENSION
    SharedStore.setPending(link)
    #else
    AppModel.shared.handle(link)
    #endif
}

/// Siri / Comandi / tasto Azione: opens the app ready to record.
struct RecordClipIntent: AppIntent {
    static var title: LocalizedStringResource = "Registra un suono"
    static var description = IntentDescription("Apre Diario Sonoro pronto a registrare il suono intorno a te.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        open(.record(.siri))
        return .result()
    }
}

/// Same, used by the Control Center control (and the Action button).
struct ControlRecordIntent: AppIntent {
    static var title: LocalizedStringResource = "Registra un suono (controllo)"
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        open(.record(.control))
        return .result()
    }
}

/// "Un anno fa oggi".
struct OpenAnniversaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Un anno fa oggi"
    static var description = IntentDescription("Riascolta i suoni registrati in questo giorno negli anni passati.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        open(.anniversary)
        return .result()
    }
}

/// Today's soundtrack.
struct OpenTodaySoundtrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Colonna sonora di oggi"
    static var description = IntentDescription("Apre la colonna sonora della giornata.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        open(.soundtrack(DayDate.today()))
        return .result()
    }
}
