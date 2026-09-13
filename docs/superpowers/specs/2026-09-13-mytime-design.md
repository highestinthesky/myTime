# myTime — Design Doc (v1)

**Status:** Approved design · 2026-09-13
**Audience:** the implementing model (Codex) and the reviewer (Claude)

---

## 0. How to use this document

- Build **everything** in this document in one pass, working through the milestones in §12 in order.
- Where this doc gives exact values, names, strings, or rules, use them **verbatim**. Where it is silent, choose the simplest thing that satisfies the rules. **Do not add features** that are not described here (the only exception is the DEV debug controls in §10.3).
- §13 lists hard rules and pitfalls. They are non-negotiable.
- When finished, write `IMPLEMENTATION_NOTES.md` at the repo root listing: (a) every deviation from this doc and why, (b) anything you could not verify, (c) the exact commands you ran and their results.

---

## 1. Product summary

myTime is a macOS menu-bar app that makes distracting apps (Discord by default) cost something to open. The user earns **tokens** by running a **focus timer** while working. Opening a blocked app shows a **gate** with a mandatory 5-second pause; getting past it costs tokens (quick look, reply mode), uses a pre-booked **session** from a weekly allowance, or uses a once-a-week **emergency pass**. When access ends, myTime quits the app. myTime runs all the time, restarts itself if quit, and delays any change that would make it less strict by 24 hours.

It is for one person, on one Mac (Apple Silicon), installed locally without a developer certificate. No accounts, no network, no cloud.

### 1.1 Glossary

| Term | Meaning |
|---|---|
| **Blocked app** | An entry in the block list. Has a display name, one or more bundle IDs, and a set of allowed access modes. |
| **Token (◆)** | Currency earned by focus time. Spent on quick looks, reply mode, extensions. |
| **Progress** | Vested focus seconds toward the next token (`0 ≤ progress < focusSecondsPerToken`). |
| **Focus session** | An open-ended, user-started stopwatch during which eligible time is credited. |
| **Unvested time** | Focus time credited since the last keyboard/mouse input. Discarded if the user turns out to be idle. |
| **Away** | State entered when idle ≥ threshold or the screen locks during focus. Nothing is credited while away. |
| **Claim** | On return from away, the user may hold a button to count some away time as focus, within a daily budget. |
| **Gate** | Floating card shown when a blocked app is opened without access. |
| **Focus card** | Variant of the gate shown when a blocked app is opened during a focus session. |
| **Grant** | A paid, time-limited permission for one blocked app (kinds: quick look, reply, emergency). |
| **Quick look** | 1 token = 30 s of access, up to 3 tokens at once. |
| **Reply mode** | 2 tokens = 3 min, requires a typed intention note, max 3 per day. |
| **Booked session** | A pre-booked window (≥ 30 min ahead) during which apps with the "Sessions" mode open freely. Draws from the weekly allowance. |
| **Allowance** | Weekly budget of booked-session time (default 5 h, resets Monday 00:00 local). |
| **Emergency pass** | Once per week: typed reason + 60 s wait → 10 min access, no tokens needed. |
| **Tightening / loosening** | A settings change that makes myTime stricter / less strict. Tightening applies now; loosening waits `looseningDelaySeconds` (default 24 h). |
| **Pending change** | A scheduled loosening change, visible and cancellable until it applies. |
| **Trusted time** | Wall clock corrected for detected manual clock changes (§5.1). All deadlines use it. |

---

## 2. Key decisions and why

| Decision | Why |
|---|---|
| Menu-bar app (`LSUIElement`), no Dock icon | Must always run to enforce; token balance and timer should be glanceable; a Dock app is one ⌘Q from off. |
| Blocking = hide immediately, show gate, **quit** on decline/expiry | No official API exists. Hide/quit via `NSRunningApplication` needs **no permissions**. Quitting also silences the app's notifications, which are themselves triggers. The user confirmed they don't need to be reachable. |
| Self-declared focus + idle detection (not an app allowlist) | Allowlists break on legitimate browser/doc reading. The user works mostly on the Mac with some off-screen time, which the capped claim flow covers. |
| 5-second pause on the gate | The pause is what dissolves impulse opens; the token price mostly sets the budget. |
| Keep 15 min → 1 token → 30 s, but start the clock after launch grace, carry progress over, cap at 10 | The ratio is right for impulse checks. What would make it fail is launch time eating the window, lost partial progress, and hoarding for a binge. |
| Tokens for impulses, weekly allowance for planned sessions | Planned calls and gaming aren't the habit being broken and shouldn't compete for the same scarce currency. Booking ≥ 30 min ahead prevents impulse use. Booking is allowed during focus. |
| Reply mode with typed note and daily limit | Legitimate server/DM replies need more than 30 s. The note, limit, and visible history keep it from becoming a loophole. |
| Weekly emergency pass | A strict blocker the user gets stuck in gets uninstalled. One hard, rare exit is safer. |
| Tighten now, loosen after 24 h | The user is both admin and target; delay removes impulsive loosening. |
| launchd LaunchAgent with KeepAlive, no Quit | Quitting myTime would otherwise unblock everything instantly. |
| SwiftPM + shell script, no Xcode project | A generated `.pbxproj` is the most fragile artifact for a one-shot build; SwiftPM + a script is plain text and deterministic. |

---

## 3. Architecture

### 3.1 Stack and constraints

- Toolchain: Xcode 26 / Swift 6.x, `// swift-tools-version: 6.0`, **Swift 5 language mode** for all targets (`swiftLanguageModes: [.v5]`).
- Deployment target: macOS 14.0, arm64.
- UI: SwiftUI views. AppKit for panels, windows, `NSWorkspace`, `NSRunningApplication`.
- Allowed frameworks: Foundation, AppKit, SwiftUI, Observation, CryptoKit, CoreGraphics, UniformTypeIdentifiers. **No third-party dependencies.**
- No App Sandbox, no entitlements, no hardened runtime. Ad-hoc signed (`codesign -s -`).
- **Must not use:** network APIs, UserNotifications, Accessibility (AX) APIs, AppleScript/Apple Events, Input Monitoring, Screen Recording, SMAppService, SwiftUI `Settings`/`Window` scenes.
- Info.plist: `LSUIElement = YES`, `NSAppSleepDisabled = YES`.
- Performance target: ~0% CPU when idle, < 50 MB RSS. One 1 Hz timer, plus a 4 Hz timer only while an overlay is hiding an app.

### 3.2 Process model and installation

One executable, `myTime`, inside `~/Applications/myTime.app`. Its behavior depends on the arguments:

| Invocation | Behavior |
|---|---|
| no arguments (build script, double-click in Finder) | **Installer mode.** Write/repair the LaunchAgent plist, bootstrap or kickstart the agent, then `exit(0)`. No UI. |
| `--agent` | **Agent mode.** The actual app. Only launchd starts this. |
| `--foreground` (DEV builds only) | Run the app without launchd, for debugging. Ignored in release builds (treated as installer mode). |

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

Result: starts at login, and launchd restarts it within ~5 s after any quit, crash, or force quit.

**Installer mode steps** (`Installer.installAndStart()`):
1. Resolve `Bundle.main.executableURL`. If the path does not contain `.app/Contents/MacOS/`, print `myTime must be run from myTime.app (use scripts/build.sh)` to stderr and `exit(1)`.
2. Write the plist with `PropertyListSerialization` (create `~/Library/LaunchAgents` if needed).
3. Run `/bin/launchctl print gui/<uid>/local.mytime.agent`. If it fails, run `/bin/launchctl bootstrap gui/<uid> <plistPath>`. Otherwise run `/bin/launchctl kickstart gui/<uid>/local.mytime.agent`. `uid = getuid()`. Use `Process` and wait for exit.
4. `exit(0)`.

**Agent-mode self-heal:** every 60 s, if the plist file is missing or its `ProgramArguments[0]` differs from the current executable path, rewrite it. Do not bootstrap (the job is already loaded).

