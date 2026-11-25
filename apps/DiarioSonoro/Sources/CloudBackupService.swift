import Foundation
import SwiftUI
import SonoroCore

/// Automatic backups in iCloud Drive, in the shared container
/// `iCloud.com.garoth93.backup` › Documents › DiarioSonoro (visible in the
/// Files app as iCloud Drive › Backup › DiarioSonoro). One JSON per day plus
/// "latest"; the clips' audio in `audio/` only when enabled in Settings,
/// each file uploaded once. Written when the data change, when the app goes
/// to background and from the background refresh. Restore from Settings, or
/// guided at first launch when the diary is empty. Nothing sensitive exists
/// in the app (no tokens, no accounts), so nothing sensitive is written.
@MainActor
@Observable
final class CloudBackupService {
    static let shared = CloudBackupService()

    /// nil = not checked yet; false = iCloud off / not signed in / no entitlement.
    private(set) var available: Bool?
    private(set) var isWorking = false
    private(set) var progress: String?
    private(set) var lastBackupAt: Date? = UserDefaults.standard.object(forKey: Keys.lastAt) as? Date
    private(set) var lastError: String?
    private(set) var entries: [CloudBackupPlan.Entry] = []
    /// Set when an empty diary finds a backup: RootView shows the guided restore.
    var offerRestore = false

    @ObservationIgnored private var scheduled: Task<Void, Never>?

    private enum Keys {
        static let fingerprint = "cloudBackup.fingerprint"
        static let lastAt = "cloudBackup.lastAt"
        static let restoreOffered = "cloudBackup.restoreOffered"
    }

    private var model: AppModel { AppModel.shared }
    private var enabled: Bool { !model.isDemo && model.settings.cloudBackup }

    // MARK: Folder

    /// Resolving the ubiquity container can block: always off the main thread.
    nonisolated static func folderURL() async -> URL? {
        await Task.detached(priority: .utility) { () -> URL? in
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: CloudBackupPlan.containerID) else { return nil }
            let folder = container.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(CloudBackupPlan.folderName, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }.value
    }

    // MARK: Backup

