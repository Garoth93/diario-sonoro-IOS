import SwiftUI
import WidgetKit
import SonoroCore

enum AppTab: Hashable {
    case record, calendar, map, stats, settings
}

enum CalendarRoute: Hashable {
    case day(DayDate)
    case search
    case anniversary
}

struct Toast: Identifiable, Equatable {
    enum Style { case success, info, error }
    let id = UUID()
    let message: String
    let icon: String
    let style: Style
}

enum RecordPhase: Equatable {
    case idle
    case starting
    case recording(started: Date, byTap: Bool)
    case saving
}

/// Launch arguments used by the CI screenshots: `-demo` loads a synthetic
/// diary in a separate folder (real data is never touched), `-screen <name>`
/// opens a given screen.
enum LaunchOptions {
    static let arguments = ProcessInfo.processInfo.arguments
    static let isDemo = arguments.contains("-demo")
    static var screen: String? {
        guard let i = arguments.firstIndex(of: "-screen"), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }
}

/// Where the diary lives: Application Support/DiarioSonoro (JSON + audio).
enum Storage {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent(LaunchOptions.isDemo ? "DiarioSonoroDemo" : "DiarioSonoro", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var dataURL: URL { root.appendingPathComponent(FileNaming.dataFile) }
    static var store: JSONFileStore<DiaryData> { JSONFileStore(url: dataURL) }

    static func url(_ relative: String) -> URL { root.appendingPathComponent(relative) }

    static var exportsFolder: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Esportazioni", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var data: DiaryData
    private(set) var today: DayDate
    var tab: AppTab = .record
    var calendarPath: [CalendarRoute] = []
    var phase: RecordPhase = .idle
    var toast: Toast?
    var errorMessage: String?
    var isLocked: Bool
    private(set) var building: Set<DayDate> = []
    /// Bumped to scroll the calendar to today.
    var calendarMonth: MonthRef
    var microphoneDenied = false

    let player = PlayerModel()
    let isDemo = LaunchOptions.isDemo

    @ObservationIgnored private let capture: CaptureController
    @ObservationIgnored private let builder: SoundtrackBuilder
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var autoStopTask: Task<Void, Never>?
    @ObservationIgnored private var queuedLink: DeepLink?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var recordingToken = UUID()

    private init() {
        let t = DayDate.today()
        today = t
        calendarMonth = MonthRef(t)
        if LaunchOptions.isDemo {
            data = DemoData.make(today: t, nowMinute: max(minuteOfDay(Date()), 9 * 60))
        } else {
            data = (try? Storage.store.load()) ?? DiaryData()
        }
        capture = CaptureController(recorder: AVRecorderService(), location: LocationService(),
                                    weather: WeatherKitProvider(), root: Storage.root)
        builder = SoundtrackBuilder(merger: AVMergeService(), root: Storage.root)
        isLocked = !LaunchOptions.isDemo && data.settings.requireFaceID
        if isDemo {
            player.simulate = true
            applyDemoScreen()
        }
    }

    var settings: DiarySettings { data.settings }

    // MARK: Persistence

    /// Saves (debounced), refreshes widgets and notifications.
    private func persist() {
        if !isDemo {
            saveTask?.cancel()
            let snapshot = data
            saveTask = Task.detached(priority: .utility) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                try? Storage.store.save(snapshot)
            }
        }
        refreshExternal()
    }

    private func flush() {
        guard !isDemo else { return }
        saveTask?.cancel()
        try? Storage.store.save(data)
    }

    private func refreshExternal() {
        guard !isDemo else { return }
        SharedStore.saveSnapshot(WidgetSnapshot.make(data: data, today: today))
        WidgetCenter.shared.reloadAllTimelines()
        Notifier.reschedule(data: data, today: today, minuteNow: minuteOfDay(Date()))
        BackgroundBuilder.schedule(time: settings.soundtrackTime)
    }

    // MARK: Lifecycle

