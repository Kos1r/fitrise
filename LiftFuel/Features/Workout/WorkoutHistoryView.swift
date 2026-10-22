import SwiftData
import SwiftUI

struct WorkoutHistoryView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Environment(\.modelContext) private var modelContext

    private struct MonthGroup: Identifiable {
        var month: Date
        var sessions: [WorkoutSession]
        var id: Date { month }
    }

    private var grouped: [MonthGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: sessions) { calendar.dateInterval(of: .month, for: $0.startedAt)?.start ?? $0.startedAt }
        return groups.keys.sorted(by: >).map { MonthGroup(month: $0, sessions: groups[$0] ?? []) }
    }

    var body: some View {
        List {
            if sessions.isEmpty {
                EmptyStateView(symbol: "clock.arrow.circlepath", title: "No workouts yet", message: "Finish a workout and it will be listed here.")
                    .listRowBackground(Color.clear)
            }
            ForEach(grouped) { group in
                Section {
                    ForEach(group.sessions) { session in
                        NavigationLink(value: WorkoutRoute.session(session.persistentModelID)) {
                            SessionRow(session: session)
                        }
                        .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.l, bottom: Spacing.xs, trailing: Spacing.l))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions {
                            Button(role: .destructive) {
                                modelContext.delete(session)
                                modelContext.saveQuietly()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(group.month.formatted(.dateTime.month(.wide).year()))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("History")
    }
}

/// A finished session: view and edit sets (no rest timer).
struct SessionDetailView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var focusedField: SetField?
    @State private var buffer = KeypadBuffer(value: 0, allowsDecimal: true)
    @State private var isEditing = false
    @State private var showDelete = false

    var body: some View {
        List {
            Section {
                HStack {
                    StatTile(value: Format.shortDuration(session.duration), label: "Duration", symbol: "timer", tint: session.splitDay.color)
                    StatTile(value: Format.volume(session.totalVolume), label: "Volume", symbol: "scalemass.fill", tint: .brand)
                    StatTile(value: "\(session.completedSetCount)", label: "Sets", symbol: "checkmark.circle.fill", tint: .brand)
                    StatTile(value: "\(session.prCount)", label: "PRs", symbol: "trophy.fill", tint: Color("ShouldersColor"))
                }
                if isEditing {
                    DatePicker("Started", selection: $session.startedAt)
                }
            }
            .listRowBackground(Color.cardBackground)

            if isEditing {
                ForEach(session.orderedLogs) { log in
                    ExerciseSetsSection(
                        log: log,
                        session: session,
                        isLive: false,
                        increment: 2.5,
                        focusedField: focusedField,
                        onFocus: focus,
                        onCompleted: { _, _ in }
                    )
                }
            } else {
                ForEach(session.orderedLogs) { log in
                    Section {
                        HStack(spacing: Spacing.m) {
                            if let exercise = log.exercise { MuscleAccent(group: exercise.muscleGroup, size: 32) }
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(log.exercise?.name ?? "Exercise").font(.headline)
                                FlowSetsView(sets: log.completedSets)
                            }
                        }
                    }
                    .listRowBackground(Color.cardBackground)
                }
            }

            Section {
                Button("Delete workout", role: .destructive) { showDelete = true }
                    .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.cardBackground)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month()))
        .toolbar {
            Button(isEditing ? "Done" : "Edit") {
                if isEditing { modelContext.saveQuietly() }
                focusedField = nil
                withAnimation { isEditing.toggle() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let focusedField {
                NumberKeypad(
                    title: focusedField.isWeight ? "Weight" : "Reps",
                    unit: focusedField.isWeight ? "kg" : "reps",
                    buffer: $buffer,
                    step: focusedField.isWeight ? 2.5 : 1,
                    onNext: { self.focusedField = nil },
                    onDone: { self.focusedField = nil }
                )
            }
        }
        .onChange(of: buffer) { _, newValue in
            guard let field = focusedField,
                  let set = session.orderedLogs.flatMap(\.orderedSets).first(where: { $0.id == field.setID }) else { return }
            if field.isWeight { set.weight = newValue.value } else { set.reps = Int(newValue.value) }
        }
        .confirmationDialog("Delete this workout?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(session)
                modelContext.saveQuietly()
                dismiss()
            }
        }
    }

    private func focus(_ field: SetField) {
        guard let set = session.orderedLogs.flatMap(\.orderedSets).first(where: { $0.id == field.setID }) else { return }
        buffer = KeypadBuffer(value: field.isWeight ? set.weight : Double(set.reps), allowsDecimal: field.isWeight)
        focusedField = field
    }
}