**Reopen:** if the user double-clicks myTime.app while the agent is running, LaunchServices re-activates the agent. Handle `applicationShouldHandleReopen` by opening the Settings window.

**Uninstall** (runs only when a pending `.uninstall` change applies, §5.6):
1. Set `isUninstalling = true` (stops self-heal) and save state.
2. Delete the plist file.
3. `FileManager.default.trashItem(at: <app bundle URL>)`; ignore errors.
4. Run `/bin/launchctl bootout gui/<uid>/local.mytime.agent` (this terminates the process). Fallback: `exit(0)` after 2 s.
5. Leave `~/Library/Application Support/myTime/` in place.

**App Nap:** in agent mode, call `ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "Enforcing app limits")` at launch and keep the token for the process lifetime.

### 3.3 Package layout

```
myTime App/
├── Package.swift
├── Packaging/
│   └── Info.plist
├── scripts/
│   ├── build.sh
│   └── uninstall.sh
├── Sources/
│   ├── MyTimeCore/                 # Foundation + CryptoKit only. Pure logic. Fully unit-tested.
│   │   ├── Model/
│   │   │   ├── SettingKey.swift        # enum + defaults/ranges/direction (§8)
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
│   │   │   ├── DurationFormat.swift
│   │   │   ├── EngineError.swift
│   │   │   └── EngineCore.swift        # façade: state + all intents + tick
│   │   └── Persistence/
│   │       └── StateCodec.swift        # HMAC envelope
│   └── MyTimeApp/                  # AppKit + SwiftUI glue and UI
│       ├── main.swift
│       ├── MyTimeScene.swift           # SwiftUI App with MenuBarExtra only
│       ├── AppDelegate.swift
│       ├── Engine/
│       │   ├── AppModel.swift          # @Observable @MainActor; owns EngineCore; tick; effects
│       │   ├── SystemProbe.swift       # clocks, boot session UUID, idle seconds, screen lock
│       │   ├── AppMonitor.swift        # NSWorkspace observers, running blocked apps
│       │   ├── Enforcer.swift          # applies EnforcementPolicy: hide/terminate/overlays
│       │   ├── StateStore.swift        # file IO, sentinel, tamper handling
│       │   ├── Installer.swift         # launchd install/self-heal/uninstall
│       │   └── WindowRouter.swift      # Settings & Booking NSWindows
│       └── UI/
│           ├── Theme.swift
│           ├── MenuBarLabel.swift
│           ├── PopoverView.swift
│           ├── FocusRing.swift
│           ├── TokenPips.swift
│           ├── OverlayPanel.swift      # NSPanel subclass + controller
│           ├── GateView.swift
│           ├── FocusCardView.swift
│           ├── PillView.swift
│           ├── ClaimPromptView.swift
│           ├── HoldButton.swift
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
    ├── MANUAL_TESTS.md
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
            │                                                                        │
 NSWorkspace│ AppMonitor ──events──▶ Enforcer ──hide/terminate──▶ NSRunningApplication│
 notifs ───▶│     │                     ▲  │                                          │
            │     │ running apps        │  └──show/close──▶ OverlayPanel (gate/card/  │
            │     ▼                     │                    pill/claim) ──intents─┐  │
 CGEvent/   │ SystemProbe ──readings──▶ AppModel ◀──────────────intents────────────┘  │
 sysctl ───▶│                           │  ▲  (PopoverView, BookingView, Settings)    │
            │                           │  │                                          │
            │                  tick(input)│ │effects                                  │
            │                           ▼  │                                          │
            │                    ┌── EngineCore (MyTimeCore, pure) ──┐                │
            │                    │ PersistedState + EngineRuntime    │                │
            │                    │ FocusAccrual · BookingRules ·     │                │
            │                    │ SettingsPolicy · TrustedClock ·   │                │
            │                    │ EnforcementPolicy                 │                │
            │                    └───────────────────────────────────┘                │
            │                           │ state                                       │
            │                           ▼                                             │
            │                      StateStore ──StateCodec──▶ state.json (HMAC)       │
            └────────────────────────────────────────────────────────────────────────┘
```

- **EngineCore** (Core) owns all rules and state. It never reads the clock or the system. Everything arrives through `TickInput` or method parameters. It returns `EngineEffect`s instead of performing side effects.
- **AppModel** (App) holds `var core: EngineCore`. It reads `SystemProbe` each tick, calls `core.tick`, runs effects, asks `Enforcer` to reconcile running apps, and saves via `StateStore`. All UI reads from and sends intents to `AppModel`.
- **Enforcer** (App) turns `EnforcementPolicy` decisions into hide/terminate calls and overlay presentation.

### 3.5 Tick loop (AppModel, every 1.0 s on `RunLoop.main` in `.common` mode)

1. `SystemProbe` readings: wall `Date()`, continuous seconds, uptime seconds, boot session UUID, idle seconds, screen locked.
2. `AppMonitor.runningBlockedApps()` → map to `Set<UUID>` of blocked-app IDs with a running `.regular` process.
3. `let effects = core.tick(TickInput(...))`. Inside, in order: trusted clock → apply due pending changes → focus accrual/away → expire grants → booking transitions → prune (once per new day key).
4. `Enforcer.reconcile(trigger: .poll)` for every running blocked app.
5. Execute effects (§4.9).
6. If `core.state` changed since the last save, save it (atomic write).

Also save on `applicationWillTerminate` and `NSWorkspace.willSleepNotification`.

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
    public var focus: FocusSession?            // nil = not focusing
    public var grants: [AccessGrant]
    public var bookings: [Booking]
    public var daily: [String: DailyStats]     // key: CalendarKeys.dayKey
    public var weekly: [String: WeeklyStats]   // key: CalendarKeys.weekKey
    public var history: [HistoryEvent]         // newest last, capped (§8.2)
    public var clock: TrustedClockState
    public var tamperNoticeUntil: Date?        // show tamper banner until this time

    public static func fresh(now: Date) -> PersistedState      // defaults, Discord blocked, 0 tokens
    public static func penalized(now: Date) -> PersistedState  // §5.7
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
    public subscript(key: SettingKey) -> Int   // returns numbers[key.rawValue] ?? key.defaultValue
}

public enum AccessMode: String, Codable, CaseIterable { case quickLook, reply, booked }

public struct BlockedApp: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var bundleIDs: [String]
    public var modes: Set<AccessMode>
}
```

Default block list (in `PersistedState.fresh`): one entry `name: "Discord"`, `bundleIDs: ["com.hnc.Discord", "com.hnc.DiscordPTB", "com.hnc.DiscordCanary"]`, `modes: [.quickLook, .reply, .booked]`.

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

A grant is **active** while `now < expiresAt`. It allows the app even before `startsAt`. Remaining time shown = `expiresAt − max(now, startsAt)`.

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
    public var warned: Bool            // 5-minute warning already emitted
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
}

public struct WeeklyStats: Codable, Equatable {
    public var emergencyUses: Int = 0
    public var allowanceForfeited: Bool = false   // set by tamper penalty
}

public enum HistoryKind: String, Codable {
    case focusStarted, focusEnded, tokenEarned, awayClaimed, quickLook, reply, extended,
         backedOff, bookingCreated, bookingCanceled, bookingEnded, bookingExtended,
         emergency, changeScheduled, changeApplied, changeCanceled, appAdded, appRemoved,
         tamperDetected
}

public struct HistoryEvent: Codable, Equatable, Identifiable {
    public var id: UUID
    public var date: Date
    public var kind: HistoryKind
    public var text: String        // pre-rendered human-readable line, e.g. "Reply mode in Discord — “reply to Sam in #capstone”"
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
    public var summary: String     // e.g. "Token cap: 10 → 20"
}

public enum SubmitResult: Equatable { case applied, scheduled(applyAt: Date), noChange }
```

### 4.7 Trusted clock state

