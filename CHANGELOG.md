# Changelog

All notable changes to OpenDisplay are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/). OpenDisplay is pre-1.0 (0.x); anything may
change until 1.0.

## [0.11.5] — 2026-10-09

### Added
- **Brightness in the Controls card.** Settings → Displays → Controls now starts with the same
  brightness slider as the menu bar (with its "Hardware · DDC" / "Software · gamma" caption), so you
  no longer have to go back to the menu bar to adjust the display you're looking at. It's there
  even on monitors that report no other hardware controls.
- **Reset to defaults.** A new "Reset to defaults…" button at the bottom of the Controls card asks
  the monitor to restore its factory settings (brightness, contrast, colour mode and whatever else
  it resets) and clears OpenDisplay's software dimming and colour temperature for that display, then
  re-reads everything. Also available as `opendisplay ddc <selector> reset`.
- **Detect supported colour modes.** Beside the Colour mode menu, "Detect…" asks the monitor which
  colour modes it actually supports and narrows the menu to those. It only runs when you click it:
  a few monitors stop answering DDC after this query until they're power-cycled.

### Fixed
- **Controls and colour mode now tell you when the monitor ignores a change** instead of showing a
  value the monitor isn't at. Some monitors accept a change and silently drop it — an LG HDR WQHD+
  ignores contrast while its picture mode locks it, and only honours three of its twelve colour
  modes. After you stop dragging (or pick a mode), OpenDisplay reads the setting back; if the
  monitor stayed put, the slider or menu moves back to the real value and a short note says the
  monitor ignored the change.

## [0.11.4] — 2026-10-09

### Fixed
- **Colour mode menu no longer hangs the app on monitors that report 65535 colour presets** (LG HDR
  WQHD+ and many others). Until the monitor's capabilities have been read, the Colour mode menu
  guessed its choices from the "highest preset" the monitor reports — but colour presets are a fixed
  list, not a range, and some monitors report 65535 there. Opening the menu then tried to build
  65,535 entries and the app beachballed. The guess is now limited to the 12 standard presets
  (sRGB through User 2, now including 11500K and User 2 by name), and the monitor's current preset
  is always listed so the menu shows what it's actually set to.

## [0.11.3] — 2026-10-05

### Added
- **Export Diagnostics.** Settings → Health & Recovery → Diagnostics builds one zip on your Desktop
  with everything needed to explain a display problem after the fact: OpenDisplay's own records,
  macOS's saved display configuration (now, and as it was before your recent disconnects), what
  macOS reports about the displays, the DisplayPort link and Thunderbolt devices, and the last 30
  minutes of display-related system log lines. The app lists what goes in before you export, the
  file is never sent anywhere, and it leaves out window titles, file names, screen contents,
  location, and your app presets. Also available as `opendisplay diagnose --bundle` for when the
  app's window is on the display that went missing. (#40)
- **A display event timeline.** Every time the display arrangement changes — hotplug, sleep, wake,
  a disconnect or reconnect and how it ended — the app records what macOS reported about each
  display at that moment. Kept locally in a small rolling file and included in the diagnostics
  export. This is the record that was missing when a monitor failed to come back: by the time it
  was reported, the moment that mattered was gone.

## [0.11.2] — 2026-10-05

### Fixed
- **A display that doesn't come back is no longer forgotten.** Clicking Reconnect (or running
  `opendisplay reconnect`) used to drop the app's record of a turned-off display as soon as macOS
  *accepted* the request. If no picture ever appeared, the off card vanished while the monitor
  stayed black, and nothing was left that knew the display existed. A reconnect is now confirmed
  against what macOS actually reports: the app waits for the display to light, tries the stronger
  system-wide restore once if it doesn't, and only then forgets it. (#40)
- **When a reconnect fails, the app says so.** The display stays in the menu marked "Didn't come
  back on", with a Try again button and a link to
  [recovery steps](Docs/Recovering-a-stranded-display.md). The failure is written to the audit log,
  and posted as a notification if you have display notifications on. The CLI exits with an error
  and the same pointer instead of printing "reconnected".

### Added
- **A copy of macOS's saved display configuration is taken before every disconnect**, kept in
  `~/Library/Application Support/OpenDisplay/display-config-backups/` (five most recent). The
  stranded-display bug in #40 comes from one of those saved entries, and until now a report could
  only be pieced together afterwards. Nothing is sent anywhere, and the originals are never
  modified.

### Known issues
- The underlying cause of #40 — a display that macOS refuses to bring back after a disconnect, on
  some monitor and dock combinations — is not fixed. This release makes the failure visible and
  recoverable; it does not prevent it. If a display you depend on has no other way back (no DDC,
  behind a dock), be cautious about turning it off.

## [0.11.1] — 2026-10-05

