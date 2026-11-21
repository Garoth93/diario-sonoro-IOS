import SwiftUI
import SonoroCore

/// "Un anno fa oggi": the same day 1, 2, 3… years ago.
struct AnniversaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    var body: some View {
        let groups = Anniversary.groups(for: model.today, in: model.data.clips)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.today.day) \(ItalianFormat.monthName(model.today.month))")
                        .font(.m3HeadlineLarge)
                        .foregroundStyle(m3.onSurface)
                    Text("Com'era questo giorno negli anni passati")
                        .font(.m3BodyMedium)
                        .foregroundStyle(m3.onSurfaceVariant)
                }
                .padding(.top, 8)
                if groups.isEmpty {
                    EmptyStateView(icon: "clock.arrow.circlepath", title: "Ancora niente da ricordare",
                                   message: "Tra un anno, in questo giorno, qui ritroverai i suoni che registri oggi.")
                } else {
                    ForEach(groups) { g in
                        AnniversaryYearCard(group: g)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(m3.surface)
        .navigationTitle("Un anno fa oggi")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AnniversaryYearCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let group: AnniversaryGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(group.year))
                    .font(.numberMedium)
                    .monospacedDigit()
                    .foregroundStyle(m3.primary)
                Text(group.title)
                    .font(.m3TitleMedium)
                    .foregroundStyle(m3.onSurface)
                Spacer()
                Button {
                    model.playAll(group.clips)
                } label: {
                    Label("Ascolta", systemImage: "play.fill")
                        .font(.m3LabelLarge)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            if let day = group.days.first, let s = model.data.soundtrack(for: day), group.days.count == 1 {
                SoundtrackCard(track: s, title: ItalianFormat.capitalized(ItalianFormat.dayTitle(day)))
            }
            VStack(spacing: 0) {
                ForEach(Array(group.clips.enumerated()), id: \.element.id) { i, clip in
                    ClipRow(clip: clip, list: group.clips, isFirst: i == 0, isLast: i == group.clips.count - 1)
                }
            }
            Button {
                if let d = group.days.first { model.calendarPath.append(.day(d)) }
            } label: {
                Text("Apri il giorno")
                    .font(.m3LabelLarge)
            }
        }
        .padding(.bottom, 8)
    }
}
