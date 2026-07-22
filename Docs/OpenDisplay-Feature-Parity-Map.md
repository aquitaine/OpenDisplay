# OpenDisplay → BetterDisplay Feature Parity Map

A complete inventory of BetterDisplay's feature surface (v4.x, as of June 2026), mapped against
OpenDisplay's current capabilities, written as a planning + handoff document.

Sources: BetterDisplay GitHub README, the official "List of free and Pro features" wiki matrix,
and betterdisplay.pro. OpenDisplay status is taken from its README/PRD claims — see the caveat
under *How to read this*.

---

## How to read this

Each feature row carries four things:

- **Feature** — the capability, described in neutral/functional terms.
- **BD tier** — `Free` or `Pro` in BetterDisplay. (Pro is their paid moat; ~half the list.)
- **OD status** — OpenDisplay today: `✅ Have` · `🟡 Partial` · `⬜ Gap`.
- **Notes / API / difficulty** — the macOS surface it needs and rough effort.

**Difficulty scale:** `trivial` → `low` → `medium` → `high` → `very high`. "Private API" means it
depends on undocumented/private frameworks (CoreDisplay, SkyLight, DisplayServices, CGVirtualDisplay,
IOAVService) — higher maintenance risk across macOS releases.

> **Caveat on OD status:** these are mapped from OpenDisplay's README, not a line-by-line code audit.
> Rows marked `✅` are explicitly claimed as functional there; `🟡` are present but Labs/experimental
> or partial; `⬜` are not mentioned. A precise code-level audit (best done with repo
> access) would tighten the `🟡`/`⬜` calls — flagged at the end.

> **Clean-room reminder:** this is a map of *capabilities to match*, not BetterDisplay's code, UI,
> assets, or copy. OpenDisplay's README already commits to clean-room/independent implementation;
> every item below should be built from public docs + first-principles, keeping that line intact.

---

## 1. Brightness control

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Multi-method brightness (native + DDC + software) | Free | ✅ Have | DisplayServices (built-in), DDC/CI (external), gamma fallback. OD's core. |
| Native brightness/volume media keys | Free | 🟡 Partial | Intercept F1/F2/volume keys, route to active display. Verify OD wires the media keys. `low` |
| DDC brightness control | Free | ✅ Have | VCP 0x10 over I2C. |
| Software dimming — colour-table (gamma) | Free | ✅ Have | CGSetDisplayTransferByTable. OD has gamma dimming. |
| Software dimming — overlay | Free | ⬜ Gap | Black NSWindow at adjustable alpha above content. `low` |
| Combined dimming (gamma + overlay) | Free | ⬜ Gap | Chain the two to go darker than either alone. `low` |
| Dimming to black / "Black Out" | Free | ✅ Have | OD has Black Out. |
| Basic brightness syncing across displays | Free | ⬜ Gap | Broadcast one slider to a group. Needs a grouping model (§12). `low–medium` |
| Advanced brightness & image-adjustment syncing | Pro | ⬜ Gap | Sync brightness + contrast + colour together. `medium` |
| Nits-based normalized brightness syncing | Pro | ⬜ Gap | Needs a per-display nits model so "300 nits" means the same on each panel. `high` |

## 2. XDR / HDR extra-brightness upscaling — *BetterDisplay's signature pillar*

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Color-table XDR/HDR upscaling (Apple Silicon) | Pro | ⬜ Gap | Private gamma/EDR manipulation. Hardware-gated (XDR/HDR panels). `very high, private API` |
| Metal XDR/HDR upscaling (AS + Intel) | Pro | ⬜ Gap | EDR-enabled Metal layer + shader pushing values >1.0. `very high` |
| Direct XDR upscaling (AS, macOS 26.3+) | Pro | ⬜ Gap | Newest private path on 26.3+. `very high, private API` |
| Native XDR upscaling (AS, ≤ macOS 26.2) | Pro | ⬜ Gap | Older private brightness path. `very high, private API` |
| Upscale to ~1600 nits on XDR panels | Pro | ⬜ Gap | The headline number; output of the methods above. |
| External HDR display brightness boost | Pro | ⬜ Gap | Display-dependent (DisplayHDR 600+). |
| HDR extra-brightness calibration | Pro | ⬜ Gap | Per-display calibration UI on top of upscaling. `high` |
| Third-party HDR extra brightness | Pro | ⬜ Gap | Extends boost to non-Apple HDR panels. `high` |

