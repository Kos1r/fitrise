import Charts
import SwiftData
import SwiftUI

/// Pure body-weight math (unit-tested).
enum BodyWeightMath {
    /// Trailing 7-day moving average for each entry (entries sorted by date).
    static func movingAverage(_ entries: [(date: Date, kg: Double)], days: Int = 7) -> [(date: Date, kg: Double)] {
        entries.map { entry in
            let windowStart = entry.date.addingTimeInterval(-Double(days) * 86_400)
            let window = entries.filter { $0.date > windowStart && $0.date <= entry.date }
            let average = window.map(\.kg).reduce(0, +) / Double(max(1, window.count))
            return (entry.date, average)
        }
    }

    /// Change per week of the moving average over the last ~3 weeks, if enough data.
    static func weeklyChange(_ entries: [(date: Date, kg: Double)]) -> Double? {
        let averaged = movingAverage(entries)
        guard let last = averaged.last else { return nil }
        let threeWeeksAgo = last.date.addingTimeInterval(-21 * 86_400)
        guard let first = averaged.first(where: { $0.date >= threeWeeksAgo }),
              last.date.timeIntervalSince(first.date) >= 6 * 86_400 else { return nil }
        let weeks = last.date.timeIntervalSince(first.date) / (7 * 86_400)
        return (last.kg - first.kg) / weeks
    }
}

struct BodyWeightView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BodyWeightEntry.date) private var entries: [BodyWeightEntry]
    @Query private var profiles: [UserProfile]
    @State private var newWeight: Double = 75
    @State private var newDate: Date = .now
    @State private var range: ChartRange = .quarter

    private var series: [(date: Date, kg: Double)] { entries.map { ($0.date, $0.weightKg) } }

    private struct ChartPoint: Identifiable {
        var date: Date
        var kg: Double
        var series: String
        var id: String { "\(series)-\(date.timeIntervalSince1970)" }
    }

    private var chartPoints: [ChartPoint] {
        let start = range.startDate(from: .now)
        let raw = series.filter { start == nil || $0.date >= (start ?? .distantPast) }
        let averaged = BodyWeightMath.movingAverage(series).filter { start == nil || $0.date >= (start ?? .distantPast) }
        return raw.map { ChartPoint(date: $0.date, kg: $0.kg, series: "Weigh-in") }
            + averaged.map { ChartPoint(date: $0.date, kg: $0.kg, series: "7-day average") }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entries.last.map { Format.kg($0.weightKg) } ?? "—").font(.statHero)
                        if let change = BodyWeightMath.weeklyChange(series) {
                            Text("\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(2)))) kg/wk")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Picker("Range", selection: $range) {
                        ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if chartPoints.count >= 2 {
                        Chart(chartPoints) { point in
                            LineMark(x: .value("Date", point.date), y: .value("kg", point.kg))
                                .foregroundStyle(by: .value("Series", point.series))
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: point.series == "Weigh-in" ? 1 : 3))
                                .opacity(point.series == "Weigh-in" ? 0.45 : 1)
                        }
                        .chartForegroundStyleScale(["Weigh-in": Color.secondary, "7-day average": Color("BicepsColor")])
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 200)
                    } else {
                        Text("Log a few weigh-ins to see your trend. Weigh yourself in the morning for consistency.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(goalHint).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, Spacing.s)
            }
            .listRowBackground(Color.cardBackground)

            Section("Log weight") {
                Stepper(value: $newWeight, in: 30...250, step: 0.1) {
                    Text(Format.kg((newWeight * 10).rounded() / 10)).font(.title3.weight(.semibold).monospacedDigit())
                }
                DatePicker("Date", selection: $newDate, in: ...Date.now)
                Button {
                    add()
                } label: {
                    Label("Save weigh-in", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("bodyWeight.save")
            }
            .listRowBackground(Color.cardBackground)

            if !entries.isEmpty {
                Section("History") {
                    ForEach(entries.reversed()) { entry in
                        HStack {
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text(Format.kg(entry.weightKg)).monospacedDigit()
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                modelContext.delete(entry)
                                modelContext.saveQuietly()
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .listRowBackground(Color.cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
        .navigationTitle("Body weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .onAppear {
            newWeight = entries.last?.weightKg ?? profiles.first?.weightKg ?? 75
        }
    }

    private var goalHint: String {
        switch profiles.first?.goal ?? .leanBulk {
        case .leanBulk: String(localized: "Lean bulk sweet spot: about +0.1 to +0.3 kg per week.")
        case .maintain: String(localized: "Maintenance: the 7-day average should stay within ±0.2 kg per week.")
        case .cut: String(localized: "Cut: aim for about −0.3 to −0.7 kg per week to keep muscle.")
        }
    }

    private func add() {
        let kg = (newWeight * 10).rounded() / 10
        modelContext.insert(BodyWeightEntry(date: newDate, weightKg: kg))
        // The latest weigh-in drives the automatic nutrition targets.
        if let profile = profiles.first, newDate >= (entries.last?.date ?? .distantPast) {
            profile.weightKg = kg
            if profile.healthKitEnabled {
                Task { _ = await HealthKitService.shared.saveBodyWeight(kg, date: newDate) }
            }
        }
        modelContext.saveQuietly()
        WidgetSyncService.update(context: modelContext)
        Haptics.success()
    }
}
