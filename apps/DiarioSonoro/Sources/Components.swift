import SwiftUI
import UIKit
import SonoroCore

// MARK: - Surfaces

/// Material 3 card: tonal surface, large continuous corners.
struct M3Card<Content: View>: View {
    @Environment(\.m3) private var m3
    var color: Color?
    var padding: CGFloat
    var corner: CGFloat
    let content: Content

    init(color: Color? = nil, padding: CGFloat = 18, corner: CGFloat = 28, @ViewBuilder content: () -> Content) {
        self.color = color
        self.padding = padding
        self.corner = corner
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color ?? m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct SectionTitle: View {
    @Environment(\.m3) private var m3
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.m3TitleMedium)
                .foregroundStyle(m3.onSurface)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.m3LabelMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 12)
    }
}

/// A big number with its caption (statistics, counters).
struct BigNumber: View {
    @Environment(\.m3) private var m3
    let value: String
    let label: String
    var font: Font = .numberMedium
    var color: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(color ?? m3.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.m3LabelMedium)
                .foregroundStyle(m3.onSurfaceVariant)
                .lineLimit(1)
        }
    }
}

/// Small app mark: accent circle with a waveform.
struct AppMark: View {
    @Environment(\.m3) private var m3
    var size: CGFloat = 64

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(m3.onPrimary)
            .frame(width: size, height: size)
            .background(m3.primary, in: Circle())
    }
}

// MARK: - Buttons

/// Pressed-state scale used by tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Material 3 filled / tonal pill button.
struct PillButton: View {
    let title: String
    let icon: String
    let tones: Tones
    var filled = true
    var height: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.m3TitleMedium)
            }
            .foregroundStyle(filled ? tones.onAccent : tones.onContainer)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(filled ? tones.accent : tones.container, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Round play / pause button.
struct PlayButton: View {
    @Environment(\.m3) private var m3
    let playing: Bool
    var size: CGFloat = 44
    var filled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(filled ? m3.onPrimary : m3.onPrimaryContainer)
                .offset(x: playing ? 0 : size * 0.03)
                .frame(width: size, height: size)
                .background(filled ? m3.primary : m3.primaryContainer, in: Circle())
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(playing ? "Pausa" : "Riproduci")
    }
}

/// Small selectable chip (filters).
struct Chip: View {
    @Environment(\.m3) private var m3
    let title: String
    var icon: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(title: title, icon: icon, selected: selected)
        }
        .buttonStyle(.plain)
    }
}

struct ChipLabel: View {
    @Environment(\.m3) private var m3
    let title: String
    var icon: String?
    let selected: Bool
    var showsChevron = false

    var body: some View {
        HStack(spacing: 6) {
            if selected && !showsChevron {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
            } else if let icon {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            }
            Text(title).font(.m3LabelLarge)
            if showsChevron {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .foregroundStyle(selected ? m3.onSecondaryContainer : m3.onSurfaceVariant)
        .background(selected ? m3.secondaryContainer : m3.surface.opacity(0.001), in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? Color.clear : m3.outlineVariant, lineWidth: 1))
        .contentShape(Capsule())
    }
}

// MARK: - Toast

struct ToastView: View {
    @Environment(\.m3) private var m3
    let toast: Toast

    var body: some View {
        let tones: Tones = {
            switch toast.style {
            case .success: return m3.primaryTones
            case .info: return m3.neutral
            case .error: return m3.danger
            }
        }()
        HStack(spacing: 10) {
            Image(systemName: toast.icon)
                .font(.system(size: 15, weight: .bold))
            Text(toast.message)
                .font(.m3LabelLarge)
        }
        .foregroundStyle(tones.onContainer)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(tones.container, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @Environment(\.m3) private var m3
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            IconBadge(icon: icon, tones: m3.primaryTones, size: 80, cookie: true)
            Text(title)
                .font(.m3TitleLarge)
                .foregroundStyle(m3.onSurface)
            Text(message)
                .font(.m3BodyMedium)
                .foregroundStyle(m3.onSurfaceVariant)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

// MARK: - Share sheet

/// Files to share (a soundtrack, a backup ZIP, a CSV).
struct ShareFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Emoji

enum EmojiCatalog {
    static let quick = ["🌲", "🐦", "🌊", "🌧️", "💨", "❄️", "🔔", "🏃", "🚴", "⛷️", "🚆", "🛒",
                        "🍝", "🎶", "👶", "🐶", "🏙️", "🏔️", "☕️", "🔥", "🌙", "☀️", "❤️", "😌"]
}
