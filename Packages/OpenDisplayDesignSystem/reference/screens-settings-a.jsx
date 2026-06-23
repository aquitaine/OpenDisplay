/* OpenDisplay screen-plan — settings window, part A:
   per-display detail variants, Arrange canvas, disconnect sheet.
   Exposes window.ODSettingsA. */
(function () {
  const DS = window.OpenDisplayDesignSystem_1a53d9;
  const K = window.ODKit;
  const I = window.ODIcons;
  const { Card, Row, Divider, Switch, Select, SegmentedControl, Button, Badge,
          Slider, DisplayTile, InlineBanner } = DS;
  const h = React.createElement;

  const studio = { id: "studio", name: "Studio Display", res: "2056 × 1329", native: "5120 × 2880",
    hz: [60], rot: 0, main: true, hdr: true, trueTone: true, brightness: 78 };

  function ActionRow({ destructiveLabel, offline }) {
    return (
      <div style={{ display: "flex", gap: 8, paddingTop: 2 }}>
        {offline
          ? <Button variant="accent" icon={h(I.reconnect, { size: 13 })}>Reconnect display</Button>
          : <Button variant="secondary" icon={h(I.disconnect, { size: 13 })} destructive>{destructiveLabel || "Disconnect display"}</Button>}
        <div style={{ flex: 1 }} />
        <Button variant="plain">Save as Preset…</Button>
      </div>
    );
  }

  function ResolutionCard({ scaled, riskySelect }) {
    return (
      <Card title="Resolution" footnote="“Default” picks the best balance of space and clarity. Scaled resolutions use HiDPI rendering.">
        <Row label="Resolution">
          <SegmentedControl value={scaled ? "scaled" : "default"} onChange={() => {}}
            options={[{ value: "default", label: "Default" }, { value: "scaled", label: "Scaled" }]} />
        </Row>
        {scaled && <>
          <Divider />
          <Row label="Scaled size" secondary="Larger text ↔ More space">
            <Select value="2056 × 1329" onChange={() => {}}
              options={["1280 × 832", "1496 × 967", "2056 × 1329", "2304 × 1496", "5120 × 2880"]} />
          </Row>
        </>}
        <Divider />
        <Row label="Refresh Rate"><Select value="60 Hz" onChange={() => {}} options={["60 Hz"]} /></Row>
      </Card>
    );
  }

  function AppearanceCard({ d, hdrUnsupported }) {
    return (
      <Card title="Appearance">
        <Row label="Brightness" leading={h(I.sunMax, { size: 15 })}>
          <div style={{ width: 168 }}><Slider value={d.brightness} onChange={() => {}} /></div>
        </Row>
        <Divider />
        <Row label="High Dynamic Range"
          secondary={hdrUnsupported ? "Not supported on this display" : "Supported"}>
          <Switch checked={!hdrUnsupported && d.hdr} disabled={hdrUnsupported} onChange={() => {}} />
        </Row>
        <Divider />
        <Row label="True Tone"><Switch checked={d.trueTone} onChange={() => {}} /></Row>
        <Divider />
        <Row label="Rotation">
          <Select value="Standard" onChange={() => {}} options={["Standard", "90°", "180°", "270°"]} />
        </Row>
      </Card>
    );
  }

  function UseAsCard() {
    return (
      <Card title="Use as">
        <Row label="Use as main display" secondary="Menu bar and Dock appear here"><Switch checked onChange={() => {}} /></Row>
        <Divider />
        <Row label="Color Profile"><Select value="Apple Display (P3)" onChange={() => {}}
          options={["Apple Display (P3)", "sRGB IEC61966-2.1", "Adobe RGB (1998)"]} /></Row>
      </Card>
    );
  }

  // 1 — display detail default
  function DetailDefault() {
    return (
      <K.Window title="Displays" active="studio" height={680}
        header={<K.WinHeader title="Studio Display" badge={<Badge tone="green">Connected</Badge>} />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <ResolutionCard />
          <AppearanceCard d={studio} />
          <UseAsCard />
          <ActionRow />
        </div>
      </K.Window>
    );
  }

  // 2 — scaled resolution open
  function DetailScaled() {
    return (
      <K.Window title="Displays" active="studio" height={560}
        header={<K.WinHeader title="Studio Display" badge={<Badge tone="green">Connected</Badge>} />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <ResolutionCard scaled />
          <AppearanceCard d={studio} />
        </div>
      </K.Window>
    );
  }

  // 3 — confirm-or-revert countdown banner
  function DetailCountdown() {
    return (
      <K.Window title="Displays" active="studio" height={620}
        header={<K.WinHeader title="Studio Display" badge={<Badge tone="green">Connected</Badge>} />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <InlineBanner tone="orange" icon={h(I.countdown, { size: 18 })}
            title="Keep changed display setting?"
            message="Resolution → 2304 × 1496 — reverting automatically if not confirmed."
            countdown={11}
            actions={<>
              <Button variant="accent" size="sm">Keep Changes</Button>
              <Button variant="secondary" size="sm">Revert</Button>
            </>} />
          <ResolutionCard scaled />
          <AppearanceCard d={studio} />
        </div>
      </K.Window>
    );
  }

  // 4 — capability reasons (HDR unsupported + DDC degraded)
  function DetailDegraded() {
    return (
      <K.Window title="Displays" active="lg" height={640}
        header={<K.WinHeader title="LG UltraFine 4K" badge={<Badge tone="orange">Degraded route</Badge>} />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <InlineBanner tone="orange" icon={h(I.warning, { size: 18 })}
            title="Hardware brightness control unavailable"
            message="The DDC route over this dock stopped responding. Brightness is using a software overlay. Reseat the cable or connect directly to restore hardware control."
            actions={<><Button variant="secondary" size="sm">Retry Route</Button><Button variant="plain" size="sm">Diagnostics…</Button></>} />
          <Card title="Appearance">
            <Row label="Brightness" secondary="Software fallback" leading={h(I.sunMax, { size: 15 })}>
              <div style={{ width: 168 }}><Slider value={50} onChange={() => {}} /></div>
            </Row>
            <Divider />
            <Row label="High Dynamic Range" secondary="Not supported on this display">
              <Switch checked={false} disabled onChange={() => {}} /></Row>
            <Divider />
            <Row label="True Tone" secondary="Not supported on this display"><Switch checked={false} disabled onChange={() => {}} /></Row>
          </Card>
          <Card title="Controls" footnote="Each unavailable control names the limiting factor — OS, hardware, route, or permission.">
            <Row label="Volume" secondary="No audio over DisplayPort on this model"><Badge tone="neutral">Unavailable</Badge></Row>
            <Divider />
            <Row label="Input Source" secondary="DDC route degraded"><Badge tone="orange">Route degraded</Badge></Row>
          </Card>
          <ActionRow />
        </div>
      </K.Window>
    );
  }

  // 5 — managed-offline state
  function DetailOffline() {
    return (
      <K.Window title="Displays" active="lg" height={560}
        header={<K.WinHeader title="LG UltraFine 4K" badge={<Badge tone="orange">Managed offline</Badge>} />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <InlineBanner tone="neutral" icon={h(I.disconnect, { size: 18 })}
            title="Logically disconnected"
            message="Removed from the active layout by you · 4m ago. The physical link may still be present. Reconnect to request it back into topology."
            actions={<Button variant="accent" size="sm" icon={h(I.reconnect, { size: 13 })}>Reconnect</Button>} />
          <Card title="Last known state" footnote="Restored automatically on reconnect unless the mode is no longer offered.">
            <Row label="Resolution"><span style={muted}>2560 × 1440 · 60 Hz</span></Row>
            <Divider />
            <Row label="Role"><span style={muted}>Secondary · right of main</span></Row>
            <Divider />
            <Row label="Checkpoint"><span style={muted}>Saved before disconnect · 14:21</span></Row>
          </Card>
          <Card title="Lifecycle">
            <Row label="Reconnect on wake" secondary="Bring this display back when the Mac wakes"><Switch checked onChange={() => {}} /></Row>
            <Divider />
            <Row label="Persistent disconnect" secondary="Re-apply after login, only when safe (off by default)"><Switch checked={false} onChange={() => {}} /></Row>
          </Card>
        </div>
      </K.Window>
    );
  }

  const muted = { font: "var(--weight-regular) 13px/1 var(--font-text)", color: "var(--label-secondary)", fontVariantNumeric: "tabular-nums" };

  // ---------- Arrange canvas ----------
  function ArrangeCanvas({ mirror, identify }) {
    const tiles = [
      { id: "studio", name: "Studio", w: 150, main: true },
      { id: "builtin", name: "Built-in", w: 118 },
      { id: "lg", name: "LG", w: 132 },
    ];
    return (
      <Card title="Arrangement" footnote="Drag displays to rearrange. The bar marks the main display; drag it to move the menu bar.">
        <div style={{ position: "relative", padding: "26px 16px 20px", display: "flex", gap: 28,
          alignItems: "flex-end", justifyContent: "center", background: "linear-gradient(180deg,#f6f7f9,#eceef1)" }}>
          {tiles.map((t, i) => (
            <div key={t.id} style={{ position: "relative" }}>
              <DisplayTile name={t.name} width={t.w} main={t.main} mirrored={mirror && !t.main}
                selected={t.id === "studio"} onClick={() => {}} />
              {identify && (
                <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center" }}>
                  <span style={{ font: "var(--weight-bold) 40px/1 var(--font-display)", color: "#fff",
                    textShadow: "0 1px 6px rgba(0,0,0,0.45)" }}>{i + 1}</span>
                </div>
              )}
            </div>
          ))}
        </div>
      </Card>
    );
  }

  // 6 — arrange default
  function Arrange() {
    return (
      <K.Window title="Displays" active="arrange"
        header={<K.WinHeader title="Arrange Displays" />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <ArrangeCanvas />
          <Card>
            <Row label="Mirror Displays" secondary="Show the same image on all displays"><Switch checked={false} onChange={() => {}} /></Row>
            <Divider />
            <Row label="Identify displays" secondary="Flash a number on each screen"><Button variant="secondary" size="sm" icon={h(I.identify, { size: 13 })}>Identify</Button></Row>
          </Card>
        </div>
      </K.Window>
    );
  }

  // 7 — mirror on
  function ArrangeMirror() {
    return (
      <K.Window title="Displays" active="arrange"
        header={<K.WinHeader title="Arrange Displays" badge={<Badge tone="neutral">Mirroring</Badge>} />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <ArrangeCanvas mirror />
          <Card>
            <Row label="Mirror Displays" secondary="Show the same image on all displays"><Switch checked onChange={() => {}} /></Row>
            <Divider />
            <Row label="Optimize for" secondary="Choose which display sets the mirrored resolution">
              <Select value="Studio Display" onChange={() => {}} options={["Studio Display", "Built-in Retina", "LG UltraFine 4K"]} /></Row>
          </Card>
        </div>
      </K.Window>
    );
  }

  // 8 — identify overlay
  function ArrangeIdentify() {
    return (
      <K.Window title="Displays" active="arrange"
        header={<K.WinHeader title="Arrange Displays" />}>
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <ArrangeCanvas identify />
          <div style={{ display: "flex", alignItems: "center", gap: 9, padding: "0 2px",
            font: "var(--weight-regular) 12px/1.4 var(--font-text)", color: "var(--label-secondary)" }}>
            {h(I.info, { size: 15 })} A large number is shown on each screen. Use this to pair identical displays before any disconnect.
          </div>
        </div>
      </K.Window>
    );
  }

  // 9 — disconnect confirmation sheet (modal over window)
  function DisconnectSheet() {
    return (
      <div style={{ position: "relative", width: 760, height: 560, borderRadius: "var(--radius-2xl)", overflow: "hidden" }}>
        <div style={{ filter: "saturate(0.92)", transform: "scale(1)" }}>
          <K.Window title="Displays" active="lg" height={560}
            header={<K.WinHeader title="LG UltraFine 4K" badge={<Badge tone="green">Connected</Badge>} />}>
            <div style={{ display: "flex", flexDirection: "column", gap: 16, opacity: 0.55 }}>
              <ResolutionCard /><AppearanceCard d={studio} />
            </div>
          </K.Window>
        </div>
        <div style={{ position: "absolute", inset: 0, background: "rgba(0,0,0,0.28)",
          display: "flex", alignItems: "flex-start", justifyContent: "center" }}>
          <div style={{ marginTop: 90, width: 380, background: "var(--raised-bg)", borderRadius: 14,
            boxShadow: "var(--shadow-popover)", padding: "22px 22px 18px", fontFamily: "var(--font-text)",
            display: "flex", flexDirection: "column", alignItems: "center", gap: 12 }}>
            <div style={{ width: 52, height: 52, borderRadius: 99, display: "flex", alignItems: "center",
              justifyContent: "center", background: "rgba(255,149,0,0.16)", color: "var(--orange)" }}>
              {h(I.countdown, { size: 26 })}</div>
            <div style={{ textAlign: "center" }}>
              <div style={{ font: "var(--weight-semibold) 15px/1.3 var(--font-text)", color: "var(--label-primary)" }}>
                Disconnect LG UltraFine 4K?</div>
              <div style={{ font: "var(--weight-regular) 12.5px/1.5 var(--font-text)", color: "var(--label-secondary)", marginTop: 6 }}>
                This removes it from the active layout. <b style={{ color: "var(--label-primary)" }}>Studio Display</b> and
                <b style={{ color: "var(--label-primary)" }}> Built-in Retina</b> stay active as safe surfaces. Reverting automatically in
                <b style={{ color: "var(--label-primary)", fontVariantNumeric: "tabular-nums" }}> 9s</b>.</div>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 7, padding: "8px 12px", width: "100%",
              boxSizing: "border-box", borderRadius: 8, background: "var(--fill-tertiary)",
              font: "var(--weight-regular) 11.5px/1.3 var(--font-text)", color: "var(--label-secondary)" }}>
              {h(I.shieldCheck, { size: 16 })}
              <span>Recovery key <kbd style={kbd}>⌃⌥⌘R</kbd> reconnects everything at any time.</span>
            </div>
            <div style={{ display: "flex", gap: 8, width: "100%" }}>
              <Button variant="secondary" size="lg" style={{ flex: 1, justifyContent: "center" }}>Cancel</Button>
              <Button variant="accent" size="lg" destructive style={{ flex: 1, justifyContent: "center" }}>Disconnect</Button>
            </div>
          </div>
        </div>
      </div>
    );
  }
  const kbd = { font: "var(--weight-medium) 11px/1 var(--font-mono)", background: "var(--fill-secondary)",
    borderRadius: 4, padding: "2px 5px", color: "var(--label-primary)" };

  window.ODSettingsA = {
    DetailDefault, DetailScaled, DetailCountdown, DetailDegraded, DetailOffline,
    Arrange, ArrangeMirror, ArrangeIdentify, DisconnectSheet,
  };
})();
