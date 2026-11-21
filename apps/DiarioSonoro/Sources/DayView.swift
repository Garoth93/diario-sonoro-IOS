import SwiftUI
import SonoroCore

/// One day: soundtrack on top, then the timeline of its clips.
struct DayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let day: DayDate
    @State private var editing: Clip?
    @State private var share: ShareFiles?
    @State private var confirmDelete: Clip?

    var body: some View {
        let clips = model.data.clips(on: day)
        let summary = DaySummary(day: day, clips: clips)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(summary)
                soundtrack(summary)
                if clips.isEmpty {
                    EmptyStateView(icon: "waveform", title: "Nessuna clip", message: "In questo giorno non hai registrato nulla.")
                } else {
                    HStack {
                        SectionTitle("Momenti")
                        Spacer()
                        Button {
                            model.playAll(clips)
                        } label: {
                            Label("Riproduci tutte", systemImage: "play.fill")
                                .font(.m3LabelLarge)
                        }
                        .padding(.top, 12)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(clips.enumerated()), id: \.element.id) { i, clip in
                            ClipRow(clip: clip, list: clips, isFirst: i == 0, isLast: i == clips.count - 1,
                                    onEdit: { editing = clip },
                                    onShare: { shareClip(clip) },
                                    onDelete: { confirmDelete = clip })
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(m3.surface)
        .navigationTitle(ItalianFormat.relativeDay(day, today: model.today))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { clip in
            ClipEditorSheet(clip: clip)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
        .sheet(item: $share) { s in
            ActivitySheet(items: s.urls).presentationDetents([.medium, .large])
        }
        .confirmationDialog("Eliminare la clip?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                if let c = confirmDelete { model.deleteClips([c.id]) }
                confirmDelete = nil
            }
        } message: {
            Text("L'audio viene cancellato dal telefono e la colonna sonora del giorno viene ricreata.")
        }
    }

    private func header(_ s: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ItalianFormat.capitalized(ItalianFormat.dayTitle(day)))
                .font(.m3HeadlineSmall)
                .foregroundStyle(m3.onSurface)
            if !s.clips.isEmpty {
                Text(dayLine(s))
                    .font(.m3BodyMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .padding(.top, 8)
    }

    private func dayLine(_ s: DaySummary) -> String {
        var parts = [ItalianFormat.clips(s.count), ItalianFormat.duration(s.totalDuration)]
        if let a = s.firstMinute, let b = s.lastMinute, a != b {
            parts.append("dalle \(ItalianFormat.time(minuteOfDay: a)) alle \(ItalianFormat.time(minuteOfDay: b))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func soundtrack(_ s: DaySummary) -> some View {
        if let track = model.data.soundtrack(for: day), !SoundtrackScheduler.needsBuild(day, in: model.data) {
            SoundtrackCard(track: track)
        } else if !s.clips.isEmpty {
            M3Card(color: m3.primaryContainer) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Colonna sonora")
                            .font(.m3TitleMedium)
                            .foregroundStyle(m3.onPrimaryContainer)
                        Text(day == model.today
                             ? "Si crea da sola alle \(model.settings.soundtrackTime.label)"
                             : "Le clip unite con dissolvenze incrociate")
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onPrimaryContainer.opacity(0.75))
                    }
                    Spacer()
                    if model.isBuilding(day) {
                        ProgressView()
                    } else {
                        Button {
                            Task { await model.playSoundtrack(day) }
                        } label: {
                            Label("Crea", systemImage: "wand.and.stars")
                                .font(.m3LabelLarge)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
        }
    }

    private func shareClip(_ clip: Clip) {
        if let url = model.shareableCopy(of: Storage.url(clip.fileName), named: FileNaming.clipExportName(clip)) {
            share = ShareFiles(urls: [url])
        }
    }
}

/// A clip in the day timeline: time on the left, a line joining the moments.
struct ClipRow: View {
    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(\.m3) private var m3
    let clip: Clip
    let list: [Clip]
    var isFirst = false
    var isLast = false
    var showDate = false
    var onEdit: () -> Void = {}
    var onShare: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        let current = player.isCurrent(clip.id.uuidString)
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? .clear : m3.outlineVariant)
                    .frame(width: 2, height: 18)
                Circle()
                    .fill(current ? m3.primary : m3.surfaceContainerHighest)
                    .overlay(Circle().strokeBorder(m3.primary, lineWidth: current ? 0 : 2))
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(isLast ? .clear : m3.outlineVariant)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ItalianFormat.time(minuteOfDay: clip.minuteOfDay))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(m3.onSurface)
                    if showDate {
                        Text(ItalianFormat.dayShort(clip.day))
                            .font(.m3LabelMedium)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    Spacer()
                    if let w = clip.weather {
                        Label(ItalianFormat.temperature(w.temperatureC), systemImage: w.symbol)
                            .font(.m3LabelMedium)
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    Button {
                        model.toggleFavorite(clip.id)
                    } label: {
                        Image(systemName: clip.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(clip.isFavorite ? m3.primary : m3.outline)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(clip.isFavorite ? "Togli dai preferiti" : "Aggiungi ai preferiti")
                }
                HStack(spacing: 12) {
                    PlayButton(playing: current && player.isPlaying, size: 40, filled: current) {
                        model.play(clip, in: list)
                    }
                    WaveformView(samples: clip.waveform, color: m3.outlineVariant, played: m3.primary,
                                 progress: current ? player.progress : 0, barCount: 34)
                        .frame(height: 30)
                    Text(ItalianFormat.clock(clip.duration))
                        .font(.m3LabelMedium)
                        .monospacedDigit()
                        .foregroundStyle(m3.onSurfaceVariant)
                }
                if let place = clip.placeLine {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .lineLimit(1)
                }
                if !clip.note.isEmpty || !clip.emoji.isEmpty {
                    Text([clip.emoji, clip.note].filter { !$0.isEmpty }.joined(separator: "  "))
                        .font(.m3BodyMedium)
                        .foregroundStyle(m3.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(current ? m3.primaryContainer.opacity(0.45) : m3.surfaceContainerLow,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.bottom, 10)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contextMenu {
                Button { onEdit() } label: { Label("Nota ed emoji", systemImage: "pencil") }
                Button { model.toggleFavorite(clip.id) } label: {
                    Label(clip.isFavorite ? "Togli dai preferiti" : "Preferito", systemImage: clip.isFavorite ? "star.slash" : "star")
                }
                Button { onShare() } label: { Label("Condividi audio", systemImage: "square.and.arrow.up") }
                Divider()
                Button(role: .destructive) { onDelete() } label: { Label("Elimina", systemImage: "trash") }
            }
            .onTapGesture(count: 2) { onEdit() }
        }
    }
}

/// Note, emoji and favourite of a clip.
struct ClipEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3) private var m3
    let clip: Clip
    @State private var note = ""
    @State private var emoji = ""
    @State private var favorite = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Nota") {
                    TextField("Cosa si sente?", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
                .listRowBackground(m3.surfaceContainerLow)
                Section("Emoji") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 8) {
                        ForEach(EmojiCatalog.quick, id: \.self) { e in
                            Button {
                                emoji = emoji == e ? "" : e
                            } label: {
                                Text(e)
                                    .font(.system(size: 24))
                                    .frame(width: 38, height: 38)
                                    .background(emoji == e ? m3.primaryContainer : .clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    TextField("Oppure scrivine una", text: Binding(
                        get: { emoji },
                        set: { emoji = String($0.trimmingCharacters(in: .whitespaces).prefix(2)) }
                    ))
                }
                .listRowBackground(m3.surfaceContainerLow)
                Section {
                    Toggle(isOn: $favorite) { Label("Preferito", systemImage: "star.fill") }
                }
                .listRowBackground(m3.surfaceContainerLow)
            }
            .scrollContentBackground(.hidden)
            .background(m3.surface)
            .navigationTitle("Clip delle \(ItalianFormat.time(minuteOfDay: clip.minuteOfDay))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        model.updateClip(clip.id, note: note, emoji: emoji, favorite: favorite)
                        dismiss()
                    }
                }
            }
            .onAppear {
                note = clip.note
                emoji = clip.emoji
                favorite = clip.isFavorite
            }
        }
    }
}