> This whole block is the hardest, most macOS-version-fragile, and most hardware-specific part of
> BetterDisplay. Realistically a late-stage target, not an early win.

## 3. Color management

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Color-mode selector — RGB / YCbCr / chroma subsampling / HDMI range (AS) | Free | ⬜ Gap | Private CoreDisplay pixel-encoding + range APIs. `high, private API` |
| Color adjustments (per-channel) | Pro | 🟡 Partial | Extend OD's existing gamma-table path to RGB channels. `medium` |
| Color temperature control | Pro | ⬜ Gap | Warm/cool via gamma. Builds on §1 gamma path. `medium` |
| Color-profile (ICC) selector | Free | ✅ Have | OD does per-display ICC via ColorSync. |
| SDR/HDR color-profile auto-switch | Pro | ⬜ Gap | Detect HDR engage/disengage, swap profile. `medium` |

## 4. DDC / hardware control

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| DDC support across most Macs | Free | ✅ Have | OD has DDC/CI layer. |
| DDC over M1/M2 built-in HDMI | Free | 🟡 Verify | BD's unique selling point. Confirm OD reaches the built-in HDMI I2C bus on AS. `medium` |
| DDC over Intel 2018 mini built-in HDMI | Free | ⬜ Gap | Intel-only edge; low priority if OD is AS-first. `medium` |
| DDC brightness | Free | ✅ Have | VCP 0x10. |
| DDC volume | Free | ✅ Have | VCP 0x62. |
| DDC input switching | Free | ✅ Have | VCP 0x60. OD lists input source. |
| DDC input customization (label/define inputs) | Free | ⬜ Gap | UI to name/whitelist input codes per display. `low` |
| DDC power control (on/standby/off) | Free | ⬜ Gap | VCP 0xD6. `low` |
| DDC capabilities + auto-config | Free | ⬜ Gap | Read/parse VCP capabilities string, auto-detect supported controls. `medium` |
| DDC + color control over DisplayLink | Free | ⬜ Gap | DisplayLink path is separate from native DDC. `medium` |
| DDC color preset selection | Free | ✅ Have | VCP 0x14. OD lists colour preset. |

## 5. Networked TV / AVR control

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| LG webOS TV control | Free | ⬜ Gap | webOS WebSocket (SSAP) protocol. `medium, no private API` |
| Samsung Tizen TV control | Free | ⬜ Gap | Tizen WebSocket / SmartThings. `medium` |
| Philips Android TV control | Free | ⬜ Gap | JointSpace HTTP API. `medium` |
| Yamaha AVR control | Free | ⬜ Gap | YNCA / HTTP control. `medium` |
| Night Shift for TVs | Free | ⬜ Gap | Apply Night Shift / colour shift to external/TV via CoreBrightness. `medium` |

> Entirely self-contained network protocols — **no private macOS APIs, no hardware gating**. A clean,
> shippable module that can be built and tested brand-by-brand. Good morale/feature-count wins.

