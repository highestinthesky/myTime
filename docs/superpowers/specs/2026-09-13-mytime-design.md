# myTime — Design Doc (v1)

**Status:** Approved design, revision 2 · 2026-09-13
**Audience:** the implementing model (Codex) and the reviewer (Claude)

**Revision 2 changes:**
- tokens reset daily at 4:00 AM, and the token cap is removed
- booking lead time is 10 min, with 5-minute start steps
- event-driven engine with no polling
- quieter UI: no claim pop-up, no pill during booked sessions, ring icon in the menu bar
- handling for nightly shutdown
- the build is split into four runs

---

## 0. How to use this document

- The app is built in **four runs** (§12). Each run gets a short brief naming the run number. **Build only that run's scope**, finish its checks, then stop.
- Read `AGENTS.md` (repo root) before starting. It holds the coding conventions and commands.
- Where this doc gives exact values, names, strings, or rules, use them **verbatim**. Where it is silent, choose the simplest thing that satisfies the rules. **Do not add features** that are not described here (the only exception is the DEV debug controls in §10.3).
- §13 lists hard rules and pitfalls. They are non-negotiable.
- At the end of each run, append a section `## Run N` to `IMPLEMENTATION_NOTES.md` (repo root) listing: (a) every deviation from this doc and why, (b) anything you could not verify, (c) the commands you ran and their results. Do **not** commit; the reviewer commits after review.

---

## 1. Product summary

myTime is a macOS menu-bar app that makes distracting apps (Discord by default) cost something to open. The user earns **tokens** by running a **focus timer** while working. Tokens reset every day at 4:00 AM.

Opening a blocked app shows a **gate** with a mandatory 5-second pause. Getting past it costs tokens (quick look, reply mode), uses a pre-booked **session** from a weekly allowance, or uses a once-a-week **emergency pass**. When access ends, myTime quits the app.

myTime runs all the time, restarts itself if quit, and delays any change that would make it less strict by 24 hours. It is quiet: it does no work unless something happens, and it never pops up over the user's work except when they try to open a blocked app.

It is for one person, on one Mac (Apple Silicon), installed locally without a developer certificate. No accounts, no network, no cloud. The user shuts the Mac down most nights.

### 1.1 Glossary

| Term | Meaning |
|---|---|
| **Blocked app** | An entry in the block list: display name, one or more bundle IDs, and a set of allowed access modes. |
| **Day** | Starts at `dayStartHour` (default 4:00 AM local). All "daily" things (token reset, reply limit, claim budget, stats) use this boundary. The week starts Monday at the same hour. |
| **Token (◆)** | Currency earned by focus time. Spent on quick looks, reply mode, and extensions. Unspent tokens and partial progress are cleared at the start of each day. There is no cap. |
| **Progress** | Vested focus seconds toward the next token (`0 ≤ progress < focusSecondsPerToken`). |
| **Focus session** | An open-ended, user-started stopwatch during which eligible time is credited. |
| **Unvested time** | Focus time since the last keyboard/mouse input. Discarded if the user turns out to be idle. |
| **Away** | State entered during focus when idle ≥ threshold, the screen locks, or the Mac sleeps. Nothing is credited while away. |
| **Unclaimed away time** | Today's accumulated away gaps. The user can count some of it as focus from the menu bar panel, within a daily budget. |
| **Gate** | Floating card shown when a blocked app is opened without access. |
| **Focus card** | Variant of the gate shown when a blocked app is opened during a focus session. |
| **Grant** | A paid, time-limited permission for one blocked app. Kinds: quick look, reply, emergency. |
| **Quick look** | 1 token = 30 s of access, up to 3 tokens at once. |
| **Reply mode** | 2 tokens = 3 min. Requires a typed intention note. Max 3 per day. |
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
| 15 min → 1 token → 30 s; clock starts after launch grace; progress carries over within a day | The ratio suits impulse checks. Without launch grace, Discord's startup would eat the window. |
| **Tokens reset daily at 4:00 AM, no cap** | Resetting stops hoarding across days, which was the cap's only job. Dropping the cap removes the irritating "stop earning" state. A 4 AM boundary keeps late-night sessions intact. |
| Tokens for impulses, weekly allowance for planned sessions | Planned calls and gaming aren't the habit being broken. Booking ≥ 10 min ahead prevents impulse use. Booking is allowed during focus. |
| Reply mode with typed note and daily limit | Legitimate replies need more than 30 s. The note, limit, and history keep it from becoming a loophole. |
| Weekly emergency pass | A blocker the user gets stuck in gets uninstalled. One hard, rare way out is safer. |
| **Quiet UI** | No pop-ups over work except the gate. Away-time claims wait in the panel, marked by a dot on the menu bar icon. Booked sessions get one heads-up, not a floating timer. No ticking clock in the menu bar. |
| Tighten now, loosen after 24 h | The user is both admin and target. The delay removes impulsive loosening. |
| launchd LaunchAgent with KeepAlive, no Quit | Quitting myTime would otherwise unblock everything instantly. |
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
| Short countdown on screen (pill, gate, open panel) | 1 Hz UI updates, only while visible. |
| Memory | < 50 MB memory footprint (the Activity Monitor "Memory" column). Measured after Run 1: 16 MB. |

### 3.2 Process model and installation

One executable, `myTime`, inside `~/Applications/myTime.app`. Its behavior depends on the arguments:

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

**Uninstall** (only when a pending `.uninstall` change applies, §5.6):
1. Set `isUninstalling = true` (stops self-heal) and save state.
2. Delete the plist file.
3. `FileManager.default.trashItem(at: <app bundle URL>)`; ignore errors.
4. `/bin/launchctl bootout gui/<uid>/local.mytime.agent`. This terminates the process. Fallback: `exit(0)` after 2 s.
5. Leave `~/Library/Application Support/myTime/` in place.

**App Nap:** allowed by default. While anything time-critical is live (a gate or focus card is showing, a grant is active, or a booking is active), hold `ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "Enforcing app limits")`. End the activity as soon as none of those are true.

