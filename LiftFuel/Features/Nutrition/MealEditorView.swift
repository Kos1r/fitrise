import SwiftData
import SwiftUI

/// Manual food logging (fallback without AI) and editing of any logged meal.
struct MealEditorView: View {
    var target: MealEditorTarget

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var mealType: MealType = .suggested(for: .now)
    @State private var date: Date = .now
    @State private var items: [FoodItemSnapshot] = [.empty]
    @State private var existing: MealEntry?
    @State private var recents: [MealEntry] = []
    @State private var loaded = false
    @State private var showDelete = false

    private var totals: MacroTotals { items.reduce(.zero) { $0 + $1.macros } }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && items.contains { !$0.name.isEmpty && $0.calories > 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                if existing == nil, !recents.isEmpty {
                    Section("Log again") {
                        ScrollView(.horizontal) {
                            HStack(spacing: Spacing.s) {
                                ForEach(recents) { meal in
                                    Button {
                                        apply(meal)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(meal.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            Text(Format.kcal(meal.totals.calories)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, Spacing.m)
                                        .padding(.vertical, Spacing.s)
                                        .background(Color.cardElevated, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                Section("Meal") {
                    TextField("Name (e.g. Chicken & rice)", text: $name)
                        .accessibilityIdentifier("mealEditor.name")
                    Picker("Type", selection: $mealType) {
                        ForEach(MealType.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    DatePicker("Time", selection: $date)
                }

                ForEach($items) { $item in
                    Section {
                        TextField("Food", text: $item.name)
                            .accessibilityIdentifier("mealEditor.itemName")
                        TextField("Portion (e.g. 200 g cooked)", text: $item.quantityDescription)
                        numberField("Grams", value: $item.grams, unit: "g")
                        numberField("Calories", value: $item.calories, unit: "kcal")
                            .accessibilityIdentifier("mealEditor.calories")
                        numberField("Protein", value: $item.protein, unit: "g")
                        numberField("Carbs", value: $item.carbs, unit: "g")
                        numberField("Fat", value: $item.fat, unit: "g")
                        numberField("Fiber", value: $item.fiber, unit: "g")
                        if items.count > 1 {
                            Button("Remove item", role: .destructive) {
                                items.removeAll { $0.id == item.id }
                            }
                        }
                    } header: {
                        Text(item.name.isEmpty ? String(localized: "Food item") : item.name)
                    }
                }

                Section {
                    Button {
                        items.append(.empty)
                    } label: {
                        Label("Add food item", systemImage: "plus.circle.fill")
                    }
                }

                Section("Total") {
                    HStack {
                        Text(Format.kcal(totals.calories)).font(.headline.monospacedDigit())
                        Spacer()
                        Text("P \(Int(totals.protein)) · C \(Int(totals.carbs)) · F \(Int(totals.fat)) g")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                if existing != nil {
                    Section {
                        Button("Save as preset") {
                            if let existing {
                                NutritionService.savePreset(from: existing, in: modelContext)
                                Haptics.success()
                            }
                        }
                        Button("Delete meal", role: .destructive) { showDelete = true }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "Add meal" : "Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("mealEditor.save")
                }
            }
            .confirmationDialog("Delete this meal?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing { NutritionService.delete(existing, in: modelContext) }
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func numberField(_ title: LocalizedStringKey, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case .new(let day):
            if !Calendar.current.isDateInToday(day) {
                date = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
                mealType = .lunch
            }
            recents = NutritionService.recentMeals(in: modelContext)
        case .edit(let id):
            guard let meal = modelContext.model(for: id) as? MealEntry else { return }
            existing = meal
            name = meal.name
            mealType = meal.mealType
            date = meal.date
            items = meal.itemSnapshots.isEmpty ? [.empty] : meal.itemSnapshots
        }
    }

    private func apply(_ meal: MealEntry) {
        name = meal.name
        mealType = meal.mealType
        items = meal.itemSnapshots
        Haptics.selection()
    }

    private func save() {
        let cleaned = items.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        if let existing {
            existing.name = name
            existing.mealType = mealType
            existing.date = date
            NutritionService.replaceItems(of: existing, with: cleaned, in: modelContext)
        } else {
            NutritionService.logMeal(name: name, mealType: mealType, items: cleaned, source: .manual, date: date, in: modelContext)
        }
        Haptics.success()
        dismiss()
    }
}

/// Saved meals for one-tap logging.
struct PresetsSheet: View {
    var day: Date
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\MealPreset.useCount, order: .reverse), SortDescriptor(\MealPreset.name)])
    private var presets: [MealPreset]

    var body: some View {
        NavigationStack {
            List {
                if presets.isEmpty {
                    EmptyStateView(
                        symbol: "star",
                        title: "No presets yet",
                        message: "Swipe right on any logged meal and tap Save preset to log it with one tap next time."
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(presets) { preset in
                    Button {
                        let date = Calendar.current.isDateInToday(day) ? Date.now : (Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day)
                        NutritionService.log(preset: preset, on: date, in: modelContext)
                        Haptics.success()
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).font(.body.weight(.semibold))
                                Text(preset.items.map(\.name).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Format.kcal(preset.totals.calories)).font(.subheadline.weight(.semibold).monospacedDigit())
                                Text("P \(Int(preset.totals.protein)) g").font(.caption).foregroundStyle(.protein)
                            }
                            Image(systemName: "plus.circle.fill").foregroundStyle(.brand).font(.title3)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            modelContext.delete(preset)
                            modelContext.saveQuietly()
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