```swift
public struct TrustedClockState: Codable, Equatable {
    public var offsetSeconds: Double = 0
    public var lastWall: Double = 0         // seconds since 1970
    public var lastContinuous: Double = 0   // CLOCK_MONOTONIC_RAW seconds
    public var bootSessionID: String = ""
}
```

### 4.8 Runtime-only state (not persisted)

```swift
public struct EngineRuntime: Equatable {
    public var unvestedSeconds: Double = 0
    public var lastUptime: Double? = nil
    public var lastIdle: Double = .infinity
    public var awayStartUptime: Double? = nil   // non-nil = away
    public var lastActiveBookingID: UUID? = nil // for detecting the active → finished transition
}
```

On load, the runtime starts fresh, so unvested time is lost on restart. That is intentional and errs on the strict side. Any booking that finished while myTime wasn't running is handled by the startup sweep (§6.7).

AppModel constructs the engine with `EngineCore(state: loaded, now: Date() + loaded.clock.offsetSeconds)`. From the first tick on, `now` is trusted time.

### 4.9 Tick input and effects

```swift
public struct TickInput {
    public var wall: Date
    public var continuous: Double       // CLOCK_MONOTONIC_RAW, seconds
    public var uptime: Double           // CLOCK_UPTIME_RAW, seconds
    public var bootSessionID: String
    public var idleSeconds: Double
    public var isLocked: Bool
    public var runningAppIDs: Set<UUID> // blocked-app IDs with a running regular process
}

public enum EngineEffect: Equatable {
    case showClaimPrompt(claimableSeconds: Double, awaySeconds: Double)
    case terminateIfNotAllowed(appID: UUID)
    case bookingWarning(bookingID: UUID)
    case focusAutoEnded
    case uninstall
}
```

AppModel handling of effects:

| Effect | Action |
|---|---|
| `showClaimPrompt` | Show the claim panel (§7.6). Replace any existing one. |
| `terminateIfNotAllowed` | For each running process of that app: if `!core.isAllowed(appID)`, terminate (§6.3). |
| `bookingWarning` | Expand the pill with "5 minutes left" for 5 s (§7.5). |
| `focusAutoEnded` | No UI beyond state change (history already recorded). |
| `uninstall` | `Installer.uninstall()`. |

---

## 5. Rules (implemented in MyTimeCore)

`EngineCore` exposes the intents below. Intents use `core.now` (the trusted time from the last tick). Throwing intents throw `EngineError`, which has a `userMessage: String` (copy in §7).

```swift
public struct EngineCore {
    public var state: PersistedState
    public var runtime: EngineRuntime
    public private(set) var now: Date
    public init(state: PersistedState, now: Date)

    public mutating func tick(_ input: TickInput) -> [EngineEffect]

    // Focus
    public mutating func startFocus()
    public mutating func endFocus()
    public mutating func confirmClaim(seconds: Double)
    public var secondsToNextToken: Double { get }     // max(0, perToken − progress − unvested)
    public var isAtCap: Bool { get }
    public var isAway: Bool { get }

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
    public func app(id: UUID) -> BlockedApp?
    public func app(bundleID: String) -> BlockedApp?

    // Settings
    public mutating func submit(_ change: SettingChange) -> SubmitResult
    public mutating func cancelPending(id: UUID)
    public func setting(_ key: SettingKey) -> Int
    public var today: DailyStats { get }

    #if DEV_TIMESCALE
    public mutating func devAddToken()                 // respects cap
    public mutating func devAddProgress(seconds: Double) // goes through vest()
    #endif
}
```

Every mutation that the user would care about appends a `HistoryEvent`.

**Effects come only from `tick`.** Intents never return effects. If an intent causes something that needs a side effect (e.g. `endBooking` should close apps), the next tick detects the state transition and emits the effect, within 1 s.

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

Moving the clock forward or back while the Mac is on gets cancelled out. Across a reboot, the offset is kept but can't be re-verified (a known gap, §14).

**CalendarKeys** (use `TimeZone.current`):
- `dayKey(date)` → `"yyyy-MM-dd"` from `Calendar(identifier: .gregorian)` components (no DateFormatter locale issues).
- `weekKey(date)` → `"YYYY-Www"` from `Calendar(identifier: .iso8601)` `yearForWeekOfYear` and `weekOfYear` (weeks start Monday).
- `startOfNextWeek(date)` → the next Monday 00:00 local.

### 5.2 Focus accrual and away (FocusAccrual)

Settings used: `focusSecondsPerToken` (P), `idleThresholdSeconds` (I), `autoEndAwaySeconds`, `awayClaimSecondsPerDay`, `tokenCap`.

**Per tick**, with `rt = runtime`:

```
d = rt.lastUptime == nil ? 0 : clamp(input.uptime - rt.lastUptime, 0, Constants.maxTickDelta /*2 s*/)
inputHappened = input.idleSeconds < rt.lastIdle || input.idleSeconds < 1.0
lastInputUptime = input.uptime - input.idleSeconds
defer { rt.lastUptime = input.uptime; rt.lastIdle = input.idleSeconds }

if let awayStart = rt.awayStartUptime:
    if !input.isLocked && inputHappened && input.idleSeconds < I:
        rt.awayStartUptime = nil
        gap = max(0, lastInputUptime - awayStart)
        claimable = min(gap, awayClaimSecondsPerDay - today.claimedAwaySeconds)
        if gap >= Constants.minAwayGapForPrompt /*120*/ && claimable >= Constants.minClaimable /*60*/ && tokens < cap:
            emit .showClaimPrompt(claimableSeconds: claimable, awaySeconds: gap)
    else if state.focus != nil && input.uptime - awayStart >= autoEndAwaySeconds:
        end focus WITHOUT vesting (history: "Focus ended after <N> min away"); emit .focusAutoEnded
    return

guard state.focus != nil else { return }

if input.isLocked || input.idleSeconds >= I:
    rt.awayStartUptime = lastInputUptime
    rt.unvestedSeconds = 0          // the idle minutes do not count
    return

if input.runningAppIDs.isEmpty:     // no credit while any blocked app is running
    rt.unvestedSeconds += d

if inputHappened:
    vest(rt.unvestedSeconds); rt.unvestedSeconds = 0
```

Away tracking continues after an auto-end, so the claim prompt can still appear when the user returns.

**vest(x):**

```
today.focusSeconds += x
state.focus?.creditedSeconds += x
if tokens >= cap: return                  // at cap: stats only, progress frozen
progress += x
while progress >= P && tokens < cap:
    progress -= P; tokens += 1; today.tokensEarned += 1
    history(.tokenEarned, "Earned a token")
```

**confirmClaim(seconds):** `x = min(seconds, awayClaimSecondsPerDay − today.claimedAwaySeconds)`. If `x > 0`, then `today.claimedAwaySeconds += x`, `vest(x)`, and append history `"Counted <N> min away as focus"`. This works even if the focus session has since ended (then `creditedSeconds` is not touched).

**startFocus():** no-op if already focusing. Otherwise `focus = FocusSession(startedAt: now, creditedSeconds: 0)`, reset `runtime` (keep `lastUptime` and `lastIdle`), and append history `"Started focus"`.

**endFocus():** `vest(unvested)`, then `unvested = 0`, `focus = nil`, `awayStartUptime = nil`, and append history `"Focus ended · <duration>"`.

**Stopping and restarting:** progress is never reset between sessions (carry-over).

### 5.3 Tokens and grants

Launch grace: `startsAt = max(now, (appLaunchDate ?? now) + Constants.launchGrace /*15 s*/)`.

**buyQuickLook(appID, tokens n):** throws if:
- the app lacks `.quickLook` → `.modeNotAllowed`
- focus is active → `.focusActive`
- `n` is not in `1...quickLookMaxTokens` → `.invalidAmount`
- `tokens < n` → `.notEnoughTokens`

Otherwise: `tokens -= n`, `today.tokensSpent += n`, `today.quickLooks += 1`. Create the grant with `kind .quickLook` and `duration = n × quickLookSecondsPerToken`. History: `"Quick look in Discord · 1:00 · 2 ◆"`.

