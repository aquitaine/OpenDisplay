# OpenDisplay → Lunar Feature Parity Map

An inventory of Lunar's marketed feature surface (lunar.fyi, as of July 2026), mapped against
OpenDisplay at v0.5.1. Companion to `OpenDisplay-Feature-Parity-Map.md` (the BetterDisplay map);
same clean-room rules apply.

Source: lunar.fyi feature pages. OpenDisplay status is taken from the CHANGELOG and a repo grep,
not marketing copy.

> **Clean-room reminder:** this is a map of *capabilities to match*, not Lunar's code, UI, assets,
> or copy. Everything below should be built from public docs + first principles.

---

## Scorecard

Of the ~18 features Lunar markets: **20 matched · 1 partial · 0 gaps** (plus two niche items we
deliberately skip). Every feature Lunar markets is now matched or consciously declined.
Several of Lunar's Pro features are free in OpenDisplay.

## Matched (20)

| Lunar feature | Lunar tier | OpenDisplay |
|---|---|---|
| DDC control (brightness/contrast/volume/input/power) | Free | ✅ Plus sharpness, RGB gain, raw VCP via CLI |
| Apple Silicon hardware control (I²C) | Free | ✅ Core of the app |
| Brightness keys → external monitors + OSD | Free | ✅ ⇧⌥ fine steps, configurable target (0.3.0) |
| Volume keys → monitor hardware volume | Free | ✅ Routes by actual sound-output device (0.4.1) |
| Sync Mode (adaptive brightness from built-in) | **Pro** | ✅ Adaptive Display, free (0.4.0) |
| Sub-zero dimming (below hardware 0%) | Free | ✅ Gamma/overlay/combined (0.5.0) goes darker than gamma-only |
| Gamma fallback when DDC fails | Free | ✅ |
| BlackOut (hotkey display off) | **Pro** | ✅ Plus safe logical disconnect, always-one-display guarantee, rescue app |
| Auto BlackOut (built-in off when external connects) | **Pro** | ✅ Auto-disconnect built-in, opt-in (0.2.0) |
| macOS Shortcuts | **Pro** | ✅ Free |
| CLI | Free | ✅ list/set/ddc/scene/diagnose/recover… |
| Multi-monitor support | Free | ✅ EDID-identity matching (correct on docks/twin monitors) |
| Colour warmth | — | ✅ Night-Shift-following (0.4.0) + manual 2700–9300 K slider (0.5.0) — Lunar doesn't headline this |
| Clock Mode (scheduled brightness) | **Pro** | ✅ First-class Clock Mode (0.6.0): time/sunrise/noon/sunset anchors, per-anchor offsets, instant/ramp/continuous transitions, NOAA solar math |
| FaceLight (video-call fill light) | **Pro** | ✅ Max DDC + warm translucent overlay, crash-safe exact-state restore (0.6.0) |
| Location Mode (sun-elevation brightness) | **Pro** | ✅ NOAA elevation math, civil-twilight→20° ramp, Adaptive Display source (0.7.0) |
| App Presets (per-app switching) | **Pro** | ✅ Debounced frontmost tracking, crash-safe restore ledger, tested arbitration (0.7.0) |
| Input Hotkeys (jump to input) | Free | ✅ Per-input global hotkeys, EDID-persistent targets, OSD confirm (0.6.0) |
| CLI `lux`/`listen`/`lid` | Free | ✅ Plus line-delimited-JSON event stream for scripting (0.6.0) |
| XDR Brightness (SDR past 500 nits) | **Pro** | ✅ One-tap 2× boost, public Metal/CG only (Lunar's private preset path broke in macOS 26.3), session-only + crash-safe (0.8.0) |

## Partial (1)

| Lunar feature | Lunar tier | OpenDisplay | Gap |
|---|---|---|---|
| Sensor Mode (ambient-light-driven brightness) | **Pro** | 🟡 Reads the built-in ALS directly, even with the panel off (0.4.0) | No *external* wireless/network sensor (Mac-mini-without-a-MacBook case) |

## Todos (1 open · 6 shipped) — filed as issues, ordered by value-per-effort

1. ~~**FaceLight**~~ — ✅ **Shipped (0.6.0, Issue #29).** Max DDC brightness/contrast + warm
   translucent click-through overlay on one press; exact prior state restored on the next press,
   crash-safe via a persist-before-write ledger. `low` · area:controls
2. ~~**Clock Mode**~~ — ✅ **Shipped (0.6.0, Issue #30).** User-defined brightness schedules with
   time / sunrise / noon / sunset anchors, per-anchor offsets, and instant/ramp/continuous
   transitions, on public-domain NOAA solar math. Precedence: an explicit Clock Mode schedule
   outranks Adaptive Display's built-in mirror. Contrast scheduling deferred (needs a silent DDC
   contrast pipeline). `medium` · area:controls
3. ~~**Location Mode**~~ — ✅ **Shipped (0.7.0, Issue #31).** Sun-elevation brightness as an
   Adaptive Display fallback source (below live built-in/ambient readings, above the flat
   schedule); NOAA elevation math validated against an independent ephemeris algorithm.
   `low after Clock Mode` · area:controls
4. ~~**Input-switch hotkeys**~~ — ✅ **Shipped (0.6.0, Issue #32).** Global hotkeys per input source
   riding the shortcut registry and VCP 0x60 switching; EDID-persistent display targeting, OSD
   confirmation, graceful offline handling. `low` · area:controls
5. ~~**App Presets**~~ — ✅ **Shipped (0.7.0, Issue #33).** Per-app-bundle-ID presets with
   debounced frontmost tracking, a crash-safe persist-before-write restore ledger, and tested
   last-writer precedence (FaceLight > App Presets > Clock Mode > Adaptive sync). `medium` ·
   area:automation
6. ~~**CLI extras**~~ — ✅ **Shipped (0.6.0, Issue #34).** `lux`, `listen` (line-delimited JSON
   event stream), `lid`. `low` · area:automation
7. ~~**XDR Brightness unlock**~~ — ✅ **Shipped (0.8.0, Issue #35).** One-tap 2× boost on the
   built-in XDR panel via the EDR-trigger + gamma-table-map technique — public Metal/CG only
   (no private API after all; Apple broke Lunar's preset-based private path in macOS 26.3, so
   the gamma route is also the *durable* one). Session-only, Labs-gated, hardware-verified at
   ~1600 nits. `shipped` · area:controls

## Deliberately skipped

- **DisplayLink / network DDC via a Raspberry Pi relay** — very niche, hardware-dependent.
- **External network ambient light sensors** — same; revisit only if headless-Mac users ask.

## Where OpenDisplay already leads Lunar

- Resolution / refresh / HiDPI switching, mirroring, layout canvas — Lunar doesn't do modes.
- Scenes, ICC profiles, rotation (Labs).
- The safety model: audited transactions, checkpoints, auto-revert, always-one-display-active,
  standalone rescue app.
- Free and GPL — Lunar's Free tier caps Manual Mode at 100 adjustments/day; OpenDisplay has no caps.
