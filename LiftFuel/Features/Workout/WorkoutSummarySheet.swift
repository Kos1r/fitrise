import SwiftUI

/// Value snapshot of a finished session for the summary sheet.
struct WorkoutSummary: Identifiable {
    struct Row: Identifiable {
        var id: String
        var name: String
        var group: MuscleGroup
        var sets: Int
        var best: String
        var hasPR: Bool
    }

    let id = UUID()
    var split: SplitDay
    var duration: TimeInterval
    var volume: Double
    var sets: Int
    var prs: Int
    var rows: [Row]

    @MainActor
    init(session: WorkoutSession) {
        split = session.splitDay
        duration = session.duration
        volume = session.totalVolume
        sets = session.completedSetCount
        prs = session.prCount
        rows = session.orderedLogs.compactMap { log in
            guard let exercise = log.exercise, !log.completedSets.isEmpty else { return nil }
            let top = log.topSet
            return Row(
                id: exercise.stableID,
                name: exercise.name,
                group: exercise.muscleGroup,
                sets: log.completedWorkingSets.count,
                best: top.map { "\(StrengthMath.formatWeight($0.weight)) kg × \($0.reps)" } ?? "—",
                hasPR: log.completedSets.contains(where: \.isPR)
            )
        }
    }
}

struct WorkoutSummarySheet: View {
    var summary: WorkoutSummary
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    VStack(spacing: Spacing.s) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(summary.split.color)
                            .scaleEffect(appeared ? 1 : 0.4)
                            .opacity(appeared ? 1 : 0)
                        Text("Workout complete").font(.title.weight(.bold))
                        Text(summary.split.dayTitle).font(.headline).foregroundStyle(.secondary)
                    }
                    .padding(.top, Spacing.xl)

                    Card {
                        HStack {
                            StatTile(value: Format.shortDuration(summary.duration), label: "Duration", symbol: "timer", tint: summary.split.color)
                            StatTile(value: Format.volume(summary.volume), label: "Volume", symbol: "scalemass.fill", tint: .brand)
                            StatTile(value: "\(summary.sets)", label: "Sets", symbol: "checkmark.circle.fill", tint: .brand)
                            StatTile(value: "\(summary.prs)", label: "PRs", symbol: "trophy.fill", tint: Color("ShouldersColor"))
                        }
                    }

                    VStack(spacing: Spacing.s) {
                        ForEach(summary.rows) { row in
                            HStack(spacing: Spacing.m) {
                                MuscleAccent(group: row.group, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name).font(.subheadline.weight(.semibold))
                                    Text("\(row.sets) sets · best \(row.best)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if row.hasPR { PRBadge() }
                            }
                            .padding(Spacing.m)
                            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, Spacing.l)
            }
            .background(Color.appBackground)
            .safeAreaInset(edge: .bottom) {
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(Spacing.l)
                    .accessibilityIdentifier("summary.done")
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
