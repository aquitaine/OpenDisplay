# OpenDisplayDesignSystem

The SwiftUI port of the OpenDisplay design kit. **macOS target** (Xcode), built in M0–M1.

The original web design system (tokens, components, screens, icon inventory, and the screen
& icon plan) is preserved verbatim under [`reference/`](reference/) as the **source of
truth**. This package re-expresses it natively, matching macOS HIG.

## Port plan

### Tokens → `Sources/.../Tokens`
Light + dark semantic tokens from `reference/ds/tokens/*.css`:

- **Color** — accent `#007AFF` (light) / `#0A84FF` (dark); status green/orange/red; label
  hierarchy (primary/secondary/tertiary/quaternary); window/sidebar/content/card/panel
  surfaces. Implement as semantic `Color` extensions backed by an asset catalog.
- **Type** — Apple system stack; scale 10→26pt (13pt body, tabular figures for metrics).
- **Spacing** — 4px base scale; rows ≈28px (menu-bar) / ≈38px (settings).
- **Radii** — 4/6/8/10/12/16/pill. **Elevation** — control/card/popover/window shadows.
- **Materials** — vibrancy via `NSVisualEffectView` only for the popover & menu bar.

### Components (14) → `Sources/.../Components`
`Button`, `IconButton`, `Switch`, `Slider`, `SegmentedControl`, `Select`, `Stepper`,
`Checkbox`, `Card`, `Row`, `Divider`, `Badge`, `InlineBanner`, `DisplayTile` — plus kit
composites `Popover`, settings `Window`/sidebar, `MBDisplay`, `MBSliderRow`, `QuickAction`,
`GlyphTile`. Each ships SwiftUI `#Preview`s mirroring the states in the web `@dsCard` demos.

### Icons → `Sources/.../Icons`
Use **SF Symbols** in production. `reference/ds/od-icons.js` + `reference/od-icons-ext.js`
ship hand-built line substitutes only and document the SF Symbol mapping for all ~60 glyphs;
replace the substitutes with the mapped SF Symbol names.

### Screens (consumed by `Apps/OpenDisplay`)
- **Menu-bar popover** (11 states): default, collapsed, built-in-only, scanning,
  managed-offline + Reconnect All, reconnecting, disconnect countdown, black out, degraded,
  ambiguous identity. Source: `reference/screens-menubar.jsx`.
- **Settings window**: per-display Detail (resolution/appearance/use-as/lifecycle/degraded/
  offline), Arrange canvas (+mirror/identify), Scenes (empty/list/dry-run), Automation,
  Health & Recovery, Labs, Add Virtual Display, the disconnect confirmation sheet, and the
  full-screen Recovery OSD. Sources: `reference/screens-settings-a.jsx`,
  `reference/screens-settings-b.jsx`, `reference/screens-shared.jsx`.

All views consume immutable domain snapshots and emit commands; they never mutate domain
state. No emoji; status via SF Symbol glyphs, color dots, and pills.