### 3.3 Package layout

```
myTime App/
├── AGENTS.md                       # conventions for any agent editing this repo
├── IMPLEMENTATION_NOTES.md         # appended by each run
├── Package.swift
├── Packaging/
│   └── Info.plist
├── scripts/
│   ├── build.sh
│   └── uninstall.sh
├── Sources/
│   ├── MyTimeCore/                 # Foundation + CryptoKit only. Pure logic. Fully unit-tested.
│   │   ├── Model/
│   │   │   ├── SettingKey.swift        # enum + defaults/ranges/direction (§8.1)
│   │   │   ├── Settings.swift
│   │   │   ├── BlockedApp.swift
│   │   │   ├── AccessGrant.swift
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
│   │   │   ├── BookingRules.swift
│   │   │   ├── SettingsPolicy.swift
│   │   │   ├── EnforcementPolicy.swift
│   │   │   ├── WakeUpPlanner.swift
│   │   │   ├── DurationFormat.swift
│   │   │   ├── EngineError.swift
│   │   │   └── EngineCore.swift        # façade: state + intents + update
│   │   └── Persistence/
│   │       └── StateCodec.swift        # HMAC envelope
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
│           ├── FocusCardView.swift
│           ├── PillView.swift
│           ├── HeadsUpView.swift       # booking 5-minute heads-up
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
            │ NSRunningApplication · OverlayPanel (gate / focus card / pill / heads-up)│
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
7. Save (atomic write) if anything other than `state.clock` changed since the last save, or if the saved clock is ≥ 60 s old. Updates run on every app switch, so saving clock-only changes every time would write to disk constantly. The once-a-second `.panel` and `.uiTick` refreshes save only when the last save is ≥ 60 s old, because during focus each one credits another second. Also save immediately on `.willSleep` and `.willPowerOff`.
8. `Scheduler.schedule(result.nextWakeUp)`. This replaces any pending timer. `critical` wake-ups use `tolerance = 1 s`; others use `5 s`. `nil` means no timer.

### 3.6 UI timers (exist only while their UI is visible)

| Timer | Interval | Runs while |
|---|---|---|
| Gate/focus card clock (pause countdown, 60 s timeout, emergency wait) | 1 s | gate or focus card visible |
| Grant countdown (`refresh(.uiTick)`: pill, menu bar label, and `canExtend` all read current time) | 1 s | a running blocked app has an active grant |
| Menu bar booking label | 60 s | a booking countdown is shown in the menu bar |
| Panel refresh (`refresh(.panel)`) | 1 s | menu bar panel open |
| Heads-up auto-hide | one-shot 8 s | heads-up visible |

All UI timers use `Timer` on `RunLoop.main` in `.common` mode, with `tolerance = 0.1 × interval`. For display, compute `displayNow = Date() + core.state.clock.offsetSeconds` without running an update.

---

## 4. Data model (MyTimeCore)

All types are `Codable`, `Equatable`, and **`public` with explicit `public init`s**. JSON: `JSONEncoder.dateEncodingStrategy = .secondsSince1970`, `outputFormatting = [.sortedKeys]`.

### 4.1 PersistedState

```swift
public struct PersistedState: Codable, Equatable {
    public var schemaVersion: Int              // 1
    public var settings: Settings
    public var pending: [PendingChange]
    public var tokens: Int
    public var progressSeconds: Double         // vested progress toward next token
    public var tokensDayKey: String            // day key the tokens belong to (§5.2 daily reset)
    public var focus: FocusSession?            // nil = not focusing
    public var grants: [AccessGrant]
    public var bookings: [Booking]
    public var daily: [String: DailyStats]     // key: CalendarKeys.dayKey
    public var weekly: [String: WeeklyStats]   // key: CalendarKeys.weekKey
    public var history: [HistoryEvent]         // newest last, capped (§8.2)
    public var clock: TrustedClockState
    public var tamperNoticeUntil: Date?        // show tamper banner until this time

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

public enum AccessMode: String, Codable, CaseIterable { case quickLook, reply, booked }

public struct BlockedApp: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bundleIDs: [String]
    public var modes: Set<AccessMode>
}
```

Default block list (in `PersistedState.fresh`): one entry with `name: "Discord"`, `bundleIDs: ["com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary"]`, `modes: [.quickLook, .reply, .booked]`.

### 4.3 AccessGrant

```swift
public enum GrantKind: String, Codable { case quickLook, reply, emergency }

