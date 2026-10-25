# myTime — Design Doc (v1)

**Status:** Approved design, revision 8 · 2026-10-24. Runs 1–4 (§12) are built and reviewed (0.1.0, 126 tests). Run 5 (Unlock, 0.2.0) is specified here and not built yet; its plan is `docs/superpowers/plans/2026-10-24-run-5-unlock.md`.
**Audience:** the implementing model (Codex) and the reviewer (Claude). For later changes, update this document first (see `AGENTS.md`).

**Revision 2 changes:**
- tokens reset daily at 4:00 AM, and the token cap is removed
- booking lead time is 10 min, with 5-minute start steps
- event-driven engine with no polling
- quieter UI: no claim pop-up, no pill during booked sessions, ring icon in the menu bar
- handling for nightly shutdown
- the build is split into four runs

**Revision 3 changes** (from Run 1–2 review and user testing):
- quit-first enforcement: a blocked app without access is quit on sight and the gate belongs to the app (§5.8, §6)
- no launch grace: a grant's countdown starts when it's bought (§5.3)
- Run 3 details pinned down: reply and emergency error order, booking history lines, booking-window choices, session time labels, heads-up placement (§5.3–§5.5, §7)

**Revision 4 changes** (from Run 3 user testing):
- myTime installs to `/Applications`, so it shows in the Applications folder (§3, §10.2)
- myTime can be quit, after a written reason and a 60-second wait, and stays off until it's opened again (§5.10, §7.11)
- a reminder shows when a booked session starts (§5.4, §7.6)
- no `DEV ` text in the menu bar; the panel title says "myTime · DEV" instead (§7.1, §7.2)

**Revision 5 changes** (Run 4 details pinned down):
- `submit` and `summary` take a `Locale`; `SettingsPolicy.isLoosening` and `SettingsPolicy.addAppProblem` are public for the Settings window (§5, §5.6)
- history kinds for each settings outcome, and `<date, time>` in copy means `sessionStart` (§5.6, §7.9)
- applying a day-start change doesn't clear the current tokens; they last until the new day start (§5.6)
- exact pruning cutoffs and `weeklyRetentionWeeks` (§8.2); `DurationFormat.historyDay` for the History tab (§7, §7.9)
- the Settings window refreshes every second while open (§3.6); every submitted change re-checks running apps (§6.8)
- uninstall trashes the app, then shuts down the same way Quit does (§3.2)

**Revision 6 changes** (from Run 4 user testing):
- General settings are typed, not stepped: a whole number plus a seconds/minutes/hours menu, a number for counts, an hour menu for the day start. Settings have no step size any more (§7.9, §8.1)
- setting values and summaries show exact durations (`DurationFormat.exact`), so "15 min 15 s" is never shown as "15 min" (§7)

**Revision 7 changes** (documentation only, no behavior change):
- status and workflow text now say v1 is complete; later changes follow the update-the-spec-first flow in `AGENTS.md` (§0, §12)

**Revision 8 changes** (Run 5, from the "Token System Changes" proposal of 2026-10-23):
- **Unlock** replaces Quick look, Reply mode, and grant extensions. Pick 1, 2, 5, or 10 minutes at the gate; each minute costs 1 token times the streak multiplier. One Unlock covers every app with the Unlock mode (§5.3)
- **Streak:** an Unlock bought less than 15 minutes after the last one ended, on the same day, costs twice the last multiplier (§5.3)
- the gate pause grows with the streak, up to 30 s (§5.3, §7.3)
- a 30-second warning before an Unlock ends, without taking keyboard focus (§5.3, §7.6.1)
- no countdown pill for Unlocks; the menu bar and panel show the time left (§7.1, §7.2, §7.5)
- schema 2 with a one-time migration from 0.1.0 files (§5.11)
- an app icon (§10)

---

## 0. How to use this document

- The app was built in **four runs** (§12), all complete. For a new change, describe the behavior here first, bump the revision line, then change Core with tests, then the UI. During a run, **build only that run's scope**, finish its checks, then stop.
- Read `AGENTS.md` (repo root) before starting. It holds the coding conventions and commands.
- Where this doc gives exact values, names, strings, or rules, use them **verbatim**. Where it is silent, choose the simplest thing that satisfies the rules. **Do not add features** that are not described here (the only exception is the DEV debug controls in §10.3).
- §13 lists hard rules and pitfalls. They are non-negotiable.
- At the end of each run or later change, append a section to `IMPLEMENTATION_NOTES.md` (repo root) listing: (a) every deviation from this doc and why, (b) anything you could not verify, (c) the commands you ran and their results. Do **not** commit; the reviewer commits after review.

---

## 1. Product summary

myTime is a macOS menu-bar app that makes distracting apps (Discord by default) cost something to open. The user earns **tokens** by running a **focus timer** while working. Tokens reset every day at 4:00 AM.

Opening a blocked app shows a **gate** with a mandatory pause (5 seconds, longer during a streak). Getting past it costs tokens (an **Unlock** of 1, 2, 5, or 10 minutes), uses a pre-booked **session** from a weekly allowance, or uses a once-a-week **emergency pass**. When access ends, myTime quits the app.

myTime runs all the time, restarts itself after a crash or force quit, can only be quit after a written reason and a wait, and delays any change that would make it less strict by 24 hours. It is quiet: it does no work unless something happens, and it never pops up over the user's work except when they try to open a blocked app.

It is for one person, on one Mac (Apple Silicon), installed locally without a developer certificate. No accounts, no network, no cloud. The user shuts the Mac down most nights.

### 1.1 Glossary

| Term | Meaning |
|---|---|
| **Blocked app** | An entry in the block list: display name, one or more bundle IDs, and a set of allowed access modes. |
| **Day** | Starts at `dayStartHour` (default 4:00 AM local). All "daily" things (token reset, Unlock streaks, claim budget, stats) use this boundary. The week starts Monday at the same hour. |
| **Token (◆)** | Currency earned by focus time. Spent on Unlocks. Unspent tokens and partial progress are cleared at the start of each day. There is no cap. |
| **Progress** | Vested focus seconds toward the next token (`0 ≤ progress < focusSecondsPerToken`). |
| **Focus session** | An open-ended, user-started stopwatch during which eligible time is credited. |
| **Unvested time** | Focus time since the last keyboard/mouse input. Discarded if the user turns out to be idle. |
| **Away** | State entered during focus when idle ≥ threshold, the screen locks, or the Mac sleeps. Nothing is credited while away. |
| **Unclaimed away time** | Today's accumulated away gaps. The user can count some of it as focus from the menu bar panel, within a daily budget. |
| **Gate** | Floating card shown when a blocked app is opened without access. |
| **Focus card** | Variant of the gate shown when a blocked app is opened during a focus session. |
| **Grant** | A time-limited permission for one blocked app. Only the emergency pass creates grants. (0.1.0 also had quick look and reply grants; a migrated file may still hold one until it expires.) |
| **Unlock** | Access to every blocked app with the Unlock mode, for 1, 2, 5, or 10 minutes chosen at the gate. Costs minutes × multiplier tokens. One at a time; no extensions, no refunds. |
| **Streak / multiplier** | An Unlock bought less than 15 minutes after the previous one ended, on the same day, costs twice the previous multiplier (1×, 2×, 4×, …). Otherwise it costs 1×. |
| **Booked session** | A window booked ≥ 10 min ahead during which apps with the "Sessions" mode open freely. Draws from the weekly allowance. |
| **Allowance** | Weekly budget of booked-session time (default 5 h). |
| **Emergency pass** | Once per week: typed reason + 60 s wait → 10 min access. No tokens needed. |
| **Tightening / loosening** | A settings change that makes myTime stricter / less strict. Tightening applies now; loosening waits `looseningDelaySeconds` (default 24 h). |
| **Pending change** | A scheduled loosening change. It is visible and cancellable until it applies. |
| **Trusted time** | Wall clock corrected for detected manual clock changes (§5.1). All deadlines use it. |
| **Refresh** | One run of the engine's update, triggered by an event or a scheduled wake-up (§3.5). There is no fixed tick. |

---

## 2. Key decisions and why

| Decision | Why |
|---|---|
| Menu-bar app (`LSUIElement`), no Dock icon | Must always run to enforce. The token balance should be glanceable. A Dock app is one ⌘Q away from off. |
| Blocking = **quit immediately**, show the gate for the app, relaunch it if access is bought | No official API exists. Quitting via `NSRunningApplication` needs **no permissions**. Hiding was tried in Run 1 and rejected: Electron apps un-hide themselves several times during startup, flashing black windows. Quitting on the first launch/activate event leaves no window on screen (measured). Quitting also silences the app's notifications, which are triggers. The user doesn't need to be reachable. |
| **Event-driven engine, no polling** | The user wants minimal system impact. macOS reports app launches, lock/unlock, and sleep/wake. Deadlines use one scheduled wake-up. Inactivity is sampled every 30 s, and only during focus. Per-second work happens only while a countdown is on screen. |
| Self-declared focus + idle detection (not an app allowlist) | Allowlists break on legitimate browser and doc reading. The user works mostly on the Mac, and the claim flow covers some off-screen time. |
| Vesting based on last-input timestamps | Accrual stays exact no matter how often the engine refreshes, which is what makes sparse (30 s) sampling safe. |
| 5-second pause on the gate | The pause is what weakens impulse opens. The token price mostly sets the budget. |
| 15 min → 1 token → 1 min of Unlock; the length is chosen up front; the countdown starts when it's bought; progress carries over within a day | Put the friction at the decision, not during use. 0.1.0's 30-second quick looks and in-use extensions meant constant clicking, which pushed the user to the phone. The app relaunches within about a second, and a countdown that waited for it read as broken (removed launch grace after Run 2 testing). |
| **Doubling streak instead of a daily cap** | Repeated checking gets expensive fast (four Unlocks in 20 minutes cost 31 tokens instead of 13) without a hard limit. Waiting 15 minutes, or a new day, resets it. The price is computed from the last Unlock whenever it's shown, so no timer runs. |
| **Tokens reset daily at 4:00 AM, no cap** | Resetting stops hoarding across days, which was the cap's only job. Dropping the cap removes the irritating "stop earning" state. A 4 AM boundary keeps late-night sessions intact. |
| Tokens for impulses, weekly allowance for planned sessions | Planned calls and gaming aren't the habit being broken. Booking ≥ 10 min ahead prevents impulse use. Booking is allowed during focus. |
| One Unlock mode (Quick look and Reply mode removed in Run 5) | Reply mode was the cheapest gate (1.5 min per token, guarded only by a note), so usage drifted to it. A 2- or 5-minute Unlock covers replying. No mode is a cheaper shortcut than another. |
| Weekly emergency pass | A blocker the user gets stuck in gets uninstalled. One hard, rare way out is safer. |
| **Quiet UI** | No pop-ups over work except the gate and the Unlock warning, which never takes keyboard focus. Away-time claims wait in the panel, marked by a dot on the menu bar icon. Booked sessions and Unlocks get one notice near the end, not a floating timer. The menu bar shows Unlock and session time in whole minutes, not a ticking clock. |
| Tighten now, loosen after 24 h | The user is both admin and target. The delay removes impulsive loosening. |
| launchd LaunchAgent with KeepAlive; **Quit myTime…** needs a reason and a 60 s wait | An instant Quit would unblock everything on impulse, but the user needs a way to turn myTime off, e.g. for a vacation. The reason and the wait keep that deliberate. |
| SwiftPM + shell script, no Xcode project | A generated `.pbxproj` is fragile for model-written code. SwiftPM is plain text and deterministic. |
| Four runs, pure-logic core with tests, `AGENTS.md` | The user expects to keep editing the app. Small reviewed runs, rules isolated from UI, and written conventions keep later changes contained. |

---

## 3. Architecture

### 3.1 Stack and constraints

- Toolchain: Xcode 26 / Swift 6.x, `// swift-tools-version: 6.0`, **Swift 5 language mode** for all targets (`swiftLanguageModes: [.v5]`).
- Deployment target: macOS 14.0, arm64.
- UI: SwiftUI views. AppKit for panels, windows, `NSWorkspace`, `NSRunningApplication`.
- Allowed frameworks: Foundation, AppKit, SwiftUI, Observation, CryptoKit, CoreGraphics, UniformTypeIdentifiers. **No third-party dependencies.**
- No App Sandbox, no entitlements, no hardened runtime. Ad-hoc signed (`codesign -s -`).
- **Must not use:** network APIs, UserNotifications, Accessibility (AX) APIs, AppleScript/Apple Events, Input Monitoring, Screen Recording, SMAppService, SwiftUI `Settings`/`Window` scenes.
- Info.plist: `LSUIElement = YES`. Do **not** set `NSAppSleepDisabled`.

**Resource budget (verified in manual tests):**

| Situation | Expected |
|---|---|
| Not focusing, nothing unlocked, no myTime UI open | **Zero** scheduled timers except the next deadline (day start, pending change). CPU 0.0%. Idle wake-ups ≈ 0. |
| Focusing | One wake-up every ~30 s (5 s tolerance). |
| Short countdown on screen (pill, gate, Unlock warning, open panel) | 1 Hz UI updates, only while visible. |
| Unlock active, nothing on screen | One menu bar update per minute, plus the end and warning wake-ups. |
| Memory | < 50 MB memory footprint (the Activity Monitor "Memory" column). Measured after Run 1: 16 MB. |

### 3.2 Process model and installation

One executable, `myTime`, inside `/Applications/myTime.app` (so it shows in the Applications folder; admin accounts can write there without sudo). Its behavior depends on the arguments:

| Invocation | Behavior |
|---|---|
| no arguments (build script, double-click in Finder) | **Installer mode.** Write/repair the LaunchAgent plist, bootstrap or kickstart the agent, `exit(0)`. No UI. |
| `--agent` | **Agent mode.** The actual app. Only launchd starts this. |
| `--foreground` (DEV builds only) | Run the app without launchd, for debugging. Release builds ignore it and use installer mode. |

**LaunchAgent** at `~/Library/LaunchAgents/local.mytime.agent.plist`:

| Key | Value |
|---|---|
| `Label` | `local.mytime.agent` |
| `ProgramArguments` | `[<absolute path to Contents/MacOS/myTime>, "--agent"]` |
| `RunAtLoad` | `true` |
| `KeepAlive` | `true` |
| `ThrottleInterval` | `5` |
| `ProcessType` | `Interactive` |
| `LimitLoadToSessionType` | `Aqua` |

Result: myTime starts at login and is restarted by launchd within ~5 s after any quit, crash, or force quit.

**Installer mode steps** (`Installer.installAndStart()`):
1. Resolve `Bundle.main.executableURL`. If the path does not contain `.app/Contents/MacOS/`, print `myTime must be run from myTime.app (use scripts/build.sh)` to stderr and `exit(1)`.
2. Write the plist with `PropertyListSerialization`, creating `~/Library/LaunchAgents` if needed.
3. Run `/bin/launchctl print gui/<uid>/local.mytime.agent`.
   - If it fails: `/bin/launchctl bootstrap gui/<uid> <plistPath>`.
   - Otherwise: `/bin/launchctl kickstart gui/<uid>/local.mytime.agent`.
   - `uid = getuid()`. Use `Process` and wait for exit.
4. `exit(0)`.

**Agent-mode self-heal:** at launch, on `didWakeNotification`, and on `willPowerOffNotification`, check the plist. If the file is missing or its `ProgramArguments[0]` differs from the current executable path, rewrite it. Do not bootstrap; the job is already loaded. There is no periodic check.

**Reopen:** handle `applicationShouldHandleReopen` by opening the Settings window.

**Uninstall** (`Installer.uninstall()`, only when a pending `.uninstall` change applies, §5.6):
1. AppModel saves state first.
2. `FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)`; ignore errors.
3. `Installer.stopAgent()` (§5.10): delete the plist, `launchctl bootout`, `exit(0)`. Self-heal can't rewrite the plist because the process ends here.
4. Leave `~/Library/Application Support/myTime/` in place.

**App Nap:** allowed by default. While anything time-critical is live (a gate or focus card is showing, a grant or an Unlock is active, or a booking is active), hold `ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Enforcing app limits")`. End the activity as soon as none of those are true.

### 3.3 Package layout

