import SwiftUI
import UniformTypeIdentifiers
import WidgetKit
import SonoroCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var share: ShareFiles?
    @State private var showImporter = false
    @State private var pendingRestore: (url: URL, manifest: BackupManifest)?
    @State private var confirmDeleteAll = false
    @State private var working = false
    @State private var showCloudRestore = false

    var body: some View {
        List {
            recordingSection
            reminderSection
            soundtrackSection
            anniversarySection
            appearanceSection
            privacySection
            cloudSection
            dataSection
            widgetSection
            infoSection
        }
        .scrollContentBackground(.hidden)
        .background(m3.surface)
        .navigationTitle("Impostazioni")
        .sheet(isPresented: $showCloudRestore) {
            CloudRestoreView(firstLaunch: false)
                .presentationCornerRadius(32)
        }
        .sheet(item: $share) { s in
            ActivitySheet(items: s.urls).presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zip]) { result in
            if case .success(let url) = result, let found = model.inspectBackup(at: url) {
                pendingRestore = (found.0, found.1)
            }
        }
        .confirmationDialog("Ripristinare il backup?", isPresented: Binding(
            get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }
        ), titleVisibility: .visible) {
            Button("Sostituisci il diario", role: .destructive) {
                if let p = pendingRestore {
                    Task {
                        working = true
                        await model.restore(from: p.url)
                        working = false
                    }
                }
                pendingRestore = nil
            }
        } message: {
            if let m = pendingRestore?.manifest {
                Text("\(ItalianFormat.clips(m.data.clips.count)) del backup del \(ItalianFormat.dayShort(DayDate(date: m.createdAt))). Il diario attuale verrà sostituito.")
            }
        }
        .confirmationDialog("Eliminare tutte le clip?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Elimina tutto", role: .destructive) { model.deleteEverything() }
        } message: {
            Text("Clip, colonne sonore e note vengono cancellate da questo iPhone. Le impostazioni restano. Fai prima un backup se vuoi conservarle.")
        }
        .overlay {
            if working {
                ProgressView("Un attimo…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func binding<T>(_ key: WritableKeyPath<DiarySettings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: key] }, set: { v in model.updateSettings { $0[keyPath: key] = v } })
    }

    private func timeBinding(_ key: WritableKeyPath<DiarySettings, ClockTime>) -> Binding<Date> {
        Binding(
            get: { model.today.date(minuteOfDay: model.settings[keyPath: key].minutes) },
            set: { d in model.updateSettings { $0[keyPath: key] = ClockTime(minutes: minuteOfDay(d)) } })
    }

    // MARK: Sections

    private var recordingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Durata clip", systemImage: "timer")
                    Spacer()
                    Text("\(model.settings.clipDuration) s")
                        .font(.m3TitleSmall)
                        .monospacedDigit()
                        .foregroundStyle(m3.primary)
                }
                Slider(value: Binding(
                    get: { Double(model.settings.clipDuration) },
                    set: { v in model.updateSettings { $0.clipDuration = Int(v.rounded()) } }
                ), in: Double(DiarySettings.durationRange.lowerBound)...Double(DiarySettings.durationRange.upperBound), step: 1)
            }
            Picker(selection: binding(\.quality)) {
                ForEach(AudioQuality.allCases) { q in Text(q.label).tag(q) }
            } label: {
                Label("Qualità", systemImage: "waveform")
            }
            Toggle(isOn: binding(\.saveLocation)) { Label("Salva il luogo", systemImage: "location.fill") }
            Toggle(isOn: binding(\.saveWeather)) { Label("Salva il meteo", systemImage: "cloud.sun.fill") }
                .disabled(!model.settings.saveLocation)
            Toggle(isOn: binding(\.quickStartRecording)) { Label("Avvio rapido registra subito", systemImage: "bolt.fill") }
            Toggle(isOn: binding(\.haptics)) { Label("Vibrazione", systemImage: "iphone.radiowaves.left.and.right") }
        } header: {
            Text("Registrazione")
        } footer: {
            Text("AAC mono, circa \(ItalianFormat.bytes(model.settings.quality.estimatedBytes(seconds: Double(model.settings.clipDuration)))) per clip. Il luogo è chiesto una volta sola al momento della registrazione, senza tracciamento. Il meteo usa WeatherKit: funziona solo se la capability WeatherKit è attiva sull'App ID dell'app (oggi è spenta, quindi le clip si salvano senza meteo). Con l'avvio rapido, aprendo l'app dal widget, dal Centro di Controllo o da Siri la registrazione parte da sola (tocca per fermarla).")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var reminderSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.settings.reminderEnabled },
                set: { v in enableNotification(v) { $0.reminderEnabled = v } }
            )) {
                Label("Ricordami di registrare", systemImage: "bell.badge.fill")
            }
            if model.settings.reminderEnabled {
                DatePicker(selection: timeBinding(\.reminderStart), displayedComponents: .hourAndMinute) {
                    Label("Dalle", systemImage: "sunrise.fill")
                }
                DatePicker(selection: timeBinding(\.reminderEnd), displayedComponents: .hourAndMinute) {
                    Label("Alle", systemImage: "sunset.fill")
                }
                Toggle(isOn: binding(\.reminderSkipIfRecorded)) {
                    Label("Salta se ho già registrato oggi", systemImage: "checkmark.circle")
                }
            }
        } header: {
            Text("Promemoria")
        } footer: {
            Text(model.settings.reminderEnabled
                 ? "Ogni giorno, in un momento a caso tra le \(model.settings.reminderStart.label) e le \(model.settings.reminderEnd.label), arriva la notifica \"È ora della tua registrazione audio\". Toccandola l'app si apre pronta a registrare. Se la fascia supera la mezzanotte vale anche per la notte."
                 : "Una notifica al giorno, in un momento a caso della fascia oraria che scegli: così il diario cattura momenti sempre diversi.")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var soundtrackSection: some View {
        Section {
            DatePicker(selection: timeBinding(\.soundtrackTime), displayedComponents: .hourAndMinute) {
                Label("Pronta alle", systemImage: "moon.stars.fill")
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Dissolvenza", systemImage: "arrow.left.and.right")
                    Spacer()
                    Text(model.settings.crossfade == 0 ? "nessuna" : "\(ItalianFormat.decimal(model.settings.crossfade)) s")
                        .font(.m3TitleSmall)
                        .monospacedDigit()
                        .foregroundStyle(m3.primary)
                }
                Slider(value: binding(\.crossfade), in: DiarySettings.crossfadeRange, step: 0.5)
            }
            Toggle(isOn: Binding(
                get: { model.settings.soundtrackNotification },
                set: { v in enableNotification(v) { $0.soundtrackNotification = v } }
            )) {
                Label("Notifica serale", systemImage: "bell.fill")
            }
            Button {
                Task { await model.rebuildAllSoundtracks() }
            } label: {
                Label("Ricrea tutte le colonne sonore", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("Colonna sonora del giorno")
        } footer: {
            Text("Ogni sera le clip del giorno vengono unite in ordine, con dissolvenze incrociate. Nei giorni senza clip non succede nulla. La notifica dice \"La colonna sonora di oggi è pronta\".")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var anniversarySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.settings.anniversaryNotification },
                set: { v in enableNotification(v) { $0.anniversaryNotification = v } }
            )) {
                Label("Notifica \"Un anno fa oggi\"", systemImage: "clock.arrow.circlepath")
            }
            if model.settings.anniversaryNotification {
                DatePicker(selection: timeBinding(\.anniversaryTime), displayedComponents: .hourAndMinute) {
                    Label("Alle", systemImage: "clock")
                }
            }
        } header: {
            Text("Un anno fa oggi")
        } footer: {
            Text("Solo nei giorni in cui hai registrato qualcosa uno, due o più anni prima.")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var appearanceSection: some View {
        Section("Aspetto") {
            Picker(selection: binding(\.appearance)) {
                ForEach(Appearance.allCases) { a in Text(a.label).tag(a) }
            } label: {
                Label("Tema", systemImage: "circle.lefthalf.filled")
            }
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.settings.requireFaceID },
                set: { v in
                    Task {
                        if await DeviceAuth.authenticate(reason: v ? "Attiva il blocco" : "Disattiva il blocco") {
                            model.updateSettings { $0.requireFaceID = v }
                        }
                    }
                }
            )) {
                Label("\(DeviceAuth.biometryName) per aprire l'app", systemImage: "faceid")
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Tutto resta su questo iPhone: nessun server, nessun account. Solo il nome del luogo (Apple Mappe) e il meteo, se attivo, vengono chiesti ad Apple con la posizione della clip.")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var cloudSection: some View {
        let cloud = CloudBackupService.shared
        return Section {
            Toggle(isOn: binding(\.cloudBackup)) {
                Label("Backup automatico su iCloud", systemImage: "icloud.fill")
            }
            Toggle(isOn: binding(\.cloudBackupAudio)) {
                Label("Includi l'audio delle clip", systemImage: "waveform")
            }
            .disabled(!model.settings.cloudBackup)
            LabeledContent {
                if cloud.isWorking {
                    ProgressView()
                } else {
                    Text(lastBackupLabel(cloud))
                        .foregroundStyle(cloud.available == false ? m3.error : m3.onSurfaceVariant)
                }
            } label: {
                Label("Ultimo backup", systemImage: "clock")
            }
            Button {
                Task {
                    if await cloud.backup(force: true) { model.show("Backup salvato su iCloud", icon: "icloud.and.arrow.up", style: .success) }
                }
            } label: {
                Label("Esegui backup ora", systemImage: "icloud.and.arrow.up")
            }
            .disabled(cloud.isWorking || model.data.clips.isEmpty || model.isDemo)
            Button {
                showCloudRestore = true
            } label: {
                Label("Ripristina da iCloud", systemImage: "icloud.and.arrow.down")
            }
            .disabled(cloud.isWorking || model.isDemo)
            if let e = cloud.lastError {
                Text(e)
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.error)
            }
        } header: {
            Text("Backup iCloud")
        } footer: {
            Text("I backup sono nell'app File in iCloud Drive › Backup › DiarioSonoro: un file al giorno (ultimi 30) con clip, giornate, note e impostazioni. Partono dopo ogni modifica, quando chiudi l'app e in background. L'audio delle clip è spento di default: sono registrazioni personali e occupano spazio su iCloud; se lo attivi ogni clip viene copiata una volta sola. Le colonne sonore non servono nel backup: si ricreano dalle clip.")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private func lastBackupLabel(_ cloud: CloudBackupService) -> String {
        if model.isDemo { return "—" }
        if cloud.available == false { return "iCloud non disponibile" }
        guard let d = cloud.lastBackupAt else { return "mai" }
        return ItalianFormat.relativeDay(DayDate(date: d), today: model.today) + ", " + ItalianFormat.time(minuteOfDay: minuteOfDay(d))
    }

    private var dataSection: some View {
        let stats = DiaryStats(data: model.data, today: model.today)
        return Section {
            LabeledContent {
                Text("\(ItalianFormat.clips(stats.totalClips)) · \(ItalianFormat.bytes(stats.totalBytes))")
            } label: {
                Label("Spazio occupato", systemImage: "internaldrive")
            }
            Button {
                Task {
                    working = true
                    if let url = await model.makeBackup() { share = ShareFiles(urls: [url]) }
                    working = false
                }
            } label: {
                Label("Esporta backup (ZIP con audio)", systemImage: "square.and.arrow.up")
            }
            .disabled(model.data.clips.isEmpty || model.isDemo)
            Button {
                showImporter = true
            } label: {
                Label("Ripristina da file ZIP", systemImage: "square.and.arrow.down")
            }
            .disabled(model.isDemo)
            Button {
                if let url = model.makeCSV() { share = ShareFiles(urls: [url]) }
            } label: {
                Label("Esporta elenco clip (CSV)", systemImage: "tablecells")
            }
            .disabled(model.data.clips.isEmpty)
            Button(role: .destructive) {
                confirmDeleteAll = true
            } label: {
                Label("Elimina tutte le clip", systemImage: "trash")
            }
            .disabled(model.data.clips.isEmpty)
        } header: {
            Text("Dati")
        } footer: {
            Text("Oltre al backup iCloud puoi esportare un file ZIP con tutte le clip (audio compreso), le note e le impostazioni, da salvare dove vuoi. Per eliminare una sola clip tienila premuta nel giorno.")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var widgetSection: some View {
        Section {
            HStack {
                Label("Dati condivisi con i widget", systemImage: SharedStore.isShared ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Spacer()
                Text(SharedStore.isShared ? "Attivi" : "Non disponibili")
                    .foregroundStyle(SharedStore.isShared ? m3.primary : m3.error)
            }
            Button {
                WidgetCenter.shared.reloadAllTimelines()
                ControlCenter.shared.reloadAllControls()
                model.show("Widget aggiornati", icon: "arrow.clockwise", style: .info)
            } label: {
                Label("Aggiorna widget", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Avvio rapido")
        } footer: {
            Text("Schermata di blocco: tieni premuto › Personalizza › aggiungi il widget Diario Sonoro. Centro di Controllo e tasto Azione: aggiungi il controllo \"Registra suono\". Siri: \"Registra con Diario Sonoro\".")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private var infoSection: some View {
        Section("Informazioni") {
            LabeledContent("Versione", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
            LabeledContent("Giorni registrati", value: "\(Set(model.data.clips.map(\.day)).count)")
            LabeledContent("Colonne sonore", value: "\(model.data.soundtracks.count)")
        }
        .listRowBackground(m3.surfaceContainerLow)
    }

    private func enableNotification(_ on: Bool, change: @escaping (inout DiarySettings) -> Void) {
        guard on else {
            model.updateSettings(change)
            return
        }
        Task {
            let ok = await Notifier.requestAuthorization()
            if ok {
                model.updateSettings(change)
            } else {
                model.errorMessage = "Le notifiche sono disattivate per Diario Sonoro nelle Impostazioni di iOS."
            }
        }
    }
}
