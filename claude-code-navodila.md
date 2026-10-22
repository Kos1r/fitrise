# Project brief: "Lift & Fuel" – native iOS gym tracker + AI nutrition coach

You are building a complete, production-quality native iOS app from scratch. Read this whole document before writing any code. First produce a short plan (architecture, folder structure, data models, screen list), then implement it step by step, building and running the app after each major milestone. Do not stop at a skeleton: deliver a working, polished app.

## 1. Product summary

A personal training app for one user (a 19-year-old lifter following a Push/Pull split). It does three things:

1. **Workout tracking**: log weight (kg) and reps for every set, similar in feel and speed to the public app "Liftoff". Show previous performance while logging, so progressive overload is obvious.
2. **Training calendar**: a Push/Pull/Rest schedule that shows what the next workouts are.
3. **AI nutrition tracking by chat**: the user texts or photographs meals; the AI estimates calories and macros and logs them automatically for the day. The AI always knows what has been eaten today and what is still missing against the daily targets.

Target: iOS 17+, iPhone first. Use **SwiftUI**, **SwiftData** for persistence, **Swift Charts** for graphs, Swift Concurrency (async/await). No third-party dependencies unless clearly justified. Everything except the AI chat must work fully offline.

UI language: English (put all strings in a String Catalog / `Localizable.xcstrings` so Slovenian can be added later). Units: kg, cm, kcal, grams.

## 2. Exercise library (FIXED – only these exercises, nothing else)

The app must contain **only** the following exercises. Do not add a generic exercise database. The user can't add custom exercises in v1 (keep the model extensible so it can be added later).

**PUSH day**
- Chest: Incline Chest Press, Pec Deck
- Shoulders: Shoulder Press, Shoulder Flyes (machine)
- Triceps: Triceps Pushdowns, Overhead Triceps Extensions

**PULL day**
- Back: Lat Pulldown, T-Bar Rows, Pullovers
- Biceps: Cable Biceps Curls (full range of motion), Hammer Curls (cable), Preacher Curls

Each exercise has: name, muscle group, equipment type (machine / cable / barbell / dumbbell), the split day it belongs to (Push or Pull), optional notes (e.g. "full range of motion" on cable curls), and a stable ID. Seed them on first launch.

Exercises are grouped by muscle group in the UI (Chest, Back, Biceps, Triceps, Shoulders) with a clear muscle-group icon/color accent.

## 3. Workout tracking (core feature)

**Starting a workout**
- Home screen shows "Today": if today is a Push or Pull day, a large "Start Push Workout" / "Start Pull Workout" button. On a rest day, show a rest message plus the option to still start a workout manually (choose Push or Pull).
- A workout session pre-loads all exercises for that split day in a sensible order.

**Logging a set**
- Per exercise: a list of set rows. Each row: set number, weight (kg, supports decimals like 42.5), reps, a checkmark to complete the set.
- Weight and reps fields should be pre-filled from the **last session** of the same exercise (shown as greyed "previous" values next to each set, e.g. "Last time: 60 kg × 10").
- "Add set" button; swipe to delete a set. Optional set type tag: normal / warm-up / drop set / failure (warm-up sets must not count toward volume and PRs).
- Completing a set automatically starts a **rest timer** (default 90 s, adjustable per exercise, with haptics and a local notification when it ends, also works when the app is in the background; consider a Live Activity / Dynamic Island for the timer).
- Fast number entry: custom compact numeric input with +/- steppers (±2.5 kg, ±1 rep) so the user rarely needs the full keyboard.
- Workout header shows elapsed time, total volume (kg × reps), and sets completed. "Finish workout" saves the session; also allow discarding. If the app is killed mid-workout, restore the active workout on relaunch.

**History and progress**
- Per-exercise detail screen: history of all sessions (date, sets), estimated 1RM (Epley), best set, volume trend. Swift Charts line chart for estimated 1RM / top-set weight over time, with time range selector (1M, 3M, 6M, All).
- **PR detection**: when a set beats the previous best (weight at given reps or est. 1RM), show a subtle celebration (badge + haptic) and store it.
- Workout history list (by date) with the ability to open and edit a past session.
- Simple **progressive overload hint**: if the user hit the top of their usual rep range for all sets last time, suggest "Try +2.5 kg today".

## 4. Training calendar (Push / Pull split)

A calendar screen showing the weekly schedule and a monthly view with colored markers per day type (Push, Pull, Rest) and a checkmark for days where a workout was actually completed.

**Default weekly schedule** (must be editable in Settings, as a per-weekday picker of Push / Pull / Rest):

| Mon | Tue | Wed | Thu | Fri | Sat | Sun |
|-----|-----|-----|-----|-----|-----|-----|
| Pull | Push | Rest | Rest | Pull | Push | Rest |