### Added
- **Launch at login.** A switch under Settings → Health & Recovery → Behavior registers OpenDisplay
  as a login item, so you no longer add it by hand in System Settings. Off by default. It shows the
  system's own state, and says so when macOS is waiting for you to approve it under Login Items.
  (#43)
- **Opening OpenDisplay again opens Settings.** The menu-bar icon is the app's only standing UI, and
  macOS can hide it — behind the notch when the bar is full, or switched off under System Settings →
  Menu Bar — leaving a running app with nothing to click. Launching the app while it is already
  running (Finder, Spotlight, a second copy) now brings up the Settings window instead of doing
  nothing. (#44)

### Fixed
- **Display groups follow the macOS brightness keys and System Settings**, not only OpenDisplay's
  own controls. Grouped displays with native brightness control are watched in the background, and
  a change made anywhere — keys, Control Center, System Settings, auto-brightness, Shortcuts, the
  CLI — moves the rest of the group. Thanks to Sam Potts for the report and the fix. (#41, #42)
- **Pro Display XDR and Studio Display get real backlight control.** Apple's own external displays
  have no DDC and were falling back to software dimming; they now use the same native route as the
  built-in panel. Third-party monitors stay on DDC.
- **A group's learned offsets are no longer overwritten by driving another display.** Moving a
  second member of a group within 30 seconds of the first was always read as a "correction", so
  riding the brightness keys to the top on another display taught it a large offset and the rest of
  the group stopped following (the known issue noted in 0.10.1). Now only a display's own slider
  teaches an offset; keys, hotkeys, and changes made outside the app always move the group.
- **Leadership changes hands without the group jumping.** When a member with a learned offset led
  the group, its own offset was ignored, so the others landed somewhere different than when they
  led. The offset is now applied in both directions.
- The offset slider in Settings no longer writes back a stale copy of the group, which could undo an
  offset learned while the window was open.

## [0.11.0] — 2026-08-24

### Added
- **XDR Brightness now knows about your battery.** The boost drives the built-in panel's backlight
  to its HDR maximum — the single largest power draw a laptop has — and until now nothing ever
  turned it back off. Four opt-in rules, under the Labs toggle in Settings → Health & Recovery, each
  independent: turn the boost off when the Mac switches to battery power, turn it off below a
  battery percentage you choose (10/20/30/50%), turn it off while Low Power Mode is on, and turn it
  off a set time after you engaged it (15 min / 30 min / 1 h / 2 h). The first three are conditions,
  so a fifth setting — "Bring the boost back when power returns", on by default — puts the *exact*
  brightness you had back once all of them clear, and stays out of the way if you changed the boost
  yourself in the meantime. The timer is not: time spent is spent, and an elapsed allowance is never
  given back. Each automatic switch-off says why in a notification ("Battery at 18%") if you have
  display notifications on. The power watcher is only held while XDR Brightness is on *and* one of
  the battery-family rules is enabled — no IOKit listeners for a user who asked for none — and a
  desktop Mac, which reports no battery at all, is unaffected by every one of these rules.
- **A boost no longer outlives the panel it was applied to.** Closing the lid (or otherwise taking
  the built-in out of service) while boosted used to leave the fraction set and the slider up on a
  display nobody was looking at. It's now cleared through the normal path, with no restore when the
  panel comes back — the same session-only rule the feature has always stated, where a relaunch
  starts at normal brightness.

## [0.10.3] — 2026-08-08

### Added
- **An app icon.** OpenDisplay finally has a face: a neon-outline display with a power symbol on a
  dark squircle, in the macOS Big Sur+ icon style. It shows up in Finder, the app switcher,
  notifications, and System Settings panes — everywhere the generic app placeholder used to be.
  Both app variants (full and public-API-only) carry it; the 1024px master lives in
  `Docs/assets/app-icon-1024.png`.

## [0.10.2] — 2026-08-08

### Fixed
- **A saved "built-in off" now survives a slow external across lid-open + unlock.** Live case: lid
  opened, thumbprint unlock, the built-in lit first (the always-one-active net doing its job) — but
  the ultrawide became an active surface only after the 20-second wake window had closed. At that
  edge the app concluded the *user* had re-enabled the built-in, erased the owed "off" from the
  ledger, and when the external finally lit, nothing put the built-in back off (the auto-disconnect
  edge didn't fire either — the external never left enumeration during this sleep, so there was no
  "arrival"). The wake's attribution is now *stamped onto the ledger entry* the moment it is made
  (`relitDuringWakeAt`): a stamped "off" stays owed past the window — time-to-unlock is unbounded —
  and is paid whenever the covering display actually lights, then the stamp comes off. The stamp
  persists with the ledger, so an app relaunch mid-convergence doesn't amnesty it; outside a wake,
  un-stamped entries are still forgotten exactly as before (a System Settings re-enable stays the
  user's decision). Past the window the backstop poll slows from 2 s to 30 s — the topology event
  the external raises on activation is what normally answers anyway.

## [0.10.1] — 2026-08-06

### Fixed
- **Every automatic display switch now leaves an audit entry.** The 0.10.0 wake fix could turn a
  display off (or light one) without a trace in `audit.jsonl` — live, a built-in that relit on wake
  and was put back off left the log still ending at the prior CLI disconnect. Wake-convergence
  writes now record under their own actor, `wakeConvergence`: `reassertOff` when a ledger "off" is
  re-asserted after wake, `netActivate` when the always-one-active net lights its fallback, and
  `netEscalate` when it falls through to the permanent-configuration restore. The
  auto-disconnect-on-external-arrival path — which on a wake can fire before the re-assert gets its
  turn, and previously wrote nothing — records as `autoDisconnect`. Entries carry the real outcome
  (`committed`/`failed`) instead of assuming success, so Settings → Recent Activity answers "why
  did my display just switch?" with the exact path that did it.

### Notes
- Known issue: driving a group leader's brightness to its maximum can overwrite the group's
  learned per-display offsets, after which followers track the leader too bright. Recreating the
  group resets the offsets; fixed in 0.11.1.

## [0.10.0] — 2026-08-06

Everything since 0.8.2 in one release: 0.9.0 was versioned in the tree but never published,
so its features ship here.

### Added
- **One-click updates.** "Check for Updates…" now does the whole job: OpenDisplay downloads the new
  version, verifies it, installs it, and relaunches itself into it — no trip to the browser, no
  dragging a new app into `/Applications`. Every download is checked against the project's EdDSA
  signing key *and* the Developer ID signature of the copy you already have, so an update that
  doesn't come from us doesn't run. Two settings govern it: "Check for updates automatically" (on by
  default, about once a day, and it only tells you) and the opt-in "Download and install updates
  automatically". A background check that finds something never interrupts you — it leaves a version
  badge on the menu's update row and waits until you click it.

- **Protected layout** (Issue #38) — mark your current display arrangement as protected, and
  OpenDisplay puts it back when something else moves it. Origins, resolution, refresh,
  mirroring, and the main display are captured per *display set* — your laptop-alone layout and
  your desk layout are protected independently — and re-applied within seconds after hotplug,
  wake, or a stray arrangement change, with a notification saying exactly what was restored.
  Rotation drift is detected and reported, but not auto-restored: rotation writes require the
  experimental rotation helper (Labs), so a rotated-out-from-under-you display produces a
  "couldn't restore" notification rather than a silent half-restore.
  Restores run through the same checkpointed, verified, audited transaction path as every other
  change, so the always-one-display-active guarantee holds throughout; a display you deliberately
  turned off stays off, restore attempts are capped (never a tug-of-war with macOS), and the app's
  own changes never trigger a restore. Managed from Settings → Arrange, or
  `opendisplay layout protect|unprotect|status`.
- **Display groups & brightness sync** (Issue #39) — group displays so moving any member's
  brightness moves them all. Each member keeps a learned offset: nudge one display to taste and
  the group remembers the difference instead of fighting you. Optional contrast sync, media-key
  support (one OSD, on the display you're driving), and a `group:` selector for the CLI
  (`opendisplay brightness group:desk 0.6`; `opendisplay group create|add|remove|list`).
  Grouped displays are excluded from Adaptive Display's brightness targeting so the two features
  can't fight. Groups are configured in Settings → Displays.

### Fixed
- **A display you turned off no longer lights back up when the Mac wakes.** With externals
  connected and the built-in panel deliberately switched off, waking the Mac brought the built-in
  back and left it on for the rest of the session. Three separate things had to be true for that,
  and all three are fixed:

  macOS relights the panel itself on wake — its display-configuration transactions don't survive a
  sleep — and OpenDisplay read that as *you* having switched it back on, so it forgot the display
  was ever meant to be off. It now tells the two apart, and switches the display back off once
  another screen is lit to take over (bounded, so it never turns into a tug-of-war with macOS).
  This works whether or not Protected Layout is on: a display you turned off is already an
  explicit instruction, not something that should need a second switch.

  The always-one-display-active safety net could also do it. For a second or two after a wake an
  external that is still re-negotiating its link is indistinguishable from one that was unplugged,
  and the net answered "nothing is on screen" by lighting the display you had turned off. It now
  waits for a display that is plainly on its way back — while still guaranteeing a screen within
  eight seconds no matter what the display list says, so the 0.8.2 black screen cannot return.

  And Protected Layout could not have helped, because a switched-off display leaves macOS's
  display list entirely: the moment it came back, the arrangement was filed under one display set
  and looked up under another. Protected layouts now cover the displays they keep switched off —
  in the key, in what is captured, and in what is restored.

### Notes
- Updating in place only works *from* a build that has the updater in it. If you are on 0.8.2 or
  older, install this release by hand once; from then on OpenDisplay keeps itself current.
- Releases now carry a second asset, `appcast.xml`, alongside `OpenDisplay.zip` — that file is the
  update feed, produced and signed by `scripts/release-signed.sh` (see `scripts/sparkle-setup.md`).
- CLI edits to app-owned settings made while the app is running — `group` edits and
  `layout protect|unprotect` alike — are overwritten when the app next saves its settings.
  Quit the app first, or use the Settings window. A shared on-disk store is planned.

## [0.8.2] — 2026-07-27

### Fixed
- **Unplugging your last external display no longer leaves you with a black screen.** If OpenDisplay
  had turned the built-in panel off (for example via "turn the built-in off when an external
  connects"), pulling the external left nothing on screen and the built-in never came back — the
  one failure the always-one-display-active guarantee exists to prevent.

  The cause: when the last real display disappears, macOS does not report zero displays. It
  substitutes a synthetic placeholder to keep the window server alive, so the safety net's "nothing
  is active any more" condition could never become true and it never fired. OpenDisplay now
  recognises that placeholder for what it is and counts only displays you can actually see.
- Recovery now **verifies itself**: re-enabling a display can report success while still showing
  nothing, so the result is checked against the live topology and escalated to a system-level
  configuration restore if the screen is still dark.
- A **sleeping** display is no longer mistaken for a missing one. `CGDisplayIsActive` reads false
  while a display sleeps, which made an idle Mac look display-less — so ordinary sleep could
  silently re-enable a built-in you had deliberately turned off and forget it was owed a restore.
  This also fixes the built-in quietly coming back on, and your preferred layout not sticking.
- A failed reconnect no longer discards the record of a display owed a restore.

## [0.8.1] — 2026-07-23

### Fixed
- **The `opendisplay` CLI can now see and recover displays the app turned off.** A display that
  OpenDisplay logically disconnects disappears from macOS's display list entirely, and the CLI
  had no record of it — so `opendisplay reconnect builtin` answered "no display matches" and the
  documented recovery path was unusable from the one surface that still works when a display is
  off. Turned-off displays now appear in `opendisplay list` (marked, with the exact command to
  bring each one back), resolve through every selector, and reconnect correctly.
- **`opendisplay disconnect` remembers what it turned off.** Previously a display disconnected
  from the CLI was unreachable by that same CLI moments later, because nothing recorded it.
- The app and the CLI now share one on-disk definition of the turned-off-display list, so the two
  can't disagree about which displays are owed a reconnect. Existing files are read unchanged.
- CLI display names fall back to a readable "Built-in Display" / class + resolution label instead
  of a raw `cg:37D8832A-…` identifier.

## [0.8.0] — 2026-07-23

The last row of the Lunar parity table: **every feature Lunar markets is now matched**.

### Added
- **XDR Brightness** (Labs, Issue #35) — drive the MacBook Pro's XDR panel past its 500-nit
  SDR cap. A compact sun badge at the end of the built-in's brightness row toggles a **2×
  boost**: a tiny extended-dynamic-range trigger makes macOS raise the physical backlight,
  and a gamma-table remap hands that raised range to your normal (SDR) content — the whole
  desktop gets genuinely brighter, hardware-verified around 1600 nits at the 3.2× internal
  ceiling. Public Metal/Core Graphics only (no private API), so it also works in the
  public-API-only build. Opt-in via Settings → Labs, session-only by design: quitting —
  or even crashing — always returns the panel to normal. Known trade-offs, stated in the
  UI: HDR content looks clipped while boosted, and sustained boost warms the panel.

### Fixed
- The app now enforces a **single running instance**: a second copy (a Debug build alongside
  the installed release, or several stale builds) exits immediately instead of fighting the
  first one for the gamma slot, DDC bus, settings file, hotkeys, and menu bar.

## [0.7.1] — 2026-07-22

A review-and-hardening pass over the whole codebase (no new features).

### Fixed
- **App Presets** no longer lose a display's saved baseline when it is unplugged while a preset
  is active: the restore stays owed and is paid back automatically when the display returns (or
  at the next launch), instead of stranding the re-plugged display at the preset's values. A
  display that *connects* while a preset is active is now governed immediately rather than
  waiting for the next app switch.
- **Settings file resilience**: one unreadable field (e.g. after a downgrade, or corruption) now
  falls back to that field's default instead of silently resetting every setting — including the
  FaceLight / app-preset / evening-preset restore ledgers — on the next save.
- Display identity: a "paired" record can no longer absorb an unrelated anonymous monitor; the
  pairing signal now requires corroborating evidence (serial, model, UUID, or registry path).
- Refresh-rate-only mode changes and 180° rotations now advance the topology generation instead
  of always sitting out the 2-second stabilization timeout.
- `opendisplay edid` on a Mac laptop no longer reports the built-in panel's EDID for an external
  display whose model number is unreadable.
- CLI: `favorite set <display> @2x` (no resolution) reports a usage error instead of crashing;
  `brightness` DDC writes round instead of truncate (0.29 wrote 28 but printed 29%).
- Clock Mode solar anchors queried just after midnight on a DST-transition day are no longer an
  hour off.
- Audit-log entries written concurrently by the app and CLI can no longer interleave mid-line.

### Changed
- Night Shift detection reuses one CoreBrightness client instead of opening a new connection
  every 5-second adaptive tick.

## [0.6.1] — 2026-07-21

### Fixed
- Pressing ⌘, (the standard macOS Settings shortcut) opened an empty stub window instead of the
  real Settings UI. The shortcut and the menu bar's gear now open the same Settings window
  (Displays / Arrange / Scenes / Health & Recovery / About), and repeated presses re-focus the
  existing window instead of spawning another.

## [0.7.0] — 2026-07-21

Wave 2 of the Lunar-parity work: Location Mode and App Presets. With these, every
Lunar-marketed feature except the XDR brightness unlock is matched.

### Added
- **Location Mode** (Issue #31) — brightness that follows the sun's real elevation at your
  location: a night floor below civil twilight (−6°), a linear ramp through dawn and dusk, and a
  full-brightness plateau once the sun is high (20°+). It slots into Adaptive Display as a
  fallback source below the live signals — the built-in mirror and the ambient-light sensor still
  win when available, an explicit Clock Mode schedule still outranks it, and manual tweaks teach
  it an offset exactly like sync mode. Great for lid-closed setups in rooms with natural light.
  The sun-elevation math extends 0.6.0's NOAA solar calculator (pure, deterministic, validated
  against an independent ephemeris algorithm within 0.5°); location is shared with Clock Mode
  (one-shot opt-in or manual latitude/longitude).
- **App Presets** (Issue #33) — per-app display presets: when a chosen app comes to the front,
  its preset (brightness, and optionally contrast and colour preset) applies to the target
  display — or all displays — and the prior state comes back when the app leaves. Switches are
  debounced (rapid ⌘-tabbing only commits the app you land on), writes go through the same
  silent, audited funnels as Adaptive Display (so they never trip the manual-change cooldown),
  and the pre-preset state is persisted *before* the first write — a crash or relaunch
  mid-preset restores your real settings, the same crash-safe ledger FaceLight uses.
  Precedence, documented and tested: FaceLight > App Presets > Clock Mode > Adaptive sync.

## [0.6.0] — 2026-07-21

The Lunar-parity feature batch: FaceLight, Clock Mode, input-switch hotkeys, and three new CLI
commands — plus an About section inside Settings.

### Added
- **FaceLight** (Issue #29) — turn the active monitor into a video-call fill light with one press:
  DDC brightness and contrast go to max and a warm, translucent, click-through overlay washes the
  screen (strong warm light with your call still legible underneath). Press again to restore the
  exact prior brightness, contrast, and overlay state. The restore ledger is persisted *before* the
  hardware writes land, so a crash or relaunch mid-FaceLight still puts the display back exactly as
  it was. Displays without DDC get the overlay-only version. Toggle from each display's card in the
  menu, or bind the new "Toggle FaceLight" global-hotkey action.
- **Input-switch hotkeys** (Issue #32) — assignable global hotkeys that jump a monitor straight to a
  specific input ("⌃⌥⌘2 → Desk, HDMI 2"), so KVM-style setups never need the menu. Configured in
  Settings; bindings target the display's persistent EDID identity, so they survive dock re-plugs
  and port reordering. The switch routes through the same audited command path as the UI and CLI,
  confirms on-screen via the OSD, and posts a notification instead of failing silently when the
  display is offline or rejects the switch.
- **CLI: `lux`, `listen`, `lid`** (Issue #34) — `opendisplay lux` prints the current ambient-light
  reading (with `--json`); `opendisplay lid` reports lid state; `opendisplay listen` streams
  brightness and display-topology events as line-delimited JSON until Ctrl-C, for scripting
  (`| jq`, tail-style automation). Schema documented in `Tools/opendisplay/README.md`.
- **About in Settings** — a new About section in the Settings sidebar (below Health & Recovery)
  showing the app version and build, a Check for Updates control, and project links — the same
  information as the About window, now one click away in Settings.
- **Clock Mode** (Issue #30) — a first-class, user-editable brightness schedule for external
  displays. Each schedule point is anchored either to a fixed clock time or to a solar event
  (sunrise, solar noon, sunset) with a per-anchor offset in minutes — so "70% thirty minutes
  before sunrise" tracks the season automatically. Three transition styles carry brightness between
  points: **instant** (step at the anchor), **30-min ramp** (ease in over the half-hour ending at
  the anchor), and **continuous** (glide across the whole gap). Transitions are silent — no OSD —
  like every other adaptive change.
  - **Solar math** is public-domain NOAA solar-position equations, computed as pure, deterministic
    logic in `TopologyCore` (`SolarCalculator`) and unit-tested against known city/date sunrise and
    sunset pairs (London, New York, Sydney) within a couple of minutes, plus polar-day/night and
    noon-symmetry invariants. Location comes from Core Location (one-shot, opt-in "Use current
    location") with a manual latitude/longitude fallback; with no location, solar anchors are
    skipped gracefully and time anchors still work.
  - **Precedence with Adaptive Display:** an explicit Clock Mode schedule outranks Adaptive
    Display's built-in mirror — enabling Clock Mode governs external brightness even when brightness
    sync is on. Adaptive warmth (colour preset) is orthogonal and unaffected. A manual brightness
    change still pauses the schedule for the cooldown, reusing the same quiet-write machinery, so
    the two never fight.
  - Settings gain a Clock Mode editor (add / edit / delete schedule points, choose the location)
    under Health & Recovery, consistent with the existing design.

## [0.5.1] — 2026-07-21

Patch release: a real About window and keyboard-accessibility fixes in the menu pop-out.

### Added
- **About window** — "About OpenDisplay" now opens a proper window instead of the bare
  system panel: the running version and build (selectable, for bug reports), a Check for
  Updates button, and links to the website, release notes, issue tracker, and license.
  Built with semantic fonts and VoiceOver labels.

### Fixed
- **No more surprise focus ring** — the menu pop-out no longer opens with a focus ring
  already drawn around the gear button. Keyboard focus is still one Tab away.
- **Tab now cycles forward through the whole pop-out** — forward Tab used to jump from
  the gear to the ··· button and stop there; only Shift-Tab could reach everything. Both
  directions now traverse every control and wrap around.

## [0.5.0] — 2026-07-20

Launch-prep feature release: a real update check, dimming that can go darker than gamma
alone, and a software colour-temperature control. 321 unit tests (up from 286).

### Added
- **Check for updates** — the menu row is live (it said "Soon"). A manual check asks GitHub
  for the newest release and, when one exists, shows its version badge and links to the
  release page. An automatic check runs at most once a day (default on, toggleable in
  Settings → Health & Recovery). Nothing is ever downloaded or installed automatically.
- **Overlay & combined dimming** — the Dimming card gains a method picker. *Gamma* is the
  original table scale (0.15 floor); *Overlay* is a black, click-through window at
  adjustable opacity; *Combined* stacks the overlay past the gamma floor — darker than
  either method alone, and still never fully black. The menu bar (and this app's menu)
  stay undimmed so the way back is always visible, overlays never appear in screenshots,
  and they vanish with the app — an overlay dim can't outlive a crash.
- **Colour temperature** — a warm/cool slider (2700–9300 K) in the Appearance card, applied
  through the display's gamma table with attenuation-only channel gains (no highlight
  clipping), snapping back to "Native" near 6500 K. Composes correctly with software
  dimming and software brightness — each remembers the other.

## [0.4.1] — 2026-07-19

Patch release: volume media keys now route by where your sound is actually playing.

### Fixed
- **Volume/mute keys follow the current sound output device** instead of the media-key
  target mode. When macOS sound output is a monitor with DDC audio, the keys drive that
  monitor's hardware volume (with the OSD); when sound plays anywhere else — built-in
  speakers, headphones, AirPods — the keys pass through to macOS untouched. Previously,
  with the target mode pointed at a DDC monitor, the keys could change the monitor's
  volume while audio played from the Mac's speakers. Brightness keys are unchanged and
  still follow the configured target mode; the Settings picker is relabelled to make the
  split explicit.

## [0.4.0] — 2026-07-03

Fourth developer preview: Adaptive Display brings macOS-grade brightness and warmth
intelligence to external monitors over DDC — sync to the built-in panel, read the ambient
light sensor directly when the built-in is off, or fall back to a schedule, plus Night-Shift-
following evening warmth. 271 unit tests (up from 240); adaptive paths attended-verified live
on a Samsung ultrawide end to end.

### Added
- **Adaptive Display (Labs, opt-in):** transfer the built-in display's intelligence to external
  monitors. **Brightness sync** mirrors the built-in panel's ambient-light-driven brightness to
  the external's real backlight over DDC (learned offset from your manual tweaks, one-minute
  hands-off after a manual change, schedule-curve fallback with the lid closed). **Evening
  warmth** switches the monitor's hardware colour preset in the evening and back each morning —
  following macOS Night Shift's live state when readable (best effort, private CoreBrightness),
  otherwise a configurable schedule. The daytime preset is remembered and restored on quit,
  disable, next morning, and even across a crash or relaunch mid-evening. Adaptive changes are
  silent (no OSD) and never write to displays without working DDC. With the built-in display
  turned OFF but the lid open (external-monitor-plus-Mac-keyboard setups), brightness reads the
  **ambient light sensor directly** — true light-driven dimming with no panel to mirror; only a
  closed lid (sensor covered) falls back to the schedule.
- Configurable day/night brightness levels and schedule times for the fallback curve.

### Fixed
- Local (non-release) builds now sign with a stable Developer ID identity instead of adhoc, so the
  macOS Accessibility grant the media-key tap needs survives a rebuild — the hardware brightness
  keys no longer silently stop working after the app is rebuilt. Notarized release builds were
  never affected.

## [0.3.0] — 2026-07-02

Third developer preview: keyboard media keys drive external-monitor hardware with a
native-style on-screen HUD, and the DDC/CI engine got substantially more robust — it now
identifies the right monitor by EDID identity and recovers replies other readers miss.
240 unit tests (up from 192); hardware paths attended-verified on Apple Silicon against a
Samsung ultrawide, including a full brightness write/read-back/restore round-trip.

### Added
- **Media keys (opt-in):** press the keyboard's brightness keys and OpenDisplay changes the
  *external monitor's real backlight* over DDC/CI — macOS-style 1/16 steps, ⇧⌥ fine steps,
  and a native-looking HUD drawn by the app. Target the display under the cursor, the main
  display, or the built-in. Needs Accessibility once; the app now shows the prompt when the
  feature is on, then arms itself the moment the grant lands — no relaunch.
- **More hardware controls:** sharpness and red/green/blue gain sliders appear automatically
  on monitors that answer them, alongside contrast and volume.
- **Raw VCP access in the CLI:** `opendisplay ddc <display> vcp 0xNN [value]` reads or writes
  ANY MCCS feature code — every control a monitor implements is reachable without a rebuild.
  Plus named features: `sharpness`, `red`, `green`, `blue`, and `mute` (accepts on/off).

### Changed
- **DDC binds to the right monitor by identity, not port order:** the display's EDID
  vendor/model/serial is scored against IORegistry attributes, so multi-monitor setups,
  docks, and identical panels get the correct I2C channel (order remains the fallback).
- **DDC reads recover misaligned replies:** wide reads with an in-buffer, checksum-validated
  frame scan — panels that prefix replies with stale bytes no longer read as "unsupported".
- **DDC transactions are truly serialized** (FIFO bus turnstile + paced inter-transaction
  gaps): concurrent slider drags and refreshes can never interleave on the I2C bus, and a
  lone write no longer pays a fixed trailing delay.
- **Fast menus on partial hardware:** features a panel repeatedly fails to answer are
  negatively cached (with a periodic recheck), instead of re-paying ~0.7s of retried I2C per
  absent control on every open.

### Fixed
- Hardware controls are rediscovered automatically on display reconfiguration and when a
  display's settings pane opens — a monitor whose DDC comes back (port switch, power-cycle)
  shows its controls without an app restart.
- Recovering from software dimming to hardware brightness lifts the leftover gamma dim, so
  the panel can't end up double-dimmed; Black Out is never overridden by background refreshes
  or colour-profile changes.
- Colour-mode menus offer the panel's advertised preset codes when capabilities are known,
  instead of guessing a contiguous range the monitor may ignore.
- CLI DDC writes validate their range (0–65535) instead of silently truncating; the
  capabilities read (`ddc … caps`) is documented as diagnostic-only — it can permanently
  wedge some monitors' DDC engines (observed on a Samsung HDMI port).

## [0.2.0] — 2026-06-24

Second developer preview. Two batches of display-management features land on top of the
0.1.0 safety core, plus a fix for Set-as-Main and a set of menu-bar UX fixes. The
platform-independent logic is unit-tested (192 tests, up from 78); hardware paths were
attended-verified on Apple Silicon.

### Added
- **Keep displays awake while an external is connected** — opt-in IOKit power assertion so
  the Mac/displays don't sleep while docked.
- **DDC power control** (VCP `0xD6`): put an external monitor into standby / wake it from
  the menu and CLI.
- **`opendisplay://` URL-scheme automation** — drive the same audited, safety-checked command
  path from URLs (confirmation-gated for destructive verbs).
- **Resolution slider** replacing the dropdown — scrub through the panel's modes by scale.
- **Timed auto-revert safety gate** for arrangement changes: a "Keep these display settings?"
  countdown that reverts on its own if you don't confirm.
- **Auto-disconnect the built-in** when an external connects (opt-in).
- **DDC capability detection** (VCP `0xF3`): controls are gated to what the panel actually
  reports it supports.
- **EDID retrieval / export** — parsed identity (manufacturer, product, serial descriptors,
  checksum, stable fingerprint) with a CLI `edid` export.
- **Favorite resolutions** — star the modes you use so they're one click away.
- **Display-config drift detection** — notice when a protected arrangement has been changed
  out from under you.
- **Configurable global hotkeys** — an expanded shortcut registry (cycle main display,
  brightness ±, reconnect-all) with a tolerant, forward-compatible settings format.
- **Connect / disconnect notifications** — optional banners when a display comes or goes.
- **One-click quit** — a power button in the menu header next to the gear.

### Fixed
- **Set-as-Main** targeted the wrong display: it computed the arrangement shift from a stale
  observation. It now re-resolves the target against a fresh snapshot before applying.
- **Menu pop-out mis-anchored** across multiple displays (SwiftUI `MenuBarExtra` opened on
  the wrong screen). Replaced with an AppKit `NSStatusItem` + `NSPopover` that anchors to the
  clicked screen and stays put when set-main relocates the primary display.
- **Settings wouldn't open** from the menu after the AppKit switch — the window is now owned
  directly by the app and reliably opens, activated and centered on the screen you're using.

### Changed
- **Quit now returns the Mac to a clean default**: reconnects any display the app turned off,
  lifts software dim/blackout, and drops the keep-awake assertion before the app exits
  (termination is deferred until the reconnect lands), rather than relying on the OS's
  process-exit auto-revert.

## [0.1.0] — 2026-06-23

First developer preview. The platform-independent safety core (domain models, state
machines, scene planner, `SafetyEngine`, serialized `TopologyCoordinator` with
checkpoint/rollback) is unit-tested (78 tests), and the macOS menu-bar app is functional
and verified on Apple Silicon hardware.

### Added
- Menu-bar app with a unified **brightness** slider (built-in via DisplayServices, external
  via DDC/CI, software-gamma fallback), **hardware controls** (contrast / volume / input /
  colour preset over DDC/CI), **mirroring**, **resolution / refresh / HiDPI** switching, a
  drag-to-arrange canvas, **per-display ICC colour profiles** (public ColorSync), **Black
  Out**, and **software dimming**.
- **Safe logical disconnect / reconnect** with an always-one-display-active guarantee,
  persisted managed-offline tracking, automatic fall-back to the built-in panel, and
  independent recovery (menu, the global ⌃⌥⌘R hotkey, and a separate `OpenDisplayRescue` app).
- **Scenes**: capture and re-apply display arrangements.
- `opendisplay` **CLI** and **Shortcuts/Siri** intents that drive the same audited,
  safety-checked command path as the UI.
- **Labs:** opt-in experimental display rotation through an isolated helper process — off by
  default and compiled out of the public-API / App Store build.

### Distribution
- Release builds are **Developer ID-signed, hardened-runtime, and notarized** by Apple, so
  the download opens with no Gatekeeper workaround. Reproducible via `make release-signed`
  (`scripts/release-signed.sh`).

### Performance
- Apple-Silicon optimisation pass: private SPI (DisplayServices), DDC/CI controller
  construction, ColorSync iteration, and EDID fingerprinting moved off the main thread;
  batched registry persistence (one write per topology event instead of one per display);
  cached display-mode enumeration in the detail pane; opt-in reconfiguration-callback
  registration that also closes a callback/deinit race; pruned DDC handle caches across
  reconnects. Removed a dead control-provider abstraction and other unused code.

### Foundations
- Project scaffolding: SPM monorepo with platform-independent domain packages
  (`DisplayDomain`, `ProviderInterfaces`, `SceneEngine`, `AutomationSchema`,
  `TopologyCore`) plus `SimulatorProvider`, and their unit tests.
- Safety core: lifecycle & transaction state machines, `SafetyEngine` (safe-surface and
  preflight rules), `IdentityScorer` (multi-signal confidence), and the serialized
  `TopologyCoordinator` with checkpoint/rollback.
- `SceneEngine` desired-state planner with deterministic, idempotent, safely-ordered diffs.
- Stable `AutomationSchema` JSON result envelope and selector grammar.
- Initial documentation (architecture, recovery model, decisions, PRD) and open-source
  governance (contributing, security, code of conduct, RFC and issue/PR templates).
- macOS target scaffolding for the app, rescue utility, CLI, providers, and design system.
- Local-first developer tooling: `Makefile` (`make bootstrap`/`build`/`test`/`lint`/`xcode`)
  and `scripts/bootstrap-swift.sh` to install a Swift 6 toolchain on Ubuntu / verify Xcode on macOS.
- Xcode project scaffolding via XcodeGen (`project.yml`, `scripts/generate-xcodeproj.sh`,
  `make xcode`): macOS app + public-API-only variant, rescue app, CLI, design-system and
  provider frameworks, with compile-ready stubs wired to the `SimulatorProvider`.

### Changed
- Hardened the disconnect transaction after review: `.blocked` preflights are non-bypassable
  (removed the `userOverride` escape hatch); the confirmation handler now defaults to *cancel*
  rather than silently approving `.needsConfirmation`; and verification now rolls back if any
  unrelated active display is unexpectedly lost, not only the target (PRD §9.2/§9.4).
- Verification is now **local-first**: removed the remote GitHub Actions CI workflow; run
  `make test` locally before pushing.