**buyReply(appID, note):** `note` is trimmed. Throws if:
- the app lacks `.reply` → `.modeNotAllowed`
- focus is active → `.focusActive`
- `note.count < Constants.minReplyNote /*8*/` → `.noteTooShort`
- `tokens < replyTokenCost` → `.notEnoughTokens`
- `today.replies >= replyPerDay` → `.replyLimitReached`

Otherwise: `tokens -= cost`, `tokensSpent += cost`, `replies += 1`. Create a `.reply` grant with `duration = replySeconds` and `note`. History includes the note.

**Extensions:** `canExtend(grantID)` is true when the grant kind is `.quickLook` or `.reply`, the grant is active, `remaining ≤ Constants.extendWindow /*10 s*/`, and `tokens ≥ 1`. `extendGrant` checks this (throws `.cannotExtend`), then `expiresAt += quickLookSecondsPerToken`, `tokens -= 1`, `tokensSpent += 1`. History: `"Extended Discord · +30 s"`. Emergency grants cannot be extended. There is no automatic renewal, ever.

**Expiry (tick):** remove grants with `now ≥ expiresAt`. For each removed grant, emit `.terminateIfNotAllowed(appID)`.

**recordBackedOff(appID):** `today.backedOff += 1`, history `"Backed off from Discord"`.

**Spending while at cap** drops the balance below the cap, so earning resumes from the frozen progress.

**isAllowed(appID)** is true if either:
- an active grant exists for the app, or
- `activeBooking != nil` and the app's modes contain `.booked`.

### 5.4 Booked sessions (BookingRules)

Settings used: `weeklyAllowanceSeconds`, `bookingLeadSeconds`, `bookingMaxSeconds`, `bookingExtensionSeconds`. Constants: `bookingMinSeconds` (30 min), `bookingStepSeconds` (15 min), `bookingHorizonSeconds` (7 days).

**State of a booking at `now`:**
- *canceled*: `canceledAt != nil`
- *upcoming*: not canceled, `now < start`
- *active*: not canceled, `endedAt == nil`, `start ≤ now < end`
- *finished*: not canceled, and either `endedAt != nil` or `now ≥ end`

**Charged seconds** (what the booking counts against the allowance):
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
3. `duration < bookingMinSeconds || duration > bookingMaxSeconds || duration % bookingStepSeconds != 0` → `.invalidDuration`
4. overlaps any upcoming or active booking (`start < other.end && other.start < start + duration`) → `.bookingOverlap`
5. `allowanceRemaining(weekOf: start) < duration` → `.allowanceExceeded`

Booking is allowed while a focus session is running.

**cancelBooking:** only if upcoming (`.cannotCancel` otherwise). Sets `canceledAt = now`.

**endBooking:** if active, set `endedAt = now`. The next tick sees the active → finished transition and emits the terminate effects.

**canExtendBooking / extendBooking:** all of these must hold:
- the booking is active
- `extensionSeconds == 0` and `bookingExtensionSeconds > 0`
- `allowanceRemaining(weekOf: start) ≥ bookingExtensionSeconds`
- the new end does not overlap the next upcoming booking

Then `extensionSeconds = bookingExtensionSeconds`. History: `"Extended session · +15 min"`.

**Tick transitions:**
- If a booking is active and `runningAppIDs` contains any app with `.booked`, set `appOpened = true`.
- If a booking is active, `!warned`, and `end − now ≤ Constants.bookingWarning /*300 s*/`, set `warned = true` and emit `.bookingWarning`.
- If `runtime.lastActiveBookingID` is non-nil and that booking is no longer active (finished by time, ended early, or otherwise), append history `"Session ended"` and emit `.terminateIfNotAllowed` for every app with `.booked`. Then set `runtime.lastActiveBookingID = activeBooking?.id`.

### 5.5 Emergency pass

- `emergencyUsesLeftThisWeek = max(0, emergencyPerWeek − weekly[weekKey(now)].emergencyUses)`.
- The UI handles the reason entry and the `emergencyWaitSeconds` countdown (§7.3). Cancelling during the wait does **not** consume the pass.
- **useEmergency(appID, reason, appLaunchDate):** `reason` is trimmed. Throws `.reasonTooShort` if `reason.count < Constants.minEmergencyReason /*15*/`, or `.emergencyUnavailable` if no uses are left.
  - Then: `emergencyUses += 1`; if focusing, `endFocus()`.
  - Create an `.emergency` grant with `duration = emergencyAccessSeconds`, `tokensSpent 0`, and `note = reason`.
  - History: `"Emergency access to Discord — “<reason>”"`.

### 5.6 Settings and pending changes (SettingsPolicy)

**isLoosening(change, settings):**

| Change | Loosening when |
|---|---|
| `.setNumber(key, v)` | `key.looserWhen == .higher ? v > current : v < current` |
| `.addApp` | never |
| `.removeApp` | always |
| `.setMode(_, _, enabled)` | `enabled == true && mode not currently enabled` |
| `.uninstall` | always |

**submit(change):**

```
remove pending items with the same fieldKey (history .changeCanceled only if the user cancels explicitly, not here)
if change is a no-op (same number; mode already in that state; app already present by bundle ID; removing a missing app):
    return .noChange
if isLoosening:
    append PendingChange(applyAt: now + setting(.looseningDelaySeconds), summary)
    history(.changeScheduled, "Scheduled: <summary> (applies <date>)")
    return .scheduled(applyAt)
apply(change); history(.changeApplied / .appAdded, "<summary>")
return .applied
```

- **Values are clamped** to the key's range (§8.1) before comparing.
- **Changing the loosening delay itself:** shortening it is loosening, so it waits out the *current* delay.
- **Apply due (tick):** for pending items with `now ≥ applyAt`, in `applyAt` order, apply them and append history `"Applied: <summary>"`. For `.uninstall`, emit `.uninstall`. If the target app no longer exists, drop the item silently.
- **cancelPending(id):** remove it and append history `"Canceled: <summary>"`. Cancelling is always immediate.

**Summaries** (exact formats):
- `"<Setting title>: <old> → <new>"` using `DurationFormat.setting(key, value)`
- `"Add <App>"`, `"Remove <App>"`
- `"Turn on <Mode title> for <App>"`, `"Turn off <Mode title> for <App>"`
- `"Uninstall myTime"`

Mode titles: quickLook → "Quick look", reply → "Reply mode", booked → "Sessions".

### 5.7 Integrity and tamper handling

**File:**
- release builds: `~/Library/Application Support/myTime/state.json`
- DEV builds: `state-dev.json`

**Envelope:**

```json
{ "v": 1, "payload": "<base64 of JSON-encoded PersistedState>", "mac": "<lowercase hex HMAC-SHA256 of the payload bytes>" }
```

- The key is `SymmetricKey(data: SHA256.hash(data: Data("myTime.integrity.v1.7c1e9b4a-5d2f-4e8a-9f61-2b3c4d5e6f70".utf8)))`.
- `StateCodec.decode(data) -> DecodeResult` returns `.ok(PersistedState)` or `.tampered`, and never throws. It returns `.tampered` for unparseable envelopes, bad base64, bad hex, a MAC mismatch, or payload decode failure. Verify with `HMAC<SHA256>.isValidAuthenticationCode(_:authenticating:using:)`, which compares in constant time.
- Writes use `Data.write(to:options: .atomic)`.

**Load logic (StateStore):**

| Situation | Result |
|---|---|
| File present, `.ok` | Use it. |
| File missing, UserDefaults bool `mytime.initialized` (DEV: `mytime.dev.initialized`) is false | `PersistedState.fresh(now:)`; set the sentinel true **after the first successful save**. |
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
public enum EnforcementTrigger { case launched, activated, poll, startupSweep }
public enum EnforcementAction: Equatable { case allow, gate, focusCard, keepHidden, terminate }

