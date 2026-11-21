import SwiftUI
import SonoroCore

/// Month calendar: each day colored by how many clips it has.
struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3

    var body: some View {
        @Bindable var model = model
        let month = model.calendarMonth
        let counts = DayGrouping.counts(model.data.clips)
        let grid = MonthGrid(month: month, counts: counts, soundtracks: Set(model.data.soundtracks.map(\.day)), today: model.today)
        let monthClips = model.data.clips.filter { month.contains($0.day) }
        let days = DayGrouping.group(monthClips)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                monthHeader(month)
                MonthGridView(grid: grid) { d in model.calendarPath.append(.day(d)) }
                    .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                        if v.translation.width < -40 { go(1) } else if v.translation.width > 40 { go(-1) }
                    })
                summary(grid: grid, clips: monthClips)
                if days.isEmpty {
                    Text(month == MonthRef(model.today) ? "Nessuna clip questo mese, per ora." : "Nessuna clip in questo mese.")
                        .font(.m3BodyMedium)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    SectionTitle("Giorni", trailing: ItalianFormat.days(days.count))
                    VStack(spacing: 10) {
                        ForEach(days) { d in
                            Button {
                                model.calendarPath.append(.day(d.day))
                            } label: {
                                DayRow(summary: d)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(m3.surface)
        .navigationTitle("Calendario")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.calendarPath.append(.anniversary)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Un anno fa oggi")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.calendarPath.append(.search)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Cerca")
            }
        }
    }

    private func go(_ delta: Int) {
        let target = model.calendarMonth.adding(months: delta)
        guard target <= MonthRef(model.today) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { model.calendarMonth = target }
    }

    private func monthHeader(_ month: MonthRef) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(ItalianFormat.capitalized(ItalianFormat.monthName(month.month)))
                    .font(.m3HeadlineLarge)
                    .foregroundStyle(m3.onSurface)
                Text(String(month.year))
                    .font(.m3TitleMedium)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            Spacer()
            HStack(spacing: 8) {
                circleButton("chevron.left") { go(-1) }
                if month != MonthRef(model.today) {
                    Button("Oggi") {
                        withAnimation { model.calendarMonth = MonthRef(model.today) }
                    }
                    .font(.m3LabelLarge)
                }
                circleButton("chevron.right") { go(1) }
                    .disabled(month >= MonthRef(model.today))
                    .opacity(month >= MonthRef(model.today) ? 0.35 : 1)
            }
        }
        .padding(.top, 4)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(m3.onSurface)
                .frame(width: 40, height: 40)
                .background(m3.surfaceContainerHigh, in: Circle())
        }
        .buttonStyle(PressableStyle())
    }

    private func summary(grid: MonthGrid, clips: [Clip]) -> some View {
        HStack(alignment: .top) {
            BigNumber(value: "\(grid.recordedDays)", label: grid.recordedDays == 1 ? "giorno" : "giorni")
            Spacer()
            BigNumber(value: "\(grid.clipCount)", label: "clip")
            Spacer()
            BigNumber(value: ItalianFormat.decimal(clips.reduce(0) { $0 + $1.duration } / 60, digits: 1), label: "minuti")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

struct MonthGridView: View {
    @Environment(\.m3) private var m3
    let grid: MonthGrid
    let onSelect: (DayDate) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(MonthGrid.weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.m3LabelMedium)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(grid.cells) { cell in
                    CalendarCellView(cell: cell)
                        .onTapGesture {
                            if let d = cell.day, cell.count > 0 { onSelect(d) }
                        }
                }
            }
        }
    }
}

struct CalendarCellView: View {
    @Environment(\.m3) private var m3
    let cell: CalendarCell

    var body: some View {
        ZStack {
            if let d = cell.day {
                Circle()
                    .fill(m3.intensity(cell.level))
                if cell.isToday {
                    Circle().strokeBorder(m3.primary, lineWidth: 2)
                }
                VStack(spacing: 1) {
                    Text("\(d.day)")
                        .font(.system(size: 16, weight: cell.count > 0 || cell.isToday ? .semibold : .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(cell.isFuture ? m3.outlineVariant : (cell.count > 0 ? m3.onIntensity(cell.level) : m3.onSurfaceVariant))
                    Circle()
                        .fill(cell.hasSoundtrack ? m3.onIntensity(cell.level).opacity(0.7) : .clear)
                        .frame(width: 4, height: 4)
                }
                .offset(y: 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
        .accessibilityElement()
        .accessibilityLabel(cell.day.map { "\(ItalianFormat.dayTitle($0)), \(ItalianFormat.clips(cell.count))" } ?? "")
    }
}

/// One recorded day in a list: date, count, places, waveform.
struct DayRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let summary: DaySummary

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text("\(summary.day.day)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(m3.onSurface)
                Text(ItalianFormat.shortWeekdays[summary.day.weekdayFromMonday])
                    .font(.m3LabelSmall)
                    .foregroundStyle(m3.onSurfaceVariant)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(ItalianFormat.clips(summary.count))
                        .font(.m3TitleSmall)
                        .foregroundStyle(m3.onSurface)
                    Text("· \(ItalianFormat.duration(summary.totalDuration))")
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                    Spacer(minLength: 0)
                    Text(summary.emojis.prefix(3).joined())
                        .font(.system(size: 13))
                }
                WaveformView(samples: dayWaveform, color: m3.primary.opacity(0.55), barCount: 36)
                    .frame(height: 18)
                if !summary.places.isEmpty {
                    Text(summary.places.prefix(3).joined(separator: " · "))
                        .font(.m3BodySmall)
                        .foregroundStyle(m3.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(m3.outline)
        }
        .padding(14)
        .background(m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var dayWaveform: [UInt8] {
        if let s = model.data.soundtrack(for: summary.day), !s.waveform.isEmpty { return s.waveform }
        return Waveform.quantize(Waveform.concat(summary.clips.map { (Waveform.dequantize($0.waveform), $0.duration) }, bins: 48))
    }
}
