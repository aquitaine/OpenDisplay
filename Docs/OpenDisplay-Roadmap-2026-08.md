# OpenDisplay — Next Features (post-0.10.3)

A prioritized backlog built from a fresh competitive sweep (2026-08-24): BetterDisplay v4.3.6/v5.0.3,
Lunar v6.11.0 (v7 due Sept–Oct), DisplayBuddy v3.9.1, MonitorControl (stagnant since Oct 2024),
the XDR-boost cohort (Vivid, BrightIntosh, LUMEL, LumiMax, MacBrightness, TotalXDR), the eye-care
cohort (f.lux, Stillcolor, Sundown, CircadianShield), resolution/virtual-display tools (SwitchResX,
DeskPad, displayplacer), plus community-demand mining (HN, MacRumors, Apple Communities, GitHub
issue trackers). Repo status verified against the live code at v0.10.3 — the June-2026 parity map's
Tier-1 list is fully drained (everything in Batches 1–4 shipped).

> **Clean-room reminder:** capabilities to match, not anyone's code, UI, assets, or copy.

---

## The strategic picture (read this once)

- **BetterDisplay's last 12 months went exactly at our backlog:** nits-normalized brightness
  (v4.2.3/4.3.3), networked TV/AVR + DisplayLink + HDMI-CEC (v4.1.0→v5.0.x), and HDR (forced HDR,
  mixed color modes, HDR virtual screens). Its paywall sits on HiDPI scaling, virtual screens,
  PIP/streaming, EDID override, disconnect (we give that away free), and config protection.
- **Lunar is mid-rewrite** (v7, drops Intel + macOS <14, lands Sept–Oct 2026) and Apple broke its
  private-API XDR + Enhanced Contrast in macOS 26.3. Its remaining unmatched ideas: ambient-conditioned
  curve learning, nits sync, Pi DDC relay, Auto Mode.