Requirements:
- Today is Thursday 22 Oct 2026 in the user's context; the app must compute everything from the real current date. Tomorrow (Friday) must show Pull, Saturday Push, Wednesday Rest, Monday Pull, Tuesday Push, as in the table above.
- Home screen shows "Today" and a "Next up" strip with the next 3–7 days.
- Tapping a day shows the planned workout, or the completed workout if it happened.
- Allow swapping/moving a day (e.g. "do Push today instead") without breaking the weekly template. Show a streak and a "workouts this week" counter (e.g. 3/4).
- Optional daily reminder notification at a user-chosen time on training days.

## 5. AI nutrition coach (chat-based food logging)

### 5.1 Profile and automatic targets
Onboarding + Settings let the user set: **gender, age, height (cm), weight (kg)**, activity level (sedentary / light / moderate / very active), and goal (lean bulk (default, optimal for muscle growth) / maintain / cut). Age is required for the formula even though the user only listed height, gender and weight.

From that, calculate daily targets automatically and show them on screen with a short explanation:
- BMR via **Mifflin–St Jeor**; TDEE = BMR × activity multiplier (1.2 / 1.375 / 1.55 / 1.725).
- Calories: lean bulk = TDEE + ~10% (about +250–400 kcal); maintain = TDEE; cut = TDEE − ~15–20%.
- Protein: 1.8–2.2 g per kg bodyweight (default 2.0 g/kg).
- Fat: ~0.8–1.0 g per kg (default 0.9), never less than 20% of calories.
- Carbs: all remaining calories (4 kcal/g carbs and protein, 9 kcal/g fat).
- Also show a fiber target (~14 g per 1000 kcal) and a water target (~35 ml/kg).
- The user can manually override any target. Recalculate when body weight is updated.
- Put the formulas in a pure, unit-tested `NutritionCalculator` type.

### 5.2 Chat interface
A dedicated **Coach** tab with a chat UI (message bubbles, typing indicator, streaming responses if feasible). The user can:
- **Type** what they ate: "2 scrambled eggs, 2 slices of toast with butter and a banana".
- **Send a photo** of a meal (camera or photo library, via `PhotosPicker` / camera). The AI estimates the food items, portions, calories, protein, carbs, fat.
- **Ask questions**: "How many calories and how much protein do I still need today?", "What should I eat for dinner to hit my protein?", "Is this meal good for muscle growth?".

### 5.3 Automatic logging (important)
Use the **Claude API (Messages API)** with **tool use** so the model returns structured data instead of free text for logging:
- Tool `log_meal`: `{ meal_name, items: [{ name, quantity_description, grams_estimate, calories, protein_g, carbs_g, fat_g, fiber_g }], meal_type (breakfast/lunch/dinner/snack), confidence (low/medium/high) }`.
- When the model calls `log_meal`, the app shows a **confirmation card** in the chat (food items + macros, with Edit / Remove / Looks good). Auto-save to today's log immediately, but let the user edit or delete afterwards (undo is always one tap away). If confidence is low, the AI should ask a short clarifying question instead of guessing ("Was the rice about one or two cups?").
- Tool `get_daily_summary`: executed locally by the app; returns today's totals, the targets and the remaining amounts. The model must call this when the user asks what is left. Also inject a compact summary of today's totals + targets + the user's profile into the system prompt of every request, so answers are always grounded in real numbers.
- Use the vision capability for photos (compress and downscale images to roughly 1024 px on the long edge before upload).
- Model: use a current Claude model (default `claude-sonnet-5-5`), configurable in one constants file.
- System prompt for the coach: concise, friendly, practical, metric units, always give numbers, never shame the user, never give medical diagnoses, acknowledge estimates are estimates. The coach should know the user trains a Push/Pull split and can mention it ("you have a Pull day tomorrow, so carb up tonight").

### 5.4 API key and backend (security – do not skip)
**Never hard-code or ship the Anthropic API key inside the app binary.** Implement this properly:
- Create a tiny backend proxy (e.g. a Cloudflare Worker or small Node/Vercel function, in a `/backend` folder) that holds the API key as an environment secret, forwards requests from the app to the Claude API, and applies basic rate limiting.
- The app talks only to the proxy URL (configurable in a `Config.swift`). Add simple app-level auth (a shared secret / app token stored in the Keychain).
- For local development, allow a debug-only mode where the key is read from a git-ignored `Secrets.xcconfig`, clearly marked "development only".
- Document setup steps in the README (how to deploy the proxy, where to set the key).
- Handle errors gracefully: offline, rate limit, timeout, invalid response. Failed requests keep the user's message and offer "Retry". Manual food logging (without AI) must also exist as a fallback form.

### 5.5 Nutrition dashboard
A **Nutrition** screen (or section on Home) showing today's progress: calorie ring + three macro progress bars (protein, carbs, fat) with "eaten / target / remaining", a list of today's meals (editable, deletable, swipe actions), water intake counter, and a weekly chart of calories and protein vs target. The day rolls over at midnight local time; browsing previous days must be possible.

## 6. Design requirements (very important)

The app must look **premium, modern and professional** and be **extremely easy to use**, comparable to the best fitness apps on the App Store.

