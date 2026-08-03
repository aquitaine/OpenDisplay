# OpenDisplay Issues — Batch 4 (v0.9.0 targets)

Two features, each shippable independently. Same house rules as Batches 1–3: **decision logic
lives in the cross-platform SPM packages** (TopologyCore / DisplayDomain / SceneEngine) where
`make test` exercises it with injected fakes; macOS side effects are thin glue in the app.
Clean-room: built from public docs + first principles, no reference to other apps' code.

Build rules for implementers:
- `make test` must stay green (currently 431). Add tests for every pure-logic branch.
- All 4 schemes must build: `OpenDisplay`, `OpenDisplay-PublicAPIOnly`, `OpenDisplayRescue`, `opendisplay` CLI.
- After adding/removing source files: run `make xcode` (the xcodeproj is generated + gitignored).
- Settings decoding is **per-key lenient** — new keys must decode-default cleanly on old files and
  old builds must not be broken by new keys (0.7.1 lesson: never let one field throw away the file).
- New user-facing toggles default OFF unless stated.
- Respect the write funnels: user brightness → `AppModel.setBrightness`; adaptive/silent writes →
  `applyAdaptiveBrightness`; gamma composition → `writeGamma` (dim × warmth × boost).
- Precedence ladder today: FaceLight > App Presets > Clock Mode > Adaptive sync. New writers must
  slot in explicitly, not race.

---

## Issue A — Layout & Display-Config Protection ("Protected Layout")

**Value**: the single most-reported OpenDisplay annoyance ("my arrangement never sticks") and a
PRD §5.3 Core-1.0 line item (property protection). BetterDisplay ships this as Pro.

**Existing assets (do not rebuild):**
- `ProtectedConfig` + `DisplayConfigDrifter` (TopologyCore, pure, tested, **zero callers today**) —
  snapshot capture + record-by-record drift detection (`originMoved/modeChanged/rotationChanged/
  mirrorChanged/activeChanged/mainChanged/disconnected/appeared`).
- `ScenePlanner` (SceneEngine) — ordered restore plans toward a desired snapshot; `SceneRecorder`
  captures one. `applyScene` in AppModel already executes plans through the coordinator
  (checkpoint → apply → verify → audit).
- `DiskCheckpointStore`-style atomic JSON persistence patterns; `DiskAuditLog`; `NotificationPolicy`.

### Requirements

