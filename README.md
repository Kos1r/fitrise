# Lift & Fuel

A native iOS gym tracker for a Push/Pull split, with an AI nutrition coach that logs your meals from a text message or a photo.

- **SwiftUI + SwiftData + Swift Charts**, iOS 17+, iPhone-first, no third-party dependencies
- Dark-first design with a full light mode, Dynamic Type, VoiceOver labels and Reduce Motion support
- Everything except the AI coach works fully offline

## Features

### Workout tracking
- Fixed exercise library (only these 12 exercises):
  - **Push**: Incline Chest Press, Pec Deck, Shoulder Press, Shoulder Flyes (machine), Triceps Pushdowns, Overhead Triceps Extensions
  - **Pull**: Lat Pulldown, T-Bar Rows, Pullovers, Cable Biceps Curls (full range of motion), Hammer Curls (cable), Preacher Curls
- You can start a workout in **one tap** from Home. Sets are pre-filled from your last session, and each set shows what you did last time.
- A custom keypad with ±2.5 kg / ±1 rep steppers, so you rarely need the system keyboard.
- Set types (warm-up, drop set, failure). Warm-up sets never count toward volume or PRs.
- A rest timer starts automatically when you complete a set. It plays a haptic when it ends, sends a local notification when the app is in the background, and shows a Live Activity / Dynamic Island.
- The workout header shows elapsed time, volume and sets done. If the app is killed mid-workout, the active workout comes back on the next launch.
- PRs are detected by estimated 1RM (Epley) or by weight at a given rep count. A new PR gets a trophy toast and a haptic.
- Each exercise has a detail screen: 1RM / top-set chart (1M, 3M, 6M, All), volume per session, best set, full history, and its own rest timer and rep range.
- Progression hints: "Try +2.5 kg today" when you hit the top of the rep range on every set, and a deload hint after 4 sessions with no progress.
- Workout history, where you can edit or delete past sessions.

### Training calendar
- Default weekly plan: Mon Pull · Tue Push · Wed Rest · Thu Rest · Fri Pull · Sat Push · Sun Rest. You can edit it in Settings.
- Month view with Push/Pull/Rest colors, a checkmark on completed days, and swipe to change month.
- Tap a day to see the planned or completed workout. You can change that single day or swap it with another; the weekly template stays the same.
- Shows your streak, workouts this week (e.g. 3/4) and a "Next up" strip on Home.
- Optional training-day reminder.

### AI nutrition coach
- Type what you ate or send a photo (camera or library; photos are downscaled to about 1024 px).
- Claude calls the `log_meal` tool. The meal is saved right away and appears as a card with **Edit / Remove / Looks good**.
- If the estimate is low-confidence, the coach asks a clarifying question instead of logging.
- `get_daily_summary` answers "what's left today?" from your real diary.
- Each request includes a compact context with your profile, today's totals, targets, remaining amounts and training schedule.
- Replies stream in. If a request fails, your message is kept with a **Retry** button.
- Manual food logging is always available as a fallback.

### Nutrition dashboard
- Calorie ring plus protein, carbs and fat bars showing eaten / target / remaining.
- Meals grouped by type, with swipe to edit, delete or save as a preset.
- Water counter, fiber, and a 7-day calories/protein chart against your target.
- Browse previous days. The day rolls over at local midnight.
- Quick add: presets, recent meals, and "Same as yesterday".

### Targets (pure, unit-tested `NutritionCalculator`)
- BMR uses Mifflin–St Jeor. TDEE = BMR × 1.2 / 1.375 / 1.55 / 1.725.
- Lean bulk adds about 10% (kept within +250 to +400 kcal). Maintain uses TDEE. Cut is −17.5%.
- Protein 2.0 g/kg (adjustable 1.6–2.4). Fat 0.9 g/kg, never below 20% of calories. Carbs fill the rest.
- Fiber 14 g per 1000 kcal. Water 35 ml/kg.
- You can override any target manually. Targets recalculate when your body weight changes.

