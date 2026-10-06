# myTime Runs 5–10 — iPhone client and shared wallet — Implementation Plan (DRAFT)

> **Status: draft for review. Nothing here is built or approved.** Source: the *myTime Expansion Proposal* (Oct 5, 2026) and its AI Prompting Summary. Anything marked **Recommendation** or **To verify** is a suggestion or an unconfirmed Apple behavior, not an established fact.

> **For the implementing agent:** Read `AGENTS.md` first. Per `AGENTS.md`, **update the spec before code** (Task 5.0). Work the runs in order. **Do not commit**; the reviewer commits.

**Goal:** One token balance, one focus session, and one per-app unlock (single purchase, single deduction, single expiry) shared by the Mac app and a new iPhone app.

**Proposal rules this plan must preserve** (do not weaken):
- One purchase, one balance deduction, one expiry honored by both devices.
- No separate device budgets, no separate purchases, no all-app unlock.
- Switching devices never produces duplicate focus credit; the same tokens are never spent twice, including offline.
- Focus is self-declared time, not proof of productivity.
- Calm tone, no guilt, no exclamation marks, no sounds.

**Order of work.** Prove the riskiest thing first (iPhone re-lock timing), then prove the sync rules with no network, then add real infrastructure last.

| Run | Scope | Needs paid Apple account | Est. (vibe-coded) |
|---|---|---|---|
| 5 | Spec revision + iPhone enforcement spike | Likely yes (**to verify**) | 3–6 days |
| 6 | Ledger + merge rules in Core, fault-injection tests | No | 4–6 days |
| 7 | Mac integrates the ledger; two-instance DEV test over a file transport | No | 3–5 days |
| 8 | iPhone app, Screen Time extensions, App Group state | Yes | 2–3 weeks |
| 9 | CloudKit transport, Mac signing, real Mac↔iPhone sync | Yes | 1–2 weeks |
| 10 | Hardening, sync-status UX, beta prep | Yes | 1–2 weeks |

Total is roughly **6–10 weeks** of focused work. Device testing and Apple's Family Controls distribution approval (calendar weeks, outside our control) dominate, not code. Apply for that approval during Run 5.

**Go/no-go gates**
- After **Run 5:** if iPhone cannot re-lock reliably at a window length the product can live with, stop and decide (D1) before Run 6.
- After **Run 7:** if the sync rules misbehave under fault injection, fix before touching iOS.

---

## Open decisions (answer before the run that needs them)

| # | Decision | Needed by | Recommendation |
|---|---|---|---|
| D1 | Shortest unlock window iPhone can honor. Mac quick looks are 30 s per token today. | Run 5 | Measure first. If iOS can't re-lock short windows, either raise the shared window for both devices or document a minimum. Don't promise a duration before the spike. |
| D2 | Who credits focus when a session is started on one device and the user works on the other? | Run 6 | Each device reports vested **intervals**; credit is the union of intervals, so overlap can't double count. Mac vests with its idle detection; iPhone reports only while its own client confirms the session is running. |
| D3 | Offline double-spend policy. | Run 6 | Allow offline spending from the last-synced balance. On merge, an overdraw becomes a **debt** that later earnings pay off. Never revoke an unlock already given. |
| D4 | Same app bought on both devices while offline. | Run 6 | Overlapping duplicate purchase is voided and refunded; extensions are not duplicates. |
| D5 | Mac signing for CloudKit. Today: ad-hoc, no entitlements. | Run 9 | Development signing for own Macs; Developer ID + notarization before any outside beta. |
| D6 | Which modes sync in the first iPhone release. | Run 8 | Tokens/quick look only. Bookings, reply mode and emergency pass stay Mac-only until platform-tested (the proposal says they still need testing). |
| D7 | iOS needs an Xcode project (app extensions, entitlements). This reverses the spec's "SwiftPM, no Xcode project" for iOS only. | Run 8 | Human creates the `.xcodeproj` once in Xcode; the agent never generates a `.pbxproj`. Mac stays SwiftPM. |

---

## Run 5 — Spec revision and iPhone enforcement spike

**Why first:** enforcement on iPhone is the make-or-break risk and does not depend on sync.

### Task 5.0 — Spec revision 8 (docs only, no code)
- [ ] Add §sync to the spec: shared wallet, focus register, unlock entitlement, offline policy, sync-status copy (new user-facing copy must exist in the spec before any UI uses it).
- [ ] Amend the rules that sync necessarily breaks, each listed in the revision notes:
  - §3.1 / `AGENTS.md` conventions 2 and 8: network allowed **only** inside the sync transport (CloudKit); entitlements and real signing allowed for sync; UserNotifications allowed **on iOS only** (Mac stays without).
  - §14: remove "Phones or other devices" and "sync, cloud" from out of scope; keep websites out of scope.