    /// After a change: back up a few seconds later (many edits → one write).
    func schedule() {
        guard enabled else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(CloudBackupPlan.debounceSeconds))
            guard !Task.isCancelled else { return }
            await self?.backup(force: false)
        }
    }

    /// Writes the backup if the content changed since the last one (or `force`).
    /// An empty diary never overwrites existing backups.
    @discardableResult
    func backup(force: Bool) async -> Bool {
        guard !model.isDemo, force || model.settings.cloudBackup else { return false }
        guard CloudBackupPlan.shouldBackup(model.data) else {
            if force { lastError = "Il diario è vuoto: niente da salvare." }
            return false
        }
        guard !isWorking else { return false }
        let withAudio = model.settings.cloudBackupAudio
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let file = CloudBackupFile(data: model.data, includesAudio: withAudio, appVersion: version)
        let fp = CloudBackupPlan.fingerprint(file)
        if !force, fp == UserDefaults.standard.string(forKey: Keys.fingerprint) { return false }
        guard let data = try? file.encoded() else { return false }
        isWorking = true
        progress = withAudio ? "Copio l'audio delle clip…" : nil
        defer {
            isWorking = false
            progress = nil
        }
        guard let folder = await Self.folderURL() else {
            available = false
            if force { lastError = "iCloud Drive non disponibile: controlla di aver fatto l'accesso a iCloud e che iCloud Drive sia attivo per Diario Sonoro." }
            return false
        }
        available = true
        let today = DayDate.today()
        let audio = withAudio ? file.audioFiles : []
        let root = Storage.root
        let result = await Task.detached(priority: .utility) { () -> String? in
            do {
                if !audio.isEmpty {
                    let remote = folder.appendingPathComponent(CloudBackupPlan.audioFolder, isDirectory: true)
                    try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
                    let existing = (try? FileManager.default.contentsOfDirectory(atPath: remote.path)) ?? []
                    let todo = Set(CloudBackupPlan.missing(audio.map(\.name), existing: existing))
                    for item in audio where todo.contains(item.name) {
                        guard let d = try? Data(contentsOf: root.appendingPathComponent(item.path)) else { continue }
                        try Self.coordinatedWrite(d, to: remote.appendingPathComponent(item.name))
                    }
                }
                try Self.coordinatedWrite(data, to: folder.appendingPathComponent(CloudBackupPlan.dailyName(for: today)))
                try Self.coordinatedWrite(data, to: folder.appendingPathComponent(CloudBackupPlan.latestName))
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
                for name in CloudBackupPlan.namesToPrune(names) {
                    Self.coordinatedDelete(folder.appendingPathComponent(name))
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }.value
        if let result {
            lastError = "Backup su iCloud non riuscito: \(result)"
            return false
        }
        let now = Date()
        lastError = nil
        lastBackupAt = now
        UserDefaults.standard.set(now, forKey: Keys.lastAt)
        UserDefaults.standard.set(fp, forKey: Keys.fingerprint)
        return true
    }

    nonisolated private static func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let e = coordError ?? writeError { throw e }
    }

    nonisolated private static func coordinatedDelete(_ url: URL) {
        var err: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &err) { target in
            try? FileManager.default.removeItem(at: target)
        }
    }

    /// Downloads (if needed) and reads an iCloud file; nil after ~`attempts`/2 s.
    nonisolated private static func coordinatedRead(_ url: URL, attempts: Int = 60) async -> Data? {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        for _ in 0..<attempts {
            var coordError: NSError?
            var out: Data?
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordError) { target in
                out = try? Data(contentsOf: target)
            }
            if let out { return out }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    // MARK: Restore

    /// Backups in the iCloud folder, newest first.
    func refreshEntries() async {
        guard !model.isDemo, let folder = await Self.folderURL() else {
            available = false
            entries = []
            return
        }
        available = true
        let names = await Task.detached(priority: .userInitiated) {
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        }.value
        entries = CloudBackupPlan.entries(fromFileNames: names)
    }

    func load(_ entry: CloudBackupPlan.Entry) async throws -> CloudBackupFile {
        guard let folder = await Self.folderURL() else { throw CloudBackupError.unreadable }
        let url = folder.appendingPathComponent(entry.name)
        guard let data = await Task.detached(priority: .userInitiated, operation: { await Self.coordinatedRead(url) }).value else {
            throw CloudBackupError.unreadable
        }
        return try CloudBackupFile.decode(data)
    }

    /// Replaces the diary with the backup and downloads the audio it has.
    func restore(_ entry: CloudBackupPlan.Entry) async {
        isWorking = true
        defer {
            isWorking = false
            progress = nil
        }
        do {
            let file = try await load(entry)
            guard let folder = await Self.folderURL() else { throw CloudBackupError.unreadable }
            if file.includesAudio {
                progress = "Scarico l'audio delle clip…"
                let audio = file.audioFiles
                let root = Storage.root
                await Task.detached(priority: .userInitiated) {
                    let remote = folder.appendingPathComponent(CloudBackupPlan.audioFolder, isDirectory: true)
                    // Ask iCloud for everything first, then read file by file.
                    for item in audio { try? FileManager.default.startDownloadingUbiquitousItem(at: remote.appendingPathComponent(item.name)) }
                    for item in audio {
                        let local = root.appendingPathComponent(item.path)
                        guard !FileManager.default.fileExists(atPath: local.path) else { continue }
                        if let d = await Self.coordinatedRead(remote.appendingPathComponent(item.name), attempts: 20) {
                            try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try? d.write(to: local, options: .atomic)
                        }
                    }
                }.value
            }
            model.restoreFromCloud(file)
            // The restored content is already in iCloud: no need to rewrite it.
            UserDefaults.standard.set(CloudBackupPlan.fingerprint(file), forKey: Keys.fingerprint)
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: First launch

    /// Empty diary + backups in iCloud → guided restore (asked once).
    func offerRestoreIfNeeded() async {
        guard !model.isDemo, model.data.clips.isEmpty, !UserDefaults.standard.bool(forKey: Keys.restoreOffered) else { return }
        await refreshEntries()
        guard !entries.isEmpty, model.data.clips.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: Keys.restoreOffered)
        offerRestore = true
    }
}

/// Restore from iCloud: list of backups, preview, confirm.
struct CloudRestoreView: View {
    let firstLaunch: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Environment(\.dismiss) private var dismiss
    @State private var choice: CloudBackupPlan.Entry?
    @State private var preview: CloudBackupFile?
    @State private var loading = false
    @State private var confirm = false

    private var cloud: CloudBackupService { CloudBackupService.shared }

    var body: some View {
        NavigationStack {
            List {
                if firstLaunch {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "icloud.and.arrow.down.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(m3.primary)
                            Text("Bentornato")
                                .font(.m3HeadlineSmall)
                            Text("In iCloud Drive c'è un backup di Diario Sonoro. Vuoi ripristinare le tue giornate?")
                                .font(.m3BodyMedium)
                                .foregroundStyle(m3.onSurfaceVariant)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(m3.surfaceContainerLow)
                }
                Section {
                    if cloud.entries.isEmpty {
                        Text(cloud.available == false ? "iCloud Drive non disponibile." : "Nessun backup trovato.")
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    ForEach(cloud.entries) { entry in
                        Button {
                            choice = entry
                            Task { await loadPreview(entry) }
                        } label: {
                            HStack {
                                Image(systemName: entry.isLatest ? "clock.arrow.circlepath" : "doc.text")
                                    .foregroundStyle(m3.primary)
                                Text(title(entry)).foregroundStyle(m3.onSurface)
                                Spacer()
                                if choice == entry {
                                    if loading { ProgressView() } else { Image(systemName: "checkmark").foregroundStyle(m3.primary) }
                                }
                            }
                        }
                    }
                } header: {
                    Text("iCloud Drive › Backup › DiarioSonoro")
                } footer: {
                    Text("Il ripristino sostituisce il diario con quello del backup. Le colonne sonore vengono ricreate dalle clip. Se il backup non contiene l'audio, le clip tornano con data, luogo e note ma senza suono.")
                }
                .listRowBackground(m3.surfaceContainerLow)
                if let preview, choice != nil {
                    Section {
                        LabeledContent("Clip", value: ItalianFormat.number(preview.data.clips.count))
                        LabeledContent("Giorni", value: ItalianFormat.number(preview.days.count))
                        LabeledContent("Audio", value: preview.includesAudio ? "incluso" : "non incluso")
                        LabeledContent("Salvato il", value: dateLabel(preview.exportedAt))
                        Button {
                            if model.data.clips.isEmpty { Task { await doRestore() } } else { confirm = true }
                        } label: {
                            Label("Ripristina", systemImage: "arrow.counterclockwise")
                                .font(.m3TitleSmall)
                        }
                        .disabled(cloud.isWorking)
                        if cloud.isWorking {
                            HStack {
                                ProgressView()
                                Text(cloud.progress ?? "Ripristino…").foregroundStyle(m3.onSurfaceVariant)
                            }
                        }
                    }
                    .listRowBackground(m3.surfaceContainerLow)
                }
                if let e = cloud.lastError {
                    Section { Text(e).foregroundStyle(m3.error) }
                        .listRowBackground(m3.surfaceContainerLow)
                }
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle("Ripristina da iCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(firstLaunch ? "Inizia da zero" : "Chiudi") { dismiss() }
                }
            }
            .confirmationDialog("Sostituire il diario attuale?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Ripristina il backup", role: .destructive) { Task { await doRestore() } }
            } message: {
                Text("Clip, note e impostazioni attuali verranno sostituite da quelle del backup.")
            }
            .task {
                await cloud.refreshEntries()
                if let first = cloud.entries.first, choice == nil {
                    choice = first
                    await loadPreview(first)
                }
            }
        }
    }

    private func doRestore() async {
        guard let choice else { return }
        await cloud.restore(choice)
        if cloud.lastError == nil { dismiss() }
    }

    private func title(_ e: CloudBackupPlan.Entry) -> String {
        if let d = e.day { return ItalianFormat.capitalized(ItalianFormat.dayTitle(d)) }
        return "Ultimo backup"
    }

    private func dateLabel(_ date: Date) -> String {
        "\(ItalianFormat.dayShort(DayDate(date: date))), \(ItalianFormat.time(minuteOfDay: minuteOfDay(date)))"
    }

    private func loadPreview(_ entry: CloudBackupPlan.Entry) async {
        loading = true
        preview = try? await cloud.load(entry)
        loading = false
    }
}