```
myTime App/
├── AGENTS.md                       # conventions for any agent editing this repo
├── IMPLEMENTATION_NOTES.md         # appended by each run
├── Package.swift
├── Packaging/
│   ├── Info.plist
│   └── AppIcon.icns                # generated by scripts/make-icon.swift, committed
├── scripts/
│   ├── build.sh
│   ├── make-icon.swift             # developer tool (§10.4), not part of the package
│   └── uninstall.sh
├── Sources/
│   ├── MyTimeCore/                 # Foundation + CryptoKit only. Pure logic. Fully unit-tested.
│   │   ├── Model/
│   │   │   ├── SettingKey.swift        # enum + defaults/ranges/direction (§8.1)
│   │   │   ├── Settings.swift
│   │   │   ├── BlockedApp.swift
│   │   │   ├── AccessGrant.swift
│   │   │   ├── Unlock.swift            # ActiveUnlock, UnlockStreak, UnlockOption, UnlockQuote
│   │   │   ├── Booking.swift
│   │   │   ├── Stats.swift             # DailyStats, WeeklyStats
│   │   │   ├── HistoryEvent.swift
│   │   │   ├── PendingChange.swift     # SettingChange, PendingChange, SubmitResult
│   │   │   └── PersistedState.swift
│   │   ├── Logic/
│   │   │   ├── Constants.swift         # §8.2, with DEV variants
│   │   │   ├── TrustedClock.swift
│   │   │   ├── CalendarKeys.swift
│   │   │   ├── FocusAccrual.swift
│   │   │   ├── UnlockPricing.swift     # the one pricing function (§5.3)
│   │   │   ├── UnlockEngine.swift      # EngineCore extension: buy, end, finish, warning, gate pause
│   │   │   ├── UnlockCopy.swift        # Unlock strings (§7)
│   │   │   ├── Emergency.swift
│   │   │   ├── BookingRules.swift
│   │   │   ├── SettingsPolicy.swift
│   │   │   ├── EnforcementPolicy.swift
│   │   │   ├── WakeUpPlanner.swift
│   │   │   ├── DurationFormat.swift
│   │   │   ├── EngineError.swift
│   │   │   └── EngineCore.swift        # façade: state + intents + update
│   │   └── Persistence/
│   │       ├── StateCodec.swift        # HMAC envelope
│   │       └── StateMigration.swift    # schema 1 → 2 (§5.11)
│   └── MyTimeApp/                  # AppKit + SwiftUI glue and UI
│       ├── main.swift
│       ├── MyTimeScene.swift           # SwiftUI App with a MenuBarExtra only
│       ├── AppDelegate.swift
│       ├── Engine/
│       │   ├── AppModel.swift          # @Observable @MainActor; owns EngineCore; refresh; effects
│       │   ├── Scheduler.swift         # single one-shot wake-up timer
│       │   ├── SystemEvents.swift      # workspace/distributed notification subscriptions
│       │   ├── SystemProbe.swift       # clocks, boot session UUID, idle seconds, screen lock
│       │   ├── AppMonitor.swift        # blocked-process lookup and app notifications
│       │   ├── Enforcer.swift          # applies EnforcementPolicy: quit/gate/relaunch
│       │   ├── StateStore.swift        # file IO, sentinel, tamper handling
│       │   ├── Installer.swift         # launchd install / self-heal / uninstall
│       │   └── WindowRouter.swift      # Settings & Booking NSWindows
│       └── UI/
│           ├── Theme.swift
│           ├── MenuBarLabel.swift
│           ├── MenuBarIcon.swift       # ring template image
│           ├── PopoverView.swift
│           ├── FocusRing.swift
│           ├── ClaimRow.swift
│           ├── HoldButton.swift
│           ├── OverlayPanel.swift      # NSPanel subclass + controller
│           ├── GateView.swift
│           ├── UnlockCard.swift        # gate length picker
│           ├── FocusCardView.swift
│           ├── PillView.swift
│           ├── HeadsUpView.swift       # booking 5-minute heads-up
│           ├── UnlockWarningView.swift # 30-second Unlock warning (+ controller)
│           ├── UnlockBlock.swift       # panel Unlock row and streak line
│           ├── BookingView.swift
│           └── Settings/
│               ├── SettingsView.swift  # TabView: General, Blocked Apps, Pending, History
│               ├── GeneralTab.swift
│               ├── BlockedAppsTab.swift
│               ├── PendingTab.swift
│               └── HistoryTab.swift
├── Tests/
│   └── MyTimeCoreTests/            # XCTest
└── docs/
    ├── MANUAL_TESTS.md             # appended by each run
    └── superpowers/specs/2026-09-13-mytime-design.md
```

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "myTime",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "myTime", targets: ["MyTimeApp"])],
    targets: [
        .target(name: "MyTimeCore"),
        .executableTarget(name: "MyTimeApp", dependencies: ["MyTimeCore"]),
        .testTarget(name: "MyTimeCoreTests", dependencies: ["MyTimeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
```

### 3.4 Component responsibilities and data flow

```
            ┌──────────────── MyTimeApp (AppKit/SwiftUI, @MainActor) ────────────────┐
 NSWorkspace│                                                                        │
 & distrib. │ SystemEvents ──event──▶ AppModel.refresh(reason) ◀──intents── UI views │
 notifs ───▶│                           │   ▲                     (popover, gate,    │
            │ SystemProbe ──readings───▶│   │ wake-up             pill, settings,    │
 CGEvent/   │                           │   │                     booking)           │
 sysctl ───▶│                           │ Scheduler (one-shot timer)                 │
            │                           │                                            │
            │            update(input)  ▼   │ UpdateResult (effects + next wake-up)  │
            │                    ┌── EngineCore (MyTimeCore, pure) ──┐               │
            │                    │ PersistedState + EngineRuntime    │               │
            │                    │ FocusAccrual · BookingRules ·     │               │
            │                    │ SettingsPolicy · TrustedClock ·   │               │
            │                    │ EnforcementPolicy · WakeUpPlanner │               │
            │                    └───────────────────────────────────┘               │
            │                           │                                            │
            │   Enforcer ◀──reconcile───┤──state──▶ StateStore ──▶ state.json (HMAC) │
            │     │ quit/gate/relaunch                                               │
            │     ▼                                                                  │
            │ NSRunningApplication · OverlayPanel (gate/card, pill, heads-up, warning) │
            └────────────────────────────────────────────────────────────────────────┘
```

- **EngineCore** (Core) owns all rules and state. It never reads the clock or the system; everything arrives through `UpdateInput` or method parameters. It returns effects and the next wake-up instead of performing side effects.
- **AppModel** (App) holds `var core: EngineCore`. On every trigger it reads `SystemProbe`, calls `core.update`, runs effects, lets `Enforcer` act on the triggering process, saves, and reschedules `Scheduler`. All UI reads from and sends intents to `AppModel`.
- **Enforcer** (App) turns `EnforcementPolicy` decisions into quit calls and gate presentation.

### 3.5 Refresh cycle (replaces any fixed tick)

**Triggers**, each calling `AppModel.refresh(reason:)`:

| Reason | Source |
|---|---|
| `.launch` | Agent start (calls `core.start` instead of `core.update`, then the startup sweep) |
| `.appLaunched(process)` / `.appActivated(process)` | `NSWorkspace` `didLaunchApplication`, `didActivateApplication`, `didUnhideApplication` |
| `.appTerminated(pid)` | `NSWorkspace` `didTerminateApplication` |
| `.screenLocked` / `.screenUnlocked` | `DistributedNotificationCenter.default()` names `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` |
| `.willSleep` / `.didWake` | `NSWorkspace` `willSleepNotification` / `didWakeNotification` (call `core.handleWillSleep` / `core.handleDidWake`, §5.2) |
| `.willPowerOff` | `NSWorkspace` `willPowerOffNotification` (refresh, self-heal, save immediately) |
| `.clockChanged` | `.NSSystemClockDidChange`, `.NSSystemTimeZoneDidChange` |
| `.wakeUp` | `Scheduler` timer fired |
| `.intent` | Any user action that changes state (run after the intent) |
| `.panel` | Menu bar panel appeared, then every 1 s while it stays open |

**`refresh(reason)` steps:**
1. Read `SystemProbe`: wall `Date()`, continuous seconds, uptime seconds, boot session UUID, idle seconds, screen locked. For `.screenLocked` / `.screenUnlocked`, force `isLocked` to `true` / `false` rather than reading it, because the session dictionary can lag the notification.
2. `AppMonitor.runningBlockedAppIDs()` → `Set<UUID>` of blocked-app IDs that have a running `.regular` process.
3. `let result = core.update(UpdateInput(...))`.
4. Execute `result.effects` (§4.9).
5. If the reason is `.appLaunched` or `.appActivated` for a blocked process, run `Enforcer.reconcile(process, trigger:)`. For `.appTerminated`, close any overlay owned by that pid.
6. Update the activity assertion (§3.2) and the UI timers (§3.6).
7. Save (atomic write) if anything other than `state.clock` changed since the last save, or if the saved clock is ≥ 60 s old. Updates run on every app switch, so saving clock-only changes every time would write to disk constantly. The once-a-second `.panel` and `.uiTick` refreshes save only when the last save is ≥ 60 s old, because during focus each one credits another second, except that any change to `state.unlock` or `state.unlockStreak` saves at once (so a warning already shown is never repeated after a restart). Also save immediately on `.willSleep` and `.willPowerOff`.
8. `Scheduler.schedule(result.nextWakeUp)`. This replaces any pending timer. `critical` wake-ups use `tolerance = 1 s`; others use `5 s`. `nil` means no timer.

### 3.6 UI timers (exist only while their UI is visible)

| Timer | Interval | Runs while |
|---|---|---|
| Gate/focus card clock (pause countdown, 60 s timeout, emergency wait, and `refresh(.uiTick)` so tokens and Unlock prices stay current) | 1 s | gate or focus card visible |
| Grant countdown (`refresh(.uiTick)`: the pill and menu bar label read current time) | 1 s | a running blocked app has an active grant |
| Menu bar booking label | 60 s | a booking countdown is shown in the menu bar |
| Menu bar Unlock label | `Constants.unlockSecondsPerUnit` (60 s; DEV 10 s) | an Unlock is active and no grant countdown is shown |
| Unlock warning countdown | 1 s | the Unlock warning is visible |
| Panel refresh (`refresh(.panel)`) | 1 s | menu bar panel open |
| Settings refresh (`refresh(.panel)`, so "Applies in" and applied changes stay current) | 1 s | Settings window open |
| Heads-up auto-hide | one-shot 8 s | heads-up visible |

All UI timers use `Timer` on `RunLoop.main` in `.common` mode, with `tolerance = 0.1 × interval`. For display, compute `displayNow = Date() + core.state.clock.offsetSeconds` without running an update.

---

## 4. Data model (MyTimeCore)

All types are `Codable`, `Equatable`, and **`public` with explicit `public init`s**. JSON: `JSONEncoder.dateEncodingStrategy = .secondsSince1970`, `outputFormatting = [.sortedKeys]`.

### 4.1 PersistedState

```swift
public struct PersistedState: Codable, Equatable {
    public var schemaVersion: Int              // 2 (Constants.schemaVersion); 0.1.0 wrote 1 (§5.11)
    public var settings: Settings
    public var pending: [PendingChange]
    public var tokens: Int
    public var progressSeconds: Double         // vested progress toward next token
    public var tokensDayKey: String            // day key the tokens belong to (§5.2 daily reset)
    public var focus: FocusSession?            // nil = not focusing
    public var grants: [AccessGrant]
    public var unlock: ActiveUnlock?           // the one Unlock, until it's finished (§5.3)
    public var unlockStreak: UnlockStreak?     // the last finished Unlock, for pricing (§5.3)
    public var bookings: [Booking]
    public var daily: [String: DailyStats]     // key: CalendarKeys.dayKey
    public var weekly: [String: WeeklyStats]   // key: CalendarKeys.weekKey
    public var history: [HistoryEvent]         // newest last, capped (§8.2)
    public var clock: TrustedClockState
    public var tamperNoticeUntil: Date?        // show tamper banner until this time
    public var migrationNotice: String?        // one-time panel notice after migration (§5.11)

    public static func fresh(now: Date, timeZone: TimeZone) -> PersistedState      // defaults, Discord blocked, 0 tokens
    public static func penalized(now: Date, timeZone: TimeZone) -> PersistedState  // §5.7
}

public struct FocusSession: Codable, Equatable {
    public var startedAt: Date
    public var creditedSeconds: Double         // vested seconds credited this session
}
```

### 4.2 Settings and blocked apps

```swift
public struct Settings: Codable, Equatable {
    public var numbers: [String: Int]          // keyed by SettingKey.rawValue — NOT [SettingKey: Int]
    public var apps: [BlockedApp]
    public subscript(key: SettingKey) -> Int   // numbers[key.rawValue] ?? key.defaultValue
}

public enum AccessMode: String, Codable, CaseIterable { case unlock, booked }   // titles: "Unlock", "Sessions"

public struct BlockedApp: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bundleIDs: [String]
    public var modes: Set<AccessMode>
}
```

Default block list (in `PersistedState.fresh`): one entry with `name: "Discord"`, `bundleIDs: ["com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary"]`, `modes: [.unlock, .booked]`.

### 4.3 AccessGrant and Unlock

```swift
public enum GrantKind: String, Codable { case quickLook, reply, emergency }   // quickLook and reply: only in files from 0.1.0

public struct AccessGrant: Codable, Equatable, Identifiable {
    public var id: UUID
    public var appID: UUID
    public var kind: GrantKind
    public var createdAt: Date
    public var expiresAt: Date    // createdAt + duration
    public var tokensSpent: Int
    public var note: String?      // emergency reason (or a 0.1.0 reply note)
}
```

A grant is **active** while `now < expiresAt`. The remaining time shown is `expiresAt − now`. Nothing creates `.quickLook` or `.reply` grants any more; one migrated from 0.1.0 runs until it expires and can't be extended.

```swift
public struct ActiveUnlock: Codable, Equatable {
    public var appID: UUID          // the app it was bought from (history only; it covers every .unlock app)
    public var startedAt: Date
    public var endsAt: Date         // startedAt + lengthSeconds
    public var lengthSeconds: Int
    public var multiplier: Int
    public var cost: Int
    public var dayKey: String       // dayKey(startedAt)
    public var warned: Bool         // the warning was shown or skipped (§5.3)
    public var endedAt: Date?       // set by endUnlock(); the next update finishes the Unlock
    public func isActive(at now: Date) -> Bool   // endedAt == nil && now < endsAt
    public var warningAt: Date { get }           // endsAt − min(unlockWarningLead, lengthSeconds / 2)
}

public struct UnlockStreak: Codable, Equatable {
    public var lastMultiplier: Int
    public var lastEnd: Date        // scheduled end, or when End Unlock was pressed if earlier
    public var dayKey: String       // day key of that Unlock's purchase
}

public struct UnlockOption: Equatable {
    public var units: Int           // 1, 2, 5, 10
    public var lengthSeconds: Int   // units × unlockSecondsPerUnit
    public var cost: Int            // units × multiplier
}

public struct UnlockQuote: Equatable {
    public var multiplier: Int
    public var options: [UnlockOption]   // in unlockLengthUnits order
    public var resetsAt: Date?           // nil when multiplier == 1
}
```

### 4.4 Booking

```swift
public struct Booking: Codable, Equatable, Identifiable {
    public var id: UUID
    public var start: Date
    public var durationSeconds: Int
    public var extensionSeconds: Int   // 0 or bookingExtensionSeconds (once)
    public var createdAt: Date
    public var canceledAt: Date?
    public var endedAt: Date?          // set when ended early by user
    public var appOpened: Bool         // any booked-mode app ran during the window
    public var warned: Bool            // heads-up already emitted
    public var end: Date { start + durationSeconds + extensionSeconds }
}
```

### 4.5 Stats and history

```swift
public struct DailyStats: Codable, Equatable {
    public var focusSeconds: Double = 0
    public var tokensEarned: Int = 0
    public var tokensSpent: Int = 0
    public var backedOff: Int = 0
    public var claimedAwaySeconds: Double = 0
    public var unclaimedAwaySeconds: Double = 0
    public var unlocks: Int = 0               // Unlocks bought
    public var unlockSeconds: Double = 0      // Unlock time actually used (to the purchase day)
    public var unlockTokens: Int = 0          // tokens spent on Unlocks
    public var highestMultiplier: Int = 0
}

public struct WeeklyStats: Codable, Equatable {
    public var emergencyUses: Int = 0
    public var allowanceForfeited: Bool = false   // set by tamper penalty
    public var unlocks: Int = 0
    public var unlockSeconds: Double = 0
    public var unlockTokens: Int = 0
    public var highestMultiplier: Int = 0
}

public enum HistoryKind: String, Codable {
    case focusStarted, focusEnded, tokenEarned, dayReset, awayClaimed, quickLook, reply, extended,
         backedOff, bookingCreated, bookingCanceled, bookingEnded, bookingExtended,
         emergency, changeScheduled, changeApplied, changeCanceled, appAdded, appRemoved,
         tamperDetected, quit, unlockBought, unlockEnded
    // quickLook, reply, extended: only in history from 0.1.0; kept so old events still decode
}

public struct HistoryEvent: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kind: HistoryKind
    public var text: String        // pre-rendered line, e.g. "Unlock in Discord · 5 min · 2× · 10 ◆"
}
```

`DailyStats` and `WeeklyStats` decode every field with `decodeIfPresent(…) ?? default` (hand-written `init(from:)`, synthesized `encode`), so files missing the Unlock fields still load.

### 4.6 Settings changes

```swift
public indirect enum SettingChange: Codable, Equatable {
    case setNumber(key: SettingKey, value: Int)
    case addApp(BlockedApp)
    case removeApp(id: UUID)
    case setMode(appID: UUID, mode: AccessMode, enabled: Bool)
    case uninstall

    public var fieldKey: String   // "number:<key>", "app:<id>" (add & remove), "mode:<appID>:<mode>", "uninstall"
}

public struct PendingChange: Codable, Equatable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var applyAt: Date
    public var change: SettingChange
    public var summary: String     // e.g. "Session time per week: 5h → 8h"
}

