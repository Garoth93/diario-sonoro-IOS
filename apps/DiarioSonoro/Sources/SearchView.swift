import SwiftUI
import SonoroCore

/// Search by note, place, emoji and date; favourites.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @State private var filter = ClipFilter()
    @State private var period: Period = .all

    enum Period: String, CaseIterable, Identifiable {
        case all, week, month, year
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "Sempre"
            case .week: return "Ultimi 7 giorni"
            case .month: return "Ultimi 30 giorni"
            case .year: return "Ultimo anno"
            }
        }
        func from(_ today: DayDate) -> DayDate? {
            switch self {
            case .all: return nil
            case .week: return today.adding(days: -6)
            case .month: return today.adding(days: -29)
            case .year: return today.adding(days: -364)
            }
        }
    }

    var body: some View {
        var f = filter
        f.from = period.from(model.today)
        let results = f.apply(model.data.clips)
        let groups = DayGrouping.group(results)
        let emojis: [String] = SearchText.emojis(in: model.data.clips).prefix(10).map { $0.emoji }
        let places: [(name: String, count: Int)] = Array(SearchText.places(in: model.data.clips).prefix(20))
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(title: "Preferiti", icon: "star", selected: filter.favoritesOnly) {
                            filter.favoritesOnly.toggle()
                        }
                        Menu {
                            ForEach(Period.allCases) { p in
                                Button(p.label) { period = p }
                            }
                        } label: {
                            ChipLabel(title: period == .all ? "Periodo" : period.label, icon: "calendar",
                                      selected: period != .all, showsChevron: true)
                        }
                        Menu {
                            Button("Tutti i luoghi") { filter.place = nil }
                            ForEach(places.indices, id: \.self) { i in
                                Button("\(places[i].name) (\(places[i].count))") { filter.place = places[i].name }
                            }
                        } label: {
                            ChipLabel(title: filter.place ?? "Luogo", icon: "mappin", selected: filter.place != nil, showsChevron: true)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
                if !emojis.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(emojis, id: \.self) { e in
                                Button {
                                    filter.emoji = filter.emoji == e ? nil : e
                                } label: {
                                    Text(e)
                                        .font(.system(size: 22))
                                        .frame(width: 44, height: 44)
                                        .background(filter.emoji == e ? m3.primaryContainer : m3.surfaceContainerLow, in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
                Text(f.isEmpty ? "\(ItalianFormat.clips(results.count)) in tutto" : "\(ItalianFormat.clips(results.count)) trovate")
                    .font(.m3LabelLarge)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .padding(.top, 4)
                if results.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "Nessun risultato",
                                   message: "Prova con un'altra parola, un luogo o un'emoji.")
                } else {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(groups.prefix(60)) { g in
                            Button {
                                model.calendarPath.append(.day(g.day))
                            } label: {
                                HStack {
                                    Text(ItalianFormat.relativeDay(g.day, today: model.today))
                                        .font(.m3TitleSmall)
                                        .foregroundStyle(m3.onSurface)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(m3.outline)
                                }
                                .padding(.top, 10)
                                .padding(.bottom, 4)
                            }
                            .buttonStyle(.plain)
                            ForEach(Array(g.clips.enumerated()), id: \.element.id) { i, clip in
                                ClipRow(clip: clip, list: g.clips, isFirst: i == 0, isLast: i == g.clips.count - 1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(m3.surface)
        .navigationTitle("Cerca")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter.text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nota, luogo, emoji, mese…")
    }
}