public struct AccessGrant: Codable, Equatable, Identifiable {
    public var id: UUID
    public var appID: UUID
    public var kind: GrantKind
    public var createdAt: Date
    public var startsAt: Date     // max(createdAt, appLaunchDate + launchGrace)
    public var expiresAt: Date    // startsAt + duration (+ extensions)
    public var tokensSpent: Int
    public var note: String?      // reply note or emergency reason
}
```

A grant is **active** while `now < expiresAt`. It allows the app even before `startsAt`. The remaining time shown is `expiresAt − max(now, startsAt)`.

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
    public var quickLooks: Int = 0
    public var replies: Int = 0
    public var claimedAwaySeconds: Double = 0
    public var unclaimedAwaySeconds: Double = 0
}

public struct WeeklyStats: Codable, Equatable {
    public var emergencyUses: Int = 0
    public var allowanceForfeited: Bool = false   // set by tamper penalty
}

public enum HistoryKind: String, Codable {
    case focusStarted, focusEnded, tokenEarned, dayReset, awayClaimed, quickLook, reply, extended,
         backedOff, bookingCreated, bookingCanceled, bookingEnded, bookingExtended,
         emergency, changeScheduled, changeApplied, changeCanceled, appAdded, appRemoved,
         tamperDetected
}

public struct HistoryEvent: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kind: HistoryKind
    public var text: String        // pre-rendered line, e.g. "Reply mode in Discord — “reply to Sam in #capstone”"
}
```

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
    case bookingHeadsUp(bookingID: UUID)
    case uninstall
}
```

AppModel handling:

| Effect | Action |
|---|---|
| `terminateIfNotAllowed` | For each running process of that app: if `!core.isAllowed(appID)`, terminate it (§6.3). |
| `bookingHeadsUp` | Show the heads-up panel (§7.6). |
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

    // Spending
    public mutating func buyQuickLook(appID: UUID, tokens: Int, appLaunchDate: Date?) throws -> AccessGrant
    public mutating func buyReply(appID: UUID, note: String, appLaunchDate: Date?) throws -> AccessGrant
    public func canExtend(grantID: UUID) -> Bool
    public mutating func extendGrant(grantID: UUID) throws
    public mutating func recordBackedOff(appID: UUID)
    public var emergencyUsesLeftThisWeek: Int { get }
    public mutating func useEmergency(appID: UUID, reason: String, appLaunchDate: Date?) throws -> AccessGrant

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

    // Enforcement queries
    public func isAllowed(appID: UUID) -> Bool
    public func activeGrant(appID: UUID) -> AccessGrant?
    public func remaining(of grant: AccessGrant) -> Double   // max(0, expiresAt − max(now, startsAt))
    public func app(id: UUID) -> BlockedApp?
    public func app(bundleID: String) -> BlockedApp?

    // Settings
    public mutating func submit(_ change: SettingChange) -> SubmitResult
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

**Effects come only from `start`, `update`, and the sleep/wake handlers.** Intents never return effects. If an intent causes something that needs a side effect (e.g. `endBooking` should close apps), the follow-up `refresh(.intent)` detects the transition and emits the effect.

**`update(input)` order:**
1. Trusted clock (§5.1) → sets `now`
2. Daily reset (§5.2)
3. Apply due pending changes (§5.6)
4. Focus accrual and away (§5.2)
5. Grant expiry (§5.3)
6. Booking transitions (§5.4)
7. Pruning, only when the daily reset ran this update (§8.2)
8. Next wake-up (§5.9)

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

A focus session in progress continues through the reset. Other daily limits need no reset logic because they read `daily[dayKey(now)]`.

**Launch handling — `start(input)`:**

```
hadPrevious = state.clock.lastWall > 0                             // capture BEFORE updating the clock
prevTrusted = state.clock.lastWall + state.clock.offsetSeconds
run TrustedClock.update → now
downtime = now.timeIntervalSince1970 - prevTrusted
if state.focus != nil && hadPrevious && downtime > idleThresholdSeconds:
    end focus WITHOUT vesting; history(.focusEnded, "Focus ended · myTime wasn't running")
runtime = EngineRuntime()
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

### 5.3 Tokens and grants

Launch grace: `startsAt = appLaunchDate == nil ? now : max(now, appLaunchDate! + Constants.launchGrace /*15 s*/)`. Grace only applies when the launch time is known.

**buyQuickLook(appID, tokens n):** throws, in this order, if:
- the app ID is not in the block list → `.unknownApp`
- the app lacks `.quickLook` → `.modeNotAllowed`
- focus is active → `.focusActive`
- `n` is not in `1...quickLookMaxTokens` → `.invalidAmount`
- `tokens < n` → `.notEnoughTokens`

Otherwise: `tokens -= n`, `today.tokensSpent += n`, `today.quickLooks += 1`. Create a `.quickLook` grant with `duration = n × quickLookSecondsPerToken`. History: `"Quick look in Discord · 1:00 · 2 ◆"`.

**buyReply(appID, note):** `note` is trimmed. Throws if:
- the app lacks `.reply` → `.modeNotAllowed`
- focus is active → `.focusActive`
- `note.count < Constants.minReplyNote /*8*/` → `.noteTooShort`
- `tokens < replyTokenCost` → `.notEnoughTokens`
- `today.replies >= replyPerDay` → `.replyLimitReached`

Otherwise: `tokens -= cost`, `today.tokensSpent += cost`, `today.replies += 1`. Create a `.reply` grant with `duration = replySeconds` and the note. History includes the note.

**Extensions:** `canExtend(grantID)` is true when the grant kind is `.quickLook` or `.reply`, the grant is active, `remaining ≤ Constants.extendWindow /*10 s*/`, and `tokens ≥ 1`. `extendGrant` checks this (throwing `.cannotExtend`), then `expiresAt += quickLookSecondsPerToken`, `tokens -= 1`, `today.tokensSpent += 1`. History: `"Extended Discord · +30 s"`. Emergency grants can't be extended. Nothing ever renews automatically.

**Expiry** (update step 5): remove grants with `now ≥ expiresAt`. Emit `.terminateIfNotAllowed(appID)` for each.

**recordBackedOff(appID):** `today.backedOff += 1`, history `"Backed off from Discord"`.

**isAllowed(appID)** is true if either:
- an active grant exists for the app, or
- `activeBooking != nil` and the app's modes contain `.booked`.

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

**cancelBooking:** only if upcoming (otherwise `.cannotCancel`). Sets `canceledAt = now`.

**endBooking:** if active, set `endedAt = now`. The follow-up update emits the terminate effects.

**canExtendBooking / extendBooking:** all of these must hold (otherwise `.cannotExtendBooking`):
- the booking is active
- `extensionSeconds == 0` and `bookingExtensionSeconds > 0`
- `allowanceRemaining(weekOf: start) ≥ bookingExtensionSeconds`
- the new end does not overlap the next upcoming booking

Then `extensionSeconds = bookingExtensionSeconds`. History: `"Extended session · +15 min"`.

**Transitions** (update step 6):
- If a booking is active and `runningAppIDs` contains any app with `.booked`, set `appOpened = true`.
- If a booking is active, `!warned`, and `end − now ≤ bookingHeadsUp`, set `warned = true` and emit `.bookingHeadsUp`.
- If `runtime.lastActiveBookingID` is non-nil and that booking is no longer active, append history `"Session ended"` and emit `.terminateIfNotAllowed` for every app with `.booked`.
- Finally, set `runtime.lastActiveBookingID = activeBooking?.id`.

### 5.5 Emergency pass

