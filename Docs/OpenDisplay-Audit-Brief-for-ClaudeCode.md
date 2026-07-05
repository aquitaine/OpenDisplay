# OpenDisplay — Repo Audit Brief (for Claude Code)

**Goal:** replace inferred status with ground truth. The parity map
(`OpenDisplay-Feature-Parity-Map.md`) marks each capability `✅ Have / 🟡 Partial / ⬜ Gap`, but those
calls were inferred from the README, not the code. Audit the actual repo and correct them.

**This pass is read + report only — do NOT build or change features.**

---

## Tasks

### 1. Status pass
For every capability in the parity map, open the relevant source and determine its real state. Record:
- **Status:** `Have / Partial / Gap`
- **Evidence:** file path(s) + function/type names that implement it (or confirm its absence)
- **If Partial:** what's specifically missing to reach `Have`

Give extra scrutiny to the rows flagged `🟡` or "Verify":
- native brightness/volume media keys
- resolution-slider UX (vs. discrete mode switching)
- DDC over the **M1/M2 built-in HDMI** bus
- the `VirtualDisplay` provider's actual state (functional vs. stub)
- color adjustments via the existing gamma path
- auto-disconnect-of-built-in on external connect (the trigger, not just the fall-back)
- screen rotation (currently Labs/opt-in)

### 2. Apple-Silicon-native confirmation  ← *Apple Silicon is the only supported target (locked); Intel is out of scope*
Apple Silicon is the confirmed sole target — Intel support is explicitly not a goal. Verify the code
matches that intent:
- Confirm the core paths are cleanly AS-native — SkyLight disconnect, IOAVService DDC, CoreDisplay
  calls, CGVirtualDisplay, DisplayServices brightness — with no dependence on anything Intel-only.
- Flag any **vestigial or half-built Intel branches / cross-arch abstractions** that exist only to
  straddle both architectures; these are removal candidates to shrink surface area (call them out —
  do **not** delete in this read-only pass).
- Note any place an AS-only assumption is implicit but unenforced (e.g. a missing arch guard) so it
  can be made explicit later.

### 3. Provider / architecture inventory
List everything under `Providers/*` and what each actually implements today vs. stubs. Note which
capabilities run through the safety-checked transaction path (`TopologyCore` / `SafetyEngine`) vs.
bypass it.

### 4. Quick-win confirmation
Of the **Tier 1** items in the parity map (DDC input customization / power / auto-config, EDID export,
display-name override, prevent-sleep-while-connected, basic keyboard shortcuts, favorite resolutions,
HTTP + URL scheme, OSD, networked TV/AVR control, Night Shift for TVs), confirm which already have
partial scaffolding to build on vs. which are true greenfield.

---

## Output

- A **corrected status column** — update the parity map in place, or emit a delta table keyed to the
  same feature names — with file/function evidence inline.
- A short **"platform reality"** paragraph answering Task 2.
- The **smallest 3–5 features to implement first**, given what scaffolding already exists.

Keep evidence concrete (paths + symbols). Don't guess — if something is ambiguous, say so and point to
the exact file to check.
