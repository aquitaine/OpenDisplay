/* OpenDisplay screen-plan — icon inventory (existing kit glyphs + net-new).
   Exposes window.ODIconInventory. */
(function () {
  const I = window.ODIcons;
  const h = React.createElement;

  // existing kit glyphs → production SF Symbol
  const EXISTING = [
    ["monitor", "display"], ["monitorLines", "display (main)"], ["sunDim", "sun.min"],
    ["sunMax", "sun.max"], ["speaker", "speaker"], ["speakerWave", "speaker.wave.2"],
    ["gear", "gearshape"], ["info", "info.circle"], ["chevronRight", "chevron.right"],
    ["chevronDown", "chevron.down"], ["mirror", "rectangle.on.rectangle"], ["rotate", "rotate.right"],
    ["plus", "plus"], ["lock", "lock"], ["bolt", "bolt"], ["eject", "eject"],
    ["arrows", "arrow.left.arrow.right"], ["sparkles", "sparkles"], ["display2", "display.2"], ["check", "checkmark"],
  ];

  // net-new glyphs → suggested SF Symbol + where used
  const NEW = [
    ["cable", "cable.connector", "Route · DDC"],
    ["usbc", "cable.connector.horizontal", "Route"],
    ["wireless", "wifi", "Wireless route"],
    ["airplay", "airplayvideo", "AirPlay display"],
    ["sidecar", "rectangle.connected.to.line.below", "Sidecar"],
    ["blackout", "rectangle.slash", "Black Out"],
    ["moon", "moon", "Monitor sleep"],
    ["powerOff", "power", "Monitor power"],
    ["disconnect", "rectangle.badge.xmark", "Logical disconnect"],
    ["reconnect", "arrow.triangle.2.circlepath", "Reconnect"],
    ["reconnectAll", "arrow.triangle.2.circlepath.circle", "Reconnect All"],
    ["shield", "shield", "Safety / Safe Mode"],
    ["shieldCheck", "checkmark.shield", "Recovery verified"],
    ["checkpoint", "flag", "Checkpoint"],
    ["health", "waveform.path.ecg", "Provider health"],
    ["warning", "exclamationmark.triangle", "Caution"],
    ["countdown", "timer", "Confirm countdown"],
    ["circuitBreaker", "bolt.slash.circle", "Circuit breaker"],
    ["scenes", "square.stack.3d.up", "Scenes"],
    ["keyboard", "keyboard", "Hotkeys"],
    ["command", "command", "Shortcut key"],
    ["terminal", "terminal", "CLI"],
    ["api", "network", "Local API"],
    ["token", "key", "Access token"],
    ["rules", "slider.horizontal.below.rectangle", "Rules"],
    ["labs", "flask", "Labs"],
    ["killSwitch", "switch.2", "Kill switch"],
    ["undo", "arrow.uturn.backward", "Undo change"],
    ["history", "clock.arrow.circlepath", "Activity log"],
    ["bundle", "shippingbox", "Diagnostics bundle"],
    ["identify", "1.square", "Identify display"],
    ["ambiguous", "questionmark.square.dashed", "Identity ambiguous"],
    ["scan", "dot.radiowaves.left.and.right", "Scanning"],
    ["tag", "tag", "Alias / tag"],
    ["contrast", "circle.righthalf.filled", "Contrast"],
    ["inputSource", "rectangle.and.hand.point.up.left", "Input source"],
    ["refresh", "arrow.clockwise", "Refresh rate"],
    ["plug", "powerplug", "Physical link"],
  ];

  function Cell({ name, sf, use, isNew }) {
    return (
      <div style={{ width: 132, display: "flex", flexDirection: "column", alignItems: "center",
        gap: 7, padding: "14px 6px", borderRadius: 10, background: "var(--card-bg)",
        boxShadow: "var(--shadow-card)" }}>
        <div style={{ width: 40, height: 40, borderRadius: 9, display: "flex", alignItems: "center",
          justifyContent: "center", background: isNew ? "var(--accent-tint)" : "var(--fill-tertiary)",
          color: isNew ? "var(--accent)" : "var(--label-primary)" }}>{h(I[name], { size: 22 })}</div>
        <div style={{ font: "var(--weight-semibold) 11.5px/1.1 var(--font-text)", color: "var(--label-primary)", textAlign: "center" }}>{name}</div>
        <div style={{ font: "var(--weight-regular) 10px/1.25 var(--font-mono)", color: "var(--label-tertiary)", textAlign: "center" }}>{sf}</div>
        {use && <div style={{ font: "var(--weight-regular) 10px/1.2 var(--font-text)", color: "var(--label-secondary)", textAlign: "center" }}>{use}</div>}
      </div>
    );
  }

  function GroupHeader({ title, count, sub }) {
    return (
      <div style={{ display: "flex", alignItems: "baseline", gap: 10, margin: "4px 2px 12px" }}>
        <h2 style={{ margin: 0, font: "var(--weight-bold) 17px/1 var(--font-display)", color: "var(--label-primary)" }}>{title}</h2>
        <span style={{ font: "var(--weight-medium) 12px/1 var(--font-text)", color: "var(--label-tertiary)" }}>{count}</span>
        <span style={{ flex: 1 }} />
        <span style={{ font: "var(--weight-regular) 11.5px/1.3 var(--font-text)", color: "var(--label-secondary)" }}>{sub}</span>
      </div>
    );
  }

  function Inventory() {
    return (
      <div style={{ width: 1040, padding: 28, fontFamily: "var(--font-text)",
        background: "var(--window-bg)", borderRadius: "var(--radius-2xl)", boxSizing: "border-box" }}>
        {/* brand row */}
        <div style={{ display: "flex", alignItems: "center", gap: 16, padding: "4px 4px 22px" }}>
          <img src="ds/opendisplay-icon.svg" width={52} height={52} alt="" style={{ borderRadius: 12 }} />
          <div style={{ flex: 1 }}>
            <h1 style={{ margin: 0, font: "var(--weight-bold) 24px/1.1 var(--font-display)",
              letterSpacing: "var(--tracking-tight)", color: "var(--label-primary)" }}>Iconography</h1>
            <div style={{ font: "var(--weight-regular) 12.5px/1.4 var(--font-text)", color: "var(--label-secondary)", marginTop: 3 }}>
              1.6px rounded line glyphs · inherit currentColor · map to SF Symbols in production.</div>
          </div>
          <img src="ds/opendisplay-wordmark.svg" height={26} alt="OpenDisplay" />
        </div>

        <GroupHeader title="Already in the kit" count={EXISTING.length + " glyphs"}
          sub="Shipping in assets/od-icons.js" />
        <div style={{ display: "flex", flexWrap: "wrap", gap: 10, marginBottom: 26 }}>
          {EXISTING.map(([n, sf]) => <Cell key={n} name={n} sf={sf} />)}
        </div>

        <GroupHeader title="Net-new for the app" count={NEW.length + " glyphs"}
          sub="Proposed — drawn here in the kit idiom" />
        <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
          {NEW.map(([n, sf, use]) => <Cell key={n} name={n} sf={sf} use={use} isNew />)}
        </div>
      </div>
    );
  }

  window.ODIconInventory = { Inventory };
})();