public enum SubmitResult: Equatable { case applied, scheduled(applyAt: Date), noChange }
```

### 4.7 Trusted clock state

```swift
public struct TrustedClockState: Codable, Equatable {
    public var offsetSeconds: Double = 0
    public var lastWall: Double = 0         // seconds since 1970, at the last update
    public var lastContinuous: Double = 0   // CLOCK_MONOTONIC_RAW seconds, at the last update
    public var bootSessionID: String = ""
}
```

### 4.8 Runtime-only state (not persisted)

```swift
public struct EngineRuntime: Equatable {
    public var unvestedSeconds: Double = 0
    public var lastUptime: Double? = nil
    public var blockedRunningAtLastUpdate: Bool = false
    public var awayStartUptime: Double? = nil   // non-nil = away
    public var lastActiveBookingID: UUID? = nil
    public var sleepStartContinuous: Double? = nil  // continuous clock when the Mac went to sleep
}
```

On launch the runtime starts fresh, so unvested time is lost on restart. That is intentional and errs on the strict side.

AppModel constructs the engine with `EngineCore(state: loaded)` and immediately calls `core.start(input)`.

### 4.9 Update input, result, and effects

```swift
public struct UpdateInput {
    public var wall: Date
    public var continuous: Double       // CLOCK_MONOTONIC_RAW, seconds
    public var uptime: Double           // CLOCK_UPTIME_RAW, seconds
    public var bootSessionID: String
    public var idleSeconds: Double
    public var isLocked: Bool
    public var runningAppIDs: Set<UUID> // blocked-app IDs with a running regular process
}

public struct WakeUp: Equatable { public var date: Date; public var critical: Bool }

public struct UpdateResult: Equatable {
    public var effects: [EngineEffect]
    public var nextWakeUp: WakeUp?
}

public enum EngineEffect: Equatable {
    case terminateIfNotAllowed(appID: UUID)
    case bookingStarted(bookingID: UUID)
    case bookingHeadsUp(bookingID: UUID)
    case unlockWarning
    case unlockEnded
    case uninstall
}
```

AppModel handling:

| Effect | Action |
|---|---|
| `terminateIfNotAllowed` | For each running process of that app: if `!core.isAllowed(appID)`, terminate it (§6.3). |
| `bookingStarted` | Show the session-start reminder (§7.6). |
| `bookingHeadsUp` | Show the heads-up panel (§7.6). |
| `unlockWarning` | Show the Unlock warning (§7.6.1). |
| `unlockEnded` | Close the Unlock warning if it's showing. |
| `uninstall` | `Installer.uninstall()`. |

---

## 5. Rules (implemented in MyTimeCore)

`EngineCore` exposes the API below. Intents use `core.now`, the trusted time from the last update. Because the engine may sit idle for minutes between refreshes, AppModel runs `refresh(.intent)` **immediately before and after** every intent; otherwise a grant bought after a quiet period would be timestamped in the past. Throwing intents throw `EngineError`, which has `userMessage: String` (§7.9).

```swift
public struct EngineCore {
    public var state: PersistedState
    public var runtime: EngineRuntime
    public private(set) var now: Date
    public let timeZone: TimeZone        // AppModel passes .current; tests pass a fixed zone
    public init(state: PersistedState, timeZone: TimeZone)   // now = Date(timeIntervalSince1970: state.clock.lastWall) until start()

    // Lifecycle
    public mutating func start(_ input: UpdateInput) -> UpdateResult     // §5.2 launch handling, then update
    public mutating func update(_ input: UpdateInput) -> UpdateResult
    public mutating func handleWillSleep(_ input: UpdateInput) -> UpdateResult
    public mutating func handleDidWake(_ input: UpdateInput) -> UpdateResult

    // Focus
    public mutating func startFocus()
    public mutating func endFocus()
    public var secondsToNextToken: Double { get }     // max(0, P − progress − unvested)
    public var isAway: Bool { get }
    public var claimableSeconds: Double { get }       // min(today.unclaimed, budget remaining)
    public mutating func confirmClaim()
    public mutating func dismissClaim()

    // Spending (§5.3)
    public var activeUnlock: ActiveUnlock? { get }                       // state.unlock if isActive(at: now)
    public func remaining(of unlock: ActiveUnlock) -> Double             // max(0, endsAt − now)
    public func unlockQuote(at date: Date) -> UnlockQuote                // prices for an Unlock bought at `date`
    public func gatePauseSeconds(appID: UUID, at date: Date) -> Int
    public mutating func buyUnlock(appID: UUID, lengthSeconds: Int, expectedCost: Int) throws -> ActiveUnlock
    public mutating func endUnlock()
    public mutating func dismissMigrationNotice()                        // migrationNotice = nil
    public mutating func recordBackedOff(appID: UUID)
    public var emergencyUsesLeftThisWeek: Int { get }
    public mutating func useEmergency(appID: UUID, reason: String) throws -> AccessGrant

    // Bookings
    public func validateBooking(start: Date, durationSeconds: Int) -> EngineError?
    public mutating func createBooking(start: Date, durationSeconds: Int) throws -> Booking
    public mutating func cancelBooking(id: UUID) throws
    public mutating func endBooking(id: UUID)
    public func canExtendBooking(id: UUID) -> Bool
    public mutating func extendBooking(id: UUID) throws
    public var activeBooking: Booking? { get }
    public var upcomingBookings: [Booking] { get }     // not canceled, start > now, sorted
    public func allowanceRemaining(weekOf date: Date) -> Int
    public var bookingDurations: [Int] { get }          // booking window duration choices (§5.4)
    public func bookingDays() -> [Date]                 // booking window day choices (§5.4)
    public func bookingStartSlots(onDayOf day: Date) -> [Date]   // booking window start choices (§5.4)

    // Enforcement queries
    public func isAllowed(appID: UUID) -> Bool
    public func activeGrant(appID: UUID) -> AccessGrant?
    public func remaining(of grant: AccessGrant) -> Double   // max(0, expiresAt − now)
    public func app(id: UUID) -> BlockedApp?
    public func app(bundleID: String) -> BlockedApp?

    // Settings
    public mutating func submit(_ change: SettingChange, locale: Locale) -> SubmitResult
    public func summary(of change: SettingChange, locale: Locale) -> String   // §5.6 summary against the current settings
    public mutating func cancelPending(id: UUID)
    public func setting(_ key: SettingKey) -> Int
    public var today: DailyStats { get }
    public var nextDayStart: Date { get }

    #if DEV_TIMESCALE
    public mutating func devAddToken()
    public mutating func devAddProgress(seconds: Double)   // goes through vest()
    public mutating func devSimulateNewDay()               // sets tokensDayKey = "" so the next update resets
    #endif
}
```

Every mutation the user would care about appends a `HistoryEvent`.

**Effects come only from `start`, `update`, and the sleep/wake handlers.** Intents never return effects. If an intent causes something that needs a side effect (e.g. `endBooking` or `endUnlock` should close apps), the follow-up `refresh(.intent)` detects the transition and emits the effect.

**`update(input)` order:**
1. Trusted clock (§5.1) → sets `now`
2. Daily reset (§5.2)
3. Apply due pending changes (§5.6)
4. Focus accrual and away (§5.2)
5. Grant expiry, then finishing the Unlock, then the Unlock warning (§5.3)
6. Booking transitions (§5.4)
7. Pruning, only when the daily reset ran this update (§8.2)
8. Next wake-up (§5.9)

Effects from steps 5 and 6 are combined in that order, skipping any effect already in the list, so a grant or Unlock that ends as a session ends closes the app once. The daily reset needs no Unlock step: pricing compares day keys.

### 5.1 Time

| Clock | Source | Used for |
|---|---|---|
| **Trusted time** | `wall + offsetSeconds` | All timestamps, deadlines, day/week keys, bookings, pending changes |
| **Continuous** | `clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1e9` (keeps counting during sleep) | Detecting manual wall-clock changes |
| **Uptime** | `clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1e9` (stops during sleep) | Focus crediting and away gaps |

Boot session ID: `sysctlbyname("kern.bootsessionuuid")`, read as a C string.

**TrustedClock.update** (pure):

```
func update(state: inout TrustedClockState, wall: Double, continuous: Double, bootSessionID: String) -> Double:
    if state.bootSessionID == bootSessionID && state.lastWall > 0:
        drift = (wall - state.lastWall) - (continuous - state.lastContinuous)
        if abs(drift) > Constants.clockJumpTolerance:     // 120 s
            state.offsetSeconds -= drift
    state.lastWall = wall
    state.lastContinuous = continuous
    state.bootSessionID = bootSessionID
    return wall + state.offsetSeconds
```

This works for any interval between updates. Moving the clock while the Mac is on gets cancelled. Across a reboot (every night for this user), the offset is kept but can't be re-verified (§14).

**CalendarKeys** (use `TimeZone.current`, with `h = dayStartHour`):
- `shifted(date)` = `Calendar(identifier: .gregorian).date(byAdding: .hour, value: -h, to: date)`.
- `dayKey(date, h)` → `"yyyy-MM-dd"` from gregorian components of `shifted(date)`. Do not use DateFormatter.
- `weekKey(date, h)` → `"YYYY-Www"` from `Calendar(identifier: .iso8601)` `yearForWeekOfYear` and `weekOfYear` of `shifted(date)`. Weeks start Monday at `h`.
- `nextDayStart(after date, h)` → the next local time with hour `h`, minute 0, second 0, strictly after `date` (`Calendar.nextDate(after:matching:matchingPolicy: .nextTime)`).
- `nextWeekStart(after date, h)` → the next Monday at hour `h`, strictly after `date`.

### 5.2 Focus, earning, and the daily reset (FocusAccrual)

Settings used: `focusSecondsPerToken` (P), `idleThresholdSeconds` (I), `autoEndAwaySeconds`, `awayClaimSecondsPerDay`, `dayStartHour`.

**Daily reset** (update step 2):

```
key = dayKey(now)
if state.tokensDayKey != key:
    if tokens > 0: history(.dayReset, "New day · <tokens> unused tokens cleared")
    tokens = 0; progressSeconds = 0; runtime.unvestedSeconds = 0
    state.tokensDayKey = key
    mark "reset ran" (enables pruning this update)
```

A focus session in progress continues through the reset. An active Unlock runs to its end. Other daily limits need no reset logic because they read `daily[dayKey(now)]`, and the Unlock streak compares day keys (§5.3).

**Launch handling — `start(input)`:**

```
hadPrevious = state.clock.lastWall > 0                             // capture BEFORE updating the clock
prevTrusted = state.clock.lastWall + state.clock.offsetSeconds
run TrustedClock.update → now
downtime = now.timeIntervalSince1970 - prevTrusted
if state.focus != nil && hadPrevious && downtime > idleThresholdSeconds:
    end focus WITHOUT vesting; history(.focusEnded, "Focus ended · myTime wasn't running")
runtime = EngineRuntime()
runtime.lastActiveBookingID = activeBooking?.id   // a session already live before the restart isn't announced again
return update(input)   // runs the daily reset, expiries, etc.
```

A KeepAlive relaunch after a crash (~5 s) keeps focus. A shutdown overnight ends it with no credit, and the downtime is not claimable.

**Per-update accrual** (update step 4):

```
elapsed = runtime.lastUptime == nil ? 0 : max(0, input.uptime - runtime.lastUptime!)
lastInputUptime = input.uptime - input.idleSeconds
defer { runtime.lastUptime = input.uptime; runtime.blockedRunningAtLastUpdate = !input.runningAppIDs.isEmpty }

// A. Away
if let awayStart = runtime.awayStartUptime:
    if !input.isLocked && lastInputUptime > awayStart + 1:
        // user returned
        runtime.awayStartUptime = nil
        gap = lastInputUptime - awayStart
        if gap >= Constants.minAwayGap: today.unclaimedAwaySeconds += gap
        runtime.unvestedSeconds = 0
        // nothing from this interval is credited as focus; it is part of the gap
        return
    if state.focus != nil && input.uptime - awayStart >= autoEndAwaySeconds:
        end focus WITHOUT vesting; history(.focusEnded, "Focus ended after <short> away")
    return

guard state.focus != nil else { return }

// B. Eligible time since last update (no credit while any blocked app was running)
if !runtime.blockedRunningAtLastUpdate: runtime.unvestedSeconds += elapsed

// C. Idle or locked → away; the idle minutes don't count
if input.isLocked || input.idleSeconds >= I:
    runtime.awayStartUptime = lastInputUptime
    runtime.unvestedSeconds = 0
    return

// D. Vest everything before the last input; time since the last input stays unvested
trailing = min(runtime.unvestedSeconds, input.idleSeconds)
vest(runtime.unvestedSeconds - trailing)
runtime.unvestedSeconds = trailing
```

- Away tracking continues after an auto-end, so the gap is still recorded when the user returns.
- **Sampling independence:** vesting uses the last-input timestamp, so time before each input is credited exactly however often updates run. The one unavoidable difference: coming back from away is noticed at the next check (up to `focusCheckInterval` later), and that stretch counts as away time instead of focus. So *focus + unclaimed away time* is the same at any update frequency (±2 s), and focus alone differs by at most one check interval per return. A unit test enforces this (§11.1).

**Sleep and wake:**
- `handleWillSleep(input)`: run `update(input)`. Set `runtime.sleepStartContinuous = input.continuous`. Then, if focusing and not away, set `awayStartUptime = input.uptime - input.idleSeconds` and `unvestedSeconds = 0`.
- `handleDidWake(input)`: if focusing and `input.continuous − sleepStartContinuous ≥ autoEndAwaySeconds`, end focus without vesting (history `"Focus ended · Mac was asleep"`). If away, set `awayStartUptime = input.uptime`, so time asleep, and time idle before sleeping, is never claimable. Set `runtime.lastUptime = input.uptime` and `sleepStartContinuous = nil`, then run `update(input)`.

**vest(x):**

```
guard x > 0
today.focusSeconds += x
state.focus?.creditedSeconds += x
progressSeconds += x
while progressSeconds >= P:
    progressSeconds -= P; tokens += 1; today.tokensEarned += 1
    history(.tokenEarned, "Earned a token")