### Extras (added beyond the brief)
- Body-weight log with a 7-day moving average and kg/week trend. The latest weigh-in updates your targets.
- Weekly summary screen (workouts, volume, PRs, sets per muscle, average calories and protein, takeaway tips) plus an optional Sunday notification.
- Chart of weekly sets per muscle group, with a 10–20 set guide.
- Home Screen widgets (small and medium) and Lock Screen widgets (rectangular, circular, inline). Tapping one deep-links into the app.
- Siri / Shortcuts: "Start my workout", "Log water", "How many calories do I have left".
- Apple Health (optional): saves workouts and body weight, and reads weight and steps. The app works normally if you decline.
- Export as JSON (complete) plus two CSVs (sets, food log) through the share sheet.
- "Load demo data" and "Reset all data" in Settings. Theme picker (Dark / Light / System).

## Requirements

- macOS with **Xcode 16 or newer** (iOS 17 SDK or later)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- For the coach: a Cloudflare account (free tier is enough) and an Anthropic API key

## Getting started

```bash
brew install xcodegen
xcodegen generate
open LiftFuel.xcodeproj
```

Choose the **LiftFuel** scheme and an iPhone simulator, then press Run. To skip onboarding with sample data, add the launch arguments `-demoData -skipOnboarding` in *Scheme › Run › Arguments*.

Run the tests with ⌘U, or from the command line:

```bash
xcodebuild test -project LiftFuel.xcodeproj -scheme LiftFuel -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

## Backend proxy (required for the AI coach)

**The Anthropic API key is never shipped in the app.** The app talks to a small Cloudflare Worker (`backend/`). The Worker:

- checks a shared **app token**
- rate-limits each token + IP to 30 requests per minute
- allows only the coach models and drops unexpected fields
- caps `max_tokens`
- forwards the request to Gemini (default) or the Claude Messages API, using the key stored as a Worker secret, and streams the response back

### Choose the model provider

The coach runs on **Google Gemini Flash** (`gemini-3.8-flash`, free tier) by default. The app always uses the Claude Messages format. When `PROVIDER = "gemini"`, the Worker translates requests and streamed replies, including tool calls and Gemini's thought signatures, so switching provider never needs an app update. Set it in `backend/wrangler.toml`:

```toml
[vars]
PROVIDER = "gemini"            # or "anthropic"
GEMINI_MODEL = "gemini-3.8-flash"
```

Gemini free-tier limits are set per project in Google AI Studio and change over time. One coach message uses 1–3 model requests (the tool calls count). On the free tier, Google may use prompts and photos to improve its products outside the EEA, Switzerland and the UK.

### Deploy

```bash
cd backend
npm install
npx wrangler login
npx wrangler secret put GEMINI_API_KEY      # key from aistudio.google.com → Get API key
npx wrangler secret put APP_TOKEN           # a long random string, e.g. from: openssl rand -hex 32
npx wrangler deploy
```

To use Claude instead, set `PROVIDER = "anthropic"`, run `npx wrangler secret put ANTHROPIC_API_KEY`, and redeploy.

`wrangler deploy` prints a URL such as `https://lift-fuel-proxy.<you>.workers.dev`. To check it:

```bash
curl https://lift-fuel-proxy.<you>.workers.dev/health
```

### Connect the app

In the app, open **Settings › Coach connection** and enter:

- **Proxy URL**: your Worker URL
- **App token**: the same `APP_TOKEN` (stored in the iOS Keychain)

You can also put your URL in `AppConfig.defaultProxyBaseURL` (`LiftFuel/Core/Config.swift`). The model itself is chosen on the proxy; other coach settings (history length, photo size) are in the same file.

Proxy tests: `cd backend && node --test`.

### Development-only direct mode

For local development you can skip the proxy:

1. `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig` (this file is git-ignored)
2. Set `ANTHROPIC_DEV_API_KEY = sk-ant-…`
3. Run `xcodegen generate` and run a **Debug** build. In Settings › Coach connection, choose *Direct API (development only)*.

