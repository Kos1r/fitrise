import Charts
import SwiftData
import SwiftUI

struct NutritionView: View {
    @Environment(DayClock.self) private var clock
    @State private var selectedDay: Date = .now
    @State private var editorTarget: MealEditorTarget?
    @State private var showPresets = false

    private var isToday: Bool { Calendar.current.isDate(selectedDay, inSameDayAs: clock.now) }

    var body: some View {
        NavigationStack {
            NutritionDayContent(
                day: selectedDay,
                isToday: isToday,
                onAddMeal: { editorTarget = .new(day: selectedDay) },
                onEditMeal: { editorTarget = .edit($0.persistentModelID) },
                onShowPresets: { showPresets = true }
            )
            .background(Color.appBackground)
            .navigationTitle("Nutrition")
            .toolbar {
                ToolbarItem(placement: .principal) { dayNavigator }
                ToolbarItem(placement: .topBarTrailing) { ProfileToolbarButton() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editorTarget) { target in
                MealEditorView(target: target)
            }
            .sheet(isPresented: $showPresets) {
                PresetsSheet(day: selectedDay)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: clock.today) { oldValue, newValue in
                // Midnight rollover: follow "today" if the user was looking at today.
                if Calendar.current.isDate(selectedDay, inSameDayAs: oldValue) { selectedDay = newValue }
            }
        }
    }

    private var dayNavigator: some View {
        HStack(spacing: Spacing.s) {
            Button { shiftDay(-1) } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.bold)).frame(width: 36, height: 36)
            }
            .accessibilityLabel("Previous day")
            Button {
                selectedDay = clock.now
            } label: {
                Text(isToday ? String(localized: "Today") : selectedDay.formatted(.dateTime.weekday(.abbreviated).day().month()))
                    .font(.headline)
                    .frame(minWidth: 110)
            }
            .foregroundStyle(.primary)
            Button { shiftDay(1) } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.bold)).frame(width: 36, height: 36)
            }
            .disabled(isToday)
            .accessibilityLabel("Next day")
        }
    }

    private func shiftDay(_ value: Int) {
        guard let day = Calendar.current.date(byAdding: .day, value: value, to: selectedDay), day <= clock.now else { return }
        withAnimation(.snappySpring) { selectedDay = day }
        Haptics.selection()
    }
}

enum MealEditorTarget: Identifiable {
    case new(day: Date)
    case edit(PersistentIdentifier)

    var id: String {
        switch self {
        case .new(let day): "new-\(day.timeIntervalSince1970)"
        case .edit(let id): "edit-\(id.hashValue)"
        }
    }
}

/// Everything for one day; @Query is rebuilt when the day changes.
struct NutritionDayContent: View {
    var day: Date
    var isToday: Bool
    var onAddMeal: () -> Void
    var onEditMeal: (MealEntry) -> Void
    var onShowPresets: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var meals: [MealEntry]
    @Query private var water: [WaterEntry]
    @Query private var profiles: [UserProfile]
    @Query private var targetRows: [NutritionTargets]
    @State private var copiedCount: Int?

