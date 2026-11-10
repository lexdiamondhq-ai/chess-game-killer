import SwiftUI

// The calendar of past Moves (Alex, 2026-11-10: "glassy, elegant"): a month on frosted glass over
// Today's Move. Under each day sits a small mark for how its Move went, and a tap shows that
// day's Move on a card, to play again for practice. A past Move never counts toward the streak.

/// How a day's Move stands on the calendar.
enum DailyCalendarMark: Equatable {
    /// Found on the first try: a gold coin.
    case found
    /// Solved with a hint or on the second look: a gold ring.
    case helped
    /// Not found: a small ember.
    case missed
    /// A day that came and went without its Move: a faint ring.
    case unplayed
    /// Today, not played yet.
    case today
    /// A day still to come, or one from before the first Move: nothing to show or play.
    case none

    init(_ outcome: Outcome) {
        switch outcome {
        case .firstTry: self = .found
        case .withHint, .afterMistake: self = .helped
        case .missed: self = .missed
        }
    }

    var spoken: String {
        switch self {
        case .found: return "found"
        case .helped: return "solved with help"
        case .missed: return "missed"
        case .unplayed: return "not played"
        case .today: return "today, not played yet"
        case .none: return "no Move"
        }
    }
}

/// One month of the calendar, laid out in weeks. Pure, so it can be tested without a screen.
struct DailyCalendarMonth: Equatable {
    struct Day: Equatable, Identifiable {
        let date: Date
        let number: Int
        let mark: DailyCalendarMark
        let isToday: Bool
        var id: Int { number }
        /// A day with a Move to show: any day from the first Move up to today.
        var hasMove: Bool { mark != .none }
    }

    /// The first day of the month.
    let start: Date
    /// Empty places before the 1st, so it falls under its weekday.
    let leading: Int
    let days: [Day]

    var found: Int { days.filter { $0.mark == .found }.count }
    var helped: Int { days.filter { $0.mark == .helped }.count }
    var missed: Int { days.filter { $0.mark == .missed }.count }

    /// The month holding `date`, marked from `results` (by day, "2026-11-09").
    init(holding date: Date, today: Date, results: [String: Outcome], calendar: Calendar = .current) {
        let first: Date = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let count: Int = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let epoch: Date = calendar.date(from: DailyMoves.epoch).map { calendar.startOfDay(for: $0) } ?? .distantPast
        let now: Date = calendar.startOfDay(for: today)
        start = first
        leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        days = (1...count).compactMap { number in
            guard let day = calendar.date(byAdding: .day, value: number - 1, to: first) else { return nil }
            let isToday: Bool = calendar.isDate(day, inSameDayAs: now)
            let mark: DailyCalendarMark
            if day < epoch || day > now {
                mark = .none
            } else if let outcome = results[DailyMoves.dayKey(day, calendar: calendar)] {
                mark = DailyCalendarMark(outcome)
            } else {
                mark = isToday ? .today : .unplayed
            }
            return Day(date: day, number: number, mark: mark, isToday: isToday)
        }
    }

    /// Whether there is a month of Moves before or after this one.
    func canStep(_ by: Int, today: Date, calendar: Calendar = .current) -> Bool {
        guard let other = calendar.date(byAdding: .month, value: by, to: start) else { return false }
        if by > 0 { return other <= today }
        guard let epoch = calendar.date(from: DailyMoves.epoch),
              let end = calendar.date(byAdding: .month, value: 1, to: other) else { return false }
        return end > epoch
    }
}

struct DailyCalendarView: View {
    let theme: BoardTheme
    let daily: DailyStore
    /// Plays the chosen day's Move: today's as today's, any other for practice.
    let play: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shown: Date = .now
    @State private var picked: Date?

    private var accent: Color { theme.trainingAccent }
    private static let ember = Color(hex: 0xB8644A)

    private var month: DailyCalendarMonth {
        DailyCalendarMonth(holding: shown, today: .now, results: daily.moveResults)
    }