## 6. Resolution / scaling / HiDPI

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Custom scaled-resolution editing | Free | ✅ Have | OD does resolution switching. |
| **Flexible HiDPI scaling** (notch/HDR/HDCP/high-refresh) | Pro | ⬜ Gap | **The flagship.** Synthesize arbitrary scaled HiDPI modes (often via mode injection / EDID override). `very high, private API` |
| Native / default resolution editing | Free | ✅ Have | CGDisplay mode set. |
| Display-mode selector menu | Free | ✅ Have | Mode enumeration + menu. |
| Refresh-rate selector menu | Free | ✅ Have | Part of OD mode switching. |
| Unexposed + NTSC (59.94 etc.) refresh rates (AS) | Free | ⬜ Gap | Surface hidden CoreDisplay modes. `medium, private API` |
| Resolution slider | Free | 🟡 Partial | Continuous slider over the mode ladder. OD has switching; confirm slider UX. `low` |
| Create custom HiDPI resolutions for real displays | Free→Pro | ⬜ Gap | Manual mode authoring; overlaps flexible scaling. `high` |
| Favorite resolutions (menu / slider / shortcut) | Pro | ⬜ Gap | Persist + quick-recall presets. `low` |
| Screen-rotation menu | Free | 🟡 Partial | OD has rotation in Labs (opt-in). Promote out of Labs. `medium` |
| Resolution syncing / UI-scale matching | Pro | ⬜ Gap | Match logical UI scale across displays. `medium` |
| Forced-HDR mode to unlock resolution limits | Pro | ⬜ Gap | Toggle HDR to access higher modes/refresh. `high, private API` |
| Hi-quality Zoom + screenshots on 1080p | Free | ⬜ Gap | Byproduct of HiDPI backing scale. Comes with flexible scaling. |

## 7. Display disconnect / reconnect — *OpenDisplay's core strength*

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Soft disconnect / reconnect displays | Pro | ✅ Have | OD's defining capability, with independent recovery (see §16). SkyLight. |
| Auto-disconnect built-in screen on external connect | Pro | 🟡 Partial | OD has auto fall-back to built-in; confirm the *auto-disconnect-on-connect* trigger + UI. `low` |
| Prevent sleep while a display is connected | Pro | ⬜ Gap | IOPMAssertion (kIOPMAssertionTypePreventUserIdleDisplaySleep). `low` |

## 8. Virtual screens

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Virtual-screen creation | Free | 🟡 Partial | CGVirtualDisplay (private). OD has a VirtualDisplay provider in Labs. `medium, private API` |
| Virtual-screen association (bind to a real output) | Free | 🟡 Partial | Pairing logic on top of creation. `medium` |
| Custom virtual screens (arbitrary res/aspect) | Pro | ⬜ Gap | Parametrized creation UI. `high` |
| HDR virtual screens (+ high-refresh) | Pro | ⬜ Gap | HDR-capable virtual mode (compatible Macs). `high, private API` |
| Headless-Mac support for remote access | Free | ⬜ Gap | Derived from virtual screens (no panel attached). |
| Scaled / portrait Sidecar via virtual-screen streaming | Pro | ⬜ Gap | Needs virtual screen + streaming (§9). `high` |

## 9. Picture-in-Picture / streaming / video filters — *whole subsystem*

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Picture-in-Picture window of any display/virtual screen | Pro | ⬜ Gap | ScreenCaptureKit capture → floating window. `high` |
| Video-filter window | Pro | ⬜ Gap | Metal render pass over captured stream. `high` |
| Full-screen video filters | Pro | ⬜ Gap | Filter applied to whole screen via self-stream. `high` |
| Full-screen streaming (display → another screen) | Pro | ⬜ Gap | Local stream redirect. `high` |
| Stream/PIP stretching + off-centering | Pro | ⬜ Gap | Geometry transforms on the stream. `medium` (once subsystem exists) |
| Stream/PIP rotation (+ portrait Sidecar) | Pro | ⬜ Gap | Rotated render. `medium` |
| Stream/PIP crop | Pro | ⬜ Gap | Crop rect on capture. `medium` |
| Teleprompter mode (stream flip) | Pro | ⬜ Gap | Horizontal mirror of stream. `low` (once subsystem exists) |
| Off-center streaming (bottom-half-of-TV widescreen) | Pro | ⬜ Gap | Position a cropped stream region. `medium` |
| Self-streaming (apply filters to own screen) | Pro | ⬜ Gap | Loopback capture + filter. `high` |

