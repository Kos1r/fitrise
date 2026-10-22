import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfile]
    @Query private var scheduleDays: [ScheduleDay]
    @AppStorage("appearance") private var appearance = AppAppearance.dark.rawValue

    @State private var exportURLs: [URL] = []
    @State private var exportError: String?
    @State private var showReset = false
    @State private var showDemoConfirm = false

    var body: some View {
        NavigationStack {
            if let profile = profiles.first {
                form(profile: profile)
            } else {
                ProgressView()
            }
        }
    }

    private func form(profile: UserProfile) -> some View {
        @Bindable var profile = profile
        return Form {
            Section("Profile") {
                TextField("Name", text: $profile.name)
                ProfileFields(profile: profile)
            }

            Section {
                NavigationLink {
                    TargetsView()
                } label: {
                    let targets = modelContext.currentTargets()
                    LabeledContent("Daily targets", value: "\(Int(targets.calories)) kcal · \(Int(targets.protein)) g P")
                }
            } header: {
                Text("Nutrition")
            } footer: {
                Text("Targets update automatically when your weight, activity or goal changes. You can override any of them.")
            }

            Section("Training") {
                NavigationLink("Weekly schedule") { ScheduleEditorView() }
                Stepper(value: $profile.defaultRestSeconds, in: 30...300, step: 15) {
                    LabeledContent("Default rest timer", value: Format.duration(TimeInterval(profile.defaultRestSeconds)))
                }
                Button("Apply rest timer to all exercises") {
                    for exercise in modelContext.allExercises() { exercise.restSeconds = profile.defaultRestSeconds }
                    modelContext.saveQuietly()
                    Haptics.success()
                }
                Picker("Weight steps", selection: $profile.weightIncrement) {
                    Text("1 kg").tag(1.0)
                    Text("1.25 kg").tag(1.25)
                    Text("2.5 kg").tag(2.5)
                    Text("5 kg").tag(5.0)
                }
                LabeledContent("Units", value: "kg · cm · kcal")
            }

            Section("Notifications") {
                Toggle("Training-day reminder", isOn: $profile.trainingReminderEnabled)
                if profile.trainingReminderEnabled {
                    DatePicker("Time", selection: reminderTime(profile), displayedComponents: .hourAndMinute)
                }
                Toggle("Weekly summary (Sunday 19:00)", isOn: $profile.weeklySummaryEnabled)
            }
            .onChange(of: profile.trainingReminderEnabled) { _, _ in updateNotifications(profile) }
            .onChange(of: profile.reminderHour) { _, _ in updateNotifications(profile) }
            .onChange(of: profile.reminderMinute) { _, _ in updateNotifications(profile) }
            .onChange(of: profile.weeklySummaryEnabled) { _, _ in updateNotifications(profile) }

            Section {
                Toggle("Apple Health", isOn: Binding(
                    get: { profile.healthKitEnabled },
                    set: { enabled in
                        profile.healthKitEnabled = enabled
                        if enabled {
                            Task { await HealthKitService.shared.requestAuthorization() }
                        }
                    }
                ))
                .disabled(!HealthKitService.shared.isAvailable)
            } header: {
                Text("Integrations")
            } footer: {
                Text("Saves workouts and body weight to Health, reads body weight and steps. Everything works without it.")
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }

            Section("Coach connection") {
                NavigationLink("Server & app token") { CoachConnectionView() }
            }

            Section("Data") {
                Button("Export data (JSON + CSV)") { export() }
                if !exportURLs.isEmpty {
                    ShareLink(items: exportURLs) {
                        Label("Share export files", systemImage: "square.and.arrow.up")
                    }
                }
                if let exportError {
                    Text(exportError).font(.caption).foregroundStyle(.red)
                }
                Button("Load demo data") { showDemoConfirm = true }
                Button("Reset all data", role: .destructive) { showReset = true }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("Coach model", value: AppConfig.claudeModel)
                Text("Nutrition estimates from photos and descriptions are approximate. This app does not give medical advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    modelContext.saveQuietly()
                    WidgetSyncService.update(context: modelContext)
                    dismiss()
                }
            }
        }
        .confirmationDialog("Reset all data?", isPresented: $showReset, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) {
                SeedService.resetAllData(modelContext)
                dismiss()
            }
        } message: {
            Text("Workouts, meals, chat and settings will be deleted. This can't be undone.")
        }
        .confirmationDialog("Load demo data?", isPresented: $showDemoConfirm, titleVisibility: .visible) {
            Button("Load demo data") {
                DemoDataService.load(into: modelContext, now: .now)
                profile.onboardingCompleted = true
                modelContext.saveQuietly()
            }
        } message: {
            Text("Adds 10 weeks of sample workouts, a week of meals and weigh-ins on top of your data.")
        }
    }

    private func reminderTime(_ profile: UserProfile) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: profile.reminderHour, minute: profile.reminderMinute, second: 0, of: .now) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                profile.reminderHour = components.hour ?? 17
                profile.reminderMinute = components.minute ?? 0
            }
        )
    }

    private func updateNotifications(_ profile: UserProfile) {
        Task {
            if profile.trainingReminderEnabled || profile.weeklySummaryEnabled {
                await NotificationService.shared.requestAuthorization()
            }
            NotificationService.shared.scheduleTrainingReminders(
                template: modelContext.weeklyTemplate(),
                hour: profile.reminderHour,
                minute: profile.reminderMinute,
                enabled: profile.trainingReminderEnabled
            )
            NotificationService.shared.scheduleWeeklySummary(enabled: profile.weeklySummaryEnabled)
        }
    }

    private func export() {
        do {
            exportURLs = try ExportService.export(context: modelContext)
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// Gender, age, height, weight, activity, goal — shared by onboarding and settings.
struct ProfileFields: View {
    @Bindable var profile: UserProfile

    var body: some View {
        Picker("Gender", selection: $profile.genderRaw) {
            ForEach(Gender.allCases) { Text($0.title).tag($0.rawValue) }
        }
        Stepper(value: $profile.age, in: 14...90) {
            LabeledContent("Age", value: "\(profile.age)")
        }
        Stepper(value: $profile.heightCm, in: 120...230, step: 1) {
            LabeledContent("Height", value: "\(Int(profile.heightCm)) cm")
        }
        Stepper(value: $profile.weightKg, in: 35...250, step: 0.5) {
            LabeledContent("Weight", value: Format.kg(profile.weightKg))
        }
        Picker("Activity", selection: $profile.activityRaw) {
            ForEach(ActivityLevel.allCases) { Text($0.title).tag($0.rawValue) }
        }
        Picker("Goal", selection: $profile.goalRaw) {
            ForEach(NutritionGoal.allCases) { Text($0.title).tag($0.rawValue) }
        }
    }
}

struct ScheduleEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var scheduleDays: [ScheduleDay]

    private var template: WeeklyTemplate {
        ScheduleService(days: scheduleDays, overrides: []).template
    }

    var body: some View {
        Form {
            Section {
                ForEach(WeeklyTemplate.mondayFirstWeekdays, id: \.self) { weekday in
                    Picker(Calendar.current.weekdaySymbols[weekday - 1], selection: Binding(
                        get: { template.split(forWeekday: weekday) },
                        set: { ScheduleEditor.setTemplate(weekday: weekday, split: $0, context: modelContext) }
                    )) {
                        ForEach(SplitDay.allCases) { split in
                            Label(split.titleString, systemImage: split.symbol).tag(split)
                        }
                    }
                    .tint(template.split(forWeekday: weekday).color)
                }
            } footer: {
                Text("\(template.trainingDaysPerWeek) training days per week. Use the Calendar to move a single day without changing this template.")
            }
            Section {
                Button("Restore default (Pull · Push · Rest · Rest · Pull · Push · Rest)") {
                    for weekday in 1...7 {
                        ScheduleEditor.setTemplate(weekday: weekday, split: WeeklyTemplate.default.split(forWeekday: weekday), context: modelContext)
                    }
                }
            }
        }
        .navigationTitle("Weekly schedule")
    }
}

struct TargetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var targetRows: [NutritionTargets]

    var body: some View {
        if let profile = profiles.first, let overrides = targetRows.first {
            content(profile: profile, overrides: overrides)
        } else {
            ProgressView()
        }
    }

    private func content(profile: UserProfile, overrides: NutritionTargets) -> some View {
        @Bindable var profile = profile
        let breakdown = NutritionCalculator.breakdown(for: profile.nutritionInput)
        let effective = NutritionCalculator.targets(for: profile.nutritionInput, overrides: overrides.overrides)
        return Form {
            Section {
                TargetsExplanation(input: profile.nutritionInput, breakdown: breakdown)
            }
            Section("Protein & fat per kg") {
                Stepper(value: $profile.proteinPerKg, in: 1.6...2.4, step: 0.1) {
                    LabeledContent("Protein", value: "\(profile.proteinPerKg.formatted(.number.precision(.fractionLength(1)))) g/kg")
                }
                Stepper(value: $profile.fatPerKg, in: 0.6...1.2, step: 0.1) {
                    LabeledContent("Fat", value: "\(profile.fatPerKg.formatted(.number.precision(.fractionLength(1)))) g/kg")
                }
            }
            Section {
                overrideRow("Calories", unit: "kcal", calculated: breakdown.targets.calories, effective: effective.calories, value: Binding(get: { overrides.caloriesOverride }, set: { overrides.caloriesOverride = $0 }))
                overrideRow("Protein", unit: "g", calculated: breakdown.targets.protein, effective: effective.protein, value: Binding(get: { overrides.proteinOverride }, set: { overrides.proteinOverride = $0 }))
                overrideRow("Carbs", unit: "g", calculated: breakdown.targets.carbs, effective: effective.carbs, value: Binding(get: { overrides.carbsOverride }, set: { overrides.carbsOverride = $0 }))
                overrideRow("Fat", unit: "g", calculated: breakdown.targets.fat, effective: effective.fat, value: Binding(get: { overrides.fatOverride }, set: { overrides.fatOverride = $0 }))
                overrideRow("Fiber", unit: "g", calculated: breakdown.targets.fiber, effective: effective.fiber, value: Binding(get: { overrides.fiberOverride }, set: { overrides.fiberOverride = $0 }))
                overrideRow("Water", unit: "ml", calculated: breakdown.targets.waterMl, effective: effective.waterMl, value: Binding(get: { overrides.waterOverride }, set: { overrides.waterOverride = $0 }))
                if overrides.hasAnyOverride {
                    Button("Use calculated targets") { overrides.clearOverrides() }
                }
            } header: {
                Text("Your targets")
            } footer: {
                Text("Leave a field empty to use the calculated value.")
            }
        }
        .navigationTitle("Daily targets")
        .onDisappear {
            modelContext.saveQuietly()
            WidgetSyncService.update(context: modelContext)
        }
    }

    private func overrideRow(_ title: LocalizedStringKey, unit: String, calculated: Double, effective: Double, value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("\(Int(effective))", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
                .foregroundStyle(value.wrappedValue == nil ? Color.secondary : Color.brand)
            Text(unit).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
        }
        .accessibilityHint(Text("Calculated: \(Int(calculated)) \(unit)"))
    }
}

