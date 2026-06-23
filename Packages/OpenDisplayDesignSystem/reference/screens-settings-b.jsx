/* OpenDisplay screen-plan — settings window, part B:
   Scenes, Automation, Health & Recovery, Recovery OSD, Labs, Add Virtual Display.
   Exposes window.ODSettingsB. */
(function () {
  const DS = window.OpenDisplayDesignSystem_1a53d9;
  const K = window.ODKit;
  const I = window.ODIcons;
  const { Card, Row, Divider, Switch, Select, SegmentedControl, Button, Badge,
          Slider, InlineBanner, Checkbox } = DS;
  const h = React.createElement;

  const muted = { font: "var(--weight-regular) 13px/1 var(--font-text)", color: "var(--label-secondary)", fontVariantNumeric: "tabular-nums" };
  const kbd = { font: "var(--weight-medium) 11px/1 var(--font-mono)", background: "var(--fill-secondary)", borderRadius: 4, padding: "2px 6px", color: "var(--label-primary)" };

  function ListRow({ icon, tone, title, sub, trailing, last }) {
    return (
      <div style={{ display: "flex", alignItems: "center", gap: 11, padding: "9px 12px",
        borderBottom: last ? "none" : "0.5px solid var(--separator)" }}>
        {icon && <K.GlyphTile icon={icon} tone={tone} size={15} />}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ font: "var(--weight-medium) 13px/1.25 var(--font-text)", color: "var(--label-primary)" }}>{title}</div>
          {sub && <div style={{ font: "var(--weight-regular) 11.5px/1.3 var(--font-text)", color: "var(--label-secondary)" }}>{sub}</div>}
        </div>
        {trailing}
      </div>
    );
  }

  // ---------- Scenes: empty ----------
  function ScenesEmpty() {
    return (
      <K.Window title="Displays" active="scenes" header={<K.WinHeader title="Scenes" />}>
        <div style={{ height: "100%", display: "flex", flexDirection: "column", alignItems: "center",
          justifyContent: "center", textAlign: "center", gap: 14, paddingBottom: 30 }}>
          <div style={{ width: 60, height: 60, borderRadius: 16, display: "flex", alignItems: "center",
            justifyContent: "center", background: "var(--fill-tertiary)", color: "var(--label-tertiary)" }}>
            {h(I.scenes, { size: 30 })}</div>
          <div>
            <div style={{ font: "var(--weight-semibold) 16px/1.3 var(--font-text)", color: "var(--label-primary)" }}>No scenes yet</div>
            <div style={{ maxWidth: 320, font: "var(--weight-regular) 12.5px/1.5 var(--font-text)", color: "var(--label-secondary)", marginTop: 6 }}>
              A scene is a desired-state snapshot — arrangement, modes, and controls you can re-apply on demand or by trigger.
            </div>
          </div>
          <Button variant="accent" icon={h(I.plus, { size: 14 })}>Save Current State as Scene…</Button>
        </div>
      </K.Window>
    );
  }

  // ---------- Scenes: list ----------
  function ScenesList() {
    const scenes = [
      { name: "Work", sub: "3 displays · Studio main · 60 Hz", trig: "On dock", icon: I.monitorLines, applied: true },
      { name: "Movie", sub: "Studio only · HDR · others asleep", trig: "Hotkey ⌃⌥1", icon: I.bolt },
      { name: "Presentation", sub: "Mirror all · 1080p", trig: "Manual", icon: I.mirror },
      { name: "Travel", sub: "Built-in only · others disconnected", trig: "On undock", icon: I.disconnect },
    ];
    return (
      <K.Window title="Displays" active="scenes" height={600}
        header={<K.WinHeader title="Scenes" badge={<Button variant="secondary" size="sm" icon={h(I.plus, { size: 13 })}>New Scene</Button>} />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <Card padded={false}>
            {scenes.map((s, i) => (
              <ListRow key={s.name} icon={s.icon} tone={s.applied ? "accent" : "neutral"}
                title={s.name} sub={s.sub} last={i === scenes.length - 1}
                trailing={<div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                  {s.applied && <Badge tone="green">Applied</Badge>}
                  <Badge tone="neutral">{s.trig}</Badge>
                  <Button variant="secondary" size="sm">Apply</Button>
                </div>} />
            ))}
          </Card>
          <div style={{ font: "var(--weight-regular) 11.5px/1.4 var(--font-text)", color: "var(--label-tertiary)", padding: "0 4px" }}>
            Applying a scene shows a diff preview first. Triggers fire only after topology stabilizes and a safe surface exists.
          </div>
        </div>
      </K.Window>
    );
  }

  // ---------- Scene dry-run / diff preview ----------
  function SceneDryRun() {
    const Op = ({ icon, label, detail, status, last }) => {
      const map = { ok: ["var(--green)", "Will apply"], skip: ["var(--label-tertiary)", "Already satisfied"],
        warn: ["var(--orange)", "Hardware-dependent"], no: ["var(--red)", "Unsupported"], exp: ["var(--orange)", "Experimental"] };
      const [c, txt] = map[status];
      return (
        <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "8px 12px",
          borderBottom: last ? "none" : "0.5px solid var(--separator)" }}>
          <span style={{ color: "var(--label-secondary)" }}>{h(icon, { size: 15 })}</span>
          <div style={{ flex: 1 }}>
            <div style={{ font: "var(--weight-medium) 12.5px/1.2 var(--font-text)", color: "var(--label-primary)" }}>{label}</div>
            <div style={{ font: "var(--weight-regular) 11px/1.3 var(--font-text)", color: "var(--label-secondary)" }}>{detail}</div>
          </div>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 5, font: "var(--weight-medium) 11px/1 var(--font-text)", color: c }}>
            <span style={{ width: 6, height: 6, borderRadius: 99, background: c }} />{txt}</span>
        </div>
      );
    };
    return (
      <K.Window title="Displays" active="scenes" height={640}
        header={<K.WinHeader title="Apply “Work”" badge={<Badge tone="neutral">Dry run</Badge>} />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div style={{ font: "var(--weight-regular) 12px/1.45 var(--font-text)", color: "var(--label-secondary)", padding: "0 2px" }}>
            Comparing the current state with the scene. Satisfied steps are skipped; only the changes below will run, in order.
          </div>
          <Card title="Topology" padded={false}>
            <Op icon={I.reconnect} label="Reconnect LG UltraFine 4K" detail="Managed offline → active, right of main" status="ok" />
            <Op icon={I.monitorLines} label="Set Studio Display as main" detail="Already the main display" status="skip" />
            <Op icon={I.arrows} label="Place Built-in left of Studio" detail="Layout change" status="ok" last />
          </Card>
          <Card title="Modes & controls" padded={false}>
            <Op icon={I.monitor} label="Studio → 2056 × 1329 · 60 Hz" detail="Matches scene" status="skip" />
            <Op icon={I.sunMax} label="Brightness Studio → 78%" detail="DDC verified" status="ok" />
            <Op icon={I.bolt} label="HDR on LG UltraFine 4K" detail="Panel reports no HDR support" status="no" last />
          </Card>
          <div style={{ display: "flex", gap: 8, alignItems: "center", paddingTop: 2 }}>
            <span style={{ font: "var(--weight-regular) 11.5px/1.3 var(--font-text)", color: "var(--label-secondary)", flex: 1 }}>
              1 step can’t be applied and will be reported, not silently skipped.</span>
            <Button variant="secondary">Cancel</Button>
            <Button variant="accent">Apply Scene</Button>
          </div>
        </div>
      </K.Window>
    );
  }

  // ---------- Automation ----------
  function Automation() {
    return (
      <K.Window title="Displays" active="automation" height={680}
        header={<K.WinHeader title="Automation" />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <Card title="Global shortcuts" footnote="Reconnect All works even when the app window is closed and during a transaction.">
            <Row label="Reconnect All" secondary="Emergency recovery — preempts queued work"><kbd style={kbd}>⌃⌥⌘R</kbd></Row>
            <Divider />
            <Row label="Apply last scene"><kbd style={kbd}>⌃⌥⌘S</kbd></Row>
            <Divider />
            <Row label="Black Out main display"><span style={muted}>Not set</span></Row>
          </Card>
          <Card title="Shortcuts & App Intents">
            <Row label="Allow Shortcuts automation" secondary="Run scenes from the Shortcuts app and Focus filters"><Switch checked onChange={() => {}} /></Row>
            <Divider />
            <Row label="Available intents"><span style={muted}>Apply Scene · Reconnect All · Set Brightness</span></Row>
          </Card>
          <Card title="Command line" padded>
            <div style={{ font: "var(--weight-regular) 11.5px/1.7 var(--font-mono)", color: "var(--label-primary)",
              background: "var(--fill-quaternary)", borderRadius: 8, padding: "10px 12px" }}>
              <div><span style={{ color: "var(--label-tertiary)" }}>$ </span>opendisplay scene apply Work</div>
              <div><span style={{ color: "var(--label-tertiary)" }}>$ </span>opendisplay reconnect --all</div>
              <div><span style={{ color: "var(--label-tertiary)" }}>$ </span>opendisplay list --json</div>
            </div>
          </Card>
          <Card title="Local API" footnote="Off by default. Local control endpoints only; tokens are stored in Keychain.">
            <Row label="Local HTTP API" secondary="Deferred to 1.x — preview"><Badge tone="neutral">Disabled</Badge></Row>
            <Divider />
            <Row label="Access tokens"><span style={muted}>None issued</span></Row>
            <Divider />
            <Row label="Audit log" secondary="Every command records actor, trigger, and result"><Button variant="plain" size="sm">View Log…</Button></Row>
          </Card>
        </div>
      </K.Window>
    );
  }

  // ---------- Health & Recovery ----------
  function Health() {
    return (
      <K.Window title="Displays" active="health" height={700}
        header={<K.WinHeader title="Health & Recovery" badge={<Badge tone="orange">1 issue</Badge>} />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div style={{ display: "flex", gap: 8 }}>
            <Button variant="accent" icon={h(I.reconnectAll, { size: 14 })}>Reconnect All</Button>
            <Button variant="secondary" icon={h(I.shield, { size: 13 })}>Restart in Safe Mode…</Button>
          </div>
          <Card title="Pending transaction" padded={false}>
            <ListRow icon={I.check} tone="neutral" title="Idle — no transaction in progress"
              sub="Last: Disconnect LG UltraFine 4K · committed · 14:21" last
              trailing={<Badge tone="green">Healthy</Badge>} />
          </Card>
          <Card title="Managed offline" padded={false}>
            <ListRow icon={I.disconnect} tone="orange" title="LG UltraFine 4K"
              sub="By you · 4m ago · checkpoint saved" last
              trailing={<Button variant="secondary" size="sm" icon={h(I.reconnect, { size: 13 })}>Reconnect</Button>} />
          </Card>
          <Card title="Provider health" padded={false}>
            <ListRow icon={I.monitor} tone="neutral" title="CoreGraphics" sub="Public API · enumeration & layout"
              trailing={<Badge tone="green">OK</Badge>} />
            <ListRow icon={I.cable} tone="orange" title="DDC / VCP" sub="Route over CalDigit dock degraded — 3 failures"
              trailing={<Badge tone="orange">Degraded</Badge>} />
            <ListRow icon={I.bolt} tone="neutral" title="Lifecycle (experimental)" sub="Logical disconnect provider · probed OK"
              trailing={<Badge tone="green">OK</Badge>} last />
          </Card>
          <Card title="Recover">
            <Row label="Restore last checkpoint" secondary="Re-apply the last known-safe topology"><Button variant="secondary" size="sm">Restore…</Button></Row>
            <Divider />
            <Row label="Reset lifecycle policies" secondary="Clear persistent disconnect & provider cache"><Button variant="plain" size="sm">Reset…</Button></Row>
            <Divider />
            <Row label="Diagnostics bundle" secondary="Redacted logs & topology timeline — no serials or tokens"><Button variant="secondary" size="sm" icon={h(I.bundle, { size: 13 })}>Create…</Button></Row>
          </Card>
        </div>
      </K.Window>
    );
  }

  // ---------- Recovery OSD (full-screen emergency) ----------
  function RecoveryOSD() {
    const Target = ({ name, state }) => (
      <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "8px 0" }}>
        <span style={{ color: "rgba(255,255,255,0.7)" }}>{h(I.monitor, { size: 16 })}</span>
        <span style={{ flex: 1, font: "var(--weight-regular) 13px/1 var(--font-text)", color: "#fff" }}>{name}</span>
        {state === "done"
          ? <span style={{ display: "inline-flex", alignItems: "center", gap: 5, color: "#5fe08a", font: "var(--weight-medium) 12px/1 var(--font-text)" }}>{h(I.check, { size: 15 })} Restored</span>
          : <span className="od-spin" style={{ color: "#fff" }}>{h(I.reconnect, { size: 15 })}</span>}
      </div>
    );
    return (
      <div style={{ width: "100%", height: "100%", display: "flex", alignItems: "center", justifyContent: "center",
        background: "radial-gradient(120% 120% at 50% 30%, #20242c 0%, #0c0e12 70%)", fontFamily: "var(--font-text)" }}>
        <div className="theme-dark" style={{ width: 460, padding: "30px 30px 26px", borderRadius: 18,
          background: "rgba(28,30,36,0.92)", boxShadow: "0 30px 80px rgba(0,0,0,0.55)",
          border: "0.5px solid rgba(255,255,255,0.12)", display: "flex", flexDirection: "column", gap: 16 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 13 }}>
            <div style={{ width: 46, height: 46, borderRadius: 12, flex: "none", display: "flex", alignItems: "center",
              justifyContent: "center", background: "rgba(255,69,58,0.18)", color: "#ff6b61" }}>
              {h(I.shield, { size: 24 })}</div>
            <div>
              <div style={{ font: "var(--weight-semibold) 17px/1.2 var(--font-display)", color: "#fff" }}>Recovering your displays</div>
              <div style={{ font: "var(--weight-regular) 12.5px/1.4 var(--font-text)", color: "rgba(255,255,255,0.6)" }}>
                A safe display disappeared during a change. Rolling back to the last checkpoint.</div>
            </div>
          </div>
          <div style={{ borderTop: "0.5px solid rgba(255,255,255,0.1)", borderBottom: "0.5px solid rgba(255,255,255,0.1)", padding: "4px 0" }}>
            <Target name="Built-in Retina" state="done" />
            <Target name="Studio Display" state="busy" />
            <Target name="LG UltraFine 4K" state="busy" />
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 9, font: "var(--weight-regular) 12px/1.4 var(--font-text)", color: "rgba(255,255,255,0.7)" }}>
            {h(I.keyboard, { size: 16 })}
            <span>This runs independently of the app. Press <kbd style={{ ...kbd, background: "rgba(255,255,255,0.16)", color: "#fff" }}>⌃⌥⌘R</kbd> to force-reconnect everything now.</span>
          </div>
          <Button variant="secondary" size="lg" style={{ alignSelf: "flex-start" }}>Cancel & Keep Current</Button>
        </div>
      </div>
    );
  }

  // ---------- Labs ----------
  function Labs() {
    return (
      <K.Window title="Displays" active="labs" height={680}
        header={<K.WinHeader title="Labs" badge={<Badge tone="orange">Experimental</Badge>} />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <InlineBanner tone="orange" icon={h(I.warning, { size: 18 })}
            title="Experimental features can destabilize your displays"
            message="These modules use undocumented behavior and are excluded from the public-API build. Each is independently kill-switchable and disabled in Safe Mode." />
          <Card title="Acknowledgement" padded>
            <label style={{ display: "flex", gap: 10, alignItems: "flex-start", cursor: "pointer" }}>
              <Checkbox checked onChange={() => {}} />
              <span style={{ font: "var(--weight-regular) 12.5px/1.45 var(--font-text)", color: "var(--label-primary)" }}>
                I understand recovery may require the rescue utility or a Safe Mode restart, and I know the Reconnect All shortcut.</span>
            </label>
          </Card>
          <Card title="Experimental providers" padded={false}>
            <ListRow icon={I.display2} tone="orange" title="Virtual displays" sub="Create headless / Sidecar-target endpoints"
              trailing={<div style={{ display: "flex", gap: 8, alignItems: "center" }}><Switch checked onChange={() => {}} /></div>} />
            <ListRow icon={I.monitor} tone="orange" title="Custom HiDPI & resolutions" sub="Unlock non-default modes and scaling"
              trailing={<Switch checked={false} onChange={() => {}} />} />
            <ListRow icon={I.bolt} tone="orange" title="Aggressive disconnect policy" sub="Re-apply persistent disconnect more eagerly"
              trailing={<Switch checked={false} onChange={() => {}} />} last />
          </Card>
          <Card title="Safety">
            <Row label="Global kill switch" secondary="Disable all Labs providers immediately"><Button variant="secondary" size="sm" destructive icon={h(I.killSwitch, { size: 13 })}>Disable All</Button></Row>
            <Divider />
            <Row label="Compatibility" secondary="macOS 14.5 · Apple silicon · validated for these modules"><Badge tone="green">Probed OK</Badge></Row>
          </Card>
        </div>
      </K.Window>
    );
  }

  // ---------- Add Virtual Display ----------
  function AddVirtual() {
    return (
      <K.Window title="Displays" active="virtual" height={600}
        header={<K.WinHeader title="Add Virtual Display" badge={<Badge tone="orange">Labs</Badge>} />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <Card title="Virtual display" footnote="A software display with no physical panel — useful for headless Macs, capture, or a Sidecar target.">
            <Row label="Name"><span style={muted}>Virtual 4K</span></Row>
            <Divider />
            <Row label="Resolution"><Select value="3840 × 2160" onChange={() => {}}
              options={["1920 × 1080", "2560 × 1440", "3840 × 2160", "5120 × 2880"]} /></Row>
            <Divider />
            <Row label="HiDPI" secondary="Render at 2× for crisp text"><Switch checked onChange={() => {}} /></Row>
            <Divider />
            <Row label="Refresh Rate"><Select value="60 Hz" onChange={() => {}} options={["30 Hz", "60 Hz"]} /></Row>
          </Card>
          <Card title="Use for">
            <Row label="Purpose">
              <SegmentedControl value="headless" onChange={() => {}}
                options={[{ value: "headless", label: "Headless" }, { value: "sidecar", label: "Sidecar" }, { value: "capture", label: "Capture" }]} /></Row>
          </Card>
          <div style={{ display: "flex", gap: 8, paddingTop: 2 }}>
            <div style={{ flex: 1 }} />
            <Button variant="secondary">Cancel</Button>
            <Button variant="accent" icon={h(I.plus, { size: 13 })}>Create Display</Button>
          </div>
        </div>
      </K.Window>
    );
  }

  window.ODSettingsB = {
    ScenesEmpty, ScenesList, SceneDryRun, Automation, Health, RecoveryOSD, Labs, AddVirtual,
  };
})();