> One cohesive pillar: **ScreenCaptureKit (capture) + Metal (render/filter) + window management.**
> Build the capture→render→window spine once; the ~10 sub-features above are then mostly geometry
> and filter variations on top. All public APIs — effort is high but risk is low.

## 10. Mirroring

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Mirror configuration (build mirrored sets) | Pro | ✅ Have | OD has mirroring + a reversible CG fallback. |
| Mirror protection (keep a mirror set intact) | Pro | ⬜ Gap | Re-apply mirror state on change — aligns with OD's desired-state model. `medium` |
| Simplify creating mirrored sets (UI) | Pro | 🟡 Partial | UX layer over existing mirroring. `low` |

## 11. EDID

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| EDID retrieval / export | Free | ⬜ Gap | IORegistry `IODisplayEDID` read + export. `low–medium` |
| Detailed display information panel | Free | 🟡 Partial | Surface registry/CoreDisplay metadata in UI. `low` |
| Display-name override | Free | ⬜ Gap | Alias at app level, or CoreDisplay/registry naming. `low` |
| EDID override (Apple Silicon) | Pro | ⬜ Gap | CoreDisplay override path. `very high, private API` |
| EDID override (Intel) | Pro | ⬜ Gap | Display-override plist approach; SIP-sensitive. `very high` |

## 12. Display-config protection / layout / groups

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Display-config protection (res / refresh / VRR / rotation / profile) | Pro | 🟡 Partial | Watch for drift, re-apply desired state. **Directly leverages OD's scene/safety engine.** `medium` |
| Layout protection with anchor points | Pro | ⬜ Gap | Persist arrangement + re-apply on reconnect. Aligns with scenes. `medium–high` |
| Advanced layout management | Pro | ⬜ Gap | Richer multi-display arrangement tooling. `medium–high` |
| Custom display groups | Pro | ⬜ Gap | Grouping model feeding syncing (§1) + controls. `medium` |
| Display group + synchronization (basic) | Free | ⬜ Gap | The basic sync atop grouping. `low–medium` |
| Move displays relative to each other from the menu | Free | ✅ Have | OD has the drag-to-arrange canvas. |

> OD's existing scene engine (desired-state diff/plan/idempotency) makes this category *cheaper for
> OpenDisplay than it was for BetterDisplay* — protection is "re-assert a saved scene on change."

## 13. Keyboard shortcuts

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Native brightness/volume keys | Free | 🟡 Partial | See §1 media-key row. |
| Basic custom keyboard shortcuts | Free | ⬜ Gap | Global hotkey registration → actions. `low` |
| Advanced custom keyboard shortcuts | Pro | ⬜ Gap | Per-display / per-action / chained shortcuts. `medium` |
| Shortcuts for brightness + audio | Free | ⬜ Gap | Specific bindings on the above. `low` |

## 14. On-screen display (OSD)

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Native / native-looking OSD | Free | ⬜ Gap | Floating HUD window on brightness/volume change. `medium` |
| OSD nits output (show nits, not %) | Pro | ⬜ Gap | Needs nits model (§1). `medium` |
| Custom OSD styles (+ classic-on-Tahoe) | Free | ⬜ Gap | Theming layer over the OSD. `low` |
| External HUD / notch-app integration API | Free | ⬜ Gap | Publish OSD events (distributed notification dispatch) so notch apps can render them. `low` |