- `emergencyUsesLeftThisWeek = max(0, emergencyPerWeek − weekly[weekKey(now)].emergencyUses)`.
- The UI handles reason entry and the `emergencyWaitSeconds` countdown (§7.3). Cancelling during the wait does **not** use the pass.
- **useEmergency(appID, reason, appLaunchDate):** `reason` is trimmed. Throws `.reasonTooShort` if `reason.count < Constants.minEmergencyReason /*15*/`, or `.emergencyUnavailable` if no uses are left.
  - Then: `emergencyUses += 1`; if focusing, `endFocus()`.
  - Create an `.emergency` grant with `duration = emergencyAccessSeconds`, `tokensSpent 0`, `note = reason`.
  - History: `"Emergency access to Discord — “<reason>”"`.

### 5.6 Settings and pending changes (SettingsPolicy)

**isLoosening(change, settings):**

| Change | Loosening when |
|---|---|
| `.setNumber(key, v)` | `looserWhen == .higher`: `v > current`; `.lower`: `v < current`; `.anyChange`: `v != current` |
| `.addApp` | never |
| `.removeApp` | always |
| `.setMode(_, _, enabled)` | `enabled == true` and mode not currently enabled |
| `.uninstall` | always |

**submit(change):**

```
clamp .setNumber values to the key's range (§8.1)
remove pending items with the same fieldKey
if change is a no-op (same number; mode already in that state; app already present by any bundle ID; removing a missing app):
    return .noChange
if isLoosening:
    append PendingChange(applyAt: now + setting(.looseningDelaySeconds), summary)
    history(.changeScheduled, "Scheduled: <summary> · applies <date, time>")
    return .scheduled(applyAt)
apply(change); history(.changeApplied or .appAdded, "<summary>")
return .applied
```

- **Changing the loosening delay itself:** shortening it is loosening, so it waits out the *current* delay.
- **Apply due** (update step 3): for pending items with `now ≥ applyAt`, in `applyAt` order, apply them and append history `"Applied: <summary>"`. For `.uninstall`, emit `.uninstall`. If the target app no longer exists, drop the item silently.
- **cancelPending(id):** remove it and append history `"Canceled: <summary>"`. Cancelling is always immediate.

**Summaries** (exact formats):
- `"<Setting title>: <old> → <new>"` using `DurationFormat.setting(key, value)`
- `"Add <App>"`, `"Remove <App>"`
- `"Turn on <Mode title> for <App>"`, `"Turn off <Mode title> for <App>"`
- `"Uninstall myTime"`

Mode titles: quickLook → "Quick look", reply → "Reply mode", booked → "Sessions".

### 5.7 Integrity and tamper handling

**File:**
- release: `~/Library/Application Support/myTime/state.json`
- DEV: `state-dev.json`

**Envelope:**

```json
{ "v": 1, "payload": "<base64 of JSON-encoded PersistedState>", "mac": "<lowercase hex HMAC-SHA256 of the payload bytes>" }
```

- Key: `SymmetricKey(data: SHA256.hash(data: Data("myTime.integrity.v1.7c1e9b4a-5d2f-4e8a-9f61-2b3c4d5e6f70".utf8)))`.
- `StateCodec.decode(data) -> DecodeResult` returns `.ok(PersistedState)` or `.tampered`, and never throws. It returns `.tampered` for unparseable envelopes, bad base64, bad hex, a MAC mismatch, or payload decode failure. Verify with `HMAC<SHA256>.isValidAuthenticationCode(_:authenticating:using:)`.
- Write with `Data.write(to:options: .atomic)`.

**Load logic (StateStore):**

| Situation | Result |
|---|---|
| File present, `.ok` | Use it. |
| File missing, UserDefaults bool `mytime.initialized` (DEV: `mytime.dev.initialized`) false | `PersistedState.fresh(now: Date())`. Set the sentinel true **after the first successful save**. |
| File missing but sentinel true | Tamper → penalized state. |
| File present, `.tampered` | Rename the file to `state.tampered-<unix>.json`, then use the penalized state. |

**`PersistedState.penalized(now)`** = `fresh(now)`, plus:
- `tokens = 0`
- `weekly[thisWeek].allowanceForfeited = true`
- `weekly[thisWeek].emergencyUses = 99`
- `daily[today].replies = 99`
- `daily[today].claimedAwaySeconds = 1_000_000`
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
| `end` of the active booking | yes |
| `end − bookingHeadsUp` of the active booking, if `!warned` and in the future | no |
| `applyAt` of each pending change | no |
| `nextDayStart` | no |
| `now + Constants.focusCheckInterval` if `state.focus != nil` or `runtime.awayStartUptime != nil` | no |

Booking *starts* need no wake-up. Access is evaluated when an app is launched or activated, and every refresh updates `now` first.

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
- **Pill:** at most one. It shows the running blocked app that has an active **grant**, choosing the one with the least remaining time. Booked sessions never show a pill.
- **Heads-up:** at most one, independent of the other two.

### 6.5 Gate outcomes

**Backed off rule:** whenever a gate or focus card closes without the app being opened, call `core.recordBackedOff` exactly once.

| User action | Result |
|---|---|
| Never mind / Esc / 60 s of no interaction | Backed off, close the gate. |
| Quick look / Reply succeeds | Buy with `appLaunchDate = now` (launch grace covers the relaunch), close the gate, relaunch the app with `NSWorkspace.shared.openApplication(at: bundleURL, configuration:)` (`activates = true`). The pill appears once the app is running. |
| Start Focus (0-token state) | Backed off, `core.startFocus()`, close the gate. |
| Book a session… | Backed off, open the Booking window, close the gate. |
| Emergency flow completes | Same as a successful quick look. |
| The app is opened again while its gate is up | It's quit quietly (§5.8 rule 3); the gate stays. |
| Focus becomes active while the gate is open | Swap the gate content to the focus card. |

Any interaction with the gate (click, typing, stepper) resets the 60 s timeout. The timeout is suspended during the emergency wait. Timing out at any other point behaves like Never mind, and an emergency pass not yet used stays unused.