```

**Claims:**
- `claimableSeconds = max(0, min(today.unclaimedAwaySeconds, awayClaimSecondsPerDay − today.claimedAwaySeconds))`.
- `confirmClaim()`: `x = claimableSeconds`. If `x > 0`, then `today.claimedAwaySeconds += x`, `vest(x)`, and history `"Counted <short(x)> away as focus"`. Always set `today.unclaimedAwaySeconds = 0` afterwards.
- `dismissClaim()`: `today.unclaimedAwaySeconds = 0`.
- Claims work whether or not a focus session is active.

**startFocus():** no-op if already focusing. Otherwise set `focus = FocusSession(startedAt: now, creditedSeconds: 0)`, `unvestedSeconds = 0`, `awayStartUptime = nil`, and append history `"Started focus"`. Keep `lastUptime`.

**endFocus():** `vest(unvestedSeconds)`, then `unvestedSeconds = 0`, `focus = nil`, `awayStartUptime = nil`, and append history `"Focus ended · <short(creditedSeconds)>"`.

**Carry-over:** progress is never reset between sessions. Only the daily reset clears it.

### 5.3 Tokens and Unlock

Tokens buy an **Unlock**: a window of 1, 2, 5, or 10 minutes, chosen at the gate, that covers every blocked app whose modes contain `.unlock`. Only one Unlock exists at a time, so Unlocks never stack. Grants (§4.3) now come only from the emergency pass. Nothing is ever extended, refunded, or renewed automatically.

Constants (§8.2): `unlockLengthUnits` `[1, 2, 5, 10]`, `unlockSecondsPerUnit` (60), `unlockStreakGap` (900 s), `unlockWarningLead` (30 s), `unlockWarningMinimum` (5 s), `gatePauseCap` (30 s).

**Pricing (`UnlockPricing`, pure).** This is the only place prices come from. The gate, the panel, the warning, and `buyUnlock` all call it, so the price shown is the price charged.

```swift
public enum UnlockPricing {
    public static func multiplier(after previous: UnlockStreak?, at date: Date, dayKey: String) -> Int
    public static func quote(after previous: UnlockStreak?, at date: Date, dayKey: String, nextDayStart: Date) -> UnlockQuote
}
```

```
multiplier(previous, date, dayKey):
    if previous != nil && previous.dayKey == dayKey && date − previous.lastEnd < unlockStreakGap:
        return previous.lastMultiplier × 2          // no cap; it becomes unaffordable on its own
    return 1

quote(previous, date, dayKey, nextDayStart):
    m = multiplier(previous, date, dayKey)
    options = unlockLengthUnits.map { units → (units, units × unlockSecondsPerUnit, units × m) }
    resetsAt = m > 1 ? min(previous.lastEnd + unlockStreakGap, nextDayStart) : nil
```

- A gap of exactly `unlockStreakGap` resets to 1×. A new day (§5.1 day key) also starts at 1×, even if the last Unlock ended less than 15 minutes earlier.
- `previous.dayKey` is the day the previous Unlock was **bought**. An Unlock bought at 3:55 AM that runs past 4:00 AM still belongs to the old day.
- Booked sessions and emergency passes neither count toward nor reset the streak.

**unlockQuote(at date):** `previous` is the current Unlock if `state.unlock != nil`, as `UnlockStreak(lastMultiplier: multiplier, lastEnd: endedAt ?? endsAt, dayKey: dayKey)`; otherwise `state.unlockStreak`. Day key and next day start are computed at `date`. The gate and panel pass display time, so prices drop back to 1× live when the reset time passes.

**buyUnlock(appID, lengthSeconds, expectedCost):** throws, in this order, if:
- the app ID is not in the block list → `.unknownApp`
- the app lacks `.unlock` → `.modeNotAllowed`
- focus is active → `.focusActive`
- `state.unlock != nil` → `.unlockActive`
- `lengthSeconds` isn't one of the quote's lengths → `.invalidLength`
- the quote's cost for that length (at `now`) differs from `expectedCost` → `.priceChanged`
- `tokens < cost` → `.notEnoughTokens`

`expectedCost` is what the gate showed. If the price or balance changed while the gate was open (the streak reset, the 4:00 AM reset), nothing is charged and the gate shows the new prices.

Otherwise:
- `tokens -= cost`; today: `tokensSpent += cost`, `unlocks += 1`, `unlockTokens += cost`, `highestMultiplier = max(highestMultiplier, m)`; this week's `WeeklyStats`: `unlocks`, `unlockTokens`, and `highestMultiplier` the same way (`WeeklyStats` has no `tokensSpent`).
- `state.unlock = ActiveUnlock(appID, startedAt: now, endsAt: now + lengthSeconds, lengthSeconds, multiplier: m, cost, dayKey: dayKey(now), warned: false, endedAt: nil)`. The countdown starts now (there is no launch grace) and runs on trusted time through sleep, quitting the app, and myTime restarts.
- History (`.unlockBought`): `"Unlock in <App> · <short(length)> · <m>× · <cost> ◆"`, followed by `" · <short(gap)> after the last"` when `state.unlockStreak?.dayKey == dayKey(now)`, where `gap = now − state.unlockStreak.lastEnd`. E.g. `"Unlock in Discord · 1 min · 2× · 2 ◆ · 3 min after the last"`.

**endUnlock():** if `activeUnlock != nil`, set `state.unlock.endedAt = now`. No refund. The follow-up update finishes it, so the streak gap starts now and the next Unlock gets cheaper sooner.

**Finishing** (update step 5, after grant expiry), when `state.unlock` has `endedAt != nil` or `now ≥ endsAt`:
- `end = min(endedAt ?? endsAt, endsAt)`. If the expiry is processed late (after sleep, after a restart), the scheduled end still counts.
- `state.unlockStreak = UnlockStreak(lastMultiplier: multiplier, lastEnd: end, dayKey: dayKey)`.
- `used = end − startedAt`; add it to `unlockSeconds` in `daily[unlock.dayKey]` and `weekly[weekKey(startedAt)]`.
- History (`.unlockEnded`): `"Unlock ended early · <short(used)> used"` if `endedAt < endsAt`, otherwise `"Unlock ended · <short(used)> used"`.
- `state.unlock = nil`. Emit `.terminateIfNotAllowed(appID)` for **every** app with `.unlock`, then `.unlockEnded`. Apps a booking still allows stay open (§6.3 checks `isAllowed`).

**Warning** (update step 5, after finishing). Let `u = activeUnlock`, `remaining = u.endsAt − now`, `lead = min(unlockWarningLead, u.lengthSeconds / 2)` (so a 1-minute Unlock warns at its halfway point). When `!u.warned && remaining ≤ lead`:
- `remaining < unlockWarningMinimum` → set `warned = true` and emit nothing (a late wake or relaunch with only seconds left).
- otherwise, if some app in `runningAppIDs` has `.unlock` and isn't **kept open by a booking**, set `warned = true` and emit `.unlockWarning`.
- otherwise do nothing yet; a covered app may still be opened before the end.

An app is kept open by a booking when it has `.booked` and some booking with `canceledAt == nil` and `endedAt == nil` has `start ≤ u.endsAt < end`. `warned` is saved with the Unlock, so a restart never repeats the warning.

**gatePauseSeconds(appID, at date):** `p = setting(.gatePauseSeconds)`. If the app has `.unlock`: `max(p, min(Constants.gatePauseCap, p × unlockQuote(at: date).multiplier))`. Otherwise `p`. The gate fixes it when it opens. Default: 5 s at 1×, 10 s at 2×, 20 s at 4×, 30 s from 8×.

**Grant expiry** (update step 5): remove grants with `now ≥ expiresAt`. Emit `.terminateIfNotAllowed(appID)` for each.

**recordBackedOff(appID):** `today.backedOff += 1`, history `"Backed off from Discord"`.

**isAllowed(appID)** is true if any of:
- an active grant exists for the app
- `activeUnlock != nil` and the app's modes contain `.unlock`
- `activeBooking != nil` and the app's modes contain `.booked`

So turning `.unlock` off for one app during an Unlock (a tightening change, applied at once) closes that app on the next sweep (§6.8), while the Unlock keeps its end time for the others.

**Worked example** (release values):

| Time | Bought | Gap since last ended | Multiplier | Cost | Ends |
|---|---|---|---|---|---|
| 2:00 PM | 5 min | — | 1× | 5 | 2:05 PM |
| 2:08 PM | 5 min | 3 min | 2× | 10 | 2:13 PM |
| 2:16 PM | 2 min | 3 min | 4× | 8 | 2:18 PM |
| 2:21 PM | 1 min | 3 min | 8× | 8 | 2:22 PM |
| 2:40 PM | 5 min | 18 min | 1× | 5 | 2:45 PM |

### 5.4 Booked sessions (BookingRules)

Settings used: `weeklyAllowanceSeconds`, `bookingLeadSeconds`, `bookingMaxSeconds`, `bookingExtensionSeconds`. Constants: `bookingMinSeconds` (30 min), `bookingStartStepSeconds` (5 min), `bookingDurationStepSeconds` (15 min), `bookingHorizonSeconds` (7 days), `bookingHeadsUp` (5 min).

**State of a booking at `now`:**
- *canceled*: `canceledAt != nil`
- *upcoming*: not canceled, `now < start`
- *active*: not canceled, `endedAt == nil`, `start ≤ now < end`
- *finished*: not canceled, and either `endedAt != nil` or `now ≥ end`

**Charged seconds** (what counts against the allowance):
- canceled → 0
- upcoming or active → `durationSeconds + extensionSeconds`
- finished and `!appOpened` → 0
- finished and `appOpened` → `min(duration + extension, roundUpToMinute((endedAt ?? end) − start))`

`allowanceRemaining(weekOf date)`:
- if `weekly[weekKey(date)].allowanceForfeited` → 0
- otherwise `max(0, weeklyAllowanceSeconds − Σ charged for bookings whose start is in that week)`

A booking counts entirely against the week it **starts** in.

**validateBooking(start, duration)** returns the first failing rule:
1. `start < now + bookingLeadSeconds` → `.bookingTooSoon`
2. `start > now + bookingHorizonSeconds` → `.bookingTooFar`
3. `duration < bookingMinSeconds || duration > bookingMaxSeconds || duration % bookingDurationStepSeconds != 0` → `.invalidDuration`
4. overlaps any upcoming or active booking (`start < other.end && other.start < start + duration`) → `.bookingOverlap`
5. `allowanceRemaining(weekOf: start) < duration` → `.allowanceExceeded`

Start times are not validated for alignment; the UI offers 5-minute slots. Booking is allowed during focus.

**createBooking:** throws `validateBooking`'s error if any. Otherwise appends `Booking(start, durationSeconds, createdAt: now)`. History (`.bookingCreated`): `"Booked a session · <short(duration)>"`.

**cancelBooking:** only if the booking exists and is upcoming (otherwise `.cannotCancel`). Sets `canceledAt = now`. History (`.bookingCanceled`): `"Canceled a session · <short(duration)>"`.

**endBooking:** if the booking exists and is active, set `endedAt = now`; otherwise do nothing. It adds no history: the follow-up update records "Session ended" and emits the terminate effects.

**canExtendBooking / extendBooking:** all of these must hold (otherwise `.cannotExtendBooking`):
- the booking is active
- `extensionSeconds == 0` and `bookingExtensionSeconds > 0`
- `allowanceRemaining(weekOf: start) ≥ bookingExtensionSeconds`
- the new end does not overlap the next upcoming booking

Then `extensionSeconds = bookingExtensionSeconds`. History (`.bookingExtended`): `"Extended session · +<short(bookingExtensionSeconds)>"`, e.g. `"Extended session · +15 min"`.

**Booking window choices** (all in the engine's time zone, calendar days from midnight):
- `bookingDurations`: `bookingMinSeconds` through `bookingMaxSeconds` in `bookingDurationStepSeconds` steps.
- `bookingStartSlots(onDayOf:)`: times on that calendar day at multiples of `bookingStartStepSeconds` from midnight, from the first one ≥ `now + bookingLeadSeconds` up to the last one before the next midnight, keeping only those ≤ `now + bookingHorizonSeconds`. So every slot passes validation rules 1–2.
- `bookingDays()`: midnight of today and the next 6 days, keeping only days with at least one start slot.

**Transitions** (update step 6):
- If a booking is active and its id differs from `runtime.lastActiveBookingID`, emit `.bookingStarted`.
- If a booking is active and `runningAppIDs` contains any app with `.booked`, set `appOpened = true`.
- If a booking is active, `!warned`, and `end − now ≤ bookingHeadsUp`, set `warned = true` and emit `.bookingHeadsUp`.
- If `runtime.lastActiveBookingID` is non-nil and that booking is no longer active, append history (`.bookingEnded`) `"Session ended"` and emit `.terminateIfNotAllowed` for every app with `.booked`.
- Finally, set `runtime.lastActiveBookingID = activeBooking?.id`.

### 5.5 Emergency pass

- `emergencyUsesLeftThisWeek = max(0, emergencyPerWeek − weekly[weekKey(now)].emergencyUses)`.
- The UI handles reason entry and the `emergencyWaitSeconds` countdown (§7.3). Cancelling during the wait does **not** use the pass.
- **useEmergency(appID, reason):** `reason` is trimmed. Throws, in this order: `.unknownApp` if the app isn't blocked, `.reasonTooShort` if `reason.count < Constants.minEmergencyReason /*15*/`, `.emergencyUnavailable` if no uses are left. The pass works whatever modes the app has.
  - Then: `emergencyUses += 1`; if focusing, `endFocus()`.
  - Create an `.emergency` grant with `duration = emergencyAccessSeconds`, `tokensSpent 0`, `note = reason`.
  - History: `"Emergency access to Discord — “<reason>”"`.

### 5.6 Settings and pending changes (SettingsPolicy)

`public enum SettingsPolicy` holds the two pure checks, `isLoosening(_:settings:)` and `addAppProblem(bundleID:path:ownBundleID:apps:)`. `submit`, `summary`, `cancelPending`, and apply-due are `EngineCore` methods.

**isLoosening(change, settings)** (for `.setNumber`, compare the clamped value):

| Change | Loosening when |
|---|---|
| `.setNumber(key, v)` | `looserWhen == .higher`: `v > current`; `.lower`: `v < current`; `.anyChange`: `v != current` |
| `.addApp` | never |
| `.removeApp` | always |
| `.setMode(_, _, enabled)` | `enabled == true` and mode not currently enabled |
| `.uninstall` | always |

**submit(change, locale):**

```
clamp .setNumber values to the key's range (§8.1)
remove pending items with the same fieldKey (no history)
if change is a no-op (same number; mode already in that state, or the app is missing; app already present by any bundle ID; removing a missing app):
    return .noChange
summary = summary(of: change, locale)
if isLoosening:
    append PendingChange(applyAt: now + setting(.looseningDelaySeconds), summary)
    history(.changeScheduled, "Scheduled: <summary> · applies <sessionStart(applyAt)>")
    return .scheduled(applyAt)