## 15. Automation / integration / CLI

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Command-line integration | Free | ✅ Have | OD ships the `opendisplay` CLI on the safety-checked path. |
| Custom integration + DDC controls (scriptable) | Pro | 🟡 Partial | Expose arbitrary DDC/actions to scripts. `medium` |
| Control integration via shell scripts + URLs | Free | 🟡 Partial | OD CLI covers shell; add URL triggers. `low` |
| macOS Shortcuts (App Intents) | Free | ✅ Have | OD has Shortcuts/Siri intents. |
| HTTP server + custom URL scheme | Free | ⬜ Gap | `opendisplay://` handler + small embedded HTTP listener. `low–medium` |
| Notifications (on events) | Free | ⬜ Gap | UserNotifications on config/display events. `low` |
| Raycast extension | 3rd-party | ⬜ N/A | Community could build one once CLI/URL surface is stable. |

## 16. Eye care / misc / platform

| Feature | BD tier | OD status | Notes / API / difficulty |
|---|---|---|---|
| Reduce PWM / temporal-dithering flicker | Free | ⬜ Gap | Disable dithering / nudge brightness method per panel. `medium, private API` |
| Localization | — | ⬜ Gap | String catalogs + community translation. `low, ongoing` |
| Homebrew cask | — | ⬜ Gap | Distribution convenience. `trivial` |
| Menu-bar app, no Dock icon | — | ✅ Have | OD is already a menu-bar agent. |
| Signed + notarized distribution | — | ✅ Have | OD ships Developer-ID-signed + notarized. |
| Trial + Pro licensing | — | ⬜ N/A | OD is GPL/free — not applicable, and a positioning advantage. |

---

## Where OpenDisplay already *leads* BetterDisplay

Worth keeping visible — these are differentiators to lean into, not gaps:

- **Scenes** — true desired-state snapshots with diff/plan/idempotency. BetterDisplay only has
  config *protection*, not a first-class scene engine.
- **Independent recovery** — a separate signed rescue app + global hotkey, with an
  always-one-display-active guarantee and auto fall-back to the built-in panel. BetterDisplay leans
  on its own UI to undo a bad state.
- **Explicit safety model** — observed-vs-desired state tracking, and outcomes verified via OS
  events/read-back or reported as `unverified` rather than assumed.
- **Audited, unified automation path** — CLI, Shortcuts, and the UI all drive the *same*
  safety-checked path.
- **Universal software fallback** — gamma dimming even below the panel's hardware minimum.
- **Open source (GPL)** vs a paid/closed model.

---

## Suggested build order (handoff tiers)

Grouped by risk/effort so a tier can be taken at a time. The principle: **broaden the free-tier
parity with low-risk, no-private-API wins first; defer the hardware-gated and private-API moat.**

**Tier 0 — already done (the free-tier core).** Brightness (3 methods), DDC hardware controls, ICC
profiles, mode/refresh/HiDPI switching, mirroring, dimming/Black Out, soft disconnect + recovery,
scenes, CLI, Shortcuts.

**Tier 1 — low-risk standalone wins (no private APIs, mostly free-tier parity):**
DDC input customization · DDC power · DDC capabilities/auto-config · display-name override ·
EDID retrieval/export · prevent-sleep-while-connected · basic + brightness/audio keyboard shortcuts ·
favorite resolutions · resolution slider polish · HTTP + URL scheme · notifications · native-looking
OSD + custom styles + notch-app integration API · **networked TV/AVR control (LG, Samsung, Philips,
Yamaha)** · Night Shift for TVs · mirror protection · display-config protection *(rides the scene engine)*.

**Tier 2 — medium, builds on the existing engine:**
display groups + brightness syncing (basic → advanced) · color adjustments + color temperature
*(extend gamma)* · SDR/HDR profile auto-switch · layout protection / anchor points / advanced layout ·
unexposed + NTSC refresh rates · advanced keyboard shortcuts · DisplayLink DDC.

**Tier 3 — high effort / private API (the resolution moat):**
**flexible HiDPI scaling (flagship)** · color-mode selector (RGB/YCbCr/chroma/HDMI range) ·
virtual screens (basic → custom → HDR) + headless · forced-HDR mode · EDID override (AS → Intel).

