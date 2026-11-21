import Foundation
import SonoroCore

/// What the app shares with the widgets through the App Group: only a small
/// `WidgetSnapshot` (never the audio or the whole diary) and the "pending"
/// link left by a control running in the widget extension.
///
/// The real group id is read from the provisioning profile, because
/// free-account signers (Sideloadly / SideStore) may rename it. Without an
/// App Group the widgets show a generic "Registra" button.
enum SharedStore {
    static let configuredGroup = "group.com.garoth93.diariosonoro"
    static let snapshotFile = "widget-snapshot.json"

    static let groupID: String? = {
        var candidates: [String] = []
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url) {
            candidates = ProvisioningProfile.appGroups(from: data)
        }
        if let declared = Bundle.main.object(forInfoDictionaryKey: "DSAppGroup") as? String, !declared.isEmpty {
            candidates.append(declared)
        }
        candidates.append(configuredGroup)
        var seen = Set<String>()
        let ordered = candidates.filter { seen.insert($0).inserted }
        let preferred = ProvisioningProfile.pickGroup(configured: configuredGroup, available: ordered)
        for id in [preferred].compactMap({ $0 }) + ordered {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil { return id }
        }
        return nil
    }()

    static var containerURL: URL? {
        groupID.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    }

    static var isShared: Bool { containerURL != nil }

    static var defaults: UserDefaults {
        groupID.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    // MARK: Widget snapshot

    static func saveSnapshot(_ snapshot: WidgetSnapshot) {
        guard let url = containerURL?.appendingPathComponent(snapshotFile) else { return }
        try? JSONFileStore<WidgetSnapshot>(url: url).save(snapshot)
    }

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let url = containerURL?.appendingPathComponent(snapshotFile) else { return nil }
        return try? JSONFileStore<WidgetSnapshot>(url: url).load()
    }

    // MARK: Pending link (control / Siri running outside the app)

    private static let pendingKey = "pendingDeepLink"
    private static let pendingDateKey = "pendingDeepLinkDate"

    static func setPending(_ link: DeepLink) {
        defaults.set(link.url.absoluteString, forKey: pendingKey)
        defaults.set(Date().timeIntervalSince1970, forKey: pendingDateKey)
    }

    /// Returns (and clears) a pending link created in the last 2 minutes.
    static func takePending() -> DeepLink? {
        let d = defaults
        guard let s = d.string(forKey: pendingKey) else { return nil }
        let t = d.double(forKey: pendingDateKey)
        d.removeObject(forKey: pendingKey)
        d.removeObject(forKey: pendingDateKey)
        guard Date().timeIntervalSince1970 - t < 120, let url = URL(string: s) else { return nil }
        return DeepLink(url: url)
    }
}