apply(change)
history(.appAdded for .addApp, otherwise .changeApplied, "<summary>")
return .applied
```

- **Applying `dayStartHour`** (now or when due) also sets `tokensDayKey = dayKey(now)` under the new hour, so the change itself doesn't clear tokens. The next reset happens at the new day start.
- `Array.removeAll { … }` closures that read `now` while mutating `state` break Swift's exclusivity rule; copy `now` into a local first.

- **Changing the loosening delay itself:** shortening it is loosening, so it waits out the *current* delay.
- **Apply due** (update step 3): remove every pending item with `now ≥ applyAt`, then in `applyAt` order apply each one and append history `"Applied: <summary>"` (kind `.appRemoved` for `.removeApp`, otherwise `.changeApplied`). For `.uninstall`, emit `.uninstall`; it comes first in the update's effect list. If the target app no longer exists (`.removeApp`, `.setMode`), drop the item silently.
- **cancelPending(id):** remove it and append history `"Canceled: <summary>"`. Cancelling is always immediate.

**Summaries** (exact formats):
- `"<Setting title>: <old> → <new>"` using `DurationFormat.setting(key, value)`
- `"Add <App>"`, `"Remove <App>"`
- `"Turn on <Mode title> for <App>"`, `"Turn off <Mode title> for <App>"`
- `"Uninstall myTime"`

Mode titles: unlock → "Unlock", booked → "Sessions". Turning Unlock on is loosening (waits the delay); turning it off is tightening (applies now, then the sweep closes apps it no longer covers).

**addAppProblem(bundleID, path, ownBundleID, apps) → String?**, checked in this order:
1. `bundleID` nil or empty → "That app can't be blocked."
2. equals `ownBundleID` → "myTime can't block itself."
3. `path` starts with `/System/` → "System apps can't be blocked."
4. an app in `apps` already has it → "<that app's name> is already blocked."
5. otherwise `nil`.

### 5.7 Integrity and tamper handling

**File:**
- release: `~/Library/Application Support/myTime/state.json`
- DEV: `state-dev.json`

**Envelope:**

```json
{ "v": 1, "payload": "<base64 of JSON-encoded PersistedState>", "mac": "<lowercase hex HMAC-SHA256 of the payload bytes>" }
```

- Key: `SymmetricKey(data: SHA256.hash(data: Data("myTime.integrity.v1.7c1e9b4a-5d2f-4e8a-9f61-2b3c4d5e6f70".utf8)))`.
- `StateCodec.decode(data) -> DecodeResult` returns `.ok(PersistedState)`, `.migrated(PersistedState)`, or `.tampered`, and never throws. It returns `.tampered` for unparseable envelopes, bad base64, bad hex, a MAC mismatch, an unknown `schemaVersion`, or payload decode failure. Verify with `HMAC<SHA256>.isValidAuthenticationCode(_:authenticating:using:)`. After the MAC check, a payload with `schemaVersion` 1 is migrated (§5.11) and returned as `.migrated`; 2 is decoded and returned as `.ok`.
- `StateCodec.seal(_ payload: Data) throws -> Data` (internal) wraps payload bytes in the envelope; `encode` uses it, and tests use it to build schema-1 files.
- Write with `Data.write(to:options: .atomic)`.

**Load logic (StateStore):**

| Situation | Result |
|---|---|
| File present, `.ok` | Use it. |
| File present, `.migrated` | Save it at once (atomic), then use it. Not tamper. |
| File missing, UserDefaults bool `mytime.initialized` (DEV: `mytime.dev.initialized`) false | `PersistedState.fresh(now: Date())`. Set the sentinel true **after the first successful save**. |
| File missing but sentinel true | Tamper → penalized state. |
| File present, `.tampered` | Rename the file to `state.tampered-<unix>.json`, then use the penalized state. |

**`PersistedState.penalized(now)`** = `fresh(now)`, plus:
- `tokens = 0`
- `weekly[thisWeek].allowanceForfeited = true`
- `weekly[thisWeek].emergencyUses = 99`
- `daily[today].claimedAwaySeconds = 1_000_000`
- no Unlock and no streak (as in `fresh`), so the next Unlock costs 1×, once tokens are earned again
- `tamperNoticeUntil = now + 7 days`
- history `.tamperDetected`, text `"Saved data was edited outside myTime. Balances were reset."`

User-added blocked apps are lost. That's accepted.

### 5.8 Enforcement policy (pure)

```swift
public enum EnforcementTrigger { case launched, activated, startupSweep }
public enum EnforcementAction: Equatable { case allow, terminate, terminateAndShowGate, terminateAndShowFocusCard }

public struct EnforcementContext {
    public var terminationPending: Bool      // myTime already asked this pid to quit
    public var isAllowed: Bool
    public var focusActive: Bool
    public var gateShowingForThisApp: Bool   // gate/card slot is showing for this blocked app
    public var gateShowingForOtherApp: Bool  // gate/card slot is showing for a different blocked app
}