    var body: some View {
        let month: DailyCalendarMonth = self.month
        ScrollView {
            VStack(spacing: 0) {
                title(month)
                tally(month)
                    .padding(.top, 12)
                weekdays
                    .padding(.top, 22)
                grid(month)
                    .padding(.top, 8)
                if let day = month.days.first(where: { isPicked($0) }), day.hasMove {
                    card(day)
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                Text("Past Moves never count toward the streak.")
                    .font(.app(.caption))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .animation(.snappy(duration: 0.28), value: picked)
        .animation(.snappy(duration: 0.28), value: shown)
        .presentationDetents([.fraction(0.84)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationBackground(.ultraThinMaterial)
        .tint(accent)
        .screenScheme(theme)
        .onAppear { if picked == nil { picked = Calendar.current.startOfDay(for: .now) } }
    }

    private func isPicked(_ day: DailyCalendarMonth.Day) -> Bool {
        guard let picked else { return false }
        return Calendar.current.isDate(day.date, inSameDayAs: picked)
    }

    // MARK: The month

    /// "‹ ——  NOVEMBER  —— ›", carved like the home's title.
    private func title(_ month: DailyCalendarMonth) -> some View {
        HStack(spacing: 12) {
            step(-1, month)
            hairline(leading: true)
            Text(month.start.formatted(.dateTime.month(.wide)).uppercased())
                .font(.custom(HomeCarvingFont.plain, size: 21))
                .tracking(5)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(month.start.formatted(.dateTime.month(.wide).year()))
            hairline(leading: false)
            step(1, month)
        }
    }

    private func hairline(leading: Bool) -> some View {
        LinearGradient(colors: [accent.opacity(0), accent.opacity(0.35)],
                       startPoint: leading ? .leading : .trailing, endPoint: leading ? .trailing : .leading)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private func step(_ by: Int, _ month: DailyCalendarMonth) -> some View {
        let open: Bool = month.canStep(by, today: .now)
        return Button {
            if let other = Calendar.current.date(byAdding: .month, value: by, to: month.start) {
                shown = other
                picked = nil
            }
        } label: {
            Image(systemName: by < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent.opacity(open ? 0.8 : 0.2))
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .accessibilityLabel(by < 0 ? "Month before" : "Month after")
    }

    /// "6 FOUND | 1 WITH HELP | 1 MISSED".
    private func tally(_ month: DailyCalendarMonth) -> some View {
        HStack(spacing: 12) {
            count(month.found, "found")
            divider
            count(month.helped, "with help")
            divider
            count(month.missed, "missed")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(month.found) found, \(month.helped) with help, \(month.missed) missed")
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.14)).frame(width: 1, height: 12)
    }

    private func count(_ value: Int, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text("\(value)")
                .font(.app(.footnote, weight: .semibold).monospacedDigit())
            Text(label.uppercased())
                .font(.app(.caption2))
                .tracking(1.4)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    private var weekdays: some View {
        let calendar = Calendar.current
        let names: [String] = calendar.shortStandaloneWeekdaySymbols
        let first: Int = calendar.firstWeekday - 1
        let ordered: [String] = Array(names[first...] + names[..<first])
        return HStack(spacing: 0) {
            ForEach(ordered, id: \.self) { name in
                Text(name.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func grid(_ month: DailyCalendarMonth) -> some View {
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<month.leading, id: \.self) { _ in Color.clear.frame(height: 46) }
            ForEach(month.days) { day in cell(day) }
        }
    }

    private func cell(_ day: DailyCalendarMonth.Day) -> some View {
        let chosen: Bool = isPicked(day) && day.hasMove
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            picked = day.date
        } label: {
            VStack(spacing: 5) {
                Text("\(day.number)")
                    .font(.app(.callout, weight: day.isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(numberStyle(day))
                mark(day.mark)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 40, height: 46)
            .background {
                if chosen {
                    shape.fill(Color.primary.opacity(0.09))
                        .overlay { shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75) }
                }
            }
            .overlay {
                if day.isToday { shape.strokeBorder(accent.opacity(0.6), lineWidth: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!day.hasMove)
        .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())), \(day.mark.spoken)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func numberStyle(_ day: DailyCalendarMonth.Day) -> AnyShapeStyle {
        if day.isToday { return AnyShapeStyle(accent) }
        switch day.mark {
        case .none: return AnyShapeStyle(Color.primary.opacity(0.22))
        case .missed, .unplayed: return AnyShapeStyle(Color.primary.opacity(0.62))
        default: return AnyShapeStyle(Color.primary)
        }
    }

    @ViewBuilder
    private func mark(_ mark: DailyCalendarMark) -> some View {
        switch mark {
        case .found:
            Circle().fill(accent).frame(width: 7, height: 7)
                .shadow(color: accent.opacity(0.55), radius: 4)
        case .helped:
            Circle().strokeBorder(accent, lineWidth: 1.5).frame(width: 7, height: 7)
        case .missed:
            Circle().fill(Self.ember.opacity(0.85)).frame(width: 5, height: 5)
        case .unplayed, .today:
            Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1).frame(width: 5, height: 5)
        case .none:
            Color.clear
        }
    }

    // MARK: The chosen day

    private func card(_ day: DailyCalendarMonth.Day) -> some View {
        let puzzle: DailyPuzzle? = daily.puzzle(on: day.date)
        return HStack(spacing: 14) {
            HomeAuroraBoard(fen: puzzle?.shownFEN, flipped: puzzle?.solverIsWhite == false, lit: false)
                .frame(width: 74, height: 74)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow(day, puzzle).uppercased())
                    .font(.custom(HomeCarvingFont.plain, size: 10))
                    .tracking(1.8)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(puzzle.map { String($0.headline.dropLast()) } ?? "Today's Move")
                    .font(.app(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(note(day))
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(button(day)) {
                dismiss()
                play(day.date)
            }
            .buttonStyle(TrainingButtonStyle(theme: theme))
            .fixedSize()
        }
        .padding(12)
        .glassPane(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func eyebrow(_ day: DailyCalendarMonth.Day, _ puzzle: DailyPuzzle?) -> String {
        let weekday: String = day.isToday ? "Today" : day.date.formatted(.dateTime.weekday(.wide))
        guard let puzzle else { return weekday }
        return "No. \(puzzle.number) · \(weekday)"
    }

    private func note(_ day: DailyCalendarMonth.Day) -> String {
        if day.isToday {
            switch day.mark {
            case .found: return "Found it. Next Move tomorrow."
            case .helped: return "Solved, with help. Next Move tomorrow."
            case .missed: return "Not this time. Next Move tomorrow."
            default: return "The same puzzle for everyone today."
            }
        }
        switch day.mark {
        case .found: return "Found it. Yours to play again, just for practice."
        case .helped: return "Solved, with help. Try it clean, just for practice."
        case .missed: return "Missed. Yours to try again, just for practice."
        default: return "Not played. Yours to try, just for practice."
        }
    }

    private func button(_ day: DailyCalendarMonth.Day) -> String {
        guard day.isToday else { return "Play" }
        return day.mark == .today ? "Solve" : "See it"
    }
}