public struct EnforcementContext {
    public var isAllowed: Bool
    public var focusActive: Bool
    public var overlayShowingForThisProcess: Bool   // gate/card slot owned by this pid
    public var overlayBusyWithOtherProcess: Bool    // gate/card slot owned by a different pid
    public var isFrontmost: Bool
    public var launchedRecently: Bool   // launchDate within Constants.recentLaunch (10 s)
}

public static func decide(trigger: EnforcementTrigger, context: EnforcementContext) -> EnforcementAction
```

Rules, first match wins:
1. `isAllowed` → `.allow`
2. `overlayShowingForThisProcess` → `.keepHidden`
3. `trigger == .startupSweep` → `.terminate`
4. `overlayBusyWithOtherProcess` → `.terminate`
5. `trigger == .poll && !isFrontmost && !launchedRecently` → `.terminate`
6. `focusActive` → `.focusCard`
7. otherwise → `.gate`

---

## 6. Enforcement (MyTimeApp)

### 6.1 Detection

`AppMonitor` subscribes on `NSWorkspace.shared.notificationCenter` (main queue) to:
- `didLaunchApplicationNotification` → trigger `.launched`
- `didActivateApplicationNotification` and `didUnhideApplicationNotification` → trigger `.activated`
- `didTerminateApplicationNotification` → close any overlay owned by that pid

The running application is `userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication`.

A process is a **blocked process** if `bundleIdentifier` exactly equals one of a blocked app's `bundleIDs` **and** `activationPolicy == .regular`. Match exactly, never by prefix; Discord's helper processes must not match.

The tick-driven `.poll` and a `.startupSweep` at agent launch catch anything the notifications miss.

### 6.2 Enforcer.reconcile(process, trigger)

Build an `EnforcementContext` from `core` and overlay state, call `EnforcementPolicy.decide`, then act:

| Action | Behavior |
|---|---|
| `.allow` | Nothing. |
| `.keepHidden` | If `!process.isHidden`, call `process.hide()`. |
| `.terminate` | §6.3. |
| `.gate` | `process.hide()`, then present the gate for `(appID, pid, launchDate)`. |
| `.focusCard` | `process.hide()`, then present the focus card for `(appID, pid, launchDate)`. |

While a gate or focus card is showing, run a 0.25 s timer that re-applies `.keepHidden` to its process (Electron apps re-show windows as they load). Stop that timer when the overlay closes.

### 6.3 Terminating

Call `process.terminate()`. After 5 s (`Constants.forceQuitAfter`), if `!process.isTerminated`, call `process.forceTerminate()`. Track pending force-quits by pid so they aren't scheduled twice.

### 6.4 Overlay ownership

- **Overlay slot:** at most one gate or focus card at a time. It is owned by one app process.
- **Pill:** at most one. It shows the running allowed blocked app with the least remaining access.
- **Claim prompt:** at most one. It is independent of the other two.

### 6.5 Gate outcomes

**Backed off rule:** whenever a gate or focus card closes without the app being opened, call `core.recordBackedOff` exactly once. The only exception is when the process terminated on its own.

| User action | Result |
|---|---|
| Never mind / Esc / 60 s of no interaction | Backed off, terminate the process, close the gate. |
| Quick look / Reply succeeds | Close the gate, `process.unhide()`, `NSApp.yieldActivation(to: process)`, `process.activate()`, show the pill. |
| Start Focus (0-token state) | Backed off, `core.startFocus()`, terminate the process, close the gate. |
| Book a session… | Backed off, open the Booking window, terminate the process, close the gate. |
| Emergency flow completes | Same as a successful quick look. |
| Process terminates while the gate is open | Close the gate; no stat. |
| Focus becomes active while the gate is open | Swap the gate content to the focus card. |

Any interaction with the gate (click, typing, stepper) resets the 60 s timeout. The timeout is suspended during the emergency wait, and timing out at any other point behaves like Never mind (an emergency pass not yet used stays unused).

### 6.6 Focus card outcomes

| User action | Result |
|---|---|
| Back to work / Esc / 60 s timeout | Backed off, terminate the process, close the card. |
| End focus… | `core.endFocus()`, then swap to the gate (with the full 5 s pause). |

### 6.7 Startup sweep

On agent launch, after loading state and running the first tick, call `reconcile(trigger: .startupSweep)` for every running blocked process. Blocked apps that launched at login get quit silently.

### 6.8 Adding an app while it runs

In Settings, if the chosen app is running, the confirmation says it will be closed. After adding, the next poll handles it: terminate unless it is frontmost or recently launched, in which case it gets gated.

---

## 7. UX flows, screens, and copy

Tone: calm, neutral, factual. No guilt, no exclamation marks, no red.

Formatting helpers (`DurationFormat`):
- `clock(s)`: `m:ss` under 1 h, `h:mm:ss` otherwise
- `short(s)`: `"45 s"`, `"12 min"`, `"2h 10m"`
- `setting(key, v)`: formats by the key's unit

Token glyph: `◆` (U+25C6). Pluralize "token"/"tokens".

### 7.1 Menu bar label (MenuBarLabel)

An SF Symbol plus text, `monospacedDigit()`. Precedence, first match:

| State | Symbol | Text |
|---|---|---|
| A running blocked app is allowed (grant or booking) | `hourglass` | `clock(least remaining)` |
| Focusing and away | `pause.circle` | `clock(secondsToNextToken)` |
| Focusing at cap | `timer` | `Full` |
| Focusing | `timer` | `clock(secondsToNextToken)` |
| Otherwise | `diamond.fill` | `"<tokens>"` |

DEV builds prefix the text with `DEV `.

### 7.2 Popover (MenuBarExtra, `.window` style, width 320)

Top to bottom, 16 pt padding, 16 pt spacing:

1. **Header row:** "myTime" (headline). On the right, a gear button that opens Settings. If `pending.count > 0`, show a small capsule `"<n> pending"` next to it that opens Settings on the Pending tab.
2. **Tamper banner** (only if `now < tamperNoticeUntil`): "Saved data was edited outside myTime, so balances were reset." Secondary style.
3. **Focus block:** FocusRing (160 pt diameter, 10 pt stroke), filled to `(progress + unvested) / P`.

   | State | Ring center | Caption | Button |
   |---|---|---|---|
   | Not focusing | `clock(secondsToNextToken)`, with "to next token" below | — | **Start Focus** (prominent) |
   | Focusing | `clock(secondsToNextToken)`, with "to next token" below | "This session · `short(creditedSeconds + unvested)`" | **End Focus** |
   | Away | same | "Paused — no activity" | **End Focus** |
   | At cap | "Full" | "Spend a token to keep earning" | Start/End Focus as usual |

4. **Tokens row:** TokenPips (`tokenCap` diamonds, filled = tokens; if cap > 12, show no pips, only one `diamond.fill`), then `"<tokens> / <cap> tokens"`.
5. **Sessions block:**
   - Title "Sessions", with "`short(allowanceRemaining(thisWeek))` left this week" on the right.
   - If a session is active: row "Live · `clock(end − now)` left", with buttons **Extend 15 min** (only if `canExtendBooking`) and **End**.
   - Up to 3 upcoming rows: "`Today 8:00 PM` · `short(duration)`" with a **Cancel** button. Use "Today", "Tomorrow", or the abbreviated weekday.
   - Button **Book a Session…** opens the Booking window.
6. **Today strip:** three equal columns: "Focus" / `short(today.focusSeconds)`, "Earned" / `tokensEarned`, "Backed off" / `backedOff`.
7. **DEV only:** a row with buttons "+1 token", "+5 min progress", "Reset state".

### 7.3 Gate (OverlayPanel, key-capable, width 420, centered on the screen with the mouse)

**Layout:**
- App icon (64 pt, from `NSWorkspace.shared.icon(forFile: bundleURL.path)`).
- Title: **"Still want to open <App>?"**
- Subtitle: `"<n> tokens · 1 token = <P in min> min of focus"`.
- **Pause phase** (`gatePauseSeconds`, default 5 s): a thin ring drains linearly around the icon, with the label `"Options unlock in <s>s"`. Everything except **Never mind** is disabled.
- **Choose phase:** show only the rows whose mode is enabled for the app.
  - **Quick look** card:
    - title "Quick look"
    - detail `"<quickLookSecondsPerToken> s per token"`
    - a stepper `– n +` (1…min(quickLookMaxTokens, tokens))
    - button **"Open for `clock(n × sec)` · n ◆"**
  - **Reply mode** card:
    - title "Reply mode"
    - detail `"<replySeconds in min> min · <cost> ◆ · <left> of <perDay> left today"`
    - text field, placeholder "What are you here to do?"
    - button **"Open"**
    - When disabled, one secondary line shows the first applicable reason: "Write at least 8 characters" / "Needs <cost> tokens" / "No replies left today".
  - **If tokens == 0 and quick look or reply is enabled:** replace those cards with the text "No tokens yet. Your next one is `short(secondsToNextToken)` of focus away." and the button **Start Focus**.
  - **Sessions line** (if `.booked` is enabled):
    - with an upcoming booking: "Next session: `Today 8:00 PM`"
    - otherwise: "Sessions: none booked" plus a link-style button **Book a session…**
    - If `.booked` is the only mode: title stays, subtitle becomes "<App> is available during booked sessions."
- **Never mind:** full-width prominent button at the bottom, with `.keyboardShortcut(.cancelAction)` (Esc). Do not bind Return to anything in the gate.
- **Footer link:**
  - if `emergencyUsesLeftThisWeek > 0`: "Emergency access"
  - otherwise, disabled text: "Emergency access used · resets Monday"

**Emergency sub-flow** (replaces the choose-phase content):
1. Title "Emergency access", body "Once a week. After a <wait>-second wait you'll get <access in min> minutes." Text field placeholder "What's the emergency?" Buttons **Start wait** (enabled once the reason has ≥ 15 characters) and **Back**.
2. Waiting: large `"Opening in <s>s"` countdown and button **Cancel** with caption "Your pass won't be used."
3. Ready: button **"Open <App> for <access in min> min"**. This calls `useEmergency`; on success, same behavior as a quick look. The 60 s timeout applies again. Timing out behaves like Never mind and does not use the pass.

Errors thrown by core intents appear as one secondary line under the relevant card, using `EngineError.userMessage`.

### 7.4 Focus card (same panel slot, width 360)

- Title **"You're focusing"**
- Body: `"<short(secondsToNextToken)> to your next token."`, or at cap: "Your tokens are full."
- Buttons: **Back to work** (default) and **End focus…**

### 7.5 Countdown pill (OverlayPanel, non-activating, not key)

- Position: top-right of the main screen's `visibleFrame`, 12 pt inset. Capsule, ~220×44 pt.
- Content: app icon (18 pt) + text.
  - Grants: `"<App> · clock(remaining)"`.
  - Emergency: `"Emergency · clock(remaining)"`.
  - Booked session: `"Session · clock(end − now)"` plus a small **End** button.
- **Reply grants:** a second line with the note in quotes, truncated to one line (the pill grows to ~60 pt tall).
- **Last 10 s** (grants): the accent switches to the warm color and the capsule pulses, unless Reduce Motion is on. If `canExtend`, show a button **"+<quickLookSecondsPerToken> s · 1 ◆"**.
- **Booking warning effect:** expand for 5 s with the line "5 minutes left", plus **Extend 15 min** if `canExtendBooking`.
- Hidden when no allowed blocked app is running.

### 7.6 Claim prompt (OverlayPanel, non-activating, top-center of the main screen, width 340)

- Line 1: `"You were away <short(awaySeconds)>."`
- Line 2: "Count it as focus?"
- **HoldButton:**
  - label `"Hold to count <short(claimable)>"`
  - if `claimable < awaySeconds`, append `" (daily limit)"`
  - it fills left-to-right over 2 s while pressed (`onLongPressGesture(minimumDuration: 2, pressing:)`); releasing early resets it; completion calls `core.confirmClaim(claimable)`
- Secondary button **Don't count**.
- Auto-dismisses after 120 s (= don't count).

### 7.7 Booking window (AppKit NSWindow via WindowRouter, titled "Book a Session", ~380×300, not resizable)

- **Day picker** (menu): Today, Tomorrow, then abbreviated weekday names up to 6 days out.
- **Start picker** (menu): slots every `bookingStepSeconds` for the chosen day, formatted with the user's locale time style. Only slots that pass rules 1–2 are listed. In DEV builds, list only the next 30 valid slots.
- **Duration picker** (menu): `bookingMinSeconds` … `bookingMaxSeconds` in `bookingStepSeconds` steps, formatted with `short`.
- A line: `"<short(allowanceRemaining(weekOf: start))> left in that week"`.
- A live validation line showing `validateBooking(...)?.userMessage`.
- Buttons: **Cancel** and **Book** (default, disabled while invalid). On success, close the window.

### 7.8 Settings window (AppKit NSWindow hosting SwiftUI `TabView`, ~560×520, titled "myTime Settings")

Header text on every tab: "Changes that make myTime stricter apply right away. Changes that loosen it apply after `short(looseningDelaySeconds)`."

If `abs(clock.offsetSeconds) > 120`, also show: "Your Mac's clock was changed. myTime is ignoring the change (`short(abs(offset))`)."

**General tab**
- A `Form` grouped by §8.1 "Group". Each row shows the title and a `Stepper` with the formatted value.
- Rows edit a local **draft** copy. The bottom bar has **Revert** and **Apply Changes** (enabled when the draft differs).
- Apply submits each changed key and then shows an alert:
  - title "Settings updated"
  - message listing `"Applied now: …"` lines and `"Applies <date, time>: …"` lines

**Blocked Apps tab**
- A list of rows: icon, name, and three toggles: "Quick look", "Reply mode", "Sessions".
  - Turning a toggle **on** shows an alert "This loosens myTime" / "It will apply <date, time>." with **Schedule** and **Cancel**. Turning one **off** applies immediately.
  - A toggle with a pending change shows a small clock badge with the tooltip "On <date, time>".
- **Remove…** per row shows the same loosening alert, then schedules. A row with a pending removal shows "Removal <date, time>".
- **Add App…** opens an `NSOpenPanel`:
  - `allowedContentTypes [.application]`, starting in `/Applications`
  - Read the bundle ID via `Bundle(url:)`.
  - **Reject** with an alert if:
    - there is no bundle ID → "That app can't be blocked."
    - the bundle ID is myTime's own → "myTime can't block itself."
    - the path starts with `/System/` → "System apps can't be blocked."
    - it's already in the list → "<App> is already blocked."
  - If the app is running, confirm first: "<App> is running and will be closed." with **Add** and **Cancel**.
  - A new entry defaults to `modes: [.quickLook, .reply, .booked]`. Adding is tightening, so it applies immediately.

**Pending tab**
- A list of pending changes: summary, "Applies in `short(applyAt − now)`", and a **Cancel** button.
- Empty state: "No pending changes."
- At the bottom, a destructive-style button **Uninstall myTime…** with an alert: "myTime will uninstall itself in `short(looseningDelaySeconds)`. You can cancel it here until then." Buttons **Schedule** and **Cancel**.

**History tab**
- The last 7 days of `history`, newest first, grouped by day ("Today", "Yesterday", weekday + date), each row showing time and text.

### 7.9 Error copy (`EngineError.userMessage`)

| Case | Message |
|---|---|
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

`SettingKey: String, CaseIterable, Codable`. Each case has `title`, `group`, `unit` (`.seconds` or `.count`), `defaultValue`, `range`, `step`, `looserWhen` (`.higher` or `.lower`). In DEV builds, use the DEV default, and every range's lower bound becomes 1.

| rawValue | Title | Group | Default | DEV default | Range | Step | Looser when |
|---|---|---|---|---|---|---|---|
| `focusSecondsPerToken` | Focus per token | Earning | 900 | 15 | 300–3600 | 60 | lower |
| `idleThresholdSeconds` | Pause after no activity | Earning | 300 | 20 | 60–1800 | 60 | higher |
| `awayClaimSecondsPerDay` | Away time you can count per day | Earning | 1800 | 60 | 0–7200 | 300 | higher |
| `autoEndAwaySeconds` | End focus after away for | Earning | 1800 | 60 | 600–7200 | 300 | higher |
| `tokenCap` | Token cap | Earning | 10 | 10 | 1–100 | 1 | higher |
| `quickLookSecondsPerToken` | Quick look per token | Spending | 30 | 30 | 10–300 | 5 | higher |
| `quickLookMaxTokens` | Max tokens per quick look | Spending | 3 | 3 | 1–10 | 1 | higher |
| `replyTokenCost` | Reply mode cost | Spending | 2 | 2 | 1–10 | 1 | lower |
| `replySeconds` | Reply mode length | Spending | 180 | 60 | 60–900 | 30 | higher |
| `replyPerDay` | Reply mode uses per day | Spending | 3 | 3 | 0–10 | 1 | higher |
| `gatePauseSeconds` | Gate pause | Spending | 5 | 5 | 0–30 | 1 | lower |
| `weeklyAllowanceSeconds` | Session time per week | Sessions | 18000 | 1200 | 0–72000 | 1800 | higher |
| `bookingLeadSeconds` | Book at least this far ahead | Sessions | 1800 | 60 | 0–86400 | 900 | lower |
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
| `bookingWarning` | 300 s | 30 s |
| `bookingMinSeconds` | 1800 | 60 |
| `bookingStepSeconds` | 900 | 60 |
| `bookingHorizonSeconds` | 604800 | 604800 |
| `gateTimeout` | 60 s | 60 s |
| `forceQuitAfter` | 5 s | 5 s |
| `holdToConfirm` | 2 s | 2 s |
| `claimPromptTimeout` | 120 s | 120 s |
| `minAwayGapForPrompt` | 120 s | 10 s |
| `minClaimable` | 60 s | 5 s |
| `maxTickDelta` | 2 s | 2 s |
| `clockJumpTolerance` | 120 s | 120 s |
| `recentLaunch` | 10 s | 10 s |
| `minReplyNote` | 8 chars | 8 chars |
| `minEmergencyReason` | 15 chars | 15 chars |
| `historyCap` | 500 events | 500 events |
| `dailyRetentionDays` | 60 | 60 |
| `bookingRetentionDays` | 14 | 14 |
| `selfHealInterval` | 60 s | 60 s |
| `tickInterval` | 1.0 s | 1.0 s |
| `rehideInterval` | 0.25 s | 0.25 s |

Pruning (once per new day key): drop `daily` entries older than 60 days, `weekly` entries older than 10 weeks, bookings that finished or were canceled more than 14 days ago, and history beyond the newest 500.

---

## 9. Visual design

- **Feel:** a quiet native utility. System materials, generous spacing, one accent color.
- **Colors** (`Theme.swift`, adaptive light/dark via `NSColor(name:dynamicProvider:)`):
  - accent (sage-teal): light `#2F8F83`, dark `#5BC0B2`
  - warm (last-seconds state): light `#D98A1F`, dark `#F2B24C`
  - everything else: system semantic colors (`.primary`, `.secondary`, `.quaternary`)