**Tier 4 — streaming subsystem (new pillar, public APIs):**
build the ScreenCaptureKit→Metal→window spine, then PIP · local/full-screen streaming · video filters ·
stretch/off-center/crop/rotate · teleprompter · scaled/portrait Sidecar.

**Tier 5 — hardware-gated, hardest, most fragile:**
XDR/HDR brightness upscaling (color-table, Metal, direct, native) · HDR calibration · third-party HDR
brightness · nits-based normalized syncing · OSD nits output *(all depend on the nits model)*.

---

## Decisions (locked) & status corrections — post-audit

**Decisions resolved:**

1. **Platform: Apple Silicon only.** Intel is explicitly out of scope. The Intel rows above
   (DDC over the 2018 mini HDMI, EDID override (Intel)) are **dropped** — ignore them. Audit confirms
   the core is cleanly AS-native with no Intel-only code; the only cleanup is vestigial cross-arch
   *build* surface (no `arm64` pin in `project.yml` → it's building universal; dead `#else` arch
   branches; runtime-not-compile-time AS guard).
2. **Private APIs / reverse engineering: in scope.** Tiers 3/5 may use reverse-engineered *Apple*
   frameworks (distinct from the BetterDisplay clean-room line). Accepted costs: cross-version
   fragility + no Mac App Store (irrelevant — ships notarized via GitHub under GPL).
3. **Audit: complete.** Ground-truth statuses below supersede the inferred `🟡`/`⬜` cells in the
   tables above.
4. **Issues: in progress.** Batch 1 (5 quick wins + 1 safety hardening) is written — see
   `OpenDisplay-Issues-Batch-1.md`. That doc + the live repo are now the source of truth for active
   work; the tables above are the strategic overview.

**Status corrections from the repo audit (these override the cells above):**

- **Already shipped (✅), do not rebuild:** DDC *input customization* (VCP `0x60`, with UI + CLI) and
  *display-name override* (alias, persisted, UI + CLI). Both were marked `⬜` above — they're done.
- **DDC over the M1/M2 built-in HDMI: confirmed working (✅)** for a single external via
  `IOAVService`/`DCPAVServiceProxy` (`Location=="External"`). **Caveat:** multi-display
  disambiguation is by enumeration order, not EDID → wrong-monitor risk with several *identical*
  externals (a real follow-up).
- **Virtual screens AND PIP/streaming are bare stubs (⬜ greenfield), not partial.**
  `VirtualDisplayProvider` and `CaptureProvider` are ~17-line stubs; `CGVirtualDisplay` /
  ScreenCaptureKit aren't used anywhere. Budget these as full new subsystems.
- **Native media keys: full gap (⬜).** Brightness/volume are app-UI only; nothing intercepts the
  F1/F2/volume keys today (the one global hotkey is ⌃⌥⌘R for Reconnect-All).
- **Auto-disconnect-on-external-connect: only the fall-back exists (⬜ trigger).** The "external
  arrived → turn off built-in" watcher isn't wired; the disconnect mechanism + safety net are. This
  is the project's original use case — small to finish (Batch 1, Issue 5).
- **Color via gamma: ⬜ as gamma** (the gamma call is a uniform all-channel scale = dim/black-out
  only), but it already takes per-channel RGB args → trivial to generalize for color-temp/RGB.
  Overall color is ✅ via ICC + DDC preset.

**⚠️ Architectural finding worth a decision:** only logical disconnect/reconnect is gated by the
SafetyEngine. **Set-main, mirror, and resolution changes alter the active arrangement but bypass it.**
A bad resolution/mirror can leave a display unreadable while still technically "active," so it doesn't
get the checkpoint/independent-recovery guarantee disconnect does — which rubs against the project's
own *safety-before-capability* principle, and gets more exposed once the resolution slider lands.
Captured as Batch 1's safety-hardening issue (timed auto-revert).