- **MonitorControl is effectively unmaintained** (no release since Oct 2024, Tahoe OSD breakage,
  maintainer redirecting users to paid BetterDisplay). Its top open requests — app-drawn OSD (#1832),
  per-display sync offsets (#1781), input hotkeys (#720, 59 👍 all-time) — are all things we already
  ship. Biggest acquisition window in the category: "the maintained free successor to MonitorControl."
- **f.lux is coasting** (no binary since 2023, breaking on Tahoe) while a paid cohort (Sundown
  $4.99/mo, CircadianShield $47) monetizes deep warmth + PWM/dither relief. Iris is abandoned.
  A free, maintained warmth/flicker engine absorbs all of them.
- **Every XDR-boost app added battery/power automations in 2025–26** — unanimous category
  convergence; we have none. Both leaders shipped 2026 Studio Display XDR support in March
  (BrightIntosh's is still broken — winnable).
- **Loudest community sentiment is pricing/trust anger** (BetterDisplay invalidated early Pro
  licenses — issue #5004; "paywalled or too narrow" spawned a wave of small free apps). Free-GPL-forever
  is itself the feature; keep giving away what others paywall.

**⚠️ Do first — platform regression check (verify, half a day):** the Lunar dev reports gamma-table
dimming broken on the newest Apple Silicon, and macOS 26.3 killed Lunar's EDR paths; Tahoe has an
EDR-after-wake bug. Live-verify our gamma dimming, sub-zero, warmth, and XDR boost on current
hardware/OS **before** building anything on top of them or marketing "our public-API path survived."

---

## Batch 5 — quick wins, all public API (each `low`–`medium`)

| # | Feature | Why / evidence | Effort |
|---|---|---|---|
| 1 | **XDR boost automations** — auto-disable on battery / below charge threshold / timer / lid-close, restore on power-adapter return | Table stakes across Vivid, BrightIntosh, LUMEL, LumiMax; battery anxiety is the #1 boost hesitation. We have zero IOPowerSources code today. | low |
| 2 | **HDR-clipping fallback for the boost** — detect real HDR playback, step the boost aside | Top functional complaint across the whole boost category; Vivid ships a setting, BrightIntosh just warns in its README. | low–medium |
| 3 | **Control Center controls + desktop widgets** (ControlWidget + WidgetKit, macOS 15+) — boost toggle, scene/preset switcher, brightness | DisplayBuddy (v3.0.1/3.9.0) and BrightIntosh (v5.3.0) both shipped it; very visible on macOS 26; cheap. | low |
| 4 | **Rules engine for Scenes** — trigger any Scene on charger connect/disconnect, dark-mode flip, **Focus mode**, app launch, display connect, time/sun; audit log says which rule fired | Covers DisplayBuddy's flagship Schedules + BD's event hooks in one stroke; nobody integrates Focus modes at all; our Scenes + audit log make the "why did that happen" answer unique. | medium |
| 5 | **Deep warmth + warmth scheduling** — extend the kelvin slider below 2700 K (f.lux hits 1200 K, Sundown 500 K), schedule color temperature through Clock/Location Mode, slow melatonin-style ramps, Movie Mode, per-app warmth suspend | Our 2700 K floor is the shallowest of any tool surveyed, free ones included; f.lux is stagnant and breaking on Tahoe — its users are catchable. Location Mode already computes sun elevation. | medium |
| 6 | **Shortcut registry expansion** — volume action, per-display bindings, scene/preset hotkeys, Lunar-style modifier scoping (⇧ = display under cursor, ⌃ = externals only) | Registry is a fixed 5-action set today; "custom shortcuts" is a compared dimension in every 2026 matrix. Rides existing plumbing. | low |
| 7 | **`opendisplay layout dump`** — emit the whole current topology as one reproducible CLI command / declarative file; `opendisplay apply setup.json` | displayplacer's beloved ergonomic (4.5k stars, dormant); dotfiles-friendly; folds in the planned shared settings store that fixes the CLI-vs-app clobber bug (0.10.0 known issue). | medium |
| 8 | **MCP server** — first-party, permission-scoped ("agents may adjust brightness, never disconnect"), every action audit-logged through the existing gateway | DisplayBuddy shipped a raw CLI-wrapper MCP in v3.3.0; ours can be the *safe* one — the right 2026 story for an app whose brand is "can't leave you with a black screen." Nearly free atop the CLI. | low–medium |
| 9 | **Split-screen compare mode** — half-screen boosted / half stock, as a demo & verification tool | Vivid's most-praised mechanic, cloned by two competitors as a paywall; for us it's a pure showpiece + a live hardware-verification aid. | low |
| 10 | **Stream Deck plugin + Raycast extension** | Stream Deck owners are told to shell-script betterdisplaycli (BD discussions #2997/#2991); CLI + URL scheme make both thin. Community-friendly, visible. | low |

## Batch 6 — the eye-care / flicker pillar (a coherent release)

| # | Feature | Why / evidence | Effort / risk |
|---|---|---|---|
| 11 | **Flicker-free (PWM-safe) dimming mode** — pin hardware backlight at 100%, dim via gamma/overlay, guard against auto-brightness fighting it | Sundown charges $4.99/mo for packaging plumbing we already own end-to-end; PWM threads recur on every Mac generation and OLED MacBooks will amplify it. Public API. | low (packaging) |
| 12 | **Temporal-dithering toggle (Stillcolor-class), per display** — off for the sensitive, *force-on* for banding-prone externals; ledger-stamped so it survives wake | BetterDisplay's tracker shows 18+ months of users offering to pay; Stillcolor's top open bug is "reverts after wake" — our wake-convergence ledger is exactly the missing machinery, and per-display policy is its unshipped 2.0 milestone. **Labs-gated**: undocumented IOMobileFramebuffer property, verify via ioreg, honest "may die any macOS release" framing. | medium / private API |
| 13 | **Grayscale + accessibility tints** — one-hotkey grayscale, arbitrary-color overlay tints with intensity + schedule (Irlen/dyslexia/astigmatism users) | No maintained Mac menu-bar utility owns this; we already draw a dimming overlay — tint is a tiny delta. | low |
| 14 | **Gamma-conflict detection** — warn when f.lux/other gamma apps are co-resident; detect external gamma shifts and self-heal our state | BrightIntosh spent its entire v6 line (Mar–Aug 2026) on this; we run gamma dimming + warmth + boost in one process and have the same exposure. | medium |

## Batch 7 — TV, KVM & desk-hardware workflows

| # | Feature | Why / evidence | Effort / risk |
|---|---|---|---|
| 15 | **LG webOS control** — volume/power/input over Wi-Fi, Wake-on-LAN, wake/sleep choreography with the Mac | The 48" OLED-as-monitor crowd today runs a Hammerspoon+Python contraption (cmer/lg-tv-control-macos); BD shipped TV control *free*, DisplayBuddy sells it. Pure network protocol, no macOS API risk. **LG only, first** — Samsung Tizen's pairing is a support-ticket factory (DisplayBuddy reworked it 4×); Samsung later, explicitly experimental, or never. | medium |
| 16 | **Software KVM** — auto-switch monitor input when a USB device (your keyboard/switch) appears/disappears | People write blog posts about their m1ddc+Hammerspoon duct tape; we already have DDC input switching + per-input hotkeys — the USB-event trigger (public IOKit matching) is the only missing half. | medium |
| 17 | **External Apple XDR boost** — Pro Display XDR + 2026 Studio Display XDR via the same public EDR path | Vivid shipped it Mar 17, BrightIntosh Mar 23 and it's *still broken* ("does not work properly", Aug 2026) — a winnable race on hardware people actively shop for. | medium |
| 18 | **Nits model from public data** — EDID/DisplayID luminance descriptors + a per-display user calibration step → nits OSD readout, nits-normalized group sync | BD's headline 2026 feature and Lunar's differentiator — but do it the durable way: public EDID data + calibration, **not** private DisplayServices readouts (which will break loudly). Feeds groups, OSD, and Adaptive. | medium–high |
| 19 | **Window-position restore per display set** — remember and restore app windows (public AX API) when a display set returns | The single most-conflated ask next to Protected Layout ("why doesn't the world's most advanced OS remember window positions" — MacRumors, TidBITS Jan 2026). Completes our wake/sleep story; Stay/DisplayMaid niche is sleepy. Needs Accessibility permission (we already have the TCC pattern from media keys). | medium–high |

## Batch 8 — differentiators nobody can copy quickly

| # | Feature | Why only us | Effort |
|---|---|---|---|
| 20 | **Open monitor-quirks database** — EDID-keyed, in-repo, crowdsourced: safe/unsafe VCP codes (our own Samsung caps-wedge entry seeds it), value remaps, wake delays, VRR-panic flags; app consumes it to auto-configure *and* auto-guard | Needs EDID identity + a safety engine + open source — competitors have at most one of the three. Directly answers MonitorControl #1745 (volume broken on many monitors); also the gate that makes DDC caps auto-config safe to ever turn on. | medium |
| 21 | **Display time machine** — timeline UI over the existing audit ledger ("what dimmed my screen at 3pm and why"), one-click revert-to-timestamp, exportable diagnostic bundle | We're the only app in the category with an audit log at all. Turns internal rigor into a visible feature. | medium |
| 22 | **Guardrailed raw DDC** — `--dry-run`, quirks-DB blocklists, rate limits, undo-last-write | "The only DDC tool that can't brick your monitor." Thin layer over the safety engine. | low |
| 23 | **iPhone as ambient-light sensor + remote** — lightweight open-source companion streaming lux + triggering scenes over local network | Lunar's answer is solder-your-own ESP8266; closes our one remaining Lunar "partial" (Sensor Mode for lid-closed/Mac-mini rigs). Scope as community-maintained (App Store obligation). | medium–high |
| 24 | **OLED care mode** — static-content detection → gentle dim, idle true-black, per-panel policy keyed to EDID | No Mac display app addresses burn-in; OLED MacBook wave is the timing hook. | medium |
| 25 | **Localization** — string catalogs + community translation (we currently have zero `.xcstrings`) | DisplayBuddy spent three consecutive releases on i18n (it converts); BrightIntosh got 9 languages from GitHub contributors — GPL attracts the same. | low, ongoing |

## Batch 9 — the big private-API bet (Labs)

| # | Feature | Why / evidence | Risk |
|---|---|---|---|
| 26 | **Virtual displays (CGVirtualDisplay)** — one engine, five payoffs: headless-Mac HiDPI remote sessions, DeskPad-style "shareable window" screen, **HiDPI-via-mirror for 1440p/ultrawides** (the *only* custom-resolution path on Apple Silicon — Apple removed override files), portrait Sidecar, SDR-safe OBS capture | The whole resolution-tool category consolidated on this one primitive; free BetterDummy died into freemium BetterDisplay and HN grumbles about paying $19 for it; DeskPad (7.8k stars) proves free demand but is single-purpose. | Private API, 60 Hz cap, our largest breakage liability — Labs-gated with capability probe, like rotation. |
| 27 | **HTTP listener** — only with token auth; never ship script-execution actions | Completes the automation story (Home Assistant/MQTT next), but an unauthenticated localhost endpoint that can black out displays is a foot-gun. Design the auth first. | medium |

## Deliberately skipped (traps — revisit only with new evidence)

- **HiDPI mode injection / EDID override / color-mode (RGB-YCbCr) selector as promised features** — deepest
  private DCP surface, BetterDisplay's full-time-maintainer moat, and Apple demonstrably closes these
  paths (26.3 killed Lunar's XDR + Enhanced Contrast). HiDPI only via the virtual-display mirror route.
- **PIP/streaming/video-filter subsystem** — enormous scope; even Lunar's author ships PIP as a
  *separate paid app*. If ever, a companion app, not core.
- **Samsung Tizen (first), DisplayLink DDC, HDMI-CEC** — flaky pairing / reverse-engineered USB to
  third-party silicon / requires Pulse-Eight hardware. LG network control covers the real use cases.
- **True Tone / keyboard-backlight toggles** — private CoreBrightness for things System Settings already does.
- **Circadian health dashboards** (melanopic scores, light debt) — scope creep + health-claim liability;
  ship the color engine, skip the wellness scoring.
- **Forced HDR / NTSC-hidden modes** — black-screen territory; only ever behind the timed-revert gate, late.
- **Nits via private DisplayServices readouts** — public-data path only (see #18).

## Fold-in fixes (carry alongside whatever batch runs first)

1. **Group leader at max overwrites learned offsets** (0.10.1 known issue — fix in progress).
2. **Shared on-disk settings store** for CLI-vs-app clobber (0.10.0 note) — lands naturally with #7.
3. **Rotation restore under Protected Layout** — still notify-only; decide whether the experimental
   helper graduates or the drift note stays.
4. **OSDBroadcaster "todo 4"** — input-switch OSD events still not broadcast to external HUDs.
5. **Name collision** — an unrelated "OpenDisplay" (peetzweg/opendisplay, opendisplay.app — a
  Sidecar/Duet-style app) ranks in search; decide whether to differentiate copy/SEO before the
  r/macapps + Show HN posts.

## Suggested order

**Verify-first** (platform regression check) → **Batch 5** (ships a visible, all-public-API release
fast; #1–3 + #8 alone justify a 0.11) → **Batch 6** (the eye-care pillar as its own themed release —
strong Show HN story: "free, open, and it survives wake") → **Batch 7** in demand order (15 → 16 →
17 → 18 → 19) → **Batch 8** interleaved as morale/community wins → **Batch 9** when ready to own the
maintenance cost.
