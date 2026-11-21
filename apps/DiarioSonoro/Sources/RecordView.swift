import SwiftUI
import UIKit
import SonoroCore

/// Home screen: today, the big hold-to-record button, today's clips,
/// the soundtrack and "un anno fa oggi".
struct RecordView: View {
    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(\.m3) private var m3

    var body: some View {
        let today = model.today
        let clips = model.data.clips(on: today)
        let summary = DaySummary(day: today, clips: clips)
        ScrollView {
            VStack(spacing: 22) {
                header(summary)
                RecordButton()
                    .padding(.top, 4)
                hint
                todayCard(summary)
                soundtrackCard(summary)
                anniversaryCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(model.isRecording)
        .background(m3.surface)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private func header(_ s: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ItalianFormat.capitalized(ItalianFormat.dayTitleNoYear(s.day)))
                .font(.m3TitleMedium)
                .foregroundStyle(m3.onSurfaceVariant)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(s.count)")
                    .font(.numberHero)
                    .monospacedDigit()
                    .foregroundStyle(m3.onSurface)
                    .contentTransition(.numericText())
                    .animation(.spring, value: s.count)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.count == 1 ? "clip oggi" : "clip oggi")
                        .font(.m3TitleMedium)
                        .foregroundStyle(m3.onSurface)
                    Text(s.count == 0 ? "il diario aspetta" : ItalianFormat.duration(s.totalDuration) + " di suoni")
                        .font(.m3BodyMedium)
                        .foregroundStyle(m3.onSurfaceVariant)
                }
                Spacer()
                let streak = DiaryStats.streaks(days: Set(model.data.clips.map(\.day)), today: model.today).current
                if streak > 1 {
                    VStack(spacing: 0) {
                        Text("\(streak)")
                            .font(.m3TitleLarge)
                            .monospacedDigit()
                            .foregroundStyle(m3.primary)
                        Text("giorni di fila")
                            .font(.m3LabelSmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }

    // MARK: Hint under the button

    @ViewBuilder
    private var hint: some View {
        if model.microphoneDenied {
            VStack(spacing: 8) {
                Text("Il microfono non è autorizzato.")
                    .font(.m3BodyMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
                Button("Apri Impostazioni") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .font(.m3LabelLarge)
            }
        } else {
            Group {
                switch model.phase {
                case .recording:
                    Text(model.recordingByTap ? "Tocca il pulsante per fermare" : "Rilascia per salvare")
                case .saving, .starting:
                    Text("Un attimo…")
                case .idle:
                    Text("Tieni premuto per registrare \(model.settings.clipDuration) secondi")
                }
            }
            .font(.m3BodyMedium)
            .foregroundStyle(m3.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .animation(.easeInOut, value: model.phase)
        }
    }

    // MARK: Today's clips

    private func todayCard(_ s: DaySummary) -> some View {
        M3Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Oggi")
                        .font(.m3TitleMedium)
                        .foregroundStyle(m3.onSurface)
                    Spacer()
                    if s.count > 1 {
                        Button {
                            model.playAll(s.clips)
                        } label: {
                            Label("Ascolta tutte", systemImage: "play.fill")
                                .font(.m3LabelLarge)
                        }
                    }
                }
                if s.clips.isEmpty {
                    Text("Ancora nessun suono. Il bosco, la strada, la cucina: ogni posto ha la sua voce.")
                        .font(.m3BodyMedium)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(s.clips.reversed()) { clip in
                                ClipChip(clip: clip, list: s.clips)
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
        }
    }

    // MARK: Soundtrack

    @ViewBuilder
    private func soundtrackCard(_ s: DaySummary) -> some View {
        let readyToday = model.data.soundtrack(for: s.day).flatMap { $0.clipIDs == s.clips.map(\.id) ? $0 : nil }
        if let track = readyToday {
            SoundtrackCard(track: track, title: "Colonna sonora di oggi")
        } else if !s.clips.isEmpty {
            M3Card {
                HStack(spacing: 14) {
                    IconBadge(icon: "moon.stars.fill", tones: m3.primaryTones, size: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Colonna sonora di oggi")
                            .font(.m3TitleSmall)
                            .foregroundStyle(m3.onSurface)
                        Text("Pronta alle \(model.settings.soundtrackTime.label), con \(ItalianFormat.clips(s.count))")
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    Spacer()
                    if model.isBuilding(s.day) {
                        ProgressView()
                    } else {
                        Button("Crea ora") {
                            Task { await model.playSoundtrack(s.day) }
                        }
                        .font(.m3LabelLarge)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                    }
                }
            }
        } else if let yesterday = model.data.soundtrack(for: s.day.adding(days: -1)) {
            SoundtrackCard(track: yesterday, title: "Colonna sonora di ieri")
        }
    }

    // MARK: Anniversary

    @ViewBuilder
    private var anniversaryCard: some View {
        let groups = Anniversary.groups(for: model.today, in: model.data.clips)
        if let first = groups.first {
            Button {
                model.handle(.anniversary)
            } label: {
                M3Card(color: m3.surfaceContainer) {
                    HStack(spacing: 14) {
                        IconBadge(icon: "clock.arrow.circlepath", tones: m3.primaryTones, size: 46, cookie: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(groups.count > 1 ? "Oggi, negli anni passati" : "\(first.title) oggi")
                                .font(.m3TitleSmall)
                                .foregroundStyle(m3.onSurface)
                            Text(anniversaryLine(groups))
                                .font(.m3BodySmall)
                                .foregroundStyle(m3.onSurfaceVariant)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(m3.outline)
                    }
                }
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func anniversaryLine(_ groups: [AnniversaryGroup]) -> String {
        let n = groups.reduce(0) { $0 + $1.clips.count }
        let places = DaySummary(day: model.today, clips: groups.flatMap(\.clips)).places
        var s = ItalianFormat.clips(n)
        if let p = places.first { s += " · \(p)" }
        if groups.count > 1 { s += " · " + groups.map { String($0.year) }.joined(separator: ", ") }
        return s
    }
}

/// Compact clip for horizontal strips: time, waveform, place.
struct ClipChip: View {
    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(\.m3) private var m3
    let clip: Clip
    let list: [Clip]

    var body: some View {
        let current = player.isCurrent(clip.id.uuidString)
        Button {
            model.play(clip, in: list)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(ItalianFormat.time(minuteOfDay: clip.minuteOfDay))
                        .font(.m3TitleSmall)
                        .monospacedDigit()
                    if !clip.emoji.isEmpty { Text(clip.emoji).font(.system(size: 13)) }
                    Spacer(minLength: 0)
                    Image(systemName: current && player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(m3.primary)
                }
                .foregroundStyle(m3.onSurface)
                WaveformView(samples: clip.waveform, color: m3.outlineVariant, played: m3.primary,
                             progress: current ? player.progress : 0, barCount: 20)
                    .frame(height: 24)
                Text(clip.displayPlace ?? "Senza luogo")
                    .font(.m3LabelSmall)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(width: 128)
            .background(current ? m3.primaryContainer.opacity(0.6) : m3.surfaceContainerHigh,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Big hold-to-record button with progress ring and live level halo.
struct RecordButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var pressed = false
    var size: CGFloat = 200

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isRecording)) { ctx in
            let elapsed = model.elapsed(at: ctx.date)
            let rules = model.rules
            let progress = rules.progress(elapsed: elapsed)
            let level = model.isRecording ? CGFloat(model.inputLevel(at: ctx.date)) : 0
            let recording = model.isRecording
            ZStack {
                Circle()
                    .fill(m3.primary.opacity(recording ? 0.16 : 0.07))
                    .frame(width: size + 64, height: size + 64)
                    .scaleEffect(recording ? 0.92 + level * 0.22 : 0.9)
                    .animation(.easeOut(duration: 0.12), value: level)
                Circle()
                    .stroke(m3.primary.opacity(0.16), lineWidth: 7)
                    .frame(width: size + 26, height: size + 26)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(m3.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size + 26, height: size + 26)
                Circle()
                    .fill(recording ? m3.primary : m3.primary)
                    .frame(width: size, height: size)
                    .shadow(color: m3.primary.opacity(0.35), radius: recording ? 26 : 14, y: 8)
                    .scaleEffect(pressed || recording ? 0.95 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pressed || recording)
                VStack(spacing: 0) {
                    if recording {
                        Text("\(rules.remainingSeconds(elapsed: elapsed))")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                        Text("secondi")
                            .font(.m3LabelLarge)
                            .opacity(0.8)
                    } else if model.phase == .saving || model.phase == .starting {
                        ProgressView().tint(m3.onPrimary).controlSize(.large)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: size * 0.28, weight: .semibold))
                    }
                }
                .foregroundStyle(m3.onPrimary)
            }
            .frame(width: size + 64, height: size + 64)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    if model.isRecording && model.recordingByTap {
                        Task { await model.stopRecording() }
                    } else if model.phase == .idle {
                        Task { await model.startRecording() }
                    }
                }
                .onEnded { _ in
                    pressed = false
                    if !model.recordingByTap {
                        Task { await model.stopRecording() }
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel(model.isRecording ? "Registrazione in corso" : "Registra")
        .accessibilityHint("Tieni premuto per registrare il suono intorno a te")
        .accessibilityAddTraits(.isButton)
    }
}
