import SwiftData
import SwiftUI

/// Welcome → profile & goal → schedule → notifications.
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var scheduleDays: [ScheduleDay]
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.l)

            TabView(selection: $page) {
                welcome.tag(0)
                profilePage.tag(1)
                schedulePage.tag(2)
                notificationsPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? nil : .gentleSpring, value: page)

            footer
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.l)
        }
        .background(Color.appBackground)
    }

    private var progress: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index <= page ? Color.brand : Color.cardElevated)
                    .frame(height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(page + 1) of \(pageCount)"))
    }

    private var footer: some View {
        HStack(spacing: Spacing.m) {
            if page > 0 {
                Button("Back") { page -= 1 }
                    .buttonStyle(SecondaryButtonStyle(tint: .secondary))
                    .frame(width: 110)
            }
            Button(page == pageCount - 1 ? "Let's go" : "Continue") {
                if page == pageCount - 1 {
                    finish()
                } else {
                    page += 1
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("onboarding.continue")
        }
    }

    // MARK: Pages

    private var welcome: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                Spacer(minLength: Spacing.xxl)
                ZStack {
                    Circle().fill(Color.brand.opacity(0.12)).frame(width: 180, height: 180)
                    Circle().fill(Color.brand.opacity(0.18)).frame(width: 130, height: 130)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.brand)
                        .rotationEffect(.degrees(-35))
                }
                VStack(spacing: Spacing.s) {
                    Text("Lift & Fuel").font(.largeTitle.weight(.heavy))
                    Text("Log every set in seconds, follow your Push/Pull plan, and let the AI coach track your food.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: Spacing.m) {
                    feature("bolt.fill", "Fast logging", "Previous weights pre-filled. One tap per set.")
                    feature("calendar", "Push / Pull plan", "Always know what's next.")
                    feature("sparkles", "AI nutrition coach", "Text or snap your meal — it's logged automatically.")
                }
                .padding(Spacing.l)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            .padding(.horizontal, Spacing.xl)
        }
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.brand)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var profilePage: some View {
        if let profile = profiles.first {
            OnboardingProfilePage(profile: profile)
        }
    }

    private var schedulePage: some View {
        let template = ScheduleService(days: scheduleDays, overrides: []).template
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                pageHeader("Your training week", "Default Push/Pull split. Tap a day to change it — you can edit this any time in Settings.")
                VStack(spacing: Spacing.s) {
                    ForEach(WeeklyTemplate.mondayFirstWeekdays, id: \.self) { weekday in
                        let split = template.split(forWeekday: weekday)
                        HStack {
                            Text(Calendar.current.weekdaySymbols[weekday - 1]).font(.body.weight(.semibold))
                            Spacer()
                            Menu {
                                ForEach(SplitDay.allCases) { option in
                                    Button(option.titleString) {
                                        ScheduleEditor.setTemplate(weekday: weekday, split: option, context: modelContext)
                                        Haptics.selection()
                                    }
                                }
                            } label: {
                                SplitBadge(split: split)
                            }
                        }
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.m)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    }
                }
                Text("\(template.trainingDaysPerWeek) training days · rest days are for growth.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
        }
    }

    private var notificationsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                pageHeader("Stay on track", "Get a nudge on training days, a sound when your rest is over, and a weekly summary on Sunday.")
                if let profile = profiles.first {
                    VStack(spacing: Spacing.s) {
                        SelectableRow(
                            title: String(localized: "Training-day reminders"),
                            detail: String(localized: "At 17:00 on Push and Pull days"),
                            symbol: "bell.badge.fill",
                            isSelected: profile.trainingReminderEnabled
                        ) { profile.trainingReminderEnabled.toggle() }
                        SelectableRow(
                            title: String(localized: "Weekly summary"),
                            detail: String(localized: "Sundays at 19:00"),
                            symbol: "chart.bar.doc.horizontal.fill",
                            isSelected: profile.weeklySummaryEnabled
                        ) { profile.weeklySummaryEnabled.toggle() }
                    }
                    Button {
                        Task { await NotificationService.shared.requestAuthorization() }
                    } label: {
                        Label("Allow notifications", systemImage: "bell.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Text("Rest-timer alerts also need notifications so they work when the app is in the background.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
        }
    }

    private func pageHeader(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title).font(.largeTitle.weight(.bold))
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
    }

    private func finish() {
        guard let profile = profiles.first else { return }
        profile.onboardingCompleted = true
        if profile.weightKg > 0, modelContext.bodyWeights().isEmpty {
            modelContext.insert(BodyWeightEntry(date: .now, weightKg: profile.weightKg))
        }
        modelContext.saveQuietly()
        NotificationService.shared.scheduleTrainingReminders(
            template: modelContext.weeklyTemplate(),
            hour: profile.reminderHour,
            minute: profile.reminderMinute,
            enabled: profile.trainingReminderEnabled
        )
        NotificationService.shared.scheduleWeeklySummary(enabled: profile.weeklySummaryEnabled)
        WidgetSyncService.update(context: modelContext)
        Haptics.success()
    }
}

struct OnboardingProfilePage: View {
    @Bindable var profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("About you").font(.largeTitle.weight(.bold))
                    Text("Used to calculate your calorie and macro targets.").foregroundStyle(.secondary)
                }
                VStack(spacing: Spacing.m) {
                    TextField("First name (optional)", text: $profile.name)
                        .textContentType(.givenName)
                        .padding(Spacing.m)
                        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    Picker("Gender", selection: $profile.genderRaw) {
                        ForEach(Gender.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    stepperCard("Age", value: "\(profile.age)") {
                        Stepper("Age", value: $profile.age, in: 14...90).labelsHidden()
                    }
                    stepperCard("Height", value: "\(Int(profile.heightCm)) cm") {
                        Stepper("Height", value: $profile.heightCm, in: 120...230, step: 1).labelsHidden()
                    }
                    stepperCard("Weight", value: Format.kg(profile.weightKg)) {
                        Stepper("Weight", value: $profile.weightKg, in: 35...250, step: 0.5).labelsHidden()
                    }
                }

                Text("Activity").font(.headline)
                VStack(spacing: Spacing.s) {
                    ForEach(ActivityLevel.allCases) { level in
                        SelectableRow(title: level.title, detail: level.detail, symbol: nil, isSelected: profile.activity == level) {
                            profile.activity = level
                        }
                    }
                }

                Text("Goal").font(.headline)
                VStack(spacing: Spacing.s) {
                    ForEach(NutritionGoal.allCases) { goal in
                        SelectableRow(title: goal.title, detail: goal.detail, symbol: goal.symbol, isSelected: profile.goal == goal) {
                            profile.goal = goal
                        }
                    }
                }

                let targets = NutritionCalculator.targets(for: profile.nutritionInput)
                Card {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        CardHeader(title: "Your daily targets", symbol: "target")
                        Text("\(Int(targets.calories)) kcal")
                            .font(.statLarge)
                            .contentTransition(.numericText())
                        Text("Protein \(Int(targets.protein)) g · Carbs \(Int(targets.carbs)) g · Fat \(Int(targets.fat)) g")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
    }

    private func stepperCard<Control: View>(_ title: LocalizedStringKey, value: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).font(.body.weight(.semibold))
            Spacer()
            Text(value).font(.body.monospacedDigit()).foregroundStyle(.secondary)
            control()
        }
        .padding(Spacing.m)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}