- **Surfaces:**
  - gate, focus card, and claim prompt: `.regularMaterial` background, corner radius 22, subtle 1 pt `.separator` stroke, window shadow
  - pill: `.thickMaterial` capsule
  - inner option cards in the gate: `.quaternary.opacity(0.5)` fill, radius 12
- **Typography:**
  - timers and counts: `.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()` in the ring; `.system(.body, design: .rounded).monospacedDigit()` in the pill and menu bar
  - titles: `.title3.weight(.semibold)`; body: default system font
- **Motion:**
  - gate/card appear: fade + scale 0.97→1.0, 0.2 s ease-out
  - pause ring: linear drain over `gatePauseSeconds`
  - focus ring progress: 0.3 s ease-in-out
  - pill last-10-s pulse: scale 1.0↔1.04, 0.6 s autoreverse
  - honor `accessibilityReduceMotion`: no scale and no pulse, fades only
- **OverlayPanel:**
  - `NSPanel` subclass, `styleMask [.borderless, .nonactivatingPanel]` (the gate drops `.nonactivatingPanel` and overrides `canBecomeKey = true` so its text fields work)
  - `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`
  - `level = .floating` (gate: `.modalPanel`)
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
  - `hidesOnDeactivate = false`
  - content via `NSHostingView`
  - when showing the gate, call `NSApp.activate()` (macOS 14 API) and `makeKeyAndOrderFront(nil)`
