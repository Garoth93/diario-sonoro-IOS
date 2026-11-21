import SwiftUI
import SonoroCore

/// Card of a daily soundtrack: play, waveform, duration, share.
struct SoundtrackCard: View {
    @Environment(AppModel.self) private var model
    @Environment(PlayerModel.self) private var player
    @Environment(\.m3) private var m3
    let track: DailySoundtrack
    var title = "Colonna sonora"
    @State private var share: ShareFiles?

    var body: some View {
        let item = PlayItem.soundtrack(track, root: Storage.root)
        let current = player.isCurrent(item.id)
        M3Card(color: m3.primaryContainer, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.m3TitleMedium)
                            .foregroundStyle(m3.onPrimaryContainer)
                        Text("\(ItalianFormat.clips(track.clipIDs.count)) · \(ItalianFormat.duration(track.duration))")
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onPrimaryContainer.opacity(0.75))
                    }
                    Spacer()
                    Button {
                        if let url = model.shareableCopy(of: model.soundtrackURL(track), named: FileNaming.soundtrackExportName(day: track.day)) {
                            share = ShareFiles(urls: [url])
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(m3.onPrimaryContainer)
                            .frame(width: 40, height: 40)
                            .background(m3.onPrimaryContainer.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Condividi")
                    PlayButton(playing: current && player.isPlaying, size: 48) {
                        player.toggle(item)
                    }
                }
                WaveformView(samples: track.waveform, color: m3.onPrimaryContainer.opacity(0.22), played: m3.primary,
                             progress: current ? player.progress : 0, barCount: 52, spacing: 2.5)
                    .frame(height: 40)
                if current {
                    HStack {
                        Text(ItalianFormat.clock(player.currentTime))
                        Spacer()
                        Text(ItalianFormat.clock(track.duration))
                    }
                    .font(.m3LabelSmall)
                    .monospacedDigit()
                    .foregroundStyle(m3.onPrimaryContainer.opacity(0.7))
                }
            }
        }
        .sheet(item: $share) { s in
            ActivitySheet(items: s.urls)
                .presentationDetents([.medium, .large])
        }
    }
}

/// Bar above the tab bar while something is loaded.
struct MiniPlayerBar: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.m3) private var m3
    @State private var expanded = false

    var body: some View {
        if let item = player.current {
            HStack(spacing: 12) {
                PlayButton(playing: player.isPlaying, size: 42) { player.togglePlayPause() }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.m3TitleSmall)
                            .foregroundStyle(m3.onSurface)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(ItalianFormat.clock(max(0, player.duration - player.currentTime)))
                            .font(.m3LabelSmall)
                            .monospacedDigit()
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    WaveformView(samples: item.waveform, color: m3.outlineVariant, played: m3.primary,
                                 progress: player.progress, barCount: 40, spacing: 1.5)
                        .frame(height: 16)
                }
                .contentShape(Rectangle())
                .onTapGesture { expanded = true }
                if player.hasNext {
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(m3.onSurfaceVariant)
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("Successiva")
                }
                Button { player.stop() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(m3.onSurfaceVariant)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Chiudi")
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(m3.outlineVariant.opacity(0.4), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.10), radius: 14, y: 4)
            .sheet(isPresented: $expanded) {
                PlayerSheet()
                    .presentationDetents([.medium])
                    .presentationCornerRadius(32)
            }
        }
    }
}

/// Expanded player: big waveform you can tap to seek, speed, queue.
struct PlayerSheet: View {
    @Environment(PlayerModel.self) private var player
    @Environment(\.m3) private var m3

    var body: some View {
        VStack(spacing: 22) {
            if let item = player.current {
                VStack(spacing: 4) {
                    Text(item.title)
                        .font(.m3TitleLarge)
                        .foregroundStyle(m3.onSurface)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.m3BodyMedium)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .lineLimit(1)
                }
                .padding(.top, 28)
                GeometryReader { geo in
                    WaveformView(samples: item.waveform, color: m3.outlineVariant, played: m3.primary,
                                 progress: player.progress, barCount: 60, spacing: 2.5)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            let f = min(1, max(0, v.location.x / max(1, geo.size.width)))
                            player.seek(to: f * player.duration)
                        })
                }
                .frame(height: 72)
                HStack {
                    Text(ItalianFormat.clock(player.currentTime))
                    Spacer()
                    Text(ItalianFormat.clock(player.duration))
                }
                .font(.m3LabelMedium)
                .monospacedDigit()
                .foregroundStyle(m3.onSurfaceVariant)
                HStack(spacing: 28) {
                    Button { player.cycleRate() } label: {
                        Text(rateLabel)
                            .font(.m3LabelLarge)
                            .monospacedDigit()
                            .foregroundStyle(m3.onSecondaryContainer)
                            .frame(width: 58, height: 36)
                            .background(m3.secondaryContainer, in: Capsule())
                    }
                    .accessibilityLabel("Velocità \(rateLabel)")
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 22, weight: .semibold))
                    }
                    PlayButton(playing: player.isPlaying, size: 68) { player.togglePlayPause() }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 22, weight: .semibold))
                    }
                    .disabled(!player.hasNext)
                    Text("\(player.index + 1)/\(player.queue.count)")
                        .font(.m3LabelMedium)
                        .monospacedDigit()
                        .foregroundStyle(m3.onSurfaceVariant)
                        .frame(width: 58)
                }
                .foregroundStyle(m3.onSurface)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(m3.surfaceContainerLow)
    }

    private var rateLabel: String {
        let r = player.rate
        return r == 1 ? "1×" : ItalianFormat.decimal(Double(r), digits: 2) + "×"
    }
}