Release builds never read this key: `AppConfig.devAPIKey` is compiled out and `Release.xcconfig` blanks it.

## Running on a real iPhone

1. Open the project in Xcode, select the **LiftFuel** target › *Signing & Capabilities*, and choose your **Team**. Do the same for **LiftFuelWidgets**.
2. Change the bundle identifiers (`com.liftfuel.app`, `com.liftfuel.app.widgets`) to ones you own. Update the App Group `group.com.liftfuel.app` in both targets *and* in `Shared/WidgetSnapshot.swift`.
3. Keep the HealthKit, App Groups and Push-free Live Activities capabilities. A free Apple ID can sideload for 7 days. HealthKit and App Groups need a paid developer account.
4. Connect your iPhone, select it as the run destination, and press Run.

To keep signing settings across regenerations, put `DEVELOPMENT_TEAM: YOURTEAMID` under `settings.base` in `project.yml`.

## Project structure

```
project.yml                 XcodeGen spec (app, widget extension, unit + UI tests)
Config/                     xcconfigs; Secrets.example.xcconfig (dev-only key template)
Shared/                     Code + colors shared with the widget (SplitDay, WidgetSnapshot, RestTimerAttributes)
LiftFuel/
  App/                      App entry, RootView/tabs, router, day clock
  Core/
    Config.swift            Model name, proxy URL, coach connection
    DesignSystem/           Theme (colors, type, spacing), cards, buttons, rings, badges
    Models/                 SwiftData models + enums
    Services/               NutritionCalculator, ScheduleService, StrengthMath, WorkoutService,
                            NutritionService, Notification/HealthKit/Export/Keychain services,
                            Claude/ (JSONValue, streaming parser, ClaudeService, tools, prompt)
  Features/
    Home/ Workout/ Calendar/ Nutrition/ Coach/ Settings/ Onboarding/
  Intents/                  App Intents + App Shortcuts
  Resources/                Assets (icon, launch logo), Localizable.xcstrings, Info.plist, entitlements
LiftFuelWidgets/            Today widget + rest-timer Live Activity
LiftFuelTests/              Nutrition formulas, schedule/date edge cases, 1RM/PR, AI parsing, SwiftData flows
LiftFuelUITests/            Start → log → finish, add set, coach logging (mock), screenshots
backend/                    Cloudflare Worker proxy + tests
.github/workflows/ios.yml   macOS CI: build, test, screenshots → `ci-results` branch
```

## Architecture notes

- **MVVM-ish with `@Observable`**: `CoachEngine`, `RestTimerManager`, `AppRouter` and `DayClock` are observable state objects passed through the environment. Domain logic is in pure, testable types (`NutritionCalculator`, `ScheduleService`, `StrengthMath`, `KeypadBuffer`, `BodyWeightMath`, `LogMealInput`, `StreamAccumulator`). Views query SwiftData directly with `@Query`.
- **SwiftData** models have defaults everywhere, optional to-many relationships and no unique constraints, so CloudKit sync only needs `cloudKitDatabase: .automatic` in `AppContainer`, plus the iCloud capability.
- **Claude integration**: raw Messages API over `URLSession` with SSE streaming (`anthropic-version: 2026-10-21`), adaptive thinking at low effort, and the opt-in server-side refusal fallback. Within a tool-use turn, assistant content blocks (including thinking blocks) are replayed unchanged. Earlier turns are sent as plain text.
- **Localization**: every user-facing string goes through `String(localized:)` or `LocalizedStringKey`, and Xcode extracts them into `Localizable.xcstrings`. To add Slovenian, add the language in the catalog.

## Known limitations

- The XcodeGen project must be generated (`xcodegen generate`); the `.xcodeproj` isn't committed.
- Food estimates from photos and descriptions are approximate by nature.
- CloudKit sync is prepared but not switched on (it needs a paid developer account and an iCloud container).
- Custom exercises aren't supported in v1 by design. The model has `isCustom` ready for later.