### 6.6 Focus card outcomes

| User action | Result |
|---|---|
| Back to work / Esc / 60 s timeout | Backed off, close the card. |
| End focus… | `core.endFocus()`, then swap to the gate (with the full 5 s pause). |

### 6.7 Startup sweep

On agent launch, after `core.start`, call `reconcile(trigger: .startupSweep)` for every running blocked process. Blocked apps launched at login, and apps whose access ended while myTime wasn't running, get quit silently.

### 6.8 Adding an app while it runs

In Settings, if the chosen app is running, the confirmation says it will be closed. After the change applies, call `reconcile(trigger: .startupSweep)` for its processes.

---

## 7. UX flows, screens, and copy

- **Tone:** calm, neutral, factual. No guilt, no exclamation marks, no red, no sounds, no bouncing.
- **Formatting helpers (`DurationFormat`):**
  - `clock(s)`: `m:ss` under 1 h, `h:mm:ss` otherwise
  - `short(s)`: `"45 s"`, `"12 min"`, `"2h 10m"`
  - `hourOfDay(h)`: locale time style, e.g. `"4:00 AM"`
  - `setting(key, v)`: formats by the key's unit
- **Token glyph:** `◆` (U+25C6). Pluralize "token"/"tokens".

### 7.1 Menu bar label (MenuBarLabel)

The label shows an icon plus optional text, with `monospacedDigit()`. Precedence, first match:

| State | Icon | Text | Updates |
|---|---|---|---|
| A running blocked app has an active grant | SF Symbol `hourglass` | `clock(least remaining)` | every 1 s |
| Active booking and a `.booked` app is running | SF Symbol `hourglass` | `short(end − now)` | every 60 s |
| Focusing, away | SF Symbol `pause.circle` | `"<tokens>"` | on refresh |
| Focusing | MenuBarIcon ring (§7.1.1) | `"<tokens>"` | on refresh (~30 s) |
| Otherwise | SF Symbol `diamond.fill` | `"<tokens>"` | on refresh |

**Claim dot:** when `claimableSeconds ≥ Constants.minClaimable` and the state is not one of the countdown rows, draw a small dot into the top-right of the icon image itself, with a clear halo so it never touches the glyph. It stays monochrome (template), like system menu bar indicators.

DEV builds prefix the text with `DEV `.

#### 7.1.1 MenuBarIcon

- A 16×16 pt **template** `NSImage`, drawn with `NSImage(size:flipped:drawingHandler:)`.
- It has a 1.5 pt circle outline and a filled pie wedge from 12 o'clock clockwise, proportional to `(progress + unvested) / P`.
- The wedge is quantized to 12 steps. Cache the 13 images and only swap when the step changes.

### 7.2 Menu bar panel (MenuBarExtra `.window` style, width 320)

`.onAppear` starts the 1 s panel refresh timer and `.onDisappear` stops it. Top to bottom, 16 pt padding, 16 pt spacing:

1. **Header row:** "myTime" (headline). On the right, a gear button that opens Settings. If `pending.count > 0`, a small capsule `"<n> pending"` next to it opens Settings on the Pending tab.
2. **Tamper banner** (only if `now < tamperNoticeUntil`): "Saved data was edited outside myTime, so balances were reset." Secondary style.
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
6. **Sessions block:**
   - Title "Sessions", with "`short(allowanceRemaining(thisWeek))` left this week" on the right.
   - If a session is active: row "Live · `short(end − now)` left", with **Extend 15 min** (only if `canExtendBooking`) and **End**.
   - Up to 3 upcoming rows: "`Today 8:05 PM` · `short(duration)`" with **Cancel**. Use "Today", "Tomorrow", or the abbreviated weekday.
   - Button **Book a Session…** opens the Booking window.
7. **Today strip:** three equal columns: "Focus" / `short(today.focusSeconds)`, "Earned" / `tokensEarned`, "Backed off" / `backedOff`.
8. **DEV only:** a row with "+1 token", "+5 min progress", "New day", "Reset state".

### 7.3 Gate (OverlayPanel, key-capable, width 420, centered on the screen with the mouse)

**Layout:**
- App icon (64 pt, from `NSWorkspace.shared.icon(forFile: bundleURL.path)`).
- Title: **"Still want to open <App>?"**
- Subtitle: `"<n> tokens · 1 token = <short(P)> of focus"` (e.g. "15 min"; "15 s" in DEV).
- **Pause phase** (`gatePauseSeconds`, default 5 s): a thin ring drains linearly around the icon, labeled `"Options unlock in <s>s"`. Everything except **Never mind** is disabled.
- **Choose phase:** show only the rows whose mode is enabled for the app.
  - **Quick look** card:
    - title "Quick look"
    - detail `"<quickLookSecondsPerToken> s per token"`
    - stepper `– n +` (1…min(quickLookMaxTokens, tokens))
    - button **"Open for `clock(n × sec)` · n ◆"**
  - **Reply mode** card:
    - title "Reply mode"
    - detail `"<replySeconds in min> min · <cost> ◆ · <left> of <perDay> left today"`
    - text field, placeholder "What are you here to do?"
    - button **"Open"**
    - When disabled, one secondary line shows the first applicable reason: "Write at least 8 characters" / "Needs <cost> tokens" / "No replies left today".
  - **If tokens == 0 and quick look or reply is enabled:** replace those cards with the text "No tokens yet. Your next one is `short(secondsToNextToken)` of focus away." and the button **Start Focus**.
  - **Sessions line** (if `.booked` is enabled):
    - with an upcoming booking: "Next session: `Today 8:05 PM`"
    - otherwise: "Sessions: none booked" plus a link-style button **Book a session…**
    - If `.booked` is the only mode, the subtitle becomes "<App> is available during booked sessions."
- **Never mind:** full-width prominent button at the bottom, with `.keyboardShortcut(.cancelAction)` (Esc). Nothing in the gate is bound to Return.
- **Footer link:**
  - if `emergencyUsesLeftThisWeek > 0`: "Emergency access"
  - otherwise, disabled text: "Emergency access used · resets Monday"