    init(day: Date, isToday: Bool, onAddMeal: @escaping () -> Void, onEditMeal: @escaping (MealEntry) -> Void, onShowPresets: @escaping () -> Void) {
        self.day = day
        self.isToday = isToday
        self.onAddMeal = onAddMeal
        self.onEditMeal = onEditMeal
        self.onShowPresets = onShowPresets
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start && $0.date < end }, sort: \MealEntry.date)
        _water = Query(filter: #Predicate<WaterEntry> { $0.date >= start && $0.date < end })
    }

    private var targets: NutritionCalculator.Targets {
        NutritionCalculator.targets(for: (profiles.first ?? UserProfile()).nutritionInput, overrides: targetRows.first?.overrides ?? .none)
    }
    private var eaten: MacroTotals { meals.reduce(.zero) { $0 + $1.totals } }
    private var waterTotal: Double { water.reduce(0) { $0 + $1.milliliters } }

    var body: some View {
        List {
            Section {
                summaryCard
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                quickActions
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            ForEach(MealType.allCases) { type in
                let typed = meals.filter { $0.mealType == type }
                if !typed.isEmpty {
                    Section {
                        ForEach(typed) { meal in
                            MealRow(meal: meal)
                                .contentShape(Rectangle())
                                .onTapGesture { onEditMeal(meal) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation { NutritionService.delete(meal, in: modelContext) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                    Button { onEditMeal(meal) } label: { Label("Edit", systemImage: "pencil") }
                                        .tint(.blue)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        NutritionService.savePreset(from: meal, in: modelContext)
                                        Haptics.success()
                                    } label: { Label("Save preset", systemImage: "star.fill") }
                                        .tint(Color("ShouldersColor"))
                                }
                        }
                    } header: {
                        HStack {
                            Label(type.title, systemImage: type.symbol)
                            Spacer()
                            Text(Format.kcal(typed.reduce(0) { $0 + $1.totals.calories }))
                                .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                    }
                    .listRowBackground(Color.cardBackground)
                }
            }

            if meals.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "fork.knife.circle",
                        title: isToday ? "Nothing logged yet" : "No meals this day",
                        message: "Tell the Coach what you ate, snap a photo, or add a meal manually.",
                        actionTitle: "Add meal",
                        action: onAddMeal
                    )
                }
                .listRowBackground(Color.cardBackground)
            }

            Section {
                WaterCard(total: waterTotal, target: targets.waterMl, day: day)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section {
                WeeklyNutritionChart(endingOn: day, targets: targets)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listSectionSpacing(Spacing.m)
        .animation(.snappySpring, value: meals.count)
        .overlay(alignment: .bottom) {
            if let copiedCount {
                Text("Copied \(copiedCount) meals from yesterday")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, Spacing.m)
                    .background(.thickMaterial, in: Capsule())
                    .padding(.bottom, Spacing.l)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var summaryCard: some View {
        Card {
            VStack(spacing: Spacing.l) {
                HStack(spacing: Spacing.l) {
                    CalorieRing(eaten: eaten.calories, target: targets.calories, size: 140)
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        labeledValue("Eaten", Format.kcal(eaten.calories))
                        labeledValue("Target", Format.kcal(targets.calories))
                        labeledValue("Fiber", "\(Int(eaten.fiber)) / \(Int(targets.fiber)) g")
                    }
                }
                MacroBar(title: "Protein", eaten: eaten.protein, target: targets.protein, tint: .protein)
                MacroBar(title: "Carbs", eaten: eaten.carbs, target: targets.carbs, tint: .carbs)
                MacroBar(title: "Fat", eaten: eaten.fat, target: targets.fat, tint: .fat)
            }
        }
        .accessibilityIdentifier("nutrition.summary")
    }

    private func labeledValue(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private var quickActions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.s) {
                quickButton("Add meal", symbol: "plus.circle.fill", action: onAddMeal)
                    .accessibilityIdentifier("nutrition.addMeal")
                quickButton("Presets", symbol: "star.fill", action: onShowPresets)
                if isToday {
                    quickButton("Same as yesterday", symbol: "arrow.uturn.backward.circle.fill") {
                        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: day) else { return }
                        let count = NutritionService.copyMeals(from: yesterday, to: day, in: modelContext)
                        Haptics.success()
                        withAnimation { copiedCount = count }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { copiedCount = nil }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.xs)
        }
        .scrollIndicators(.hidden)
    }

    private func quickButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m)
                .background(Color.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.xs) {
                    Text(meal.name).font(.body.weight(.semibold)).lineLimit(1)
                    if meal.source == .ai {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(.brand)
                            .accessibilityLabel("Logged by coach")
                    }
                }
                Text(meal.orderedItems.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: Spacing.s) {
                    macro("P", meal.totals.protein, .protein)
                    macro("C", meal.totals.carbs, .carbs)
                    macro("F", meal.totals.fat, .fat)
                    Text(meal.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Text("\(Int(meal.totals.calories))")
                .font(.headline.monospacedDigit())
            + Text(" kcal").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func macro(_ letter: String, _ value: Double, _ tint: Color) -> some View {
        Text("\(letter) \(Int(value.rounded()))g")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(tint)
    }
}

struct WaterCard: View {
    var total: Double
    var target: Double
    var day: Date
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Card {
            HStack(spacing: Spacing.l) {
                ZStack {
                    ProgressRing(progress: target > 0 ? total / target : 0, tint: .water, lineWidth: 8)
                    Image(systemName: "drop.fill").foregroundStyle(.water)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Water").font(.cardTitle)
                    Text("\(Format.ml(total)) / \(Format.ml(target))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CircleIconButton(symbol: "minus", tint: .water, size: 40, accessibilityLabel: "Remove last water") {
                    NutritionService.removeLastWater(on: day, in: modelContext)
                    Haptics.selection()
                }
                .disabled(total <= 0)
                Button {
                    let date = Calendar.current.isDateInToday(day) ? Date.now : (Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day)
                    NutritionService.addWater(250, on: date, in: modelContext)
                    Haptics.impact(.light)
                } label: {
                    Text("+250 ml")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, Spacing.m)
                        .frame(height: 40)
                        .background(Color.water.opacity(0.18), in: Capsule())
                        .foregroundStyle(.water)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("nutrition.addWater")
            }
        }
    }
}

struct WeeklyNutritionChart: View {
    var endingOn: Date
    var targets: NutritionCalculator.Targets
    @Environment(\.modelContext) private var modelContext
    @Query private var allMeals: [MealEntry]
    @State private var metric = 0

    private struct DayPoint: Identifiable {
        var date: Date
        var calories: Double
        var protein: Double
        var id: Date { date }
    }

    init(endingOn: Date, targets: NutritionCalculator.Targets) {
        self.endingOn = endingOn
        self.targets = targets
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: endingOn)) ?? endingOn
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? endingOn
        _allMeals = Query(filter: #Predicate<MealEntry> { $0.date >= start && $0.date < end })
    }

    private var points: [DayPoint] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: endingOn)
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let meals = allMeals.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let totals = meals.reduce(MacroTotals.zero) { $0 + $1.totals }
            return DayPoint(date: date, calories: totals.calories, protein: totals.protein)
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack {
                    CardHeader(title: "Last 7 days", symbol: "chart.bar.fill", tint: .brand)
                    Picker("Metric", selection: $metric) {
                        Text("kcal").tag(0)
                        Text("Protein").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                let target = metric == 0 ? targets.calories : targets.protein
                Chart {
                    ForEach(points) { point in
                        let value = metric == 0 ? point.calories : point.protein
                        BarMark(x: .value("Day", point.date, unit: .day), y: .value("Amount", value))
                            .foregroundStyle((metric == 0 ? Color.brand : Color.protein).gradient)
                            .cornerRadius(5)
                            .opacity(value >= target * 0.9 ? 1 : 0.55)
                    }
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(.primary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Target \(Int(target))").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .frame(height: 170)
                let hit = points.filter { (metric == 0 ? $0.calories : $0.protein) >= target * 0.9 }.count
                Text("Target hit on \(hit) of 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