    func setActive(_ active: Bool) {
        isActive = active
        guard active else {
            if case .recording = phase { Task { await stopRecording() } }
            flush()
            return
        }
        let t = DayDate.today()
        if t != today {
            today = t
            calendarMonth = MonthRef(t)
        }
        if let pending = SharedStore.takePending() { queuedLink = pending }
        if let link = queuedLink, !isLocked {
            queuedLink = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self.handle(link)
            }
        }
        if !isDemo {
            refreshExternal()
            Task { await buildDueSoundtracks() }
        }
    }

    func lockIfNeeded() {
        if settings.requireFaceID && !isDemo { isLocked = true }
    }

    func unlock() async {
        if await DeviceAuth.authenticate(reason: "Sblocca Diario Sonoro") {
            isLocked = false
            if let link = queuedLink {
                queuedLink = nil
                handle(link)
            }
        }
    }

    // MARK: Links

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        handle(link)
    }

    func handle(_ link: DeepLink) {
        guard isActive, !isLocked else {
            queuedLink = link
            return
        }
        switch link {
        case .record(let source):
            tab = .record
            if source != .app, settings.quickStartRecording, phase == .idle {
                Task { await startRecording(byTap: true) }
            }
        case .day(let d):
            openDay(d)
        case .soundtrack(let d):
            openDay(d)
            Task { await playSoundtrack(d) }
        case .anniversary:
            tab = .calendar
            calendarPath = [.anniversary]
        case .calendar:
            tab = .calendar
            calendarPath = []
        case .map:
            tab = .map
        case .stats:
            tab = .stats
        }
    }

    func openDay(_ d: DayDate) {
        tab = .calendar
        calendarMonth = MonthRef(d)
        calendarPath = [.day(d)]
    }

    // MARK: Recording

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    var recordingStart: Date? {
        if case .recording(let s, _) = phase { return s }
        return nil
    }

    var recordingByTap: Bool {
        if case .recording(_, let byTap) = phase { return byTap }
        return false
    }

    var rules: RecordingRules { RecordingRules(clipDuration: settings.clipDuration) }

    /// Frozen elapsed time for the "recording" screenshot.
    @ObservationIgnored var demoElapsed: Double?

    func elapsed(at date: Date) -> Double {
        if let d = demoElapsed { return d }
        guard let s = recordingStart else { return 0 }
        return max(0, date.timeIntervalSince(s))
    }

    /// Live microphone level 0…1 for the halo around the button.
    func inputLevel(at date: Date) -> Float {
        if isDemo { return 0.55 + 0.35 * Float(sin(date.timeIntervalSince1970 * 5)) }
        return capture.recorder.currentLevel
    }

    /// Finger down on the big button (or quick start from a widget).
    func startRecording(byTap: Bool = false) async {
        guard phase == .idle else { return }
        if isDemo {
            phase = .recording(started: Date(), byTap: byTap)
            return
        }
        if AudioSessionHelper.microphoneUndetermined {
            let ok = await AudioSessionHelper.requestMicrophone()
            microphoneDenied = !ok
            if ok { show("Microfono pronto: tieni premuto per registrare", icon: "mic.fill", style: .info) }
            return
        }
        guard AudioSessionHelper.microphoneAllowed else {
            microphoneDenied = true
            return
        }
        microphoneDenied = false
        player.pause()
        phase = .starting
        do {
            try await capture.begin(settings: settings)
        } catch {
            phase = .idle
            errorMessage = "Non riesco ad avviare la registrazione. Controlla che il microfono non sia usato da un'altra app."
            return
        }
        if settings.haptics { Haptics.start() }
        let token = UUID()
        recordingToken = token
        phase = .recording(started: Date(), byTap: byTap)
        let max = rules.maxDuration
        autoStopTask?.cancel()
        autoStopTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max))
            guard !Task.isCancelled, self.recordingToken == token else { return }
            await self.stopRecording()
        }
    }

    /// Finger up (or time is over): save what was recorded (minimum 2 s).
    func stopRecording() async {
        if phase == .starting {
            // Released before the recorder started: wait for it, then stop.
            for _ in 0..<20 where phase == .starting { try? await Task.sleep(for: .milliseconds(50)) }
        }
        guard case .recording = phase else { return }
        autoStopTask?.cancel()
        recordingToken = UUID()
        if isDemo {
            phase = .idle
            return
        }
        phase = .saving
        let result: CaptureResult
        do {
            result = try await capture.finish()
        } catch {
            phase = .idle
            return
        }
        phase = .idle
        switch result {
        case .tooShort:
            if settings.haptics { Haptics.warning() }
            show("Tieni premuto almeno 2 secondi", icon: "hand.tap.fill", style: .info)
        case .saved(let clip):
            if settings.haptics { Haptics.end() }
            data.add(clip)
            persist()
            show("Salvata · \(ItalianFormat.duration(clip.duration))", icon: "checkmark", style: .success)
            let s = settings
            let capture = capture
            Task { @MainActor in
                let enriched = await capture.enrich(clip, settings: s)
                guard enriched != clip, self.data.clip(clip.id) != nil else { return }
                self.data.update(clip.id) {
                    $0.location = enriched.location
                    $0.placeName = enriched.placeName
                    $0.locality = enriched.locality
                    $0.weather = enriched.weather
                }
                self.persist()
            }
            Task { await buildDueSoundtracks() }
        }
    }

    // MARK: Soundtracks

    func isBuilding(_ day: DayDate) -> Bool { building.contains(day) }

    /// Builds every soundtrack that is due (past days, today after the evening time).
    func buildDueSoundtracks() async {
        guard !isDemo else { return }
        var changed = false
        for orphan in SoundtrackScheduler.orphans(in: data) {
            try? FileManager.default.removeItem(at: Storage.url(orphan.fileName))
            data.removeSoundtrack(for: orphan.day)
            changed = true
        }
        let due = SoundtrackScheduler.dueDays(data: data, today: DayDate.today(), minuteNow: minuteOfDay(Date()))
        for day in due.prefix(30) where !building.contains(day) {
            if await buildSoundtrack(day, persistAfter: false) { changed = true }
        }
        if changed { persist() }
    }

    /// Builds (or rebuilds) one day now. Returns true on success.
    @discardableResult
    func buildSoundtrack(_ day: DayDate, persistAfter: Bool = true) async -> Bool {
        guard !building.contains(day) else { return false }
        if isDemo { return false }
        building.insert(day)
        defer { building.remove(day) }
        do {
            let s = try await builder.build(day: day, data: data)
            data.setSoundtrack(s)
            if persistAfter { persist() }
            return true
        } catch {
            if persistAfter { errorMessage = "Non riesco a creare la colonna sonora di questo giorno." }
            return false
        }
    }

    func playSoundtrack(_ day: DayDate) async {
        if SoundtrackScheduler.needsBuild(day, in: data) { await buildSoundtrack(day) }
        guard let s = data.soundtrack(for: day) else { return }
        player.play([PlayItem.soundtrack(s, root: Storage.root)])
    }

    // MARK: Playback helpers

    func items(_ clips: [Clip]) -> [PlayItem] { clips.map { PlayItem.clip($0, root: Storage.root) } }

    func play(_ clip: Clip, in list: [Clip]) {
        player.toggle(PlayItem.clip(clip, root: Storage.root), in: items(list))
    }

    func playAll(_ clips: [Clip]) {
        player.play(items(clips.sorted(by: Clip.chronological)))
    }

    func soundtrackURL(_ s: DailySoundtrack) -> URL { Storage.url(s.fileName) }

    /// A copy with a friendly name, for sharing.
    func shareableCopy(of source: URL, named name: String) -> URL? {
        let dest = Storage.exportsFolder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        } catch {
            errorMessage = "Il file audio non è disponibile."
            return nil
        }
    }

    // MARK: Editing

    func toggleFavorite(_ id: UUID) {
        data.update(id) { $0.isFavorite.toggle() }
        persist()
    }

    func updateClip(_ id: UUID, note: String, emoji: String, favorite: Bool) {
        data.update(id) {
            $0.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.emoji = emoji
            $0.isFavorite = favorite
        }
        persist()
    }

    func deleteClips(_ ids: Set<UUID>) {
        if let current = player.current?.clipID, ids.contains(current) { player.stop() }
        let removed = data.removeClips(ids)
        for c in removed { try? FileManager.default.removeItem(at: Storage.url(c.fileName)) }
        // Soundtracks of touched days are rebuilt (or removed if empty).
        for d in Set(removed.map(\.day)) {
            if let s = data.removeSoundtrack(for: d) { try? FileManager.default.removeItem(at: Storage.url(s.fileName)) }
        }
        persist()
        show(removed.count == 1 ? "Clip eliminata" : "\(removed.count) clip eliminate", icon: "trash", style: .info)
        Task { await buildDueSoundtracks() }
    }

    func deleteEverything() {
        player.stop()
        for folder in [FileNaming.clipsFolder, FileNaming.soundtracksFolder] {
            try? FileManager.default.removeItem(at: Storage.url(folder))
        }
        let s = data.settings
        data = DiaryData(settings: s)
        persist()
        show("Diario svuotato", icon: "trash", style: .info)
    }

    // MARK: Settings

    func updateSettings(_ change: (inout DiarySettings) -> Void) {
        let old = data.settings
        change(&data.settings)
        persist()
        if old.crossfade != data.settings.crossfade || old.soundtrackTime != data.settings.soundtrackTime {
            Task { await buildDueSoundtracks() }
        }
    }

    /// Crossfade changed: rebuild today's soundtrack and the past ones lazily.
    func rebuildAllSoundtracks() async {
        for s in data.soundtracks { try? FileManager.default.removeItem(at: Storage.url(s.fileName)) }
        data.soundtracks.removeAll()
        persist()
        await buildDueSoundtracks()
        show("Colonne sonore ricreate", icon: "waveform", style: .success)
    }

    // MARK: Backup

    func makeBackup() async -> URL? {
        let url = Storage.exportsFolder.appendingPathComponent(FileNaming.backupName(day: today))
        let snapshot = data
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try BackupArchive.create(data: snapshot, root: Storage.root, to: url, appVersion: version)
            }.value
            return url
        } catch {
            errorMessage = "Non riesco a creare il backup: \(error.localizedDescription)"
            return nil
        }
    }

    func makeCSV() -> URL? {
        let url = Storage.exportsFolder.appendingPathComponent(FileNaming.csvName(day: today))
        do {
            try CSVExport.clips(data.clips).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            errorMessage = "Non riesco a creare il file CSV."
            return nil
        }
    }

    /// Copies a picked file in the sandbox and reads its manifest.
    func inspectBackup(at picked: URL) -> (URL, BackupManifest)? {
        let ok = picked.startAccessingSecurityScopedResource()
        defer { if ok { picked.stopAccessingSecurityScopedResource() } }
        let local = Storage.exportsFolder.appendingPathComponent("ripristino.zip")
        try? FileManager.default.removeItem(at: local)
        do {
            try FileManager.default.copyItem(at: picked, to: local)
            return (local, try BackupArchive.inspect(local))
        } catch BackupError.newerVersion {
            errorMessage = "Il backup è stato creato da una versione più recente dell'app."
        } catch {
            errorMessage = "Il file scelto non è un backup di Diario Sonoro."
        }
        return nil
    }

    func restore(from local: URL) async {
        player.stop()
        do {
            let restored = try await Task.detached(priority: .userInitiated) {
                try BackupArchive.restore(local, into: Storage.root)
            }.value
            data = restored
            persist()
            show("Backup ripristinato: \(ItalianFormat.clips(restored.clips.count))", icon: "checkmark", style: .success)
            await buildDueSoundtracks()
        } catch {
            errorMessage = "Ripristino non riuscito: \(error.localizedDescription)"
        }
        try? FileManager.default.removeItem(at: local)
    }

    // MARK: Toast

    func show(_ message: String, icon: String, style: Toast.Style) {
        let t = Toast(message: message, icon: icon, style: style)
        toast = t
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            if self.toast?.id == t.id { self.toast = nil }
        }
    }

    // MARK: Demo screens (CI screenshots)

    private func applyDemoScreen() {
        switch LaunchOptions.screen {
        case "calendar": tab = .calendar
        case "day":
            tab = .calendar
            let d = today.adding(days: -1)
            calendarPath = [.day(d)]
            let clips = data.clips(on: d)
            if let s = data.soundtrack(for: d) {
                player.play([PlayItem.soundtrack(s, root: Storage.root)] + items(clips))
                player.seek(to: s.duration * 0.38)
                player.pause()
            }
        case "anniversary":
            tab = .calendar
            calendarPath = [.anniversary]
        case "search":
            tab = .calendar
            calendarPath = [.search]
        case "map": tab = .map
        case "stats": tab = .stats
        case "settings": tab = .settings
        case "recording":
            tab = .record
            phase = .recording(started: Date().addingTimeInterval(-3.6), byTap: false)
            demoElapsed = 3.6
        default: tab = .record
        }
    }
}