**Emergency sub-flow** (replaces the choose-phase content):
1. Title "Emergency access", body "Once a week. After a <wait>-second wait you'll get <access in min> minutes." Text field placeholder "What's the emergency?" Buttons **Start wait** (enabled once the reason has ≥ 15 characters) and **Back**.
2. Waiting: large `"Opening in <s>s"` and button **Cancel**, captioned "Your pass won't be used."
3. Ready: button **"Open <App> for <access in min> min"**. This calls `useEmergency`; on success, same behavior as a quick look.

Errors thrown by core intents appear as one secondary line under the relevant card, using `EngineError.userMessage`.

### 7.4 Focus card (same panel slot, width 360)

- Title **"You're focusing"**
- Body: `"<short(secondsToNextToken)> to your next token."`
- Buttons: **Back to work** (prominent) and **End focus…**. Esc = Back to work.

### 7.5 Countdown pill (OverlayPanel, non-activating, not key) — grants only

- Position: top-right of the main screen's `visibleFrame`, 12 pt inset, or wherever the user last dragged it (stored in UserDefaults `mytime.pillOrigin`, used only if still on a connected screen). Capsule, ~220×44 pt.
- Content: app icon (18 pt) + text.
  - `"<App> · clock(remaining)"`
  - for emergency grants: `"Emergency · clock(remaining)"`
- **Reply grants:** a second line with the note in quotes, truncated to one line (the pill grows to ~60 pt).
- **Last 10 s:** the text and icon tint cross-fade to the warm color (0.3 s). No pulsing or scaling. If `canExtend`, show a button **"+<quickLookSecondsPerToken> s · 1 ◆"**.
- Hidden when no running blocked app has an active grant.

### 7.6 Booking heads-up (OverlayPanel, non-activating, top-right like the pill, width 260)

- Shown once per booking on the `bookingHeadsUp` effect, and only if a `.booked` app is running. Otherwise it is skipped.
- Text: "Session ends in 5 minutes". Button **Extend 15 min** if `canExtendBooking`, otherwise no button.
- Auto-hides after 8 s. Clicking outside does nothing.

### 7.7 HoldButton and claim behavior

- **Label:** `"Hold to count <short(claimableSeconds)>"`. Append `" (daily limit)"` if `claimableSeconds < today.unclaimedAwaySeconds`.
- **Fill:** left-to-right over `Constants.holdToConfirm` (2 s) while pressed, using `onLongPressGesture(minimumDuration: 2, pressing:)`. Releasing early resets it.
- **Completion:** calls `model.confirmClaim()` (→ `core.confirmClaim()` + `refresh(.intent)`).
- **Accessibility:** an action named "Count away time" that confirms immediately.
- The claim never pops up. It is shown only via the dot (§7.1) and the panel row (§7.2).

### 7.8 Booking window (AppKit NSWindow via WindowRouter, "Book a Session", ~380×300, not resizable)

- **Day picker** (menu): Today, Tomorrow, then abbreviated weekday names up to 6 days out.
- **Start picker** (menu): slots every `bookingStartStepSeconds` (5 min) for the chosen day, in locale time style, listing only slots that pass rules 1–2. In DEV builds, list only the next 30 valid slots.
- **Duration picker** (menu): `bookingMinSeconds` … `bookingMaxSeconds` in `bookingDurationStepSeconds` steps, formatted with `short`.
- A line: `"<short(allowanceRemaining(weekOf: start))> left in that week"`.
- A live validation line: `validateBooking(...)?.userMessage`.
- Buttons: **Cancel** and **Book** (default, disabled while invalid). On success, close the window.

### 7.9 Settings window (AppKit NSWindow hosting SwiftUI `TabView`, ~560×520, "myTime Settings")

Header on every tab: "Changes that make myTime stricter apply right away. Changes that loosen it apply after `short(looseningDelaySeconds)`."

If `abs(clock.offsetSeconds) > 120`, also show: "Your Mac's clock was changed. myTime is ignoring the change (`short(abs(offset))`)."

**General tab**
- A `Form` grouped by §8.1 "Group". Each row has the title and a `Stepper` with the formatted value.
- The `dayStartHour` row shows the caption "Changing this always waits `short(looseningDelaySeconds)`."
- Rows edit a local **draft**. The bottom bar has **Revert** and **Apply Changes** (enabled when the draft differs).
- Apply submits each changed key, then shows an alert titled "Settings updated" listing `"Applied now: …"` and `"Applies <date, time>: …"` lines.

**Blocked Apps tab**
- Rows: icon, name, and three toggles: "Quick look", "Reply mode", "Sessions".
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
  - A new entry defaults to `modes: [.quickLook, .reply, .booked]`. Adding is tightening, so it applies immediately.

**Pending tab**
- List rows: summary, "Applies in `short(applyAt − now)`", **Cancel**. Empty state: "No pending changes."
- At the bottom, a destructive-style button **Uninstall myTime…** with an alert: "myTime will uninstall itself in `short(looseningDelaySeconds)`. You can cancel it here until then." Buttons **Schedule** and **Cancel**.

**History tab**
- The last 7 days of `history`, newest first, grouped by day ("Today", "Yesterday", weekday + date), each row showing time and text.

### 7.10 Error copy (`EngineError.userMessage`)

Cases that carry values: `invalidAmount(max:)`, `bookingTooSoon(leadSeconds:)`, `invalidDuration(minSeconds:maxSeconds:)`.