public static func decide(trigger: EnforcementTrigger, context: EnforcementContext) -> EnforcementAction
```

Rules, first match wins:
1. `terminationPending` → `.terminate` (the Enforcer treats a repeat as a no-op)
2. `isAllowed` → `.allow`
3. `gateShowingForThisApp` → `.terminate` (reopened while its gate is up: quit quietly, the gate stays)
4. `trigger == .startupSweep` → `.terminate`
5. `gateShowingForOtherApp` → `.terminate`
6. `focusActive` → `.terminateAndShowFocusCard`
7. otherwise → `.terminateAndShowGate`

### 5.9 Next wake-up (WakeUpPlanner, update step 8)

The earliest of these candidates that is strictly after `now` (overdue items are handled earlier in the same update, and ignoring them prevents a busy loop). On a tie, the critical candidate wins. Returns `nil` if there are none:

| Candidate | Critical |
|---|---|
| `expiresAt` of each active grant | yes |
| `endsAt` of the active Unlock | yes |
| `warningAt` of the active Unlock, if `!warned` | no |
| `start` of each upcoming booking | yes |
| `end` of the active booking | yes |
| `end − bookingHeadsUp` of the active booking, if `!warned` and in the future | no |
| `applyAt` of each pending change | no |
| `nextDayStart` | no |
| `now + Constants.focusCheckInterval` if `state.focus != nil` or `runtime.awayStartUptime != nil` | no |

Booking starts wake the engine so the start reminder shows on time. Access itself is evaluated when an app is launched or activated, and every refresh updates `now` first. The streak reset needs no wake-up; pricing computes it when a price is shown.

### 5.10 Quitting (Quit.swift)

`quit(reason:) throws`:
1. Trim the reason. Fewer than `Constants.minQuitReason` (15) characters → `reasonTooShort`.
2. If focusing, `endFocus()` (vests as usual).
3. Append history (`.quit`) `"Quit myTime — “<reason>”"`.

The Quit window (§7.11) runs the `Constants.quitWait` countdown before calling it. Then AppModel saves and calls `Installer.stopAgent()`: remove the LaunchAgent plist, `launchctl bootout gui/<uid>/local.mytime.agent`, `exit(0)`. With the plist gone, nothing restarts myTime (not even a login) until the user opens it from Applications, which runs installer mode (§3) and starts the agent again. Tokens, sessions, and history are kept.

### 5.11 Migration from schema 1 (`StateMigration`, Run 5)

Runs once, on the first launch of 0.2.0, inside `StateCodec.decode` after the MAC check (so a valid old file never looks tampered). `static func migrateV1(_ json: inout [String: Any])` (internal) works on the `JSONSerialization` payload, the only place that knows the schema-1 shape:

1. **Apps:** each app's `modes` becomes `["unlock"]` if it contained `"quickLook"` or already contained `"unlock"` (a schema-1 file saved by a pre-release Run 5 build), plus `"booked"` if it contained `"booked"`. `"reply"` alone doesn't enable Unlock, since that would be a loosening change. A pending `setMode` for `"unlock"` is kept as is.
2. **Pending changes:** a `setMode` with mode `"quickLook"` becomes the same change with mode `"unlock"`, keeping its `id`, `createdAt`, and `applyAt`; its summary becomes `"Turn on Unlock for <App>"`. A `setMode` with mode `"reply"` is dropped. A `setNumber` whose key was removed (§8.1) is dropped. Everything else is kept.
3. **Settings numbers:** remove `quickLookSecondsPerToken`, `quickLookMaxTokens`, `replyTokenCost`, `replySeconds`, `replyPerDay`.
4. **Daily stats:** remove `quickLooks` and `replies` (the daily reply count). Lenient decoding (§4.5) fills the Unlock fields.
5. **Kept as is:** tokens, progress, focus, grants (an active quick look or reply grant runs until it expires and can't be extended), bookings, weekly stats, history (old events keep their labels), clock, tamper notice. No Unlock and no streak, so the first Unlock costs 1×.
6. **Notice:** `schemaVersion = 2` and `migrationNotice` = the concatenation of:
   - `"Quick look and Reply mode are now Unlock. Choose 1, 2, 5, or 10 minutes at the gate, 1 token a minute. An Unlock bought less than 15 minutes after the last one costs twice as much."`
   - for each app that had `"reply"` but neither `"quickLook"` nor `"unlock"`: `" Unlock is off for <App> because Quick look was off."`
   - if one pending change was dropped: `" A pending Quick look or Reply mode change was canceled."`; if `n > 1`: `" <n> pending Quick look or Reply mode changes were canceled."`

The panel shows the notice until **Dismiss** (§7.2). DEV builds show the same text.

Running 0.1.0 after migrating would decode the file as tampered (it doesn't know `"unlock"`). Don't.

---

## 6. Enforcement (MyTimeApp)

### 6.1 Detection

- `SystemEvents` forwards `NSWorkspace` app notifications (main queue) to `AppModel.refresh`. The running application is `userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication`.
- A process is a **blocked process** if its `bundleIdentifier` exactly equals one of a blocked app's `bundleIDs` **and** `activationPolicy == .regular`. Match exactly, never by prefix; Discord's helper processes must not match.
- There is no polling. Coverage comes from launch/activate/unhide notifications, the startup sweep, and expiry wake-ups (via `terminateIfNotAllowed`). A blocked app without access never keeps running, so nothing needs re-checking while a gate is up.

### 6.2 Enforcer.reconcile(process, trigger)

Build an `EnforcementContext` from `core` and overlay state, call `EnforcementPolicy.decide`, then act:

| Action | Behavior |
|---|---|
| `.allow` | Nothing. |
| `.terminate` | §6.3. |
| `.terminateAndShowGate` | Capture `process.bundleURL`, quit (§6.3), present the gate for `(app, bundleURL)`. |
| `.terminateAndShowFocusCard` | Capture `process.bundleURL`, quit (§6.3), present the focus card for `(app, bundleURL)`. |

### 6.3 Terminating

Add the pid to `terminationPending`, then call `process.terminate()`. After 5 s (`Constants.forceQuitAfter`, one-shot timer), if `!process.isTerminated`, call `process.forceTerminate()`. Remove the pid when the terminate notification arrives.

### 6.4 Overlay ownership

- **Overlay slot:** at most one gate or focus card at a time. It belongs to a blocked **app** (the app itself is no longer running).
- **Pill:** at most one. It shows the running blocked app that has an active **grant**, choosing the one with the least remaining time. Unlocks and booked sessions never show a pill.
- **Heads-up:** at most one, independent of the other overlays.
- **Unlock warning:** at most one, independent of the others. It closes on `unlockEnded`.

### 6.5 Gate outcomes

**Backed off rule:** whenever a gate or focus card closes without the app being opened, call `core.recordBackedOff` exactly once.

| User action | Result |
|---|---|
| Never mind / Esc / 60 s of no interaction | Backed off, close the gate. |
| Unlock succeeds | Buy with the shown price as `expectedCost` (the countdown starts now), close the gate, relaunch the app about a second later with `NSWorkspace.shared.openApplication(at: bundleURL, configuration:)` (`activates = true`). No pill. |
| Unlock refused with `.priceChanged` or `.notEnoughTokens` | Nothing is charged. Clear the chosen length and show the error line; the gate stays open with the new prices. |
| Start Focus (no length affordable) | Backed off, `core.startFocus()`, close the gate. |
| Book a session… | Backed off, open the Booking window, close the gate. |
| Emergency flow completes | Same as a successful Unlock, except a pill appears once the app is running. |
| The app is opened again while its gate is up | It's quit quietly (§5.8 rule 3); the gate stays. |
| Focus becomes active while the gate is open | Swap the gate content to the focus card. |

Any interaction with the gate (click, typing, choosing a length) resets the 60 s timeout. The timeout is suspended during the emergency wait. Timing out at any other point behaves like Never mind, and an emergency pass not yet used stays unused.

### 6.6 Focus card outcomes

| User action | Result |
|---|---|
| Back to work / Esc / 60 s timeout | Backed off, close the card. |
| End focus… | `core.endFocus()`, then swap to the gate (with the full pause from `gatePauseSeconds(appID:at:)`). |

### 6.7 Startup sweep

On agent launch, after `core.start`, call `reconcile(trigger: .startupSweep)` for every running blocked process. Blocked apps launched at login, and apps whose access ended while myTime wasn't running, get quit silently.

### 6.8 Adding an app while it runs

In Settings, if the chosen app is running, the confirmation says it will be closed. After **any** submitted change, AppModel runs `Enforcer.sweep()` (`reconcile(trigger: .startupSweep)` for every running blocked process), so an added app, or one that just lost a mode it was using, closes without a gate.

---

## 7. UX flows, screens, and copy

- **Tone:** calm, neutral, factual. No guilt, no exclamation marks, no red, no sounds, no bouncing.
- **Formatting helpers (`DurationFormat`):**
  - `clock(s)`: `m:ss` under 1 h, `h:mm:ss` otherwise
  - `short(s)`: `"45 s"`, `"12 min"`, `"2h 10m"`
  - `hourOfDay(h)`: locale time style, e.g. `"4:00 AM"`
  - `exact(s)`: whole seconds without rounding: `"45 s"`, `"15 min"`, `"15 min 15 s"`, `"1h 30m"`, `"1h 0m 5s"`
  - `setting(key, v)`: formats by the key's unit (`exact` for seconds, the number for counts, `hourOfDay` for hours)
  - `timeOfDay(date, timeZone, locale)`: locale time style, e.g. `"8:05 PM"`
  - `dayLabel(date, now, timeZone, locale)`: `"Today"`, `"Tomorrow"`, or the abbreviated weekday (`"Wed"`), by calendar day
  - `sessionStart(date, now, timeZone, locale)`: `"<dayLabel> <timeOfDay>"`, e.g. `"Today 8:05 PM"`. Copy that says `<date, time>` uses this.
  - `historyDay(date, now, timeZone, locale)`: `"Today"`, `"Yesterday"`, or the localized template `"EEEEMMMd"` (`"Thursday, Sep 10"`), by calendar day
- **Token glyph:** `◆` (U+25C6). Pluralize "token"/"tokens".
- **Unlock strings (`UnlockCopy`, Core, tested):**
  - `streakLine(multiplier:resetsAt:timeZone:locale:)` → `"<m>× — resets at <timeOfDay(resetsAt)>"`, e.g. `"4× — resets at 2:28 PM"`
  - `nextUnlockLine(multiplier:resetsAt:timeZone:locale:)` → `"Next Unlock: <m>× until <timeOfDay(resetsAt)>"`
  - `unlockButton(lengthSeconds:cost:)` → `"Unlock <short(length)> · <cost> token(s)"`, e.g. `"Unlock 5 min · 10 tokens"`
  - `needsMore(n)` → `"Needs <n> more"`
  - `shortOfTokens(needed:lengthSeconds:)` → `"Unlock needs <n> more token(s) for <short(length)>."`
  - `closesIn(appNames:remaining:)` → one name: `"<App> closes in <clock(remaining)>"`; several: `"Unlocked apps close in <clock(remaining)>"`
  - `menuBarRemaining(s)` → `short(ceil(s / unlockSecondsPerUnit) × unlockSecondsPerUnit)`, at least one unit, e.g. 241 s → `"5 min"`

### 7.1 Menu bar label (MenuBarLabel)

The label shows an icon plus optional text, with `monospacedDigit()`. Precedence, first match:

| State | Icon | Text | Updates |
|---|---|---|---|
| A running blocked app has an active grant | SF Symbol `hourglass` | `clock(least remaining)` | every 1 s |
| An Unlock is active (whether or not a covered app is running) | SF Symbol `hourglass` | `UnlockCopy.menuBarRemaining(endsAt − now)` | every `unlockSecondsPerUnit` |
| Active booking and a `.booked` app is running | SF Symbol `hourglass` | `short(end − now)` | every 60 s |
| Focusing, away | SF Symbol `pause.circle` | `"<tokens>"` | on refresh |
| Focusing | MenuBarIcon ring (§7.1.1) | `"<tokens>"` | on refresh (~30 s) |
| Otherwise | SF Symbol `diamond.fill` | `"<tokens>"` | on refresh |

**Claim dot:** when `claimableSeconds ≥ Constants.minClaimable` and the state is not one of the countdown rows, draw a small dot into the top-right of the icon image itself, with a clear halo so it never touches the glyph. It stays monochrome (template), like system menu bar indicators.

No `DEV ` prefix: on a display with a notch there is no room for it. DEV builds mark themselves in the panel title instead (§7.2).

#### 7.1.1 MenuBarIcon

- A 16×16 pt **template** `NSImage`, drawn with `NSImage(size:flipped:drawingHandler:)`.
- It has a 1.5 pt circle outline and a filled pie wedge from 12 o'clock clockwise, proportional to `(progress + unvested) / P`.
- The wedge is quantized to 12 steps. Cache the 13 images and only swap when the step changes.

### 7.2 Menu bar panel (MenuBarExtra `.window` style, width 320)

`.onAppear` starts the 1 s panel refresh timer and `.onDisappear` stops it. Top to bottom, 16 pt padding, 16 pt spacing:

1. **Header row:** "myTime" (headline; "myTime · DEV" in DEV builds). On the right, a gear button that opens Settings. If `pending.count > 0`, a small capsule `"<n> pending"` next to it opens Settings on the Pending tab.
2. **Tamper banner** (only if `now < tamperNoticeUntil`): "Saved data was edited outside myTime, so balances were reset." Secondary style.
   **Migration notice** (only if `migrationNotice != nil`, §5.11): the notice text (secondary) and a plain button **Dismiss**, which calls `core.dismissMigrationNotice()`.
3. **Focus block:** FocusRing (160 pt diameter, 10 pt stroke), filled to `(progress + unvested) / P`.

   | State | Ring center | Caption | Button |
   |---|---|---|---|
   | Not focusing | `clock(secondsToNextToken)`, "to next token" below | — | **Start Focus** (prominent) |
   | Focusing | `clock(secondsToNextToken)`, "to next token" below | "This session · `short(creditedSeconds + unvested)`" | **End Focus** |
   | Away | same | "Paused — no activity" | **End Focus** |

4. **Claim row** (only if `claimableSeconds ≥ Constants.minClaimable`; see §7.7):
   - text `"You were away <short(today.unclaimedAwaySeconds)> during focus today."`
   - HoldButton
   - a plain text button **Dismiss**
5. **Tokens row:** `◆ <tokens> tokens`, with the secondary caption `"Resets at <hourOfDay(dayStartHour)>"` on the right.
   **Unlock block** (`UnlockBlock`), with `q = unlockQuote(at: displayNow)`:
   - During an Unlock: row `"Unlock · <clock(remaining)> left"` with a bordered button **End Unlock** (`core.endUnlock()`, which quits covered apps; no refund). Below it, if `q.multiplier > 1`, `UnlockCopy.nextUnlockLine(q.multiplier, q.resetsAt)` (secondary).
   - No Unlock and `q.multiplier > 1`: `UnlockCopy.streakLine(q.multiplier, q.resetsAt)` (secondary).
   - Otherwise nothing.
6. **Sessions block:**
   - Title "Sessions", with "`short(allowanceRemaining(thisWeek))` left this week" on the right.
   - If a session is active: row "Live · `short(end − now)` left", with **Extend `short(bookingExtensionSeconds)`** (e.g. "Extend 15 min"; only if `canExtendBooking`) and **End**.
   - Up to 3 upcoming rows: "`sessionStart(start)` · `short(duration)`" (e.g. "Today 8:05 PM · 1h") with **Cancel**.
   - Button **Book a Session…** opens the Booking window.
7. **Today strip:** three equal columns: "Focus" / `short(today.focusSeconds)`, "Earned" / `tokensEarned`, "Backed off" / `backedOff`.
8. **DEV only:** a row with "+1 token", "+5 min progress", "New day", "Reset state".
9. **Quit myTime…** (small, borderless, secondary) opens the Quit window (§7.11).

### 7.3 Gate (OverlayPanel, key-capable, width 420, centered on the screen with the mouse)

**Layout:**
- App icon (64 pt, from `NSWorkspace.shared.icon(forFile: bundleURL.path)`).
- Title: **"Still want to open <App>?"**
- Subtitle: `"<n> tokens · 1 token = <short(P)> of focus"` (e.g. "15 min"; "15 s" in DEV).
- **Pause phase** (`core.gatePauseSeconds(appID:at: displayNow)`, fixed when the gate opens: 5 s by default, growing with the Unlock streak up to 30 s, §5.3): a thin ring drains linearly around the icon, labeled `"Options unlock in <s>s"`. Everything except **Never mind** is disabled, but the Unlock lengths and prices are already visible.
- **Choose phase:** show only the rows whose mode is enabled for the app. While the gate is open its clock refreshes the engine every second (§3.6), so the balance and prices stay current.
  - **Unlock card** (`UnlockCard`, if `.unlock` is enabled), with `q = core.unlockQuote(at: displayNow)`:
    - Header: "Unlock" (headline). On the right, if `q.multiplier > 1`, `UnlockCopy.streakLine(q.multiplier, q.resetsAt)` (secondary), e.g. after the 2:13 PM Unlock ends: "4× — resets at 2:28 PM".
    - **Lengths:** four equal buttons, one per `q.options` entry, each with two lines: `short(lengthSeconds)` and, below, `"<cost> ◆"` if `cost ≤ tokens`, otherwise `UnlockCopy.needsMore(cost − tokens)`. Unaffordable lengths are disabled. **Nothing is preselected**, so every Unlock is an explicit choice. The chosen length is marked with the accent tint (a bordered style, not prominent). If the chosen length becomes unaffordable, the choice is cleared.
    - **Unlock button** (bordered, full width): `"Choose a length"` (disabled) until a length is chosen, then `UnlockCopy.unlockButton(length, cost)` for the current quote, e.g. **"Unlock 5 min · 10 tokens"**. It buys with that quote's `lengthSeconds` and `cost` as `expectedCost`.
    - **No length affordable** (the shortest option costs more than `tokens`): replace the length buttons and the Unlock button with `UnlockCopy.shortOfTokens(needed: shortest.cost − tokens, lengthSeconds: shortest.lengthSeconds)`, the line `"Your next token is <short(secondsToNextToken)> of focus away."`, and the button **Start Focus**. The header's streak line stays, showing when the price drops.
  - **Sessions line** (if `.booked` is enabled):
    - with an upcoming booking: "Next session: `sessionStart(start)`"
    - otherwise: "Sessions: none booked" plus a link-style button **Book a session…**
    - If `.booked` is the only mode, the subtitle becomes "<App> is available during booked sessions."
- **Never mind:** full-width prominent button at the bottom, with `.keyboardShortcut(.cancelAction)` (Esc). Nothing in the gate is bound to Return.
- **Footer link** (below Never mind; hidden while the emergency sub-flow is showing):
  - if `emergencyUsesLeftThisWeek > 0`: "Emergency access"
  - otherwise, disabled text: "Emergency access used · resets Monday"

**Emergency sub-flow** (replaces the choose-phase content):
1. Title "Emergency access", body "Once a week. After a <wait>-second wait you'll get <access in min> minutes." ("minute" when it's 1). Text field placeholder "What's the emergency?" Buttons **Start wait** (enabled once the trimmed reason has ≥ 15 characters) and **Back** (returns to the choose phase).
2. Waiting: large `"Opening in <s>s"` and button **Cancel**, captioned "Your pass won't be used." Cancel returns to step 1 with the reason kept.
3. Ready: button **"Open <App> for <access in min> min"**. This calls `useEmergency`; on success, the app relaunches as after an Unlock (§6.5).

**Never mind** is the only prominent button in the gate. The panel grows and shrinks with its content and keeps its top edge (NSHostingView does this by default; verified).

**Gate states** (summary):

| State | Shows |
|---|---|
| Pause | Lengths and prices (disabled), token balance, streak line if above 1×; only **Never mind** works |
| Ready | Lengths, Unlock button, sessions line, Emergency, Never mind |
| Some lengths unaffordable | Those lengths disabled, labeled "Needs <n> more" |
| No length affordable | Tokens needed for the shortest length, next-token line, **Start Focus**, streak line if above 1× |
| Focusing | The focus card (§7.4); no prices |
| Unlock not enabled for this app | No Unlock card; sessions line, Emergency, Never mind |

Errors thrown by core intents appear as one secondary line under the relevant card, using `EngineError.userMessage`.

### 7.4 Focus card (same panel slot, width 360)

- Title **"You're focusing"**
- Body: `"<short(secondsToNextToken)> to your next token."`
- Buttons: **Back to work** (prominent) and **End focus…**. Esc = Back to work.

### 7.5 Countdown pill (OverlayPanel, non-activating, not key) — grants only (emergency, and quick look or reply grants left from 0.1.0)

- Position: top-right of the main screen's `visibleFrame`, 12 pt inset, or wherever the user last dragged it (stored in UserDefaults `mytime.pillOrigin`, used only if still on a connected screen). Capsule, ~220×44 pt.
- Content: app icon (18 pt) + text.
  - `"<App> · clock(remaining)"`
  - for emergency grants: `"Emergency · clock(remaining)"`
- **Last 10 s:** the text and icon tint cross-fade to the warm color (0.3 s). No pulsing or scaling. There is no extend button; nothing can be extended.
- Hidden when no running blocked app has an active grant.

### 7.6 Session notices (OverlayPanel, non-activating, top-right like the pill, width 260)

**Start reminder**, on the `bookingStarted` effect, always shown:
- Title "Your session has started" (headline), then "Until `timeOfDay(end)`" (secondary).
- Button **Open <App>** for the first app with `.booked` that isn't running and whose bundle ID resolves via `NSWorkspace.urlForApplication(withBundleIdentifier:)`. It opens the app and closes the notice. No button if there's no such app.

**Heads-up**, on the `bookingHeadsUp` effect:
- Shown once per booking, and only if a `.booked` app is running. Otherwise it is skipped.
- Text: `"Session ends in <short(end − now)>"` (e.g. "Session ends in 5 min"). Button **Extend `short(bookingExtensionSeconds)`** if `canExtendBooking`, otherwise no button.
- Placement: 12 pt inside the top-right of the main screen's `visibleFrame`, or 8 pt below the pill if the pill is showing.
- Both notices use the same placement, auto-hide after 8 s, and clicking outside does nothing. A new notice replaces a visible one.
- Booked sessions keep this 5-minute heads-up; the Unlock warning below is separate.

#### 7.6.1 Unlock warning (`UnlockWarningController`, OverlayPanel, non-activating, **not key**, width 260)

Shown on the `unlockWarning` effect (Core already checked that a covered app is running and no booking keeps it open, §5.3). It never takes keyboard focus, so typing in the app continues.
- Title (headline): `UnlockCopy.closesIn(appNames:remaining:)` with the names of running blocked apps that have `.unlock`, e.g. "Discord closes in 0:30". It counts down every second while visible (§3.6).
- Below (secondary), with `q = unlockQuote(at: displayNow)`, only if `q.multiplier > 1`: `UnlockCopy.nextUnlockLine(q.multiplier, q.resetsAt)`. (It is above 1× during an Unlock, except one that runs past the day start.)
- Button **End now** (bordered): `model.endUnlock()`. No extend button.
- Placement: as the heads-up (§7.6), 8 pt below the pill if one shows. No auto-hide; it closes on `unlockEnded` or **End now**. Clicking outside does nothing.

### 7.7 HoldButton and claim behavior

- **Label:** `"Hold to count <short(claimableSeconds)>"`. Append `" (daily limit)"` if `claimableSeconds < today.unclaimedAwaySeconds`.
- **Fill:** left-to-right over `Constants.holdToConfirm` (2 s) while pressed, using `onLongPressGesture(minimumDuration: 2, pressing:)`. Releasing early resets it.
- **Completion:** calls `model.confirmClaim()` (→ `core.confirmClaim()` + `refresh(.intent)`).
- **Accessibility:** an action named "Count away time" that confirms immediately.
- The claim never pops up. It is shown only via the dot (§7.1) and the panel row (§7.2).

### 7.8 Booking window (AppKit NSWindow via WindowRouter, "Book a Session", ~380×300, not resizable)

- Opening the window refreshes the engine first, so the choices use the current time.
- **Day picker** (menu): `bookingDays()`, labeled with `dayLabel`. Defaults to the first.
- **Start picker** (menu): `bookingStartSlots(onDayOf: day)`, labeled with `timeOfDay`. Defaults to the first slot, and resets to the first slot when the day changes. In DEV builds, list only the first 30.
- **Duration picker** (menu): `bookingDurations`, formatted with `short`. Defaults to the first.
- A line: `"<short(allowanceRemaining(weekOf: start))> left in that week"`.
- A live validation line: `validateBooking(...)?.userMessage`.
- Buttons: **Cancel** and **Book** (default, disabled while invalid). On success, close the window.

### 7.9 Settings window (AppKit NSWindow hosting SwiftUI `TabView`, ~560×520, "myTime Settings")

Header on every tab: "Changes that make myTime stricter apply right away. Changes that loosen it apply after `short(looseningDelaySeconds)`."

If `abs(clock.offsetSeconds) > 120`, also show: "Your Mac's clock was changed. myTime is ignoring the change (`short(abs(offset))`)."

Open it with `WindowRouter.showSettings(tab:)` from the panel gear, the pending capsule (Pending tab), and `applicationShouldHandleReopen`. If it's already open, switch to the requested tab and bring it forward. While it's open, the 1 s Settings refresh runs (§3.6).

**General tab**
- A `Form` grouped by §8.1 "Group". Each row has the title and a typed value:
  - seconds keys: a whole-number field plus a menu of `DurationUnit` (seconds, minutes, hours). It opens in `DurationUnit.natural(for:)`, the largest unit that shows the value as a whole number (zero shows as minutes). The stored value is number × unit.
  - count keys: a whole-number field
  - `dayStartHour`: a menu of `hourOfDay(0…23)`
- Under a row whose text isn't a whole number: "Enter a whole number." Under a value outside the key's range: `rangeMessage` = "Choose between `setting(lower)` and `setting(upper)`." Apply Changes is disabled while any row has a message.
- The `dayStartHour` row shows the caption "Changing this always waits `short(looseningDelaySeconds)`."
- Rows edit a local **draft**. The bottom bar has **Revert** and **Apply Changes** (both enabled only when the draft differs).
- Apply submits each changed key, then shows an alert titled "Settings updated" listing `"Applied now: …"` and `"Applies <date, time>: …"` lines.

**Blocked Apps tab**
- Rows: icon, name, and two toggles: "Unlock", "Sessions".
  - Turning a toggle **on** shows an alert "This loosens myTime" / "It will apply <date, time>." with **Schedule** and **Cancel**. Turning one **off** applies immediately.
  - A toggle with a pending change shows a small clock badge with the tooltip "On <date, time>".
- **Remove…** per row shows the same loosening alert, then schedules. A row with a pending removal shows "Removal <date, time>".
- **Add App…** opens an `NSOpenPanel`:
  - `allowedContentTypes [.application]`, starting in `/Applications`
  - Read the bundle ID via `Bundle(url:)`.
  - **Reject** with an alert if:
    - there is no bundle ID → "That app can't be blocked."
    - it is myTime's own bundle ID → "myTime can't block itself."
    - the path starts with `/System/` → "System apps can't be blocked."
    - it's already in the list → "<App> is already blocked."
  - If the app is running, confirm first: "<App> is running and will be closed." with **Add** and **Cancel**.
  - Check with `SettingsPolicy.addAppProblem(bundleID:path:ownBundleID: Bundle.main.bundleIdentifier, apps:)` and show its message.
  - A new entry is `BlockedApp(name: url.deletingPathExtension().lastPathComponent, bundleIDs: [bundleID], modes: [.unlock, .booked])`. Adding is tightening, so it applies immediately.

**Pending tab**
- List rows: summary, "Applies in `short(applyAt − now)`", **Cancel**. Empty state: "No pending changes."
- At the bottom, a destructive-style button **Uninstall myTime…** with an alert: "myTime will uninstall itself in `short(looseningDelaySeconds)`. You can cancel it here until then." Buttons **Schedule** and **Cancel**.

**History tab**
- The last 7 days of `history`, newest first, grouped by calendar day under `historyDay` headings, each row showing `timeOfDay` and the text.

### 7.10 Error copy (`EngineError.userMessage`)

Cases that carry values: `bookingTooSoon(leadSeconds:)`, `invalidDuration(minSeconds:maxSeconds:)`. Run 5 removes `invalidAmount`, `noteTooShort`, `replyLimitReached`, and `cannotExtend`.

| Case | Message |
|---|---|
| `unknownApp` | "That app isn't blocked anymore." |
| `unknownGrant` | "That access has already ended." |
| `modeNotAllowed` | "That option is turned off for this app." |
| `focusActive` | "End your focus session first." |
| `notEnoughTokens` | "Not enough tokens." |
| `unlockActive` | "An Unlock is already running." |
| `invalidLength` | "Choose one of the listed lengths." |
| `priceChanged` | "The price changed. Choose again." |
| `reasonTooShort` | "Write at least 15 characters." |
| `emergencyUnavailable` | "Emergency access used · resets Monday." |
| `bookingTooSoon` | "Book at least `short(lead)` ahead." |
| `bookingTooFar` | "Book up to 7 days ahead." |
| `invalidDuration` | "Choose a length between `short(min)` and `short(max)`." |
| `bookingOverlap` | "That overlaps another session." |
| `allowanceExceeded` | "Not enough session time left that week." |
| `cannotCancel` | "That session has already started." |
| `cannotExtendBooking` | "Can't extend this session." |

### 7.11 Quit window (AppKit NSWindow via WindowRouter, "Quit myTime", width 360)

- Title "Quit myTime?" (headline) and the secondary line "Blocked apps stay unlocked until you open myTime again from the Applications folder."
- Text field "Why are you quitting?".
- Buttons: **Cancel** (closes; always available) and **Start 60-second wait** (`Int(quitWait)`; enabled at 15+ trimmed characters).
- During the wait the field is disabled and the button reads "Quit in <s>s" (disabled, updates every second). At 0 it becomes **Quit myTime**, which calls `model.quit(reason:)`.
- Closing the window starts over: nothing is saved between openings.

---

## 8. Settings and constants reference

### 8.1 SettingKey (user-configurable)

`SettingKey: String, CaseIterable, Codable`. Each case has `title`, `group`, `unit` (`.seconds`, `.count`, `.hourOfDay`), `defaultValue`, `range`, and `looserWhen`. Any whole value inside the range is valid (`.higher`, `.lower`, `.anyChange`). In DEV builds, use the DEV default, and each range's lower bound becomes `min(release lower bound, 1)` (`dayStartHour` stays 0–23).

| rawValue | Title | Group | Default | DEV default | Range | Looser when |
|---|---|---|---|---|---|---|
| `focusSecondsPerToken` | Focus per token | Earning | 900 | 15 | 300–3600 | lower |
| `dayStartHour` | Day starts at | Earning | 4 | 4 | 0–23 | any change |
| `idleThresholdSeconds` | Pause after no activity | Earning | 300 | 20 | 60–1800 | higher |
| `awayClaimSecondsPerDay` | Away time you can count per day | Earning | 1800 | 60 | 0–7200 | higher |
| `autoEndAwaySeconds` | End focus after away for | Earning | 1800 | 60 | 600–7200 | higher |
| `gatePauseSeconds` | Gate pause | Spending | 5 | 5 | 0–30 | lower |
| `weeklyAllowanceSeconds` | Session time per week | Sessions | 18000 | 1200 | 0–72000 | higher |
| `bookingLeadSeconds` | Book at least this far ahead | Sessions | 600 | 60 | 0–86400 | lower |
| `bookingMaxSeconds` | Longest session | Sessions | 10800 | 600 | 1800–28800 | higher |
| `bookingExtensionSeconds` | Session extension | Sessions | 900 | 60 | 0–3600 | higher |
| `emergencyPerWeek` | Emergency passes per week | Emergency | 1 | 1 | 0–3 | higher |
| `emergencyWaitSeconds` | Emergency wait | Emergency | 60 | 10 | 10–600 | lower |
| `emergencyAccessSeconds` | Emergency access length | Emergency | 600 | 60 | 60–3600 | higher |
| `looseningDelaySeconds` | Delay for loosening changes | Safety | 86400 | 60 | 3600–604800 | lower |

Run 5 removed `quickLookSecondsPerToken`, `quickLookMaxTokens`, `replyTokenCost`, `replySeconds`, and `replyPerDay` (§5.11). Unlock lengths, price, streak gap, and warning time are fixed constants, not settings, so they add no new way to loosen limits.

### 8.2 Constants (not user-configurable; `Constants.swift`)

| Name | Release | DEV |
|---|---|---|
| `schemaVersion` | 2 | 2 |
| `unlockLengthUnits` | [1, 2, 5, 10] | [1, 2, 5, 10] |
| `unlockSecondsPerUnit` | 60 | 10 |
| `unlockStreakGap` | 900 s | 30 s |
| `unlockWarningLead` | 30 s | 5 s |
| `unlockWarningMinimum` | 5 s | 2 s |
| `gatePauseCap` | 30 s | 30 s |
| `focusCheckInterval` | 30 s | 5 s |
| `bookingHeadsUp` | 300 s | 30 s |
| `bookingMinSeconds` | 1800 | 60 |
| `bookingStartStepSeconds` | 300 | 60 |
| `bookingDurationStepSeconds` | 900 | 60 |
| `bookingHorizonSeconds` | 604800 | 604800 |
| `gateTimeout` | 60 s | 60 s |
| `forceQuitAfter` | 5 s | 5 s |
| `holdToConfirm` | 2 s | 2 s |
| `headsUpVisible` | 8 s | 8 s |
| `quitWait` | 60 s | 10 s |
| `minAwayGap` | 120 s | 10 s |
| `minClaimable` | 60 s | 5 s |
| `clockJumpTolerance` | 120 s | 120 s |
| `criticalWakeTolerance` | 1 s | 1 s |
| `normalWakeTolerance` | 5 s | 5 s |
| `minEmergencyReason` | 15 chars | 15 chars |
| `minQuitReason` | 15 chars | 15 chars |
| `historyCap` | 500 events | 500 events |
| `dailyRetentionDays` | 60 | 60 |
| `bookingRetentionDays` | 14 | 14 |
| `weeklyRetentionWeeks` | 10 | 10 |

**Pruning** (update step 7, only in an update where the daily reset ran). Keys compare as strings:
- drop `daily` keys `< dayKey(now − dailyRetentionDays days)`
- drop `weekly` keys `< weekKey(now − weeklyRetentionWeeks × 7 days)`
- drop canceled bookings with `canceledAt < now − bookingRetentionDays days`, and finished bookings whose `endedAt ?? end` is before that
- keep only the newest `historyCap` history events

---

## 9. Visual design

- **Feel:** a quiet native utility. System materials, generous spacing, one accent color. Nothing blinks, bounces, or makes sound.
- **Colors** (`Theme.swift`, adaptive via `NSColor(name:dynamicProvider:)`):
  - accent (sage-teal): light `#2F8F83`, dark `#5BC0B2`
  - warm (last-seconds state): light `#D98A1F`, dark `#F2B24C`
  - everything else: system semantic colors