/// "How we calculated this" card.
struct TargetsExplanation: View {
    var input: NutritionCalculator.Input
    var breakdown: NutritionCalculator.Breakdown

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("How we calculated this").font(.headline)
            row("BMR (Mifflin–St Jeor)", "\(Int(breakdown.bmr)) kcal")
            row("× \(input.activity.multiplier.formatted()) activity = TDEE", "\(Int(breakdown.tdee)) kcal")
            row(input.goal.title, "\(breakdown.goalAdjustment >= 0 ? "+" : "")\(Int(breakdown.goalAdjustment)) kcal")
            Divider()
            row(String(localized: "Daily calories"), "\(Int(breakdown.targets.calories)) kcal", bold: true)
            row(String(localized: "Protein \(input.proteinPerKg.formatted()) g/kg"), "\(Int(breakdown.targets.protein)) g")
            row(String(localized: "Fat (≥20% of kcal)"), "\(Int(breakdown.targets.fat)) g")
            row(String(localized: "Carbs (the rest)"), "\(Int(breakdown.targets.carbs)) g")
            row(String(localized: "Fiber (14 g / 1000 kcal)"), "\(Int(breakdown.targets.fiber)) g")
            row(String(localized: "Water (35 ml/kg)"), Format.ml(breakdown.targets.waterMl))
            Text(input.goal.detail).font(.caption).foregroundStyle(.secondary).padding(.top, Spacing.xs)
        }
        .padding(.vertical, Spacing.xs)
    }

    private func row(_ title: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit()).fontWeight(bold ? .bold : .regular)
        }
    }
}