- **Accessibility:**
  - every button has a label
  - the hold button exposes an accessibility action "Count away time" that performs the confirm immediately (VoiceOver users can't hold)
  - text contrast follows system colors

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
| `NSAppSleepDisabled` | `true` |
| `NSHighResolutionCapable` | `true` |

### 10.2 `scripts/build.sh` (bash, `set -euo pipefail`, executable)

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
- Popover debug row (§7.2): "+1 token" (respects cap), "+5 min progress" (calls vest), "Reset state" (writes `fresh`).
- `--foreground` launch flag is honored.

---

## 11. Testing

### 11.1 Unit tests (`swift test`, XCTest, MyTimeCoreTests)

Build `EngineCore` with fixed dates and feed synthetic `TickInput`s. Required cases:

**TrustedClock**
- A forward jump of +3 h within the same boot session → trusted time advances only by the continuous delta.
- A backward jump → cancelled.
- 30 s of drift → accepted (offset unchanged).
- A new boot session ID → offset kept, no adjustment.

**CalendarKeys**
- The day key flips at local midnight.
- The week key for Sunday vs Monday differs, and Monday starts a new week.

**FocusAccrual**
- Credits `d` per tick only while focusing, not away, and with no blocked app running.
- 900 s of vested time mints exactly 1 token, and the remainder carries over.
- Carry-over persists across end/start of sessions.
- Unvested time is discarded when idle crosses the threshold, so a 5-min idle credits 0 for those minutes.
- Input vests unvested time.
- The screen lock enters away immediately.
- At cap: no progress, but `focusSeconds` still increases.
- Return from away emits `showClaimPrompt` with claimable limited by the daily budget. No prompt if gap < 120 s, claimable < 60 s, or at cap.
- `confirmClaim` vests, respects the budget, and works after auto-end.
- Auto-end after `autoEndAwaySeconds` of away.
- `maxTickDelta` clamps large deltas.

**Grants**
- Quick look cost/duration and all error cases.
- Reply note trim/length, cost, daily limit.
- `startsAt` honors launch grace.
- Extension only within the last 10 s, and it consumes a token.
- Emergency grants can't be extended.
- Expiry removes the grant and emits `terminateIfNotAllowed`.
- `isAllowed` with a grant, with a booking + `.booked` mode, and with a booking without `.booked` mode.

**BookingRules**
- Each validation error.
- Overlap detection.
- Charged seconds for canceled, unopened, ended-early (rounded up to the minute), and extended bookings.
- `allowanceRemaining` per week, including forfeited.
- Extension rules (once, allowance, overlap).
- The 5-min warning emitted once.
- The end transition emits terminate effects.
- Booking allowed during focus.

**Emergency**
- Weekly limit.
- Reason length.
- Ends focus.
- Week rollover restores the pass.

**SettingsPolicy**
- Direction per key (higher/lower).
- Tightening applies immediately.
- Loosening is scheduled at `now + delay`.
- The same fieldKey supersedes.
- A no-op cancels existing pending for that key.
- Apply-due order.
- Shortening the delay uses the old delay.
- Add app immediate; remove app scheduled; mode on scheduled / off immediate.
- Uninstall scheduled, then emits `.uninstall` when due.
- Values clamped to range.

**StateCodec**
- Round trip.
- Flipping one payload byte → `.tampered`.
- Garbage → `.tampered`.
- `penalized` has 0 tokens, forfeited allowance, and no emergency left.

**EnforcementPolicy**
- A table test covering all 7 rules.

### 11.2 Manual test checklist (`docs/MANUAL_TESTS.md`)

Write this file with these steps, run against `scripts/build.sh --dev`. Each step has an expected result.

1. **Install:** the menu bar shows `DEV ◆ 0`. `launchctl print gui/$(id -u)/local.mytime.agent` shows the job running.
2. **Keep-alive:** force quit myTime in Activity Monitor → it's back in the menu bar within ~5 s.
3. **Startup sweep:** open Discord, run `launchctl kickstart -k gui/$(id -u)/local.mytime.agent` → Discord quits with no gate.
4. **Gate, no tokens:** open Discord → it's hidden, the gate appears, options are locked for 5 s, the no-tokens state shows **Start Focus**.
5. **Never mind:** Discord quits and "Backed off" increments.
6. **Earn:** Start Focus, keep using the Mac for ~15 s → 1 token (DEV rate).
7. **Idle:** during focus, don't touch anything for 20 s → the label shows the pause icon and progress falls back. Touch the mouse after ~30 s → the claim prompt appears. Hold 2 s → progress increases.
8. **Focus card:** open Discord during focus → focus card. **Back to work** quits Discord.
9. **Quick look:** end focus, get ≥ 2 tokens (debug button), open Discord, wait 5 s, buy 2 tokens → Discord appears, the pill counts from 1:00 (after launch grace). At ≤ 10 s the pill turns warm and offers +30 s. At 0, Discord quits.
10. **Reply mode:** a note < 8 chars is disabled. A valid note → the pill shows the note. The 4th reply today is refused.
11. **Booking:** book a session 1 min ahead for 1 min (DEV) → at start, Discord opens freely with no gate; the pill shows Session; 30 s before the end, the warning appears; at the end, Discord quits. Book another and never open Discord → allowance fully refunded.
12. **Emergency:** from the gate, enter a 15+ character reason, wait 10 s, open → 1 min of access. The gate then shows "Emergency access used".
13. **Loosening:** raise the token cap in General → the alert says it applies in ~1 min, the Pending tab lists it, it applies after 1 min. Lower the cap → applies immediately.
14. **Blocked apps:** add TextEdit → opening TextEdit shows the gate. Remove TextEdit → pending, and still blocked until applied.
15. **Clock tamper:** set the system time +2 h in System Settings → no tokens are gained, pending changes don't apply early, and Settings shows the clock-change note.
16. **File tamper:** edit one character in `state-dev.json`, then kickstart the agent → tokens are 0 and the tamper banner shows.
17. **Uninstall:** schedule uninstall → after 1 min myTime disappears from the menu bar and is not relaunched, and `~/Applications/myTime.app` is in the Trash.

---

## 12. Milestones (in order, one pass)

Each milestone ends with the stated checks passing before you move on.

### M1 — Foundations
- `Package.swift`, `Packaging/Info.plist`, `scripts/build.sh`, `scripts/uninstall.sh`.
- Core models (§4), `SettingKey`/`Constants` (§8), `TrustedClock`, `CalendarKeys`, `DurationFormat`, `StateCodec`, and the `EngineCore` skeleton with `tick` running the trusted clock.
- App: `main.swift` with the modes, `Installer` (install, self-heal, uninstall), `SystemProbe`, `StateStore` (load/save/sentinel/tamper), `AppModel` tick loop, `MyTimeScene` with MenuBarExtra showing the token label, and an empty popover shell.
- Unit tests for TrustedClock, CalendarKeys, StateCodec.
- **Checks:** `swift build` and `swift test` pass. `scripts/build.sh --dev` installs; the menu bar shows `DEV ◆ 0`; force quit → relaunch.

### M2 — Blocking, gate, quick look, pill
- `AppMonitor`, `EnforcementPolicy` (+ tests), `Enforcer`, `OverlayPanel`, `GateView` (pause, Never mind, quick look, no-tokens state), grants in `EngineCore` (buy, extend, expire, isAllowed) + tests, `PillView`, startup sweep, force-quit fallback, DEV debug row.
- **Checks:** manual steps 3, 4, 5, 9.

### M3 — Earning
- `FocusAccrual` in `EngineCore` + tests, idle and lock probing, `FocusRing`, `TokenPips`, the popover focus block and tokens row, `FocusCardView`, `ClaimPromptView` + `HoldButton`, the today strip.
- **Checks:** manual steps 6, 7, 8.

### M4 — Reply, sessions, emergency
- Reply mode (core + gate card), `BookingRules` + tests, the popover sessions block, `BookingView` + `WindowRouter`, booking enforcement, pill session state and warning, emergency core + gate sub-flow.
- **Checks:** manual steps 10, 11, 12.

### M5 — Safety and management
- `SettingsPolicy` + tests, apply-due in tick, the Settings window (General with draft/apply, Blocked Apps with add/remove/toggles and alerts, Pending with uninstall, History), clock-change note, tamper banner, pruning, App Nap activity, `docs/MANUAL_TESTS.md`, `IMPLEMENTATION_NOTES.md`.
- **Checks:** manual steps 1, 2, 13–17. The full `swift test` passes. The release build (`scripts/build.sh`) installs and runs with release defaults.

---

## 13. Hard rules and pitfalls

1. **Swift 5 language mode.** Mark `AppModel`, `Enforcer`, `AppMonitor`, `WindowRouter`, overlay controllers, and all views `@MainActor`. Use `Timer` for periodic work. Do not use `Task.sleep` loops or detached tasks.
2. **MyTimeCore imports only Foundation and CryptoKit.** It must never call `Date()`, read clocks, or touch AppKit. Time and system state come in through parameters.
3. **Public API:** every Core type, property, method, and initializer used by the app target must be `public`. Memberwise initializers are *not* public, so write explicit `public init`s.
4. **Dictionaries:** use `[String: Int]` / `[String: DailyStats]`. Enum-keyed dictionaries encode as arrays in JSON; don't use them.
5. **No Xcode project,** no SwiftUI `Settings` or `Window` scenes, and no `@main` attribute. `main.swift` dispatches on arguments and calls `MyTimeScene.main()` in agent mode.
6. **Do not use:** UserNotifications, AX/Accessibility APIs, AppleScript, Screen Recording, SMAppService, the network, App Sandbox, or entitlements.
7. **Match blocked processes by exact bundle ID** and `.regular` activation policy.
8. **Terminate politely first,** then force after 5 s.
9. **No Quit menu item or command** anywhere. No "pause blocking" feature.
10. **Never auto-renew** grants or bookings.
11. Idle seconds: `CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)`. Use `.hidSystemState` so synthetic "mouse jiggler" events don't count as activity. Screen lock: `CGSessionCopyCurrentDictionary()` key `"CGSSessionScreenIsLocked"` present and true.
12. **Persist on every meaningful change** (dirty flag, saved at the end of the tick), on sleep, and on terminate. Always use atomic writes.
13. **Keep files focused** (roughly ≤ 300 lines). Put logic in Core; views stay declarative.
14. `swift build` must finish with **zero errors**. Deprecation warnings (e.g. `activate(ignoringOtherApps:)`) are acceptable.
15. **Do not invent features, settings, or copy** not in this doc (DEV debug row excepted). If something is impossible as specified, implement the closest behavior and record it in `IMPLEMENTATION_NOTES.md`.

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

**Known bypasses** (accepted; each requires a deliberate, multi-step action):
- Terminal: `launchctl bootout`, `scripts/uninstall.sh`, rebuilding with `--dev`, or editing the source.
- System Settings → General → Login Items → "Allow in the Background" toggle for myTime (macOS lets users disable any LaunchAgent there).
- Changing the system clock *and* rebooting before myTime starts (the offset can't be verified across boots).
- Deleting both the state file and myTime's UserDefaults.