| Case | Message |
|---|---|
| `unknownApp` | "That app isn't blocked anymore." |
| `unknownGrant` | "That access has already ended." |
| `modeNotAllowed` | "That option is turned off for this app." |
| `focusActive` | "End your focus session first." |
| `invalidAmount` | "Choose between 1 and <max> tokens." |
| `notEnoughTokens` | "Not enough tokens." |
| `noteTooShort` | "Write at least 8 characters." |
| `replyLimitReached` | "No replies left today." |
| `cannotExtend` | "Can't extend right now." |
| `reasonTooShort` | "Write at least 15 characters." |
| `emergencyUnavailable` | "Emergency access used · resets Monday." |
| `bookingTooSoon` | "Book at least `short(lead)` ahead." |
| `bookingTooFar` | "Book up to 7 days ahead." |
| `invalidDuration` | "Choose a length between `short(min)` and `short(max)`." |
| `bookingOverlap` | "That overlaps another session." |
| `allowanceExceeded` | "Not enough session time left that week." |
| `cannotCancel` | "That session has already started." |
| `cannotExtendBooking` | "Can't extend this session." |

---

## 8. Settings and constants reference

### 8.1 SettingKey (user-configurable)

`SettingKey: String, CaseIterable, Codable`. Each case has `title`, `group`, `unit` (`.seconds`, `.count`, `.hourOfDay`), `defaultValue`, `range`, `step`, and `looserWhen` (`.higher`, `.lower`, `.anyChange`). In DEV builds, use the DEV default, and each range's lower bound becomes `min(release lower bound, 1)` (`dayStartHour` stays 0–23).

| rawValue | Title | Group | Default | DEV default | Range | Step | Looser when |
|---|---|---|---|---|---|---|---|
| `focusSecondsPerToken` | Focus per token | Earning | 900 | 15 | 300–3600 | 60 | lower |
| `dayStartHour` | Day starts at | Earning | 4 | 4 | 0–23 | 1 | any change |
| `idleThresholdSeconds` | Pause after no activity | Earning | 300 | 20 | 60–1800 | 60 | higher |
| `awayClaimSecondsPerDay` | Away time you can count per day | Earning | 1800 | 60 | 0–7200 | 300 | higher |
| `autoEndAwaySeconds` | End focus after away for | Earning | 1800 | 60 | 600–7200 | 300 | higher |
| `quickLookSecondsPerToken` | Quick look per token | Spending | 30 | 30 | 10–300 | 5 | higher |
| `quickLookMaxTokens` | Max tokens per quick look | Spending | 3 | 3 | 1–10 | 1 | higher |
| `replyTokenCost` | Reply mode cost | Spending | 2 | 2 | 1–10 | 1 | lower |
| `replySeconds` | Reply mode length | Spending | 180 | 60 | 60–900 | 30 | higher |
| `replyPerDay` | Reply mode uses per day | Spending | 3 | 3 | 0–10 | 1 | higher |
| `gatePauseSeconds` | Gate pause | Spending | 5 | 5 | 0–30 | 1 | lower |
| `weeklyAllowanceSeconds` | Session time per week | Sessions | 18000 | 1200 | 0–72000 | 1800 | higher |
| `bookingLeadSeconds` | Book at least this far ahead | Sessions | 600 | 60 | 0–86400 | 300 | lower |
| `bookingMaxSeconds` | Longest session | Sessions | 10800 | 600 | 1800–28800 | 900 | higher |
| `bookingExtensionSeconds` | Session extension | Sessions | 900 | 60 | 0–3600 | 300 | higher |
| `emergencyPerWeek` | Emergency passes per week | Emergency | 1 | 1 | 0–3 | 1 | higher |
| `emergencyWaitSeconds` | Emergency wait | Emergency | 60 | 10 | 10–600 | 10 | lower |
| `emergencyAccessSeconds` | Emergency access length | Emergency | 600 | 60 | 60–3600 | 60 | higher |
| `looseningDelaySeconds` | Delay for loosening changes | Safety | 86400 | 60 | 3600–604800 | 3600 | lower |

### 8.2 Constants (not user-configurable; `Constants.swift`)

| Name | Release | DEV |
|---|---|---|
| `launchGrace` | 15 s | 15 s |
| `extendWindow` | 10 s | 10 s |
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
| `minAwayGap` | 120 s | 10 s |
| `minClaimable` | 60 s | 5 s |
| `clockJumpTolerance` | 120 s | 120 s |
| `criticalWakeTolerance` | 1 s | 1 s |
| `normalWakeTolerance` | 5 s | 5 s |
| `minReplyNote` | 8 chars | 8 chars |
| `minEmergencyReason` | 15 chars | 15 chars |
| `historyCap` | 500 events | 500 events |
| `dailyRetentionDays` | 60 | 60 |
| `bookingRetentionDays` | 14 | 14 |

**Pruning** (only in an update where the daily reset ran): drop `daily` entries older than 60 days, `weekly` entries older than 10 weeks, bookings that finished or were canceled more than 14 days ago, and history beyond the newest 500.

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
| `CFBundleShortVersionString` / `CFBundleVersion` | `0.1.0` / `1` |
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
codesign --force --sign - "$APP"

launchctl bootout "gui/$(id -u)/local.mytime.agent" 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/myTime.app"
cp -R "$APP" "$HOME/Applications/myTime.app"
"$HOME/Applications/myTime.app/Contents/MacOS/myTime"   # installer mode: installs + starts the agent
echo "myTime installed ($MODE)."
```

`scripts/uninstall.sh`: `launchctl bootout gui/$(id -u)/local.mytime.agent || true`, then remove the plist and `~/Applications/myTime.app`. Leave Application Support in place. This is a deliberate developer escape hatch (§14).

### 10.3 DEV builds (`#if DEV_TIMESCALE`)

- DEV defaults and constants from §8.
- Data file `state-dev.json` and sentinel `mytime.dev.initialized`.
- `DEV ` prefix in the menu bar label.
- Panel debug row (§7.2):
  - "+1 token"
  - "+5 min progress" (via vest)
  - "New day" (`devSimulateNewDay` + refresh)
  - "Reset state" (writes `fresh`)
- `--foreground` launch flag is honored.

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
- Reply limit and claim budget are fresh on the new day.

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
- Quick look cost/duration and all error cases.
- Reply note trim/length, cost, daily limit.
- `startsAt` honors launch grace.
- Extension only within the last 10 s, and it consumes a token.
- Emergency grants can't be extended.
- Expiry emits `terminateIfNotAllowed`.
- `isAllowed` with a grant, with a booking + `.booked`, and with a booking without `.booked`.