struct CoachConnectionView: View {
    @State private var mode = CoachConnection.mode
    @State private var proxyURL = CoachConnection.proxyBaseURL
    @State private var token = CoachConnection.appToken ?? ""
    @State private var saved = false

    var body: some View {
        Form {
            #if DEBUG
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(CoachConnection.Mode.allCases) { Text($0.title).tag($0) }
                }
                if mode == .directDevelopment {
                    Label(AppConfig.devAPIKey == nil ? "No key in Config/Secrets.xcconfig" : "Using key from Secrets.xcconfig", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color("ShouldersColor"))
                        .font(.footnote)
                }
            } footer: {
                Text("Direct mode is for local development only and is not available in release builds.")
            }
            #endif
            Section {
                TextField("https://your-worker.workers.dev", text: $proxyURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("App token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Secure proxy")
            } footer: {
                Text("The Anthropic API key lives only on your proxy server. The app token is stored in the iOS Keychain. See README › Backend proxy.")
            }
            Section {
                Button(saved ? "Saved ✓" : "Save") {
                    CoachConnection.mode = mode
                    CoachConnection.proxyBaseURL = proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    CoachConnection.appToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    saved = true
                    Haptics.success()
                }
            }
        }
        .navigationTitle("Coach connection")
    }
}