1. **Pure core (TopologyCore): `LayoutProtectionPolicy`.**
   - Model: a protected layout is keyed by its **display-set fingerprint** (the sorted set of
     member `DisplayRecordID`s), so "laptop alone" and "laptop + Desk" are separate protected
     layouts that can coexist. Store: `[fingerprint: ProtectedConfig]`.
   - `decide(current:protected:trigger:)` returns one of: `.noMatch` (no protected layout for this
     display set), `.clean`, `.restore(DriftAnalysis)`, `.ignore(reason)`. Pure, injectable clock.
   - **Which drifts trigger restore** (each individually testable):
     `originMoved`, `modeChanged`, `rotationChanged`, `mirrorChanged`, `mainChanged` → restore.
     `activeChanged` → restore **only** when the change is not explained by the managed-offline
     ledger (a display the user deliberately turned off must stay off — never fight
     `ManagedOfflineStore`). `appeared`/`disconnected` → `.noMatch` handling (different
     display set → look up that set's own protected layout instead).
   - **Anti-fight guards** (all unit-tested):
     - Suppression window: after OpenDisplay itself applies a change (scene apply, restore,
       user action through the app), suppress drift-restore for that generation — the app's own
       writes must never trigger a restore loop. Model as `noteSelfChange(generation:)`.
     - Debounce: only evaluate after topology has been stable for N seconds (reuse
       `awaitStableGeneration` semantics; default 3 s) — hotplug storms and wake emit bursts.
     - Retry cap: max 2 restore attempts per stable generation, then give up + notify
       ("Couldn't restore your protected layout") — never infinite-loop against macOS.
   - **Sleep rule (0.8.2 lesson)**: a *sleeping* display counts as present-and-active
     (`DisplayActivity.isActiveSurface`); drift evaluation must use the same activity predicate as
     the safety net, never raw `isActive`.

2. **Capture & persistence.**
   - "Protect current layout" captures a `ProtectedConfig` via `SceneRecorder.capture`-equivalent
     snapshot (arrangement origins, mode, rotation, mirror set, main, active/managed-off state)
     under the current fingerprint. Re-protecting overwrites.
   - Persist in `OpenDisplaySettings` (new keys `layoutProtectionEnabled: Bool = false`,
     `protectedLayouts: [String: ProtectedConfig] = [:]` — fingerprint string key). Per-key
     lenient decode, regression test with an old settings file.
   - "Update protection" (re-capture) and "Remove protection" per fingerprint.

3. **Restore execution (app glue).**
   - On the drift decision `.restore`, build a one-shot Scene from the protected snapshot
     (members = protected records, `required: false`, desired = origin/mode/rotation/mirror/main)
     and run it through the **existing** `applyScene` path so checkpointing, verification, audit
     logging, and the always-one-active safety net all apply for free. `activeChanged` restores go
     through the same lifecycle paths the menu uses (`reconnectOffline` / disconnect), not new code.
   - Triggers: topology-generation change (hotplug, arrangement drift), wake from sleep, app
     launch (after first stable snapshot).
   - Post a user notification on every auto-restore (respecting `displayNotificationsEnabled`):
     "Restored your protected layout" with the changed-fields summary from `DriftAnalysis`.
     Audit-log entries (`actor: "layoutProtection"`) for every restore attempt + outcome.

4. **UI (Settings → Arrange tab).**
   - Section "Protected layout": master toggle (`layoutProtectionEnabled`), status line for the
     *current* display set ("Protected · 2 displays · captured Jul 30" / "Not protected"),
     buttons **Protect Current Layout** / **Update** / **Remove**. List other stored fingerprints
     with display names + a remove affordance.
   - Menu bar: nothing new (keep the popover clean).

5. **CLI**: `opendisplay layout protect|unprotect|status` routed through `CommandGateway`
   (audited like everything else). `status` prints per-fingerprint protection + last restore.

### Acceptance criteria
- [ ] Pure policy: full decision table covered (each drift kind, ledger-explained activeChanged,
      suppression, debounce, retry cap, sleep-counts-as-active) — expect ~20+ new tests.
- [ ] Old settings.json decodes unchanged; new keys survive round-trip.
- [ ] `make test` green; all 4 schemes build; `make xcode` run if files added.
- [ ] [deferred: attended verification] Drag the external's origin in System Settings →
      OpenDisplay restores it within ~5 s + notification. Change resolution → restored. Set main
      to the other display → restored. Unplug/replug external → protected arrangement re-applied.
      Built-in deliberately off (managed-offline) stays off through all of the above.

---

## Issue B — Display Groups & Brightness Sync

**Value**: last Core-1.0 controls line item with zero code (`groups, sync`); BetterDisplay Free
(basic sync) + Pro (advanced sync). Distinct from Adaptive Display's built-in→external mirror:
groups are user-defined, any-member-drives-all, work with the built-in off.

### Requirements

1. **Pure core (TopologyCore): `DisplayGroup` + `GroupSyncPolicy`.**
   - Model: `DisplayGroup { id, name, memberRecordIDs: [DisplayRecordID], syncBrightness: Bool = true,
     syncContrast: Bool = false, offsetByMember: [DisplayRecordID: Float] }`. A display may belong
     to at most one group (enforced in the store logic; adding to a second removes from the first —
     tested).
   - `GroupSyncPolicy.followerWrites(leader:value:group:) -> [(member, value)]`:
     followers get `clamp01(value + offset[member])`; leader excluded; members not currently
     present are skipped (returned separately as `absent` so the caller can ignore them silently).
   - **Echo suppression** (the loop-killer, fully tested): sync-originated writes are marked; a
     marked write must never re-enter the policy. Model as a token/sequence the caller passes
     back (`SyncEcho.begin(leader:) -> token`, writes tagged with token are ignored as leaders).
   - **Offset learning**: when the user adjusts a *follower* directly (unmarked write to a display
     that is in a group but wasn't the leader), re-learn that member's offset as
     `newValue − leaderValue` instead of fighting: the group tracks intent, sliders never war.
     (Mirror of `AdaptiveDisplayPolicy.noteManualBrightness` semantics.)
   - **Precedence**: group sync sits **below** FaceLight and App Presets (a governed display is
     skipped exactly like `adaptiveTick` skips them) and **beside** manual writes: a user slider
     move on any member is the leader event. Adaptive Display and group sync are mutually
     exclusive per display: a display in a group is excluded from adaptive brightness targeting
     (tested), and the Settings UI says so.
   - Contrast sync (when `syncContrast`): same fan-out over the DDC contrast control; no offset
     learning for contrast (flat mirror), skipped for displays whose probe tracker says
     contrast is unsupported.

2. **Persistence**: `displayGroups: [DisplayGroup] = []` in `OpenDisplaySettings` (per-key
   lenient; round-trip + old-file regression tests).

3. **App wiring.**
   - `AppModel.setBrightness` (user funnel): after applying to the target, if the target is a
     grouped member and the write is unmarked → compute follower writes → apply each through the
     **silent** path (`applyAdaptiveBrightness`-style: no per-follower OSD, no manual-cooldown
     teaching, native/DDC/software method resolved per member as today). One OSD for the leader
     only. DDC writes ride the existing coalescing writers (`ddcTarget`/`drainDDCWrites`) — no
     new I2C pacing code.
   - Media-key brightness on a grouped target: same leader fan-out (media keys already land in
     `setBrightness`; verify + test at the policy level).
   - Follower-adjustment offset learning wired per 1.
   - `adaptiveTick`: skip displays that are members of any group (with the exclusion note in
     Settings under Adaptive Display).

4. **UI (Settings → Displays tab, new "Groups" card).**
   - Create/rename/delete group; membership checkboxes listing current + registry-known displays
     (by friendly name); per-member offset shown as a small ± slider (−0.5…+0.5); toggles for
     Sync brightness / Sync contrast. Empty state: "Group displays to move their brightness
     together."
   - A grouped display's detail row shows a subtle "synced with <group>" caption.

5. **CLI**: `group create|delete|list|add|remove` + selector `group:<name>` for existing verbs
   (`opendisplay set brightness 0.6 group:desk` fans out through the same policy). Routed through
   `CommandGateway`, audited.

### Acceptance criteria
- [ ] Pure policy: fan-out with offsets, clamp, absent-member skip, echo suppression, offset
      learning, one-group-per-display invariant, precedence/governed-skip, contrast flat-mirror —
      expect ~25+ new tests.
- [ ] Settings round-trip + old-file regression green.
- [ ] `make test` green; all 4 schemes build; `make xcode` run if files added.
- [ ] [deferred: attended verification] Group {built-in, Desk}: move built-in slider → Desk DDC
      brightness follows (offset applied); nudge Desk directly → offset re-learned, no war;
      media key on built-in → both move; OSD appears once; adaptive tick leaves both alone.

---

## Explicitly out of scope (both issues)
- Nits-normalized sync (needs a per-display nits model — separate future issue).
- Colour/gamma sync beyond contrast.
- Window placement restore (`Scene.Policy.windowPlacement` stays `unchanged`).
- Layout protection UI beyond the Arrange-tab section (no menu-bar surface).
