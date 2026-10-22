import SwiftData
import SwiftUI

struct CalendarScreen: View {
    @Environment(DayClock.self) private var clock
    @Query private var scheduleDays: [ScheduleDay]
    @Query private var overrides: [ScheduleOverride]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var finishedSessions: [WorkoutSession]

    @State private var displayedMonth: Date = .now
    @State private var selectedDay: Date?
    @Namespace private var selection

    private var schedule: ScheduleService { ScheduleService(days: scheduleDays, overrides: overrides) }
    private var completedKeys: Set<Int> { finishedSessions.completedDayKeys() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    statsCard
                    weekTemplateCard
                    monthCard
                    legend
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xxl)
            }
            .background(Color.appBackground)
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() }
            }
            .sheet(item: Binding(
                get: { selectedDay.map(IdentifiableDate.init) },
                set: { selectedDay = $0?.date }
            )) { day in
                DayDetailSheet(date: day.date)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var statsCard: some View {
        let done = schedule.completedDays(inWeekContaining: clock.now, completedDayKeys: completedKeys)
        let planned = schedule.plannedTrainingDays(inWeekContaining: clock.now)
        let streak = schedule.streak(completedDayKeys: completedKeys, today: clock.now)
        let next = schedule.nextTrainingDay(after: clock.now)
        return Card {
            HStack(spacing: Spacing.m) {
                StatTile(value: "\(streak)", label: "Day streak", symbol: "flame.fill", tint: Color("PushColor"))
                StatTile(value: "\(done)/\(planned)", label: "Workouts this week", symbol: "checkmark.seal.fill", tint: .brand)
                StatTile(
                    value: next.map { $0.date.formatted(.dateTime.weekday(.abbreviated)) + " · " + $0.split.titleString } ?? "—",
                    label: "Next training",
                    symbol: "arrow.forward.circle.fill",
                    tint: next?.split.color ?? .secondary
                )
            }
        }
    }

    private var weekTemplateCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                CardHeader(title: "This week", symbol: "calendar.badge.clock")
                HStack(spacing: Spacing.xs) {
                    ForEach(schedule.daysOfWeek(containing: clock.now)) { day in
                        let isToday = Calendar.current.isDate(day.date, inSameDayAs: clock.now)
                        let completed = completedKeys.contains(schedule.dayKey(for: day.date))
                        Button {
                            selectedDay = day.date
                        } label: {
                            VStack(spacing: Spacing.xs) {
                                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(isToday ? Color.primary : Color.secondary)
                                ZStack {
                                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                        .fill(day.split.color.opacity(isToday ? 0.35 : 0.16))
                                    Image(systemName: completed ? "checkmark" : day.split.symbol)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(day.split.color)
                                }
                                .frame(height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                        .strokeBorder(isToday ? day.split.color : .clear, lineWidth: 2)
                                )
                                Text(day.split.shortLabel)
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(day.split.color)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(day.date.formatted(.dateTime.weekday(.wide))): \(day.split.dayTitle)\(completed ? ", completed" : "")"))
                    }
                }
            }
        }
    }

    private var monthCard: some View {
        Card {
            VStack(spacing: Spacing.m) {
                HStack {
                    Button {
                        shiftMonth(-1)
                    } label: {
                        Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Previous month")
                    Spacer()
                    Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.headline)
                        .contentTransition(.numericText())
                    Spacer()
                    Button {
                        shiftMonth(1)
                    } label: {
                        Image(systemName: "chevron.right").font(.headline).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Next month")
                }

                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(WeeklyTemplate.mondayFirstWeekdays, id: \.self) { weekday in
                        Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(schedule.monthGrid(for: displayedMonth).enumerated()), id: \.offset) { _, date in
                        if let date {
                            MonthDayCell(
                                date: date,
                                split: schedule.plannedSplit(on: date),
                                isToday: Calendar.current.isDate(date, inSameDayAs: clock.now),
                                isCompleted: completedKeys.contains(schedule.dayKey(for: date)),
                                isPast: date < Calendar.current.startOfDay(for: clock.now),
                                namespace: selection
                            )
                            .onTapGesture { selectedDay = date }
                        } else {
                            Color.clear.frame(height: 46)
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 30).onEnded { value in
                        if value.translation.width < -40 { shiftMonth(1) }
                        if value.translation.width > 40 { shiftMonth(-1) }
                    }
                )
            }
        }
    }

    private var legend: some View {
        HStack(spacing: Spacing.l) {
            ForEach(SplitDay.allCases) { split in
                HStack(spacing: Spacing.xs) {
                    Circle().fill(split.color).frame(width: 10, height: 10)
                    Text(split.title).font(.caption.weight(.semibold))
                }
            }
            HStack(spacing: Spacing.xs) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.brand).font(.caption)
                Text("Done").font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func shiftMonth(_ value: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        withAnimation(.snappySpring) { displayedMonth = month }
        Haptics.selection()
    }
}

struct IdentifiableDate: Identifiable {
    var date: Date
    var id: Date { date }
}

struct MonthDayCell: View {
    var date: Date
    var split: SplitDay
    var isToday: Bool
    var isCompleted: Bool
    var isPast: Bool
    var namespace: Namespace.ID

    var body: some View {
        VStack(spacing: 3) {
            Text(date.formatted(.dateTime.day()))
                .font(.subheadline.weight(isToday ? .bold : .medium).monospacedDigit())
                .foregroundStyle(isPast && !isCompleted ? Color.secondary : Color.primary)
            ZStack {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(split.isTraining ? split.color : Color.brand)
                } else {
                    Circle()
                        .fill(split.color.opacity(isPast ? 0.35 : 1))
                        .frame(width: 7, height: 7)
                }
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(split.color.opacity(0.18))
                    .matchedGeometryEffect(id: "today", in: namespace)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(date.formatted(.dateTime.day().month(.wide))), \(split.dayTitle)\(isCompleted ? ", workout completed" : "")"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Day detail

struct DayDetailSheet: View {
    var date: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(DayClock.self) private var clock
    @Query private var scheduleDays: [ScheduleDay]
    @Query private var overrides: [ScheduleOverride]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt)
    private var finishedSessions: [WorkoutSession]
    @Query(sort: \Exercise.sortOrder) private var exercises: [Exercise]

    private var schedule: ScheduleService { ScheduleService(days: scheduleDays, overrides: overrides) }
    private var planned: PlannedDay { schedule.plannedDay(on: date) }
    private var sessions: [WorkoutSession] { finishedSessions.sessions(on: date) }
    private var isToday: Bool { Calendar.current.isDate(date, inSameDayAs: clock.now) }
    private var isFuture: Bool { date > clock.now }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    HStack {
                        SplitBadge(split: planned.split)
                        if planned.isOverride {
                            Chip(title: String(localized: "Changed from \(schedule.templateSplit(on: date).titleString)"), symbol: "arrow.left.arrow.right", tint: .secondary)
                        }
                    }

                    if !sessions.isEmpty {
                        SectionLabel("Completed")
                        ForEach(sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if planned.split.isTraining {
                        SectionLabel("Planned workout")
                        VStack(spacing: Spacing.s) {
                            ForEach(exercises.filter { $0.splitDay == planned.split }) { exercise in
                                HStack(spacing: Spacing.m) {
                                    MuscleAccent(group: exercise.muscleGroup, size: 30)
                                    Text(exercise.name).font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text("\(exercise.repRangeText) reps").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(Spacing.m)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    } else {
                        Text(isFuture || isToday ? "Rest day. Recovery is part of the program." : "Rest day.")
                            .foregroundStyle(.secondary)
                    }

                    if isToday && sessions.isEmpty {
                        Button {
                            dismiss()
                            WorkoutLauncher.start(planned.split.isTraining ? planned.split : .push, context: modelContext, router: router)
                        } label: {
                            Label(planned.split.isTraining ? "Start \(planned.split.titleString) workout" : "Train anyway", systemImage: "play.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: planned.split.isTraining ? planned.split.color : .brand))
                    }

                    if isToday || isFuture {
                        SectionLabel("Change this day")
                        HStack(spacing: Spacing.s) {
                            ForEach(SplitDay.allCases) { split in
                                Button {
                                    ScheduleEditor.setSplit(split, on: date, context: modelContext)
                                    Haptics.selection()
                                } label: {
                                    Text(split.title)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(split == planned.split
                                             ? AnyButtonStyle(PrimaryButtonStyle(tint: split.color, compact: true))
                                             : AnyButtonStyle(SecondaryButtonStyle(tint: split.color, compact: true)))
                            }
                        }
                        if let swapTarget = swapCandidate {
                            Button {
                                ScheduleEditor.swap(date, swapTarget.date, context: modelContext)
                                Haptics.success()
                            } label: {
                                Label("Swap with \(swapTarget.date.formatted(.dateTime.weekday(.wide))) (\(swapTarget.split.titleString))", systemImage: "arrow.left.arrow.right")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(SecondaryButtonStyle(tint: swapTarget.split.color))
                        }
                        if planned.isOverride {
                            Button("Reset to weekly plan") {
                                ScheduleEditor.resetOverride(on: date, context: modelContext)
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        Text("Changes affect this date only — your weekly template stays the same.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Spacing.l)
            }
            .background(Color.appBackground)
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The next day with a different split, for a one-tap swap ("do tomorrow's Pull today").
    private var swapCandidate: PlannedDay? {
        schedule.upcoming(after: date, count: 6).first { $0.split != planned.split }
    }
}
