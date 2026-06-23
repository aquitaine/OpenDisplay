# Interface Redesign — Restore the Menu-Bar / Settings Division of Labor

Status: Proposed · Owner: TBD · Target: M1 polish

## Problem

The menu-bar popover has absorbed the entire Settings "Detail" pane. The per-display
card in [`MenuBarView.swift`](../Apps/OpenDisplay/Sources/MenuBarView.swift) carries a
**12-row action list with nested disclosure-within-disclosure** (Set as main, Display
mode, Mirror, Move in arrangement, Rotation, Colour mode, Colour profile, Image
adjustments, Hardware control, Input source, Rename, Display info).

The reference design kit (the project's source of truth,
[`reference/screens-shared.jsx`](../Packages/OpenDisplayDesignSystem/reference/screens-shared.jsx)
`MBDisplay`) intends a lean card: brightness + volume sliders, a status-chip row, and a
small set of quick actions. The Settings window — meant to be a sidebar (Detail · Arrange
· Scenes · Automation · Health & Recovery · Labs) — is instead a thin 3-tab shell that
**duplicates the display list** and **mis-files Arrange under Scenes**.

### Concrete redundancy / doubling inventory

1. **Brightness ×3** — native slider, "Image adjustments" (software gamma), "Hardware
   control" (DDC brightness). All dim the screen; three separate places.
2. **Display list ×2** — menu-bar cards + Settings "Displays" tab (adds only alias edit).
3. **Resolution ×2** — inline slider + "Display mode" expandable (refresh / HiDPI).
4. **Colour ×2 rows** — "Colour mode" (DDC preset) vs "Colour profile" (ColorSync).
5. **Arrangement ×3 entry points** — card "Move in arrangement…", Tools "Displays &
   arrangement…", and the canvas itself filed under Settings → **Scenes**.
6. **Reconnect All ×2** — menu bar + Settings (this one is *intentional* per PRD recovery
   requirement; keep both but share one component).
7. **Rotation split** — control lives in the card; its enable-toggle is buried in
   Settings → Diagnostics → Labs.
8. **Settings structure drift** — intended sidebar collapsed into 3 tabs; Arrange under
   "Scenes" is a category error.

### Key finding

Every capability in the reference (`blackOut`, `monitorPower`/Sleep, `volume`,
`nativeBrightness` / `ddcBrightness` / `softwareDimming`, `hdr`, `colorProfile`, …) is
**already modeled** in [`Capability.swift`](../Packages/DisplayDomain/Sources/DisplayDomain/Capability.swift).
This is a **UI reorganization**, not a backend build. The only genuinely new wiring is
Black Out / Sleep quick actions (capabilities exist; provider hookup may be partial).

## Principle

**Menu bar = fast, frequent, safe. Settings = detail, configuration, recovery.**
Every change below follows from re-establishing that split, matching the reference kit.

## Decisions (locked)

- **Scope:** Faithful rebuild toward the reference kit (both surfaces).
- **Brightness:** One capability-aware slider (native → DDC → software-gamma, auto-picked,
  method shown as a caption). Explicit manual split moves to Settings → Controls.

---

## Phased plan

### Phase 0 — Design-system components (foundation)

The card hand-rolls everything inline (`MenuActionRow`, `DisplayCard`). Port the shared
kit components into `OpenDisplayDesignSystem` so both surfaces consume them (README already
scopes these as the "14 components" port):

- `Badge`, `Dot`, `GlyphTile`, `SectionLabel`
- `Card`, `Row`, `LabeledRow`
- `MBSliderRow`, `MBChip`, `QuickAction`

Each ships SwiftUI `#Preview`s mirroring the reference states. No behavior change yet.

### Phase 1 — Capability-aware brightness service

Introduce a `BrightnessController` (in `AppModel` or a dedicated service) that resolves the
best route per display from capability: `nativeBrightness` → `ddcBrightness` →
`softwareDimming`. Exposes:

- `level(for:) -> Double?` and `setLevel(_:for:)`
- `method(for:) -> BrightnessMethod` (`native` / `hardware` / `software`) for the caption

Consolidates the three existing paths (`brightness`, `softwareDim`, DDC brightness). The
explicit per-route controls survive only in Settings → Controls for power users.

### Phase 2 — Slim the menu-bar card (`MBDisplay`)

Rebuild `DisplayCard` to match the reference:

- **Collapsed:** GlyphTile · name · sub (`res · Hz`) · trailing badge (Main / Offline /
  Reconnecting / Degraded / Ambiguous) · chevron.
- **Expanded (active only):**
  - Brightness slider (unified, with method caption)
  - Volume slider — *rendered only when `volume` capability is supported*
  - Status-chip row: resolution · Hz · HDR · True Tone (chips reflect/toggle state)
  - Quick actions: **Black Out · Sleep · Set as main** (and Disconnect where the header
    on/off toggle lives today) — *each gated on its capability; hidden or "Soon" when absent*
  - One **"Display settings…"** deep-link row (replaces the 12-row list)

Remove from the card → moves to Settings Detail: Display mode, Colour mode, Colour
profile, Image adjustments, Hardware control, Input source, Rotation, Rename, Display info.

Capability gating rule: never render a faked control. If a capability is `unsupported`,
hide it; if `unknown`/probing, show "Reading…"; consistent with today's "Soon" pill.

### Phase 3 — Settings: sidebar + per-display Detail pane

Replace the 3-tab `TabView` with a `NavigationSplitView` sidebar matching the kit:

- **Displays** — a selection list (left) feeding a **Detail pane** (right). The list
  *replaces* today's duplicated "Displays" tab. Detail pane is `Card`-based:
  - *Resolution* — resolution menu/slider + refresh + HiDPI (from card "Display mode")
  - *Appearance* — rotation, colour mode, colour profile, image adjustments
  - *Controls* — DDC hardware (contrast/volume), input source, explicit brightness split
  - *Use as* — set as main, mirror
  - *Lifecycle* — disconnect / reconnect / managed-offline state
  - *Info* + *Rename* (alias)
- **Arrange** — promote `DisplayArrangementView` out of Scenes into its own item.
- **Scenes** — keep, minus the arrangement canvas.
- **Health & Recovery** — rename "Diagnostics & Recovery"; providers + recovery + recent
  activity, with **Labs** (rotation enable toggle, future virtual displays, kill switch)
  as a section here or its own sidebar item.

### Phase 4 — Deep-linking & entry-point dedupe

- Card **"Display settings…"** opens Settings to the selected display's Detail pane
  (add `selectedDisplayID` to `AppModel`).
- Collapse "Move in arrangement…" + "Rename & manage…" + per-feature "Open Display
  Settings…" into that single deep-link.
- Extract a shared `ReconnectAllButton` used by both the menu bar and Health & Recovery
  (keep both placements — recovery-critical per PRD UX-001 / §recovery).

### Phase 5 — Polish & verify

- Risk pills (UX-06), VoiceOver labels (UX-07), reduced-motion for disclosure animations.
- Build, launch, screenshot both surfaces; compare against reference screens.

---

## Sequencing & risk

- Phase 0 and 1 are prerequisites. Phases 2 and 3 can proceed in parallel once 0/1 land.
  Phase 4 depends on 3.
- Lowest risk: it's reorganization over an already-complete domain/provider layer. No new
  private APIs; rotation stays gated as today.
- Biggest behavioral change for users: the card gets dramatically shorter; detail moves
  one click away into Settings. Mitigate with the deep-link so detail is never buried.

## Out of scope (this pass)

- New providers for Black Out / Sleep beyond wiring existing capabilities.
- Automation surface (stub only / defer).
- Virtual displays, Recovery OSD full-screen (tracked separately in the kit).