**BookingRules**
- Each validation error (lead of 10 min: 9 min ahead fails, 10 min ahead passes).
- Overlap detection.
- Charged seconds for canceled, unopened, ended-early (rounded up to the minute), and extended bookings.
- `allowanceRemaining` per week, including forfeited.
- Extension rules.
- Heads-up emitted once.
- The end transition, including after `endBooking`, emits terminate effects.
- Booking allowed during focus.

**Emergency**
- Weekly limit.
- Reason length.
- Ends focus.
- The next week (Monday at `dayStartHour`) restores the pass.

**SettingsPolicy**
- Direction per key, including `.anyChange` for `dayStartHour`.
- Tightening applies immediately; loosening is scheduled at `now + delay`.
- The same fieldKey supersedes; a no-op cancels existing pending for that key.
- Apply-due order.
- Shortening the delay uses the old delay.
- Add app immediate; remove app scheduled; mode on scheduled / off immediate.
- Uninstall emits `.uninstall` when due.
- Values clamped to range.

**StateCodec**
- Round trip.
- Flipping one payload byte → `.tampered`.
- Garbage → `.tampered`.
- `penalized` has 0 tokens, forfeited allowance, and no emergency left.

**EnforcementPolicy**
- A table test covering all 7 rules.

**WakeUpPlanner**
- Returns the earliest candidate with the correct `critical` flag.
- When idle (not focusing, no grants, bookings, or pending changes), it returns exactly the next day start, non-critical.
- The focus interval is present only while focusing or away.

### 11.2 Manual test checklist (`docs/MANUAL_TESTS.md`)

Each run appends its steps, run against `scripts/build.sh --dev`. Each step states its expected result.

**Run 1**
1. **Install:** the menu bar shows `DEV ◆ 0`. `launchctl print gui/$(id -u)/local.mytime.agent` shows the job running.
2. **Keep-alive:** force quit myTime in Activity Monitor → it's back within ~5 s.
3. **Startup sweep:** with Discord open, `launchctl kickstart -k gui/$(id -u)/local.mytime.agent` → Discord quits with no gate.
4. **Gate, no tokens:** open Discord → it quits with no window flashing, the gate appears, options stay locked for 5 s, and "No tokens yet…" shows. Opening Discord again while the gate is up quits it quietly without a second gate. The gate can be dragged.
5. **Never mind:** Discord quits.
6. **Quick look:**
   - Press "+1 token" twice, open Discord, wait 5 s, buy 2.
   - Discord relaunches, and the pill and menu bar count down from 1:00 (after launch grace).
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

**Run 3**
14. **Reply mode:**
    - A note under 8 characters keeps Open disabled.
    - A valid note → the pill shows it.
    - The 4th reply today is refused.
15. **Booking:**
    - Book a 1-minute session starting ~1 minute ahead.
    - At the start, Discord opens freely with no gate and no pill, and the menu bar shows the hourglass.
    - 30 s before the end, the heads-up shows for 8 s.
    - At the end, Discord quits.
    - Book another and never open Discord → the allowance is fully refunded.
16. **Emergency:** from the gate, enter a 15+ character reason, wait 10 s, open → 1 minute of access. The gate then shows "Emergency access used".

**Run 4**
17. **Loosening:** raise "Session time per week" → the alert says it applies in ~1 minute, the Pending tab lists it, and it applies. Lower it → applies immediately.
18. **Day start:** change "Day starts at" → scheduled, never immediate.
19. **Blocked apps:** add TextEdit → opening it shows the gate. Remove TextEdit → pending, still blocked until applied.
20. **Clock tamper:** set the system time +2 h → no tokens gained, pending changes don't apply early, and Settings shows the clock-change note.
21. **File tamper:** edit one character in `state-dev.json`, then kickstart the agent → tokens are 0 and the tamper banner shows.
22. **Uninstall:** schedule uninstall → after ~1 minute myTime leaves the menu bar and is not relaunched, and `~/Applications/myTime.app` is in the Trash.

---

## 12. Runs (build in order; each run leaves a working app)

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

**Manual:** steps 8–13.

### Run 3 — Reply mode, sessions, emergency

**Core:** reply mode, `BookingRules` + transitions, emergency pass.

**App:**
- gate reply card, sessions line, emergency sub-flow and footer link
- panel sessions block
- `BookingView` + `WindowRouter`
- `HeadsUpView`
- menu bar booking row

**Tests:** grants/reply additions, BookingRules, Emergency.

**Manual:** steps 14–16.

### Run 4 — Safety and management

**Core:** `SettingsPolicy`, apply-due (update step 3), pruning, `.uninstall` effect.

**App:**
- Settings window: General with draft/apply, Blocked Apps with add/remove/toggles and alerts, Pending with uninstall, History
- pending capsule in the panel
- clock-change note, tamper banner
- `Installer.uninstall`
- adding a running app (§6.8)

**Tests:** SettingsPolicy.

**Manual:** steps 17–22, then re-run steps 1–7 against a release build (`scripts/build.sh`).

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
10. **No Quit menu item or command** anywhere. No "pause blocking" feature.
11. **Never auto-renew** grants or bookings.
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
- Charts and weekly reports beyond the History tab
- A custom app icon
- Localization

**Known bypasses** (accepted; each needs a deliberate, multi-step action):
- Terminal: `launchctl bootout`, `scripts/uninstall.sh`, rebuilding with `--dev`, or editing the source.
- System Settings → General → Login Items → "Allow in the Background" toggle for myTime (macOS lets users disable any LaunchAgent there).
- Changing the system clock *before* myTime starts after a boot. The offset can't be verified across reboots, so this could, for example, keep yesterday's tokens past the reset. The user shuts down nightly, so this window exists every morning; it still takes a deliberate clock change.
- Deleting both the state file and myTime's UserDefaults.
