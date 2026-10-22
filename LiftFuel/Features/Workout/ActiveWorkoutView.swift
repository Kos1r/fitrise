import SwiftData
import SwiftUI

struct ActiveWorkoutView: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var modelContext
    @Environment(RestTimerManager.self) private var restTimer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [UserProfile]

    @State private var focusedField: SetField?
    @State private var buffer = KeypadBuffer(value: 0, allowsDecimal: true)
    @State private var prToast: PRToast?
    @State private var showFinishConfirm = false
    @State private var showDiscardConfirm = false
    @State private var finishedSummary: WorkoutSummary?

    private var increment: Double { profiles.first?.weightIncrement ?? 2.5 }

    var body: some View {
        List {
            ForEach(session.orderedLogs) { log in
                ExerciseSetsSection(
                    log: log,
                    session: session,
                    isLive: true,
                    increment: increment,
                    focusedField: focusedField,
                    onFocus: focus,
                    onCompleted: handleCompletion
                )
            }
            Section {
                Button(role: .destructive) {
                    showDiscardConfirm = true
                } label: {
                    Label("Discard workout", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .listSectionSpacing(Spacing.l)
        .safeAreaInset(edge: .top, spacing: 0) {
            WorkoutStatsBar(session: session)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomPanel
        }
        .navigationTitle(session.splitDay.dayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") { requestFinish() }
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .tint(.brand)
                    .foregroundStyle(.black.opacity(0.85))
                    .accessibilityIdentifier("workout.finish")
            }
        }
        .overlay(alignment: .top) {
            if let prToast {
                PRToastView(toast: prToast)
                    .padding(.top, 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .confirmationDialog("Finish workout?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Finish workout") { finish() }
                .accessibilityIdentifier("workout.finishConfirm")
            Button("Keep training", role: .cancel) {}
        } message: {
            Text("Sets you haven't checked off will be removed.")
        }
        .confirmationDialog("Discard this workout?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) {
                restTimer.skip()
                WorkoutService.discard(session, in: modelContext)
            }
        } message: {
            Text("Nothing from this session will be saved.")
        }
        .sheet(item: $finishedSummary) { summary in
            WorkoutSummarySheet(summary: summary)
        }
        .onChange(of: buffer) { _, newValue in
            write(buffer: newValue)
        }
    }

    // MARK: Bottom panel (keypad / rest timer)

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: Spacing.s) {
            if restTimer.isRunning, focusedField == nil {
                RestTimerBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let focusedField {
                NumberKeypad(
                    title: focusedField.isWeight ? "Weight" : "Reps",
                    unit: focusedField.isWeight ? "kg" : "reps",
                    buffer: $buffer,
                    step: focusedField.isWeight ? increment : 1,
                    onNext: advanceFocus,
                    onDone: { withAnimation(.snappySpring) { self.focusedField = nil } }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .padding(.bottom, Spacing.s)
        .animation(reduceMotion ? nil : .snappySpring, value: focusedField)
        .animation(reduceMotion ? nil : .snappySpring, value: restTimer.isRunning)
    }

    // MARK: Focus & editing

    private func set(for id: UUID) -> SetEntry? {
        for log in session.orderedLogs {
            if let set = log.orderedSets.first(where: { $0.id == id }) { return set }
        }
        return nil
    }

    private func focus(_ field: SetField) {
        guard let set = set(for: field.setID) else { return }
        buffer = KeypadBuffer(value: field.isWeight ? set.weight : Double(set.reps), allowsDecimal: field.isWeight)
        withAnimation(.snappySpring) { focusedField = field }
        Haptics.selection()
    }

    private func write(buffer: KeypadBuffer) {
        guard let field = focusedField, let set = set(for: field.setID) else { return }
        if field.isWeight {
            set.weight = buffer.value
        } else {
            set.reps = Int(buffer.value)
        }
    }

    /// weight → reps of the same set → weight of the next set.
    private func advanceFocus() {
        guard let field = focusedField else { return }
        modelContext.saveQuietly()
        if field.isWeight {
            focus(.reps(field.setID))
            return
        }
        let allSets = session.orderedLogs.flatMap(\.orderedSets)
        if let index = allSets.firstIndex(where: { $0.id == field.setID }), allSets.indices.contains(index + 1) {
            focus(.weight(allSets[index + 1].id))
        } else {
            withAnimation(.snappySpring) { focusedField = nil }
        }
    }

    // MARK: Completion

    private func handleCompletion(_ set: SetEntry, _ pr: StrengthMath.PRKind?) {
        if focusedField?.setID == set.id {
            withAnimation(.snappySpring) { focusedField = nil }
        }
        guard set.isCompleted, let log = set.log, let exercise = log.exercise else { return }
        let next = log.orderedSets.first { !$0.isCompleted }
        let nextText = next.map { "\(StrengthMath.formatWeight($0.weight)) kg × \($0.reps)" } ?? String(localized: "Next exercise")
        restTimer.start(seconds: exercise.restSeconds, exerciseName: exercise.name, nextSet: nextText)

        if let pr {
            Haptics.success()
            let toast = PRToast(title: pr.title, detail: "\(exercise.name) · \(StrengthMath.formatWeight(set.weight)) kg × \(set.reps)")
            withAnimation(reduceMotion ? nil : .gentleSpring) { prToast = toast }
            Task {
                try? await Task.sleep(for: .seconds(2.6))
                withAnimation(reduceMotion ? nil : .gentleSpring) {
                    if prToast?.id == toast.id { prToast = nil }
                }
            }
        }
    }

    private func requestFinish() {
        focusedField = nil
        let hasIncomplete = session.orderedLogs.contains { log in log.orderedSets.contains { !$0.isCompleted } }
        if hasIncomplete {
            showFinishConfirm = true
        } else {
            finish()
        }
    }

    private func finish() {
        restTimer.skip()
        let summary = WorkoutSummary(session: session)
        WorkoutService.finish(session, in: modelContext)
        if profiles.first?.healthKitEnabled == true {
            let start = session.startedAt
            let end = session.endedAt ?? .now
            let volume = session.totalVolume
            Task {
                if await HealthKitService.shared.saveWorkout(start: start, end: end, totalVolumeKg: volume) {
                    session.savedToHealth = true
                    modelContext.saveQuietly()
                }
            }
        }
        WidgetSyncService.update(context: modelContext)
        Haptics.success()
        finishedSummary = summary
    }
}

// MARK: - Exercise section

struct ExerciseSetsSection: View {
    let log: ExerciseLog
    let session: WorkoutSession
    var isLive: Bool
    var increment: Double
    var focusedField: SetField?
    var onFocus: (SetField) -> Void
    var onCompleted: (SetEntry, StrengthMath.PRKind?) -> Void

    @Environment(\.modelContext) private var modelContext

    private var exercise: Exercise? { log.exercise }
    private var previousSets: [SetEntry] {
        guard let exercise else { return [] }
        return WorkoutService.lastCompletedLog(for: exercise, excluding: session)?.completedSets ?? []
    }

    var body: some View {
        Section {
            header
                .listRowSeparator(.hidden)
            SetColumnsHeader()
                .listRowSeparator(.hidden)
            let previous = previousSets
            ForEach(Array(log.orderedSets.enumerated()), id: \.element.id) { index, set in
                SetRowView(
                    set: set,
                    displayNumber: workingNumber(for: index),
                    previous: previous.indices.contains(index) ? previous[index] : nil,
                    focusedField: focusedField,
                    onFocus: onFocus,
                    onToggleComplete: { toggle(set) },
                    onChangeType: { type in
                        set.setType = type
                        modelContext.saveQuietly()
                    },
                    onDelete: { delete(set) }
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.m, bottom: 0, trailing: Spacing.m))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { delete(set) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Button {
                withAnimation(.snappySpring) {
                    _ = WorkoutService.addSet(to: log, in: modelContext)
                }
                Haptics.impact(.light)
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("workout.addSet")
        }
        .listRowBackground(Color.cardBackground)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            if let exercise {
                MuscleAccent(group: exercise.muscleGroup)
            }
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let exercise {
                    NavigationLink(value: WorkoutRoute.exercise(exercise.persistentModelID)) {
                        Text(exercise.name).font(.headline)
                    }
                    Text("\(exercise.muscleGroup.title) · \(exercise.equipment.title) · \(exercise.repRangeText) reps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let notes = exercise.notes {
                        Text(notes).font(.caption).foregroundStyle(exercise.muscleGroup.color)
                    }
                    if isLive {
                        hints(for: exercise)
                    }
                } else {
                    Text("Exercise").font(.headline)
                }
            }
        }
        .padding(.top, Spacing.xs)
    }

    @ViewBuilder
    private func hints(for exercise: Exercise) -> some View {
        if let last = previousSets.first {
            Text("Last time: \(StrengthMath.formatWeight(last.weight)) kg × \(last.reps)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        if let suggestion = WorkoutService.overloadHint(for: exercise, excluding: session, increment: increment) {
            Label("Try \(Format.kg(suggestion)) today", systemImage: "arrow.up.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.brand)
        } else if WorkoutService.isPlateaued(exercise) {
            Label("Stalled 4 sessions — consider a deload or new rep range", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("ShouldersColor"))
        }
    }

    /// Warm-ups show "W"; working sets are numbered 1, 2, 3… skipping warm-ups.
    private func workingNumber(for index: Int) -> Int {
        log.orderedSets.prefix(index + 1).filter { $0.setType != .warmup }.count
    }

    private func toggle(_ set: SetEntry) {
        let pr = WorkoutService.toggleCompletion(of: set, in: modelContext)
        onCompleted(set, pr)
    }

    private func delete(_ set: SetEntry) {
        withAnimation(.snappySpring) {
            WorkoutService.delete(set, in: modelContext)
        }
    }
}

// MARK: - Stats bar

struct WorkoutStatsBar: View {
    let session: WorkoutSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: Spacing.m) {
                StatTile(value: Format.duration(session.duration), label: "Elapsed", symbol: "timer", tint: session.splitDay.color)
                StatTile(value: Format.volume(session.totalVolume), label: "Volume", symbol: "scalemass.fill", tint: .brand)
                StatTile(value: "\(session.completedSetCount)/\(session.totalSetCount)", label: "Sets", symbol: "checkmark.circle.fill", tint: .brand)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .background(.bar)
        }
    }
}

// MARK: - PR toast

struct PRToast: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var detail: String
}

struct PRToastView: View {
    var toast: PRToast

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "trophy.fill")
                .font(.title2)
                .foregroundStyle(Color("ShouldersColor"))
                .symbolEffect(.bounce, value: toast.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.headline)
                Text(toast.detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
        .background(.thickMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
