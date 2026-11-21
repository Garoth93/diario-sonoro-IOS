import SwiftUI
import WidgetKit
import SonoroCore

// Widget content, compiled in both targets: the widget extension draws it on
// the Home / Lock Screen, the app shows it in the widget gallery (CI screenshots).

struct TodayWidgetContent: View {
    let snapshot: WidgetSnapshot
    let family: WidgetFamily
    /// `false` when the widget cannot read the App Group.
    var hasData = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let m3 = M3Theme(seed: Palette.defaultAccent, dark: colorScheme == .dark)
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemMedium: medium(m3)
        default: small(m3)
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                if hasData && snapshot.todayClips > 0 {
                    Text("\(snapshot.todayClips)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
        }
        .widgetAccentable()
        .accessibilityLabel("Registra con Diario Sonoro")
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(.white.opacity(0.18))
                Image(systemName: "mic.fill").font(.system(size: 17, weight: .semibold))
            }
            .frame(width: 34, height: 34)
            .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text("Diario Sonoro")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(todayLine)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("Tocca per registrare")
                    .font(.system(size: 12))
                    .opacity(0.75)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var inline: some View {
        Label(hasData && snapshot.todayClips > 0 ? todayLine : "Registra un suono", systemImage: "mic.fill")
    }

    private var todayLine: String {
        guard hasData else { return "Il suono di oggi" }
        if snapshot.todayClips == 0 { return "Nessuna clip oggi" }
        return "\(ItalianFormat.clips(snapshot.todayClips)) oggi"
    }

    // MARK: Home Screen

    private func small(_ m3: M3Theme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                micButton(m3, size: 44)
                Spacer()
                if hasData && snapshot.streak > 1 {
                    Text("\(snapshot.streak) g")
                        .font(.m3LabelMedium)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(m3.surfaceContainerHigh, in: Capsule())
                }
            }
            Spacer(minLength: 6)
            Text(hasData ? "\(snapshot.todayClips)" : "–")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(m3.onSurface)
                .contentTransition(.numericText())
            Text("clip oggi")
                .font(.m3LabelLarge)
                .foregroundStyle(m3.onSurfaceVariant)
            WaveformView(samples: snapshot.waveform, color: snapshot.todayClips > 0 ? m3.primary : m3.outlineVariant, barCount: 18)
                .frame(height: 16)
                .padding(.top, 8)
        }
        .padding(16)
    }

    private func medium(_ m3: M3Theme) -> some View {
        HStack(spacing: 14) {
            small(m3)
                .padding(-16)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                infoRow(m3, icon: snapshot.soundtrackReady ? "waveform.circle.fill" : "moon.stars.fill",
                        title: "Colonna sonora",
                        value: snapshot.soundtrackReady ? "Pronta da ascoltare" : (snapshot.todayClips > 0 ? "Alle \(snapshot.soundtrackTime.label)" : "Registra per crearla"))
                if !snapshot.anniversaryYears.isEmpty {
                    infoRow(m3, icon: "clock.arrow.circlepath", title: ItalianFormat.yearsAgo(snapshot.anniversaryYears[0]),
                            value: "\(ItalianFormat.clips(snapshot.anniversaryClips)) da riascoltare")
                } else if let place = snapshot.lastPlace, let minute = snapshot.lastMinute {
                    infoRow(m3, icon: "mappin.circle.fill", title: place, value: "Ultima alle \(ItalianFormat.time(minuteOfDay: minute))")
                } else {
                    infoRow(m3, icon: "calendar", title: "\(ItalianFormat.days(snapshot.totalDays))", value: "registrati finora")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    private func infoRow(_ m3: M3Theme, icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(m3.primary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.m3TitleSmall)
                    .foregroundStyle(m3.onSurface)
                    .lineLimit(1)
                Text(value)
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(2)
            }
        }
    }

    private func micButton(_ m3: M3Theme, size: CGFloat) -> some View {
        Image(systemName: "mic.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(m3.onPrimary)
            .frame(width: size, height: size)
            .background(m3.primary, in: Circle())
    }
}

/// Widget background color (also used by the in-app gallery).
struct WidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let m3 = M3Theme(seed: Palette.defaultAccent, dark: colorScheme == .dark)
        m3.surfaceContainerLow
    }
}
