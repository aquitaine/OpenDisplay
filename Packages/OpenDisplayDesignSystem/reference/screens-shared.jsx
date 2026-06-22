/* OpenDisplay screen-plan — shared shells & helpers.
   Pulls DS primitives + glyphs from window; exposes window.ODKit. */
(function () {
  const DS = window.OpenDisplayDesignSystem_1a53d9;
  const I = window.ODIcons;
  const { Badge } = DS;
  const h = React.createElement;

  /* ---------- macOS desktop backdrop (for chrome that floats) ---------- */
  function Desktop({ children, style }) {
    return (
      <div style={{
        position: "relative", width: "100%", height: "100%", overflow: "hidden",
        background:
          "radial-gradient(120% 90% at 18% 0%, #6a8fd6 0%, transparent 55%)," +
          "radial-gradient(120% 100% at 100% 30%, #b98ec9 0%, transparent 50%)," +
          "linear-gradient(160deg,#2f5aa8 0%,#5566b8 45%,#8a6fc0 100%)",
        ...style,
      }}>{children}</div>
    );
  }

  /* ---------- translucent menu bar with the OpenDisplay glyph lit ---------- */
  function MenuBar({ active }) {
    const item = { opacity: 0.95 };
    return (
      <div style={{
        position: "absolute", top: 0, left: 0, right: 0, height: 25,
        background: "rgba(255,255,255,0.18)",
        WebkitBackdropFilter: "saturate(180%) blur(24px)", backdropFilter: "saturate(180%) blur(24px)",
        display: "flex", alignItems: "center", gap: 16, padding: "0 12px",
        fontSize: 13, color: "#fff", zIndex: 5, boxShadow: "inset 0 -0.5px 0 rgba(0,0,0,0.12)",
      }}>
        <span style={{ fontWeight: 600 }}></span>
        <span style={{ fontWeight: 600 }}>File</span>
        <span style={item}>Edit</span><span style={item}>View</span><span style={item}>Window</span>
        <div style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: 14 }}>
          <span style={{
            display: "flex", alignItems: "center", justifyContent: "center", color: "#fff",
            padding: "2px 4px", borderRadius: 5,
            background: active ? "rgba(255,255,255,0.26)" : "transparent",
          }}>{h(I.monitor, { size: 15 })}</span>
          <span style={{ fontVariantNumeric: "tabular-nums" }}>Sat 9:41 AM</span>
        </div>
      </div>
    );
  }

  /* ---------- popover frame (320px, blurred panel) ---------- */
  function Popover({ children, connectedLabel, health }) {
    return (
      <div style={{
        width: 320, background: "var(--panel-bg)",
        WebkitBackdropFilter: "var(--blur-thick)", backdropFilter: "var(--blur-thick)",
        borderRadius: "var(--radius-xl)", boxShadow: "var(--shadow-popover)",
        padding: 8, fontFamily: "var(--font-text)", boxSizing: "border-box",
      }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "4px 6px 8px" }}>
          <img src="ds/opendisplay-icon.svg" width={22} height={22} alt="" />
          <div style={{ flex: 1 }}>
            <div style={{ font: "var(--weight-semibold) 14px/1 var(--font-text)", color: "var(--label-primary)" }}>Displays</div>
            <div style={{ font: "var(--weight-regular) 11px/1.3 var(--font-text)", color: "var(--label-secondary)" }}>{connectedLabel}</div>
          </div>
          {health}
          <DS.IconButton label="Add virtual display">{h(I.plus, { size: 16 })}</DS.IconButton>
          <DS.IconButton label="Settings">{h(I.gear, { size: 16 })}</DS.IconButton>
        </div>
        {children}
      </div>
    );
  }

  const SECTION = {
    font: "var(--weight-semibold) 11px/1 var(--font-text)", letterSpacing: "0.03em",
    textTransform: "uppercase", color: "var(--label-tertiary)", padding: "2px 8px 6px",
  };
  function SectionLabel({ children, trailing }) {
    return (
      <div style={{ ...SECTION, display: "flex", alignItems: "center" }}>
        <span style={{ flex: 1 }}>{children}</span>{trailing}
      </div>
    );
  }
  function HairDivider() {
    return <div style={{ height: 0.5, background: "var(--separator)", margin: "8px 6px" }} />;
  }

  function GlyphTile({ icon, tone, size }) {
    const bg = tone === "accent" ? "var(--accent)" : tone === "red" ? "rgba(255,59,48,0.14)"
      : tone === "orange" ? "rgba(255,149,0,0.16)" : "var(--fill-secondary)";
    const fg = tone === "accent" ? "var(--accent-fg)" : tone === "red" ? "var(--red)"
      : tone === "orange" ? "var(--orange)" : "var(--label-secondary)";
    return (
      <div style={{
        width: 28, height: 28, flex: "none", borderRadius: 7, display: "flex",
        alignItems: "center", justifyContent: "center", background: bg, color: fg,
      }}>{h(icon, { size: size || 17 })}</div>
    );
  }

  function Dot({ color }) {
    return <span style={{ width: 7, height: 7, borderRadius: 99, background: color, flex: "none" }} />;
  }

  function MBChip({ children, on, tone }) {
    const bg = on ? "var(--accent-tint)" : tone === "warn" ? "rgba(255,149,0,0.14)" : "var(--fill-tertiary)";
    const fg = on ? "var(--accent)" : tone === "warn" ? "var(--orange)" : "var(--label-secondary)";
    return (
      <span style={{
        display: "inline-flex", alignItems: "center", gap: 4, height: 22, padding: "0 8px",
        borderRadius: 6, font: "var(--weight-medium) 11px/1 var(--font-text)", background: bg, color: fg,
      }}>{children}</span>
    );
  }

  function MBSliderRow({ icon, hi, value, sub, disabled }) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 9, padding: "5px 8px", opacity: disabled ? 0.4 : 1 }}>
        <span style={{ color: "var(--label-secondary)", flex: "none" }}>{h(icon, { size: 15 })}</span>
        <div style={{ flex: 1 }}>
          <DS.Slider value={value} onChange={() => {}}
            trailing={hi ? <span style={{ color: "var(--label-tertiary)" }}>{h(hi, { size: 15 })}</span> : null} />
        </div>
        <span style={{ width: 30, textAlign: "right", flex: "none",
          font: "var(--weight-regular) 11px/1 var(--font-text)", color: "var(--label-secondary)",
          fontVariantNumeric: "tabular-nums" }}>{sub}</span>
      </div>
    );
  }

  /* ---------- menu-bar display block (covers every reachability state) ---------- */
  function MBDisplay({ d, expanded }) {
    const st = d.state || "active";
    const trailing =
      st === "offline" ? <Badge tone="neutral">Offline</Badge>
      : st === "reconnecting" ? <Badge tone="accent">Reconnecting…</Badge>
      : st === "blackout" ? <Badge tone="neutral">Blacked Out</Badge>
      : st === "asleep" ? <Badge tone="neutral">Asleep</Badge>
      : st === "degraded" ? <Badge tone="orange">Degraded</Badge>
      : st === "ambiguous" ? <Badge tone="orange">Ambiguous</Badge>
      : d.main ? <Badge tone="accent" solid>Main</Badge>
      : d.mirrored ? <Badge tone="neutral">Mirrored</Badge>
      : <Dot color="var(--green)" />;
    const tileIcon = st === "offline" ? I.disconnect : st === "blackout" ? I.blackout
      : st === "asleep" ? I.moon : d.main ? I.monitorLines : I.monitor;
    const tileTone = st === "offline" ? "neutral" : st === "degraded" || st === "ambiguous" ? "orange"
      : d.main ? "accent" : "neutral";
    const sub = st === "offline" ? "Managed offline · " + (d.actor || "you") + " · " + (d.ago || "2m ago")
      : st === "reconnecting" ? "Requesting back into topology…"
      : st === "ambiguous" ? "Identity unconfirmed — 2 identical panels"
      : d.res + " · " + d.hz + " Hz";
    return (
      <div style={{
        borderRadius: 9, background: expanded ? "var(--card-bg)" : "transparent",
        boxShadow: expanded ? "var(--shadow-card)" : "none", marginBottom: 2,
      }}>
        <div style={{ width: "100%", display: "flex", alignItems: "center", gap: 9, padding: "7px 8px", borderRadius: 9 }}>
          <GlyphTile icon={tileIcon} tone={tileTone} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ font: "var(--weight-semibold) 13px/1.25 var(--font-text)", color: "var(--label-primary)",
              whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{d.name}</div>
            <div style={{ font: "var(--weight-regular) 11px/1.3 var(--font-text)",
              color: st === "ambiguous" ? "var(--orange)" : "var(--label-secondary)" }}>{sub}</div>
          </div>
          {trailing}
          {st !== "offline" && st !== "reconnecting" &&
            <span style={{ color: "var(--label-tertiary)", display: "flex",
              transform: expanded ? "rotate(90deg)" : "none" }}>{h(I.chevronRight, { size: 15 })}</span>}
          {st === "offline" &&
            <DS.Button variant="plain" size="sm" icon={h(I.reconnect, { size: 13 })}>Reconnect</DS.Button>}
        </div>
        {expanded && st === "active" && (
          <div style={{ padding: "0 2px 8px" }}>
            <MBSliderRow icon={I.sunDim} hi={I.sunMax} value={d.brightness} sub={d.brightness + "%"} />
            {d.audio && <MBSliderRow icon={I.speaker} hi={I.speakerWave} value={d.volume} sub={d.volume + "%"} />}
            <div style={{ display: "flex", flexWrap: "wrap", gap: 6, padding: "6px 8px 8px" }}>
              <MBChip on={d.hdr}>{h(I.bolt, { size: 12 })} HDR</MBChip>
              <MBChip on={d.trueTone}>True Tone</MBChip>
              <MBChip>{d.res}</MBChip>
              <MBChip>{d.hz + " Hz"}</MBChip>
            </div>
            <div style={{ display: "flex", gap: 6, padding: "0 8px" }}>
              <QuickAction icon={I.blackout} label="Black Out" />
              <QuickAction icon={I.moon} label="Sleep" />
              <QuickAction icon={I.disconnect} label="Disconnect" tone="red" />
            </div>
          </div>
        )}
      </div>
    );
  }

  function QuickAction({ icon, label, tone }) {
    return (
      <span style={{
        flex: 1, display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 5,
        height: 26, borderRadius: 7, background: "var(--fill-tertiary)",
        color: tone === "red" ? "var(--red)" : "var(--label-primary)",
        font: "var(--weight-medium) 11px/1 var(--font-text)",
      }}>{h(icon, { size: 13 })}{label}</span>
    );
  }

  /* ---------- settings window shell ---------- */
  function WinTitleBar({ title }) {
    const dot = (c) => ({ width: 12, height: 12, borderRadius: 99, background: c });
    return (
      <div style={{ display: "flex", alignItems: "center", height: 38, padding: "0 14px", gap: 8,
        borderBottom: "0.5px solid var(--separator)", flex: "none" }}>
        <span style={dot("#ff5f57")} /><span style={dot("#febc2e")} /><span style={dot("#28c840")} />
        <span style={{ flex: 1, textAlign: "center", marginLeft: -52,
          font: "var(--weight-semibold) 13px/1 var(--font-text)", color: "var(--label-primary)" }}>{title}</span>
      </div>
    );
  }

  function SidebarItem({ icon, label, sub, active, badge, danger }) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 8, width: "100%",
        padding: "5px 8px", borderRadius: 7,
        background: active ? "var(--accent)" : "transparent",
        color: active ? "var(--accent-fg)" : danger ? "var(--red)" : "var(--label-primary)" }}>
        <span style={{ display: "flex", flex: "none", width: 22, height: 22, alignItems: "center",
          justifyContent: "center", borderRadius: 5,
          background: active ? "rgba(255,255,255,0.22)" : "var(--fill-tertiary)",
          color: active ? "var(--accent-fg)" : danger ? "var(--red)" : "var(--label-secondary)" }}>
          {h(icon, { size: 14 })}</span>
        <span style={{ flex: 1, minWidth: 0 }}>
          <span style={{ display: "block", font: "var(--weight-regular) 13px/1.2 var(--font-text)",
            whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{label}</span>
          {sub && <span style={{ display: "block", font: "var(--weight-regular) 11px/1.2 var(--font-text)",
            color: active ? "rgba(255,255,255,0.8)" : "var(--label-secondary)" }}>{sub}</span>}
        </span>
        {badge}
      </div>
    );
  }

  // Full Core-1.0 sidebar. `active` matches a nav id.
  function Sidebar({ active }) {
    const displays = [
      { id: "studio", name: "Studio Display", sub: "2056 × 1329", icon: I.monitor, main: true },
      { id: "builtin", name: "Built-in Retina", sub: "1800 × 1169", icon: I.monitorLines },
      { id: "lg", name: "LG UltraFine 4K", sub: "Managed offline", icon: I.disconnect, offline: true },
    ];
    return (
      <div style={{ width: 210, flex: "none", background: "var(--sidebar-bg)",
        borderRight: "0.5px solid var(--separator)", padding: 10, display: "flex",
        flexDirection: "column", gap: 2 }}>
        <div style={SECTION}>Connected</div>
        {displays.map((d) => (
          <SidebarItem key={d.id} icon={d.icon} label={d.name}
            sub={d.offline ? <span style={{ color: "var(--orange)" }}>{d.sub}</span> : d.sub}
            active={active === d.id}
            badge={d.main ? <Badge tone={active === d.id ? "neutral" : "accent"} solid={active !== d.id}>Main</Badge>
              : d.offline ? <Dot color="var(--orange)" /> : null} />
        ))}
        <div style={{ height: 0.5, background: "var(--separator)", margin: "8px 4px" }} />
        <SidebarItem icon={I.arrows} label="Arrange Displays" active={active === "arrange"} />
        <SidebarItem icon={I.scenes} label="Scenes" active={active === "scenes"} />
        <SidebarItem icon={I.keyboard} label="Automation" active={active === "automation"} />
        <SidebarItem icon={I.shield} label="Health & Recovery" active={active === "health"}
          badge={<Dot color="var(--orange)" />} />
        <SidebarItem icon={I.labs} label="Labs" active={active === "labs"} />
        <div style={{ flex: 1 }} />
        <SidebarItem icon={I.display2} label="Add Virtual Display" active={active === "virtual"} />
        <div style={{ display: "flex", alignItems: "center", gap: 7, padding: "6px 8px",
          color: "var(--label-secondary)", font: "var(--weight-regular) 11px/1.3 var(--font-text)" }}>
          {h(I.sparkles, { size: 13 })} OpenDisplay 1.0 · open source
        </div>
      </div>
    );
  }

  function Window({ title, active, header, children, contentBg, height }) {
    return (
      <div style={{ width: 760, height: height || 560, display: "flex", flexDirection: "column",
        background: "var(--content-bg)", borderRadius: "var(--radius-2xl)", overflow: "hidden",
        boxShadow: "var(--shadow-window)", fontFamily: "var(--font-text)" }}>
        <WinTitleBar title={title} />
        <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
          <Sidebar active={active} />
          <div style={{ flex: 1, minWidth: 0, overflow: "hidden", padding: "18px 22px",
            background: contentBg || "var(--window-bg)" }}>
            <div style={{ maxWidth: 480, margin: "0 auto", height: "100%", display: "flex", flexDirection: "column" }}>
              {header}
              <div style={{ flex: 1, minHeight: 0 }}>{children}</div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  function WinHeader({ title, badge }) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 14 }}>
        <h1 style={{ margin: 0, font: "var(--weight-bold) 22px/1.1 var(--font-display)",
          letterSpacing: "var(--tracking-tight)", color: "var(--label-primary)" }}>{title}</h1>
        <div style={{ flex: 1 }} />
        {badge}
      </div>
    );
  }

  window.ODKit = {
    Desktop, MenuBar, Popover, SectionLabel, HairDivider, GlyphTile, Dot,
    MBChip, MBSliderRow, MBDisplay, QuickAction,
    Window, WinHeader, Sidebar, SidebarItem,
  };
})();