- **Surfaces:**
  - gate, focus card, heads-up: `.regularMaterial`, corner radius 22, 1 pt `.separator` stroke, window shadow
  - pill: `.thickMaterial` capsule
  - gate option cards: `.quaternary.opacity(0.5)` fill, radius 12
- **Typography:**
  - ring center: `.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()`
  - pill and menu bar: `.system(.body, design: .rounded).monospacedDigit()`
  - titles: `.title3.weight(.semibold)`; body: default
- **Motion:**
  - gate/card/heads-up appear: fade + scale 0.97→1.0, 0.2 s ease-out
  - pause ring: linear drain over `gatePauseSeconds`
  - focus ring changes: 0.3 s ease-in-out
  - pill warm transition: 0.3 s color cross-fade
  - honor `accessibilityReduceMotion`: fades only, no scale
- **OverlayPanel:**
  - `NSPanel` subclass, `styleMask [.borderless, .nonactivatingPanel]` for **every** overlay. The gate overrides `canBecomeKey = true` so Esc and text fields work without activating myTime.
  - `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`
  - `level = .floating` (gate: `.modalPanel`)
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
  - `hidesOnDeactivate = false`, `isMovableByWindowBackground = true` (every overlay can be dragged by any non-control area; the gate re-centers each time it opens)
  - content via `NSHostingView`
  - when showing the gate, call `orderFrontRegardless()` then `makeKey()`. Do **not** call `NSApp.activate`: since macOS 14 a background app can't take activation while another app is in front, and the gate would render inactive (verified in Run 1 review).
- **Accessibility:** every button has a label; follow system contrast.

---

## 10. Build, install, and developer workflow

### 10.1 `Packaging/Info.plist`

| Key | Value |
|---|---|
| `CFBundleIdentifier` | `local.mytime.app` |
| `CFBundleName` / `CFBundleDisplayName` | `myTime` |
| `CFBundleExecutable` | `myTime` |
| `CFBundlePackageType` | `APPL` |
| `CFBundleShortVersionString` / `CFBundleVersion` | `0.2.0` / `2` (Run 5) |
| `CFBundleIconFile` | `AppIcon` (Run 5) |
| `LSMinimumSystemVersion` | `14.0` |
| `LSUIElement` | `true` |
| `NSHighResolutionCapable` | `true` |

### 10.2 `scripts/build.sh` (bash, executable)

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="release"; [[ "${1:-}" == "--dev" ]] && MODE="dev"
FLAGS=(-c release --arch arm64)
[[ "$MODE" == "dev" ]] && FLAGS+=(-Xswiftc -DDEV_TIMESCALE)

swift build "${FLAGS[@]}"
BIN_DIR="$(swift build "${FLAGS[@]}" --show-bin-path)"

APP="build/myTime.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/myTime" "$APP/Contents/MacOS/myTime"
cp Packaging/Info.plist "$APP/Contents/Info.plist"
cp Packaging/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

launchctl bootout "gui/$(id -u)/local.mytime.agent" 2>/dev/null || true
rm -rf "$HOME/Applications/myTime.app"   # older builds installed here
rm -rf "/Applications/myTime.app"
cp -R "$APP" "/Applications/myTime.app"
"/Applications/myTime.app/Contents/MacOS/myTime"   # installer mode: installs + starts the agent
echo "myTime installed ($MODE)."
```

`scripts/uninstall.sh`: `launchctl bootout gui/$(id -u)/local.mytime.agent || true`, then remove the plist, `/Applications/myTime.app`, and any old `~/Applications/myTime.app`. Leave Application Support in place. This is a deliberate developer escape hatch (§14).

### 10.3 DEV builds (`#if DEV_TIMESCALE`)

- DEV defaults and constants from §8. For Unlock: 10, 20, 50, and 100-second lengths, a 30-second streak gap, and a 5-second warning (not shown under 2 s left). The rules are the same as release.
- Data file `state-dev.json` and sentinel `mytime.dev.initialized`.
- "myTime · DEV" panel title (§7.2).
- Panel debug row (§7.2):
  - "+1 token"
  - "+5 min progress" (via vest)
  - "New day" (`devSimulateNewDay` + refresh)
  - "Reset state" (writes `fresh`)
- `--foreground` launch flag is honored.

### 10.4 App icon (`scripts/make-icon.swift`, Run 5)

A developer tool, run as `swift scripts/make-icon.swift <outDir>`; it isn't part of the package and uses only AppKit/CoreGraphics. It writes `AppIcon.iconset` with the ten standard files (`icon_16x16.png` through `icon_512x512@2x.png`), each drawn at its own pixel size, then runs `/usr/bin/iconutil -c icns`. Only `Packaging/AppIcon.icns` is committed.

Design, on a 1024 canvas:
- the macOS icon grid: an 824 pt rounded square, centered, corner radius 185, with a soft drop shadow (y −12, blur 28, black at 30%)
- fill: a vertical gradient from the dark-mode accent `#5BC0B2` (top) to the light-mode accent `#2F8F83` (bottom)
- center: a white ring (diameter 520, stroke 64) and, inside it with a 36 pt gap, a white pie wedge from 12 o'clock clockwise through 270°, echoing the menu bar ring (§7.1.1)
- at 16 and 32 px: no gap and a thicker stroke, so the ring stays readable

---

## 11. Testing

### 11.1 Unit tests (`swift test`, XCTest, MyTimeCoreTests)

Build `EngineCore` with fixed dates and feed synthetic `UpdateInput`s. Each run adds the tests for its scope (§12). Required cases:

**TrustedClock**
- A forward jump of +3 h within the same boot → cancelled.
- A backward jump → cancelled.
- 30 s of drift → accepted.
- A new boot session ID → offset kept, no adjustment.
- A 10-minute gap between updates with no jump → no adjustment.

**CalendarKeys**
- With `h = 4`: 3:59 AM belongs to the previous day key, 4:00 AM to the new one.
- Sunday 11 PM and Monday 3 AM share a week key; Monday 4 AM starts a new week.
- `nextDayStart` from 3:00 AM is 4:00 AM the same date; from 5:00 AM it's 4:00 AM the next date.

**Daily reset**
- Crossing the day start clears tokens and progress and records history once.
- A start after an overnight downtime clears yesterday's tokens.
- A focus session continues across the reset.
- The claim budget is fresh on the new day.

**Launch handling**
- Focus active and downtime > idle threshold → focus ended, no credit.
- Downtime of 5 s → focus kept.

**FocusAccrual**
- Credits eligible time only while focusing, not away, and with no blocked app running at the previous update.
- 900 s of vested time mints exactly 1 token; the remainder carries over across sessions.
- **Sampling independence:** a scripted 25-minute scenario (typing, a 6¾-minute absence, a blocked app open for 2 minutes, typing) gives the same focus + unclaimed away total (±2 s) with updates every 1 s and every 30 s; focus alone differs by at most one interval.
- The idle threshold crossing discards unvested time, so a 5-minute idle credits 0 for those minutes.
- Screen lock enters away immediately. Unlock plus input returns and records the gap if ≥ `minAwayGap`.
- Sleep → wake: time asleep never appears in `unclaimedAwaySeconds`.
- Auto-end after `autoEndAwaySeconds` away; the gap is still recorded on return.
- `claimableSeconds` respects the daily budget. `confirmClaim` vests and clears unclaimed. `dismissClaim` clears without vesting.

**Grants**
- The countdown starts when the grant is created (`remaining` equals the full duration right after).
- Expiry emits `terminateIfNotAllowed`.
- `isAllowed` with a grant, with a booking + `.booked`, and with a booking without `.booked`.

**Unlock pricing** (`UnlockPricingTests`)
- First Unlock of the day: 1×, costs 1, 2, 5, 10.
- 14 min 59 s after the previous one ended → 2×; exactly 15 min → 1×.
- Doubling has no cap.
- A different purchase day → 1×.
- `resetsAt` is the end plus the gap, capped at the next day start.

**Unlock** (`UnlockTests`)
- Buying spends tokens, records stats and history, and covers every `.unlock` app but no other.
- Error order.
- The worked example in §5.3 (costs 5, 10, 8, 8, 5).
- History notes the gap since the last Unlock.
- Expiry quits every covered app, emits `unlockEnded`, and records the streak at the scheduled end.
- End Unlock: no refund; the gap starts at once (a 10-minute Unlock bought at 2:00, ended at 2:02, gives 1× at 2:18).
- Bought at 3:55 AM, next at 4:10 AM → 1×.
- A 4:00 AM reset while the gate is open → purchase refused, tokens 0.
- A price that changed since it was shown → `.priceChanged`, nothing charged.
- Ends during sleep: apps quit at wake; the gap counts from the scheduled end.
- A restart keeps the same end.
- A wall clock jump doesn't shorten it.
- A booking covering the end keeps its apps open, with no warning; the streak still starts at the Unlock's end.
- Turning Unlock off for one app keeps the others.
- Focus can start during an Unlock.
- Gate pause: 5, 10, 20, 30, 30 s at 1×, 2×, 4×, 8×, 16×; 5 s for apps without `.unlock`.

**Unlock warning** (`UnlockWarningTests`)
- Once, 30 s before the end, with a covered app running.
- Waits for a covered app to run.
- A restart doesn't repeat it.
- A wake with 3 s left shows no warning; apps quit at the end.
- A 40 s Unlock warns at its halfway point.
- Wake-ups: the warning (non-critical), then the end (critical).

**Unlock copy** (`UnlockCopyTests`): every `UnlockCopy` string in §7.

**Migration** (`MigrationTests`)
- Quick look and Reply enabled → Unlock enabled; tokens and stats carried over; the base notice.
- Reply only → Unlock off, with the per-app notice line.
- A pending Quick look enable due in 6 hours → a pending Unlock enable due in 6 hours.
- Pending Reply changes and removed setting changes are dropped and counted.
- Removed setting numbers are dropped.
- An active legacy grant keeps running.
- A current file decodes as `.ok`; an unknown version is `.tampered`.
- The notice can be dismissed.

**BookingRules**
- Each validation error (lead of 10 min: 9 min ahead fails, 10 min ahead passes).
- Overlap detection.
- Charged seconds for canceled, unopened, ended-early (rounded up to the minute), and extended bookings.
- `allowanceRemaining` per week, including forfeited.
- Extension rules.
- Heads-up emitted once.
- The end transition, including after `endBooking`, emits terminate effects.
- Booking allowed during focus.
- Canceled and ended sessions don't block new bookings.
- Booking window choices: durations, start slots (aligned, lead time, end of day), and days with no slots left dropped.
- A grant expiring as a session ends yields one terminate effect.

**Emergency**
- Weekly limit, whatever the app's modes.
- Error order and reason length.
- Ends focus.
- The next week (Monday at `dayStartHour`) restores the pass.
- Can't be extended.

**Session time labels**
- `dayLabel` gives Today / Tomorrow / weekday by calendar day; `timeOfDay` and `sessionStart` in `en_US`.

