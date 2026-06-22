/* OpenDisplay screen-plan — menu-bar popover states. Exposes window.ODMenubar. */
(function () {
  const DS = window.OpenDisplayDesignSystem_1a53d9;
  const K = window.ODKit;
  const I = window.ODIcons;
  const { Badge, Button, SegmentedControl, InlineBanner } = DS;
  const h = React.createElement;

  // gradient backdrop + menu bar + anchored popover
  function MBFrame({ children, w }) {
    return (
      <K.Desktop>
        <K.MenuBar active />
        <div style={{ position: "absolute", top: 32, right: 20, width: w || 320 }}>{children}</div>
      </K.Desktop>
    );
  }

  function HealthBadge({ tone, label }) {
    const c = tone === "orange" ? "var(--orange)" : tone === "red" ? "var(--red)" : "var(--green)";
    return (
      <span style={{ display: "inline-flex", alignItems: "center", gap: 5, height: 22, padding: "0 8px",
        borderRadius: 6, background: "var(--fill-tertiary)", color: "var(--label-secondary)",
        font: "var(--weight-medium) 11px/1 var(--font-text)" }}>
        <span style={{ width: 7, height: 7, borderRadius: 99, background: c }} />{label}
      </span>
    );
  }

  function PresetFooter({ preset }) {
    return (
      <>
        <K.HairDivider />
        <K.SectionLabel>Preset</K.SectionLabel>
        <div style={{ padding: "0 6px 8px" }}>
          <SegmentedControl value={preset || "work"} onChange={() => {}} size="md"
            style={{ width: "100%", display: "flex" }}
            options={[{ value: "work", label: "Work" }, { value: "movie", label: "Movie" }, { value: "present", label: "Present" }]} />
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "2px 6px 4px" }}>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 6, height: 26, padding: "0 10px",
            borderRadius: 7, background: "var(--fill-tertiary)", color: "var(--label-primary)",
            font: "var(--weight-medium) 12px/1 var(--font-text)" }}>{h(I.mirror, { size: 14 })} Mirror</span>
          <div style={{ flex: 1 }} />
          <Button variant="plain">Display Settings…</Button>
        </div>
      </>
    );
  }

  const D = {
    studio: { id: "studio", name: "Studio Display", res: "2056 × 1329", hz: 60, brightness: 78, volume: 40, audio: true, hdr: true, trueTone: true, main: true },
    builtin: { id: "builtin", name: "Built-in Retina", res: "1800 × 1169", hz: 120, brightness: 64, volume: 55, audio: true, hdr: true, trueTone: true },
    lg: { id: "lg", name: "LG UltraFine 4K", res: "2560 × 1440", hz: 60, brightness: 50, volume: 0, audio: false },
  };

  // 1 — canonical, Studio expanded
  function Default() {
    return (
      <MBFrame>
        <K.Popover connectedLabel="3 connected">
          <K.SectionLabel>Displays</K.SectionLabel>
          <K.MBDisplay d={D.studio} expanded />
          <K.MBDisplay d={D.builtin} />
          <K.MBDisplay d={D.lg} />
          <PresetFooter />
        </K.Popover>
      </MBFrame>
    );
  }

  // 2 — all collapsed
  function Collapsed() {
    return (
      <MBFrame>
        <K.Popover connectedLabel="3 connected">
          <K.SectionLabel>Displays</K.SectionLabel>
          <K.MBDisplay d={D.studio} />
          <K.MBDisplay d={D.builtin} />
          <K.MBDisplay d={D.lg} />
          <PresetFooter />
        </K.Popover>
      </MBFrame>
    );
  }

  // 3 — built-in only (no external displays)
  function BuiltinOnly() {
    return (
      <MBFrame>
        <K.Popover connectedLabel="1 connected">
          <K.SectionLabel>Displays</K.SectionLabel>
          <K.MBDisplay d={{ ...D.builtin, main: true }} expanded />
          <div style={{ padding: "10px 8px 4px", display: "flex", gap: 9, alignItems: "flex-start" }}>
            <span style={{ color: "var(--label-tertiary)", marginTop: 1 }}>{h(I.info, { size: 15 })}</span>
            <div style={{ font: "var(--weight-regular) 11px/1.4 var(--font-text)", color: "var(--label-secondary)" }}>
              No external displays connected. Plug in a display or add a virtual one to manage more here.
            </div>
          </div>
          <PresetFooter />
        </K.Popover>
      </MBFrame>
    );
  }

  // 4 — scanning / loading
  function Scanning() {
    const Skeleton = () => (
      <div style={{ display: "flex", alignItems: "center", gap: 9, padding: "7px 8px" }}>
        <div style={{ width: 28, height: 28, borderRadius: 7, background: "var(--fill-tertiary)" }} />
        <div style={{ flex: 1 }}>
          <div style={{ height: 9, width: "55%", borderRadius: 4, background: "var(--fill-tertiary)", marginBottom: 6 }} />
          <div style={{ height: 7, width: "38%", borderRadius: 4, background: "var(--fill-quaternary)" }} />
        </div>
      </div>
    );
    return (
      <MBFrame>
        <K.Popover connectedLabel={<span style={{ display: "inline-flex", alignItems: "center", gap: 5 }}>
          <span className="od-spin" style={{ display: "inline-flex", color: "var(--label-tertiary)" }}>{h(I.scan, { size: 12 })}</span>
          Scanning…</span>}>
          <K.SectionLabel>Displays</K.SectionLabel>
          <Skeleton /><Skeleton /><Skeleton />
          <div style={{ padding: "6px 8px 2px", font: "var(--weight-regular) 11px/1.4 var(--font-text)", color: "var(--label-tertiary)" }}>
            Looking for displays and connection routes. Slow DDC probes continue in the background.
          </div>
        </K.Popover>
      </MBFrame>
    );
  }

  // 5 — managed-offline present + Reconnect All
  function ManagedOffline() {
    return (
      <MBFrame>
        <K.Popover connectedLabel="2 connected · 1 managed offline"
          health={<HealthBadge tone="green" label="Healthy" />}>
          <div style={{ padding: "0 2px 6px" }}>
            <Button variant="accent" size="md" icon={h(I.reconnectAll, { size: 14 })}
              style={{ width: "100%", justifyContent: "center" }}>Reconnect All</Button>
          </div>
          <K.SectionLabel>Displays</K.SectionLabel>
          <K.MBDisplay d={{ ...D.studio, main: true }} />
          <K.MBDisplay d={D.builtin} />
          <K.MBDisplay d={{ ...D.lg, state: "offline", actor: "you", ago: "2m ago" }} />
          <PresetFooter />
        </K.Popover>
      </MBFrame>
    );
  }

  // 6 — reconnecting in progress
  function Reconnecting() {
    return (
      <MBFrame>
        <K.Popover connectedLabel="2 connected · reconnecting 1">
          <K.SectionLabel>Displays</K.SectionLabel>
          <K.MBDisplay d={{ ...D.studio, main: true }} />
          <K.MBDisplay d={D.builtin} />
          <K.MBDisplay d={{ ...D.lg, state: "reconnecting" }} />
          <div style={{ padding: "2px 8px 6px" }}>
            <div style={{ height: 4, borderRadius: 99, background: "var(--fill-tertiary)", overflow: "hidden" }}>
              <div style={{ width: "62%", height: "100%", borderRadius: 99, background: "var(--accent)" }} />
            </div>
          </div>
          <PresetFooter />
        </K.Popover>
      </MBFrame>
    );
  }

  // 7 — disconnect countdown confirmation (inline)
  function DisconnectCountdown() {
    return (
      <MBFrame>
        <K.Popover connectedLabel="3 connected">
          <div style={{ padding: 4 }}>
            <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 10,
              padding: "16px 14px 14px", background: "var(--card-bg)", borderRadius: 10,
              boxShadow: "var(--shadow-card)" }}>
              <div style={{ width: 46, height: 46, borderRadius: 99, display: "flex", alignItems: "center",
                justifyContent: "center", background: "rgba(255,149,0,0.16)", color: "var(--orange)" }}>
                {h(I.countdown, { size: 24 })}</div>
              <div style={{ textAlign: "center" }}>
                <div style={{ font: "var(--weight-semibold) 14px/1.3 var(--font-text)", color: "var(--label-primary)" }}>
                  Disconnect LG UltraFine 4K?</div>
                <div style={{ font: "var(--weight-regular) 12px/1.45 var(--font-text)", color: "var(--label-secondary)", marginTop: 4 }}>
                  Reverting automatically in <b style={{ color: "var(--label-primary)", fontVariantNumeric: "tabular-nums" }}>9s</b>.
                  Two displays stay active. Press <Kbd>⌃⌥⌘R</Kbd> any time to reconnect all.</div>
              </div>
              <div style={{ display: "flex", gap: 8, width: "100%" }}>
                <Button variant="secondary" size="md" style={{ flex: 1, justifyContent: "center" }}>Cancel</Button>
                <Button variant="accent" size="md" destructive style={{ flex: 1, justifyContent: "center" }}>Disconnect Now</Button>
              </div>
            </div>
          </div>
        </K.Popover>
      </MBFrame>
    );
  }

  function Kbd({ children }) {
    return <kbd style={{ font: "var(--weight-medium) 11px/1 var(--font-mono)", background: "var(--fill-secondary)",
      borderRadius: 4, padding: "2px 5px", color: "var(--label-primary)" }}>{children}</kbd>;
  }

  // 8 — Black Out active
  function BlackOut() {
    return (
      <MBFrame>
        <K.Popover connectedLabel="3 connected">
          <div style={{ padding: "0 2px 6px" }}>
            <InlineBanner tone="neutral" icon={h(I.blackout, { size: 18 })}
              title="Black Out is active on Studio Display"
              message="The panel stays powered and in the layout. Windows are unaffected."
              actions={<Button variant="secondary" size="sm">Turn Off</Button>} />
          </div>
          <K.SectionLabel>Displays</K.SectionLabel>
          <K.MBDisplay d={{ ...D.studio, state: "blackout", main: true }} />
          <K.MBDisplay d={D.builtin} expanded />
          <K.MBDisplay d={D.lg} />
        </K.Popover>
      </MBFrame>
    );
  }

  // 9 — provider health degraded
  function Degraded() {
    return (
      <MBFrame>
        <K.Popover connectedLabel="3 connected" health={<HealthBadge tone="orange" label="Degraded" />}>
          <div style={{ padding: "0 2px 6px" }}>
            <InlineBanner tone="orange" icon={h(I.warning, { size: 18 })}
              title="DDC route degraded on LG UltraFine 4K"
              message="Brightness fell back to software. Check the cable or dock, then retry hardware control."
              actions={<><Button variant="secondary" size="sm">Retry</Button><Button variant="plain" size="sm">Diagnostics…</Button></>} />
          </div>
          <K.SectionLabel>Displays</K.SectionLabel>
          <K.MBDisplay d={{ ...D.studio, main: true }} />
          <K.MBDisplay d={D.builtin} />
          <K.MBDisplay d={{ ...D.lg, state: "degraded" }} />
          <PresetFooter />
        </K.Popover>
      </MBFrame>
    );
  }

  // 10 — Reconnect All in progress
  function ReconnectAll() {
    const Target = ({ name, state }) => (
      <div style={{ display: "flex", alignItems: "center", gap: 9, padding: "6px 8px" }}>
        <span style={{ color: "var(--label-secondary)" }}>{h(I.monitor, { size: 15 })}</span>
        <span style={{ flex: 1, font: "var(--weight-regular) 12px/1 var(--font-text)", color: "var(--label-primary)" }}>{name}</span>
        {state === "done" ? <span style={{ color: "var(--green)" }}>{h(I.check, { size: 15 })}</span>
          : state === "busy" ? <span className="od-spin" style={{ color: "var(--accent)" }}>{h(I.reconnect, { size: 14 })}</span>
          : <span style={{ font: "var(--weight-regular) 11px/1 var(--font-text)", color: "var(--label-tertiary)" }}>Queued</span>}
      </div>
    );
    return (
      <MBFrame>
        <K.Popover connectedLabel="Reconnecting all displays…" health={<HealthBadge tone="green" label="Recovery" />}>
          <div style={{ padding: "4px 8px 6px", font: "var(--weight-regular) 11px/1.4 var(--font-text)", color: "var(--label-secondary)" }}>
            Reconnect All preempts queued work. Each endpoint is restored independently — <b style={{ color: "var(--label-primary)" }}>2 of 3 complete</b>.
          </div>
          <div style={{ background: "var(--card-bg)", borderRadius: 9, boxShadow: "var(--shadow-card)", padding: "2px 0", margin: "0 2px" }}>
            <Target name="Built-in Retina" state="done" />
            <Target name="Studio Display" state="done" />
            <Target name="LG UltraFine 4K" state="busy" />
          </div>
          <div style={{ padding: "8px 2px 2px" }}>
            <div style={{ height: 4, borderRadius: 99, background: "var(--fill-tertiary)", overflow: "hidden" }}>
              <div style={{ width: "66%", height: "100%", borderRadius: 99, background: "var(--accent)" }} />
            </div>
          </div>
        </K.Popover>
      </MBFrame>
    );
  }

  // 11 — identity ambiguous (identical panels)
  function Ambiguous() {
    return (
      <MBFrame>
        <K.Popover connectedLabel="3 connected" health={<HealthBadge tone="orange" label="Check" />}>
          <div style={{ padding: "0 2px 6px" }}>
            <InlineBanner tone="orange" icon={h(I.ambiguous, { size: 18 })}
              title="Two identical displays detected"
              message="Confirm which Dell U2720Q is which before any disconnect. Use Identify to flash a number on each."
              actions={<Button variant="secondary" size="sm" icon={h(I.identify, { size: 13 })}>Identify</Button>} />
          </div>
          <K.SectionLabel>Displays</K.SectionLabel>
          <K.MBDisplay d={{ ...D.studio, name: "Built-in Retina", main: true, hz: 120 }} />
          <K.MBDisplay d={{ id: "d1", name: "Dell U2720Q", res: "2560 × 1440", hz: 60, state: "ambiguous" }} />
          <K.MBDisplay d={{ id: "d2", name: "Dell U2720Q", res: "2560 × 1440", hz: 60, state: "ambiguous" }} />
        </K.Popover>
      </MBFrame>
    );
  }

  window.ODMenubar = {
    Default, Collapsed, BuiltinOnly, Scanning, ManagedOffline, Reconnecting,
    DisconnectCountdown, BlackOut, Degraded, ReconnectAll, Ambiguous,
  };
})();