- [ ] Record D1–D7 answers once given.
- [ ] Bump the revision line and update `README.md` / `AGENTS.md` if commands or counts change.

### Task 5.1 — Spike app (throwaway, not committed to `Sources/`)
Human creates a bare iOS Xcode project on the paid developer account. Build the minimum to answer:
- [ ] Select one app with the Family Activity picker; shield it with `ManagedSettingsStore`.
- [ ] Remove the shield for N seconds, then re-shield. Try (a) `DeviceActivitySchedule` windows shorter than 15 min (**to verify:** the system may reject short intervals), (b) 15-min schedule plus thresholds, (c) an in-app timer, (d) a local notification as a nudge.
- [ ] Shield Action button flow: what can the shield do on tap, and can it get the user into myTime to buy access (**to verify**)?
- [ ] State handoff through an App Group container to the extensions; note extension memory/time limits.
- [ ] Survive: app force-quit, reboot, Low Power Mode, airplane mode.
- [ ] Measure re-shield latency (expected vs actual) over 20+ trials per mechanism.

**Deliverable:** a short results table appended to `IMPLEMENTATION_NOTES.md` under `## Run 5`: mechanism, shortest window honored, worst-case lateness, failure modes. This answers D1.

### Task 5.2 — Apply for Family Controls (Distribution)
- [ ] Human submits Apple's entitlement request. TestFlight and App Store need it; development builds don't (**to verify**).

---

## Run 6 — Ledger and merge rules in Core

**Idea (Recommendation):** make tokens a *derived view* of an append-only ledger so any two devices converge regardless of delivery order. Core stays pure Swift (Foundation + CryptoKit), no clocks, no `Date()`. It already builds for iOS if `Package.swift` adds `.iOS(.v17)`.

### Model (`Sources/MyTimeCore/Sync/`, each file ≤ ~300 lines)
- `DeviceID`, `HybridStamp` (wall ms, counter, device ID; total order, passed in as input, never read from a clock).
- `FocusInterval { id: "<sessionID>/<deviceID>/<start>", dayKey, start, end }` — merge by ID, keep the larger `end`.
- `Purchase { id, appKey, dayKey, kind, tokens, seconds, createdAt }` — add-only set.
- `UnlockGrant`: `appKey` + set of purchase IDs. **Expiry is derived**: `createdAt + Σ purchase seconds`; tokens spent derived from the set. Concurrent extensions both count because both were paid.
- `SharedFocus { sessionID, state, stamp }` — last-writer-wins by `HybridStamp`. Concurrent starts: lower session ID wins deterministically.
- `SharedEconomy { focusSecondsPerToken, quickLookSecondsPerToken, quickLookMaxTokens, dayStartHour, stamp }` — last-writer-wins. Needed so both devices compute the same balance. Tightening applies now; loosening reuses the existing 24 h pending-change rule. Other settings stay per-device.
- `AppKey` = cross-device identity for a blocked app. iOS app selections are opaque and device-local, so each device maps its own local selection to an `AppKey` (user pairs "Discord" on both). Bundle IDs stay Mac-side.
- `LedgerState.merge(_:)` — pure, **commutative, associative, idempotent**.
- `Balance`: `tokens(dayKey) = floor(unionSeconds(intervals) / focusSecondsPerToken) − Σ purchases − debt`; daily reset is free because entries carry a `dayKey` and only the current key counts.

### Tasks (tests first; once written they are the contract and are copied verbatim)
- [ ] 6.1 `LedgerMergeTests`: merge is commutative, associative, idempotent; duplicate and out-of-order delivery converge; three-device permutations.
- [ ] 6.2 `FocusCreditTests`: overlapping intervals from Mac and iPhone count once; start on one device, stop on the other; concurrent start; interval extended after a partition.
- [ ] 6.3 `SpendTests`: same purchase delivered twice charges once; offline overdraw becomes debt, not revocation (D3); duplicate overlapping purchase voided and refunded (D4); extension is not a duplicate; one purchase unlocks the app on both devices with one expiry.
- [ ] 6.4 `DayBoundaryTests`: reset at day start; entries from different time zones keep the writer's `dayKey`.
- [ ] 6.5 `FaultyTransportTests` (in-memory transport that delays, reorders, duplicates, drops, goes offline): all replicas converge after healing.
- [ ] 6.6 `MigrationTests`: schema 1 → 2 turns the existing `tokens`/`progressSeconds` into an opening entry; `StateCodec` HMAC still verifies.
- [ ] 6.7 Refactor `EngineCore` so `tokens`/`progressSeconds` are materialized from the ledger. **All 126 existing tests must pass unchanged.** This is the riskiest step; do it last in this run, in small commits-worth of change.

**Done when:** `swift test` passes, formatted, and `IMPLEMENTATION_NOTES.md` has `## Run 6`.