**SettingsPolicy**
- Direction per key, including `.anyChange` for `dayStartHour`.
- Tightening applies immediately; loosening is scheduled at `now + delay`.
- The same fieldKey supersedes; a no-op cancels existing pending for that key.
- Apply-due order.
- Shortening the delay uses the old delay.
- Add app immediate; remove app scheduled; mode on scheduled / off immediate.
- Uninstall emits `.uninstall` when due.
- Values clamped to range.
- Applying a removal drops later changes for that app; canceling records history.
- A day-start change keeps the current tokens until the new day start.
- Add-app problems in order.

**Pruning**
- Runs only with the daily reset; cutoffs keep the boundary day and week; canceled and finished bookings by their end; history capped.

**Setting input**
- `DurationUnit.natural(for:)`, `DurationFormat.exact`, exact `setting` formatting, and `rangeMessage`.

**History labels**
- `historyDay` gives Today / Yesterday / full weekday and date.

**StateCodec**
- Round trip.
- Flipping one payload byte → `.tampered`.
- Garbage → `.tampered`.
- `penalized` has 0 tokens, forfeited allowance, no emergency left, and no Unlock or streak.

**EnforcementPolicy**
- A table test covering all 7 rules.

**WakeUpPlanner**
- Returns the earliest candidate with the correct `critical` flag.
- When idle (not focusing, no grants, bookings, or pending changes), it returns exactly the next day start, non-critical.
- The focus interval is present only while focusing or away.

### 11.2 Manual test checklist (`docs/MANUAL_TESTS.md`)

Each run appends its steps, run against `scripts/build.sh --dev`. Each step states its expected result. From Run 5 on, steps 6 (quick look) and 16 (reply mode) no longer apply, and step 4's "No tokens yet…" text is the Unlock card's "Unlock needs 1 more token for 10 s." (DEV); steps 26–30 cover Unlock instead.

**Run 1**
1. **Install:** the menu bar shows `◆ 0` and the panel title says "myTime · DEV". `launchctl print gui/$(id -u)/local.mytime.agent` shows the job running.
2. **Keep-alive:** force quit myTime in Activity Monitor → it's back within ~5 s.
3. **Startup sweep:** with Discord open, `launchctl kickstart -k gui/$(id -u)/local.mytime.agent` → Discord quits with no gate.
4. **Gate, no tokens:** open Discord → it quits with no window flashing, the gate appears, options stay locked for 5 s, and "No tokens yet…" shows. Opening Discord again while the gate is up quits it quietly without a second gate. The gate can be dragged.
5. **Never mind:** Discord quits.
6. **Quick look:**
   - Press "+1 token" twice, open Discord, wait 5 s, buy 2.
   - Discord relaunches, and the pill and menu bar count down from 1:00 right away.
   - At ≤ 10 s (not later) the pill turns warm and offers +30 s. The pill can be dragged and reopens where it was left.
   - At 0, Discord quits within ~1 s.
7. **Idle cost:** with nothing unlocked and the panel closed, watch Activity Monitor → Energy for 2 minutes → myTime shows 0.0 CPU and near-zero idle wake-ups.

**Run 2**
8. **Earn:** Start Focus and keep using the Mac for ~20 s → a token appears within ~5 s of crossing 15 s, and the menu bar ring fills.
9. **Idle:**
   - During focus, don't touch anything for 30 s → the pause icon appears.
   - Touch the mouse → within ~5 s the claim dot appears, and the panel shows the claim row.
   - Hold 2 s → progress increases and the dot clears.
10. **Lock:** during focus, lock the screen for 30 s, then unlock → the claim row offers ~30 s.
11. **Focus card:** open Discord during focus → the focus card appears. **Back to work** quits Discord, and "Backed off" +1.
12. **New day:** press "New day" → tokens and progress go to 0, and history records the reset.
13. **Shutdown:** Start Focus, restart the Mac → after login, focus is off and no time was credited for the restart.
14. **Short sleep:** during focus, close the lid for 1 minute and reopen → focus is still on, and no away time is offered for the sleep.
15. **Focus card:** during focus, open Discord → Discord quits with no window flashing and the "You're focusing" card appears. **End focus…** swaps to the gate with a fresh 5 s pause, and "Backed off" does **not** increase.

**Run 3**
16. **Reply mode:**
    - Typing in the gate's text field works while another app is in front.
    - A note under 8 characters keeps Open disabled, with "Write at least 8 characters".
    - A valid note → Discord relaunches and the pill shows the note.
    - The 4th reply today is refused ("No replies left today").
17. **Booking:**
    - From the gate, "Book a session…" closes the gate and opens the Booking window in front. The day, start, and duration menus list valid choices only.
    - Book a 1-minute session starting ~1 minute ahead. The panel lists it under Sessions with **Cancel**, and the gate shows "Next session: …".
    - At the start, the "Your session has started" reminder shows for 8 s even with Discord closed; **Open Discord** opens it.
    - Discord opens freely with no gate and no pill, and the menu bar shows the hourglass.
    - 30 s before the end, the heads-up shows for 8 s (below the pill if one is showing).
    - At the end, Discord quits.
    - Book another and never open Discord → the allowance is fully refunded.
18. **Emergency:** from the gate, enter a 15+ character reason, wait 10 s (Cancel during the wait keeps the pass), open → 1 minute of access with an "Emergency" pill. The gate then shows "Emergency access used · resets Monday".
19. **Quit:**
    - `/Applications/myTime.app` exists and shows in Finder's Applications folder.
    - Panel → **Quit myTime…**: Start stays disabled until 15 characters; Cancel or closing the window during the 10 s wait keeps myTime running.
    - After the wait, **Quit myTime** → the menu bar item disappears, Discord opens with no gate, and myTime is not back after 30 s or after logging out and in.
    - Open myTime from Applications → the menu bar item returns with the same token count, and Discord is gated again.

**Run 4**
20. **Loosening:** raise "Session time per week" → the "Settings updated" alert lists it under "Applies <time>" about a minute ahead, the panel shows "1 pending", the Pending tab lists it, and it applies. Lower it → "Applied now". Opening myTime from Applications while it runs opens Settings.
21. **Day start:** change "Day starts at" → scheduled, never immediate.
22. **Blocked apps:** add TextEdit → opening it shows the gate. Remove TextEdit → pending, still blocked until applied.
23. **Clock tamper:** set the system time +2 h → no tokens gained, pending changes don't apply early, and Settings shows the clock-change note.
24. **File tamper:** edit one character in `state-dev.json`, then kickstart the agent → tokens are 0 and the tamper banner shows.
25. **Uninstall:** schedule uninstall → after ~1 minute myTime leaves the menu bar and is not relaunched, and `/Applications/myTime.app` is in the Trash.

**Run 5**
26. **Unlock gate:** press "+1 token" 6 times, open Discord. The lengths 10 s, 20 s, 50 s, 100 s show their prices but stay disabled for 5 s; nothing is preselected and the button reads "Choose a length". Pick 20 s → "Unlock 20 s · 2 tokens". Buy → Discord relaunches, no pill shows, and the menu bar shows the hourglass and "20 s".
27. **Warning:** type in Discord during an Unlock. At 5 s left, "Discord closes in 0:05" appears top-right and typing still goes to Discord. **End now** quits Discord at once.
28. **Streak:** reopen Discord within 30 s of the end → the pause is 10 s, prices are doubled, and the card header reads "2× — resets at …". Choose a length and keep the gate open past that time → the prices and the Unlock button drop to 1× without closing the gate.
29. **Panel:** during an Unlock the panel shows "Unlock · 0:15 left", **End Unlock**, and "Next Unlock: 2× until …". **End Unlock** quits Discord.
30. **Restart:** during an Unlock, `launchctl kickstart -k gui/$(id -u)/local.mytime.agent` → the same end time; a warning already shown doesn't show again; at the end Discord quits.
31. **Migration:** with a `state-dev.json` written by 0.1.0 (Quick look on), install the DEV build → no tamper banner, tokens unchanged, the migration notice shows in the panel, and Settings shows Unlock on for Discord. **Dismiss** removes it for good.
32. **Settings:** Blocked Apps shows "Unlock" and "Sessions". Turning Unlock on shows the loosening alert. With TextEdit blocked with Unlock and an Unlock running, turning Unlock off for TextEdit quits it at once; Discord stays open until the end.
33. **Icon:** `/Applications/myTime.app` shows the new icon in Finder and Get Info (if Finder shows a blank icon, `touch /Applications/myTime.app`).

---

## 12. Runs (build in order; each run leaves a working app)

**Status:** Runs 1–4 are complete and committed. Their plans in `docs/superpowers/plans/` are historical. Run 5 is specified and not built. The sections below record each run's scope.

After each run: `swift build` and `swift test` pass, `scripts/build.sh --dev` installs, that run's manual steps pass, and `IMPLEMENTATION_NOTES.md` has a `## Run N` section. The reviewer then reviews, fixes, and commits before the next run starts. Later runs may extend earlier files; they must not rewrite working code without reason.

### Run 1 — Foundations, blocking, gate, quick look

**Core**
- `Package.swift`, all model types (§4, full shape including fields used by later runs), `SettingKey` and `Constants` (§8), `TrustedClock`, `CalendarKeys`, `DurationFormat`, `StateCodec`.
- `EngineCore` with `init`, `start` (clock + update only; launch handling comes in Run 2), `update` (steps 1, 2, 5, 8; Run 2 adds step 4, Run 3 adds step 6, Run 4 adds steps 3 and 7), daily reset, grants (`buyQuickLook`, `canExtend`, `extendGrant`, expiry, `isAllowed`, `recordBackedOff`), `EnforcementPolicy`, `WakeUpPlanner`, DEV helpers.

**App**
- `main.swift` modes, `Installer` (install + self-heal; uninstall can be a stub until Run 4), `SystemProbe`, `SystemEvents` (app events and clock change; others later), `StateStore` (load/save/sentinel/tamper), `AppModel.refresh` + `Scheduler`, `AppMonitor`, `Enforcer`, `OverlayPanel`.
- `GateView`: pause, Never mind, quick look, no-tokens text without the Start Focus button, and the footer link hidden until Run 3.
- `PillView`, `MenuBarLabel` (diamond and hourglass rows), a minimal panel (tokens row + DEV row), startup sweep, activity assertion, `Packaging/Info.plist`, `scripts/build.sh`, `scripts/uninstall.sh`.

**Plan:** `docs/superpowers/plans/2026-09-13-run-1-foundations-blocking.md`.

**Tests:** TrustedClock, CalendarKeys, daily reset, grants, StateCodec, EnforcementPolicy, WakeUpPlanner.

**Manual:** steps 1–7.

### Run 2 — Earning

**Core:** `FocusAccrual` (accrual, away, sleep/wake handlers, claims, launch handling), focus intents.

**App:**
- lock/unlock and sleep/wake/power-off events
- `MenuBarIcon` ring, pause icon, claim dot
- panel focus block, claim row, `HoldButton`, today strip, "Resets at" caption
- `FocusCardView`
- gate Start Focus button

**Tests:** FocusAccrual (including sampling independence), launch handling.

**Manual:** steps 8–15.

### Run 3 — Reply mode, sessions, emergency

**Core:** reply mode, `BookingRules` + transitions, emergency pass.

**App:**
- gate reply card, sessions line, emergency sub-flow and footer link
- panel sessions block
- `BookingView` + `WindowRouter`
- `HeadsUpView`
- menu bar booking row

**Tests:** grants/reply additions, BookingRules, booking transitions, Emergency, session time labels.

**Manual:** steps 16–19.

### Run 4 — Safety and management

**Core:** `SettingsPolicy`, apply-due (update step 3), pruning, `.uninstall` effect.

**App:**
- Settings window: General with draft/apply, Blocked Apps with add/remove/toggles and alerts, Pending with uninstall, History
- pending capsule in the panel
- clock-change note, tamper banner
- `Installer.uninstall`
- adding a running app (§6.8)

**Tests:** SettingsPolicy.

**Manual:** steps 20–25, then re-run steps 1–7 against a release build (`scripts/build.sh`).

### Run 5 — Unlock (0.2.0)

**Plan:** `docs/superpowers/plans/2026-10-24-run-5-unlock.md`. Tasks in order; the icon can be built alongside the others.

**Core:** `ActiveUnlock`, `UnlockStreak`, `UnlockPricing`, buy/end/finish/warning, gate pause, Unlock stats and history, wake-ups, `UnlockCopy`. Then remove Quick look, Reply mode, and extensions; schema 2 and `StateMigration`.

**App:**
- gate Unlock card with the length picker; streak pause; the gate clock refreshes the engine
- Unlock warning
- menu bar Unlock row, panel Unlock block, migration notice
- remove the Quick look and Reply cards, the extend button, and the pill's note line; "Unlock" toggle in Blocked Apps
- app icon (`scripts/make-icon.swift`, `Packaging/AppIcon.icns`)

**Tests:** Unlock pricing, Unlock, Unlock warning, Unlock copy, Migration; Quick look, Reply, and extension tests removed.

**Manual:** steps 26–33, then a day on DEV and a week on release. After two weeks, use the Unlock history to revisit the lengths, the 15-minute gap, and a possible booking top-up (tokens buying extra session minutes at 2 minutes per token, up to 1 hour a week), which is not part of Run 5.

---

## 13. Hard rules and pitfalls

1. **Swift 5 language mode.** Mark `AppModel`, `Enforcer`, `AppMonitor`, `SystemEvents`, `Scheduler`, `WindowRouter`, overlay controllers, and all views `@MainActor`. Use `Timer`. Do not use `Task.sleep` loops or detached tasks.
2. **No polling.** The only repeating timers allowed are the UI timers in §3.6, each running only while its UI is visible. The engine is driven by events plus the single `Scheduler` timer. Every `Timer` sets a `tolerance`.
3. **MyTimeCore imports only Foundation and CryptoKit.** It never calls `Date()`, reads clocks, or touches AppKit. Time and system state come in through parameters.
4. **Public API:** every Core type, property, method, and initializer used by the app target must be `public`. Memberwise initializers are *not* public, so write explicit `public init`s.
5. **Dictionaries:** use `[String: …]` keys. Enum-keyed dictionaries encode as arrays in JSON; don't use them.
6. **No Xcode project,** no SwiftUI `Settings` or `Window` scenes, and no `@main` attribute. `main.swift` dispatches on arguments and calls `MyTimeScene.main()` in agent mode.
7. **Do not use:** UserNotifications, AX/Accessibility APIs, AppleScript, Screen Recording, SMAppService, the network, App Sandbox, entitlements, or `NSAppSleepDisabled`.
8. **Match blocked processes by exact bundle ID** and `.regular` activation policy.
9. **Terminate politely first,** then force after 5 s.
10. **No instant Quit.** The only way to quit is the Quit window (§7.11), with its reason and wait. No "pause blocking" feature.
11. **Never auto-renew** grants, Unlocks, or bookings. Unlocks have no extensions and no refunds.
12. Idle seconds: `CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)` (hardware input only, so "mouse jiggler" apps don't count). Screen lock: `CGSessionCopyCurrentDictionary()` key `"CGSSessionScreenIsLocked"` present and true.
13. **Persist** at the end of any refresh that changed state, and on `willPowerOff`, `willSleep`, and `applicationWillTerminate`. Always use atomic writes.
14. **Keep files focused** (roughly ≤ 300 lines). Put logic in Core; views stay declarative.
15. `swift build` must finish with **zero errors**. Deprecation warnings are acceptable.
16. **Do not invent features, settings, or copy** not in this doc (DEV debug row excepted). If something is impossible as specified, implement the closest behavior and record it in `IMPLEMENTATION_NOTES.md`.

---

## 14. Out of scope and known gaps

**Out of scope for v1:**
- Blocking websites (discord.com in a browser)
- Phones or other devices
- Multiple users, accounts, sync, cloud
- System notifications
- Per-app prices
- Charts and weekly reports beyond the History tab (Unlock stats are stored, not shown)
- Localization
- Booking top-up with tokens (a possible later run, §12 Run 5)
- Per-app Unlocks (one Unlock covers every app with the mode)

**Known bypasses** (accepted; each needs a deliberate, multi-step action):
- Terminal: `launchctl bootout`, `scripts/uninstall.sh`, rebuilding with `--dev`, or editing the source.
- System Settings → General → Login Items → "Allow in the Background" toggle for myTime (macOS lets users disable any LaunchAgent there).
- Changing the system clock *before* myTime starts after a boot. The offset can't be verified across reboots, so this could, for example, keep yesterday's tokens past the reset. The user shuts down nightly, so this window exists every morning; it still takes a deliberate clock change.
- Deleting both the state file and myTime's UserDefaults.