- Dark-first design with a full, well-crafted light mode. A single strong accent color (e.g. electric blue or lime) and distinct, consistent colors for Push, Pull and Rest. Define a design system: colors (asset catalog), typography scale (SF Pro, rounded numerals for stats), spacing, corner radii, reusable components (cards, buttons, chips, progress rings, set rows).
- Clean card-based layouts, generous spacing, large readable numbers, subtle gradients and materials, smooth spring animations, matched-geometry transitions, and haptic feedback on key actions (set completed, PR, timer end).
- Gym-friendly ergonomics: large tap targets, important actions reachable with the thumb, minimal typing, works great one-handed, high contrast for use in a bright or dim gym.
- Tab bar: **Home**, **Workout**, **Calendar**, **Nutrition**, **Coach** (and Settings via a profile button). Keep navigation shallow: starting a workout should take at most 2 taps from launch; logging a set at most 2 taps.
- Include empty states, loading skeletons, and friendly onboarding (3–4 screens: welcome, profile + goal, schedule, notification permission).
- Full support for Dynamic Type, VoiceOver labels, Reduce Motion, and both orientations where sensible (portrait is primary).
- App icon: create a simple, tasteful icon concept (e.g. a stylized dumbbell/plate on a gradient), plus launch screen.
- Add SwiftUI previews for the main components, with sample data.

## 7. Smart extras (include these, and add anything else clever you think is valuable)

Include the following unless technically problematic, and use your own judgment to add other genuinely useful features the user did not think of. List what you added at the end.

- Rest timer with Live Activity / Dynamic Island.
- Body weight log with a trend chart (7-day moving average), feeding back into the automatic targets.
- Weekly summary screen/notification: workouts completed, total volume, PRs, average calories/protein vs target.
- Home Screen widget (today's workout + remaining calories/protein) and optional Lock Screen widget.
- Apple Health integration (optional, permission-based): write workouts and body weight, read body weight and step count. App must work fine if the user declines.
- Favorite and recent foods / "log the same as yesterday" quick action, so repeat meals take one tap.
- Quick-add meal presets (user-saved meals with macros).
- Export data (CSV / JSON) and iCloud (CloudKit) sync if it can be added cleanly with SwiftData; otherwise structure the code so it can be added later.
- Deload / plateau detection hint (e.g. no progress on an exercise for 3–4 sessions → suggest a deload or rep-range change).
- Muscle-group weekly volume chart (sets per muscle group per week) to help balance training.
- Siri Shortcuts / App Intents: "Start my workout", "Log water", "How many calories do I have left?".
- Settings: units, rest timer defaults, schedule editor, targets override, notifications, data export, reset data, About.

## 8. Architecture and code quality

- MVVM with `@Observable` view models (or an equivalent clean architecture), feature-based folder structure (`Features/Workout`, `Features/Calendar`, `Features/Nutrition`, `Features/Coach`, `Core/DesignSystem`, `Core/Models`, `Core/Services`).
- SwiftData models for: `Exercise`, `WorkoutSession`, `ExerciseLog`, `SetEntry`, `ScheduleDay`, `UserProfile`, `NutritionTargets`, `MealEntry`, `FoodItem`, `BodyWeightEntry`, `ChatMessage`. Define relationships and delete rules carefully.
- A `ClaudeService` (network layer, protocol-based so it can be mocked), `NutritionCalculator`, `ScheduleService`, `NotificationService`, `HealthKitService`.
- Strict Swift concurrency, no force unwraps, meaningful error types, no massive views (split into small composable views).
- Unit tests for: nutrition formulas, schedule logic (including the default weekly schedule and date edge cases like week boundaries), 1RM/PR calculation, and parsing of the AI tool-use responses. A few UI tests for the main flows (start workout, log a set, finish).
- Include realistic **sample data** for previews and a debug "load demo data" option.

## 9. Process and deliverables

1. Check the environment first (Xcode version, simulators, Swift version). If something is missing, tell the user exactly what to install. Create the Xcode project (use a project generator like XcodeGen or write the project cleanly) so it opens and builds with no manual steps.
2. Present a concise plan, then build in milestones: (a) design system + data models + seeding, (b) workout logging, (c) calendar/schedule, (d) profile + targets, (e) AI coach + backend proxy, (f) nutrition dashboard, (g) extras, polish, tests.
3. After each milestone, build for the iOS Simulator and fix all warnings and errors. Run the tests. Take simulator screenshots of the main screens to verify the design looks professional; iterate on anything that looks off.
4. Write a `README.md`: features, setup, how to deploy the proxy, how to add the API key, how to run on a real iPhone (signing), and the project structure.
5. Finish with a summary: what was built, what extras you added, known limitations, and the next steps the user must do manually (Apple Developer signing, API key/proxy deploy).

## 10. Rules

- Only the exercises listed in section 2 appear in the app.
- Never commit secrets. Add a proper `.gitignore`.
- Prefer native Apple frameworks. Ask the user only if something blocks you completely; otherwise make a sensible decision, note it, and continue.
- Quality bar: this should feel like a finished product a user would pay for, not a demo.
