import SwiftUI
import Charts
import SonoroCore

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    var body: some View {
        let s = DiaryStats(data: model.data, today: model.today)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if s.isEmpty {
                    EmptyStateView(icon: "chart.bar.fill", title: "Ancora nessun dato",
                                   message: "Le statistiche si riempiono man mano che registri i suoni delle tue giornate.")
                } else {
                    hero(s)
                    kpis(s)
                    monthsCard(s)
                    placesCard(s)
                    hoursCard(s)
                    weekdaysCard(s)
                    storageCard(s)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(m3.surface)
        .navigationTitle("Statistiche")
        .toolbarTitleDisplayMode(.inlineLarge)
    }

    // MARK: Hero

    private func hero(_ s: DiaryStats) -> some View {
        M3Card(color: m3.primaryContainer, padding: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Giorni registrati")
                    .font(.m3LabelLarge)
                    .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
                Text(ItalianFormat.number(s.recordedDays))
                    .font(.numberHero)
                    .monospacedDigit()
                    .foregroundStyle(m3.onPrimaryContainer)
                if let first = s.firstDay {
                    Text("Dal \(ItalianFormat.dayShort(first)): \(ItalianFormat.percent(s.coverage)) dei giorni ha la sua voce.")
                        .font(.m3BodyMedium)
                        .foregroundStyle(m3.onPrimaryContainer.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(m3.onPrimaryContainer.opacity(0.12))
                        Capsule().fill(m3.primary).frame(width: geo.size.width * s.coverage)
                    }
                }
                .frame(height: 8)
                .padding(.top, 6)
            }
        }
    }

    private func kpis(_ s: DiaryStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile(value: ItalianFormat.number(s.totalClips), label: "clip totali",
                 foot: "\(ItalianFormat.decimal(s.averagePerDay)) al giorno")
            tile(value: ItalianFormat.decimal(s.totalMinutes, digits: s.totalMinutes < 100 ? 1 : 0), label: "minuti di suoni",
                 foot: ItalianFormat.duration(s.totalDuration))
            tile(value: "\(s.currentStreak)", label: "giorni di fila", foot: "record \(s.longestStreak)", accent: s.currentStreak > 0)
            tile(value: "\(s.distinctPlaces)", label: "luoghi", foot: "\(s.favorites) preferite")
        }
    }

    private func tile(value: String, label: String, foot: String, accent: Bool = false) -> some View {
        M3Card(padding: 18, corner: 24) {
            VStack(alignment: .leading, spacing: 8) {
                BigNumber(value: value, label: label, font: .numberLarge, color: accent ? m3.primary : nil)
                Text(foot)
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Charts

    private func monthsCard(_ s: DiaryStats) -> some View {
        card(title: "Ultimi 12 mesi", subtitle: "giorni registrati") {
            Chart(s.byMonth) { m in
                BarMark(x: .value("Mese", ItalianFormat.shortMonths[m.month.month - 1] + (m.month.month == 1 ? " \(m.month.year % 100)" : "")),
                        y: .value("Giorni", m.days))
                    .foregroundStyle(m.month == MonthRef(model.today) ? m3.primary : m3.primary.opacity(0.45))
                    .cornerRadius(5)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(m3.outlineVariant.opacity(0.5))
                    AxisValueLabel().foregroundStyle(m3.onSurfaceVariant)
                }
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().foregroundStyle(m3.onSurfaceVariant) }
            }
            .frame(height: 170)
        }
    }

    private func placesCard(_ s: DiaryStats) -> some View {
        card(title: "Luoghi più registrati", subtitle: nil) {
            let top = s.topPlaces.first?.clips ?? 1
            VStack(spacing: 14) {
                ForEach(s.topPlaces) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(p.name)
                                .font(.m3TitleSmall)
                                .foregroundStyle(m3.onSurface)
                                .lineLimit(1)
                            Spacer()
                            Text("\(p.clips)")
                                .font(.m3TitleSmall)
                                .monospacedDigit()
                                .foregroundStyle(m3.onSurface)
                        }
                        GeometryReader { geo in
                            Capsule()
                                .fill(m3.primary.opacity(p.id == s.topPlaces.first?.id ? 1 : 0.5))
                                .frame(width: max(8, geo.size.width * CGFloat(p.clips) / CGFloat(top)))
                        }
                        .frame(height: 6)
                        Text("\(ItalianFormat.days(p.days)) · \(ItalianFormat.duration(p.duration))")
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                }
            }
        }
    }

    private func hoursCard(_ s: DiaryStats) -> some View {
        card(title: "Orari tipici", subtitle: s.typicalHour.map { "di solito verso le \($0):00" }) {
            Chart {
                ForEach(0..<24, id: \.self) { h in
                    BarMark(x: .value("Ora", h), y: .value("Clip", s.byHour[h]))
                        .foregroundStyle(h == s.typicalHour ? m3.primary : m3.primary.opacity(0.4))
                        .cornerRadius(3)
                }
            }
            .chartXScale(domain: 0...23)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                    AxisValueLabel {
                        if let h = v.as(Int.self) { Text("\(h)") }
                    }
                    .foregroundStyle(m3.onSurfaceVariant)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 130)
        }
    }

    private func weekdaysCard(_ s: DiaryStats) -> some View {
        let maxValue = max(1, s.byWeekday.max() ?? 1)
        return card(title: "Giorni della settimana", subtitle: nil) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text("\(s.byWeekday[i])")
                            .font(.m3LabelSmall)
                            .monospacedDigit()
                            .foregroundStyle(m3.onSurfaceVariant)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(s.byWeekday[i] == maxValue ? m3.primary : m3.primary.opacity(0.4))
                            .frame(height: max(6, 90 * CGFloat(s.byWeekday[i]) / CGFloat(maxValue)))
                        Text(MonthGrid.weekdaySymbols[i])
                            .font(.m3LabelMedium)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
    }

    private func storageCard(_ s: DiaryStats) -> some View {
        card(title: "Spazio occupato", subtitle: nil) {
            VStack(alignment: .leading, spacing: 14) {
                Text(ItalianFormat.bytes(s.totalBytes))
                    .font(.numberLarge)
                    .monospacedDigit()
                    .foregroundStyle(m3.onSurface)
                GeometryReader { geo in
                    let share = s.totalBytes > 0 ? CGFloat(s.clipBytes) / CGFloat(s.totalBytes) : 0
                    HStack(spacing: 3) {
                        Capsule().fill(m3.primary).frame(width: max(6, (geo.size.width - 3) * share))
                        Capsule().fill(m3.primary.opacity(0.35))
                    }
                }
                .frame(height: 10)
                HStack {
                    legend(color: m3.primary, title: "Clip", value: ItalianFormat.bytes(s.clipBytes))
                    Spacer()
                    legend(color: m3.primary.opacity(0.35), title: "Colonne sonore", value: ItalianFormat.bytes(s.soundtrackBytes))
                }
                Text("In media \(ItalianFormat.bytes(s.totalClips > 0 ? s.clipBytes / s.totalClips : 0)) per clip, qualità \(model.settings.quality.label.lowercased()).")
                    .font(.m3BodySmall)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
        }
    }

    private func legend(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.m3LabelMedium).foregroundStyle(m3.onSurfaceVariant)
                Text(value).font(.m3TitleSmall).monospacedDigit().foregroundStyle(m3.onSurface)
            }
        }
    }

    private func card<Content: View>(title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        M3Card(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.m3TitleMedium)
                        .foregroundStyle(m3.onSurface)
                    if let subtitle {
                        Text(subtitle)
                            .font(.m3BodySmall)
                            .foregroundStyle(m3.onSurfaceVariant)
                    }
                }
                content()
            }
        }
    }
}