---

## Run 7 — Mac integrates the ledger (still no network)

Pure Mac, no accounts. Validates the sync rules end to end.

- [ ] New SwiftPM target `MyTimeSync` (Foundation only): `SyncTransport` protocol, `SyncCoordinator`, `FileTransport` (a shared folder), `FaultyTransport` for tests. CloudKit is **not** added here.
- [ ] `EngineEffect.grantArrived(appID:)`: a remote unlock lifts a visible gate and relaunches the app, mirroring what `buyQuickLook` does locally.
- [ ] `StateStore`: schema 2, HMAC kept; separate DEV state dir per instance (`state-dev.json` today) so two DEV instances can run side by side.
- [ ] Sync triggers are events only (state change, app foreground, one scheduled retry). **No polling timer**; any retry `Timer` sets `tolerance`.
- [ ] Panel: quiet sync line (copy defined in Task 5.0). Never a pop-up.
- [ ] `docs/MANUAL_TESTS.md`: two DEV instances against one folder — start focus on A, stop on B, earn once; buy on A, unlocked on B with the same expiry; disconnect, spend on both, reconnect, observe debt rule.

**Gate:** sync rules proven under fault injection and with two live instances.

---

## Run 8 — iPhone client

- [ ] D7: human creates the Xcode project: app target, Shield Configuration, Shield Action and Device Activity Monitor extensions, App Group, Family Controls capability. `MyTimeCore` and `MyTimeSync` are linked as local Swift packages.
- [ ] State lives in the App Group container as the same schema-2 file; extensions read it to decide shielding. Keep extensions small (memory limits, **to verify**).
- [ ] Use the mechanism Run 5 proved for re-shielding; implement the D1 outcome.
- [ ] iOS UI: wallet balance, start/stop focus, per-app unlock for tokens (D6 scope), pairing of local app selection with `AppKey`, sync status.
- [ ] iOS gate flow follows Run 5's findings. Keep the 5-second pause behavior unless the shield cannot support it; record any deviation.
- [ ] Real-device test matrix: unlock on iPhone → Mac unlocks; unlock on Mac → iPhone unlocks; expiry on both; airplane mode; force-quit; reboot.

---

## Run 9 — CloudKit and Mac signing

- [ ] `MyTimeCloudKit` target: CloudKit **private database** adapter implementing `SyncTransport`. CloudKit is eventually consistent with no cross-record transactions, which the Run 6/7 fault-injection tests already cover.
- [ ] Records are the ledger entries (immutable, keyed by deterministic ID) so retries are idempotent; `SharedFocus` and `SharedEconomy` are single records resolved by `HybridStamp`.
- [ ] Push-driven change notifications (silent push) instead of polling.
- [ ] Mac: real signing identity, entitlements plist, embedded provisioning profile, iCloud container. Update `scripts/build.sh` (currently ad-hoc `codesign -s -`) and re-verify LaunchAgent self-heal, install to `/Applications`, and uninstall.
- [ ] Clock skew: unlock expiry is absolute UTC. Estimate device skew from server timestamps and document tolerance; the Mac `TrustedClock` stays authoritative on Mac.
- [ ] iCloud signed out, account change, container reset: define calm behavior in the spec first.

---

## Run 10 — Hardening and beta prep

- [ ] "Other device hasn't received an update" states for all screens (stale, offline, long-offline), copy from the spec.
- [ ] Revisit bypasses in §14 for iPhone: deleting the app, removing Screen Time authorization, toggling the extensions. List them as known bypasses; don't promise more than the spike showed.
- [ ] Website bypass remains out of scope on both platforms; say so in README.
- [ ] Beta logistics (D5): TestFlight for iOS (needs the distribution entitlement), Developer ID + notarization for Mac.
- [ ] Measurement hooks for the beta questions in the proposal, kept **local-only** (no analytics network): both clients active, apps accessed on both devices, token management burden, compulsion to spend.

---

## Risks, by likelihood × impact

1. **iPhone can't re-lock short windows** (Run 5). Mitigation: spike first; D1.
2. **Entitlement approval delay.** Mitigation: apply in Run 5; development builds proceed meanwhile.
3. **Run 6.7 refactor regresses the Mac app.** Mitigation: 126 existing tests are the guard; ledger is a view behind the same public API.
4. **Offline spend UX feels punitive.** Mitigation: debt rule, no revocation, neutral copy.
5. **Signing change breaks LaunchAgent/installer** (Run 9). Mitigation: manual test pass on a release build.
6. **Scope creep** into bookings/reply/emergency on iPhone. Mitigation: D6; revisit after beta signals.

## Not in this plan
Website blocking, pricing and payment model, final earn rate and access-window durations (proposal leaves them open), Android, a custom backend.
