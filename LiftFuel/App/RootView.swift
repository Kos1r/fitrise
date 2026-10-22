import SwiftData
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: String(localized: "Dark")
        case .light: String(localized: "Light")
        case .system: String(localized: "System")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

struct RootView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @Environment(RestTimerManager.self) private var restTimer
    @Environment(DayClock.self) private var clock
    @AppStorage("appearance") private var appearance = AppAppearance.dark.rawValue

    private var onboardingDone: Bool { profiles.first?.onboardingCompleted ?? false }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            if onboardingDone {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.gentleSpring, value: onboardingDone)
        .tint(.brand)
        .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .dark).colorScheme)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                clock.refresh()
                restTimer.refresh()
                handlePendingActions()
                WidgetSyncService.update(context: modelContext)
            case .background:
                WidgetSyncService.update(context: modelContext)
            default:
                break
            }
        }
        .onOpenURL(perform: handle(url:))
    }

    private func handlePendingActions() {
        guard onboardingDone, PendingAction.consumeStartWorkout() else { return }
        WorkoutLauncher.startPlanned(context: modelContext, router: router, now: clock.now)
    }

    /// liftfuel://workout/start, liftfuel://nutrition, liftfuel://coach, liftfuel://calendar
    private func handle(url: URL) {
        guard url.scheme == "liftfuel" else { return }
        switch url.host() {
        case "workout":
            if url.path().contains("start") {
                WorkoutLauncher.startPlanned(context: modelContext, router: router, now: clock.now)
            } else {
                router.selectedTab = .workout
            }
        case "nutrition": router.selectedTab = .nutrition
        case "coach": router.selectedTab = .coach
        case "calendar": router.selectedTab = .calendar
        default: router.selectedTab = .home
        }
    }
}

/// Starts (or resumes) a workout and jumps to the Workout tab — at most two taps from launch.
@MainActor
enum WorkoutLauncher {
    static func start(_ split: SplitDay, context: ModelContext, router: AppRouter) {
        WorkoutService.startSession(split: split, in: context)
        Haptics.impact(.medium)
        router.selectedTab = .workout
    }

    /// Starts today's planned split; on a rest day falls back to the next planned training split.
    static func startPlanned(context: ModelContext, router: AppRouter, now: Date) {
        if context.activeSession() != nil {
            router.selectedTab = .workout
            return
        }
        let schedule = context.scheduleService()
        let today = schedule.plannedSplit(on: now)
        let split = today.isTraining ? today : (schedule.nextTrainingDay(after: now)?.split ?? .push)
        start(split, context: context, router: router)
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)
            WorkoutTabView()
                .tabItem { Label("Workout", systemImage: "dumbbell.fill") }
                .tag(AppTab.workout)
            CalendarScreen()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            NutritionView()
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }
                .tag(AppTab.nutrition)
            CoachView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right.fill") }
                .tag(AppTab.coach)
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $router.showWeeklySummary) {
            NavigationStack { WeeklySummaryView() }
        }
        .sheet(isPresented: $router.showBodyWeight) {
            NavigationStack { BodyWeightView() }
        }
    }
}

/// Toolbar button that opens Settings, shown on every tab.
struct ProfileToolbarButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.showSettings = true
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.title3)
        }
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("toolbar.settings")
    }
}
