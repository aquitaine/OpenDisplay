/* OpenDisplay — net-new line glyphs proposed for the app.
   Authored in the same idiom as assets/od-icons.js: 24x24 viewBox,
   1.6px rounded stroke, currentColor, no fill (unless noted). These are
   the icons the PRD surfaces require beyond the ~20 the kit already ships.
   In production each maps to a matching SF Symbol (noted in the inventory). */
(function () {
  var h = React.createElement;
  function svg(paths, vb) {
    return function Icon(props) {
      props = props || {};
      var size = props.size || 16;
      return h(
        "svg",
        {
          width: size, height: size, viewBox: vb || "0 0 24 24",
          fill: "none", stroke: "currentColor",
          strokeWidth: props.weight || 1.6,
          strokeLinecap: "round", strokeLinejoin: "round",
          style: props.style, "aria-hidden": "true",
        },
        paths.map(function (d, i) {
          if (typeof d === "string") return h("path", { key: i, d: d });
          return h(d.t, Object.assign({ key: i }, d.a));
        })
      );
    };
  }
  var ext = {
    // ---- Routes & connection ----
    cable: svg(["M7 3v6a3 3 0 0 0 3 3h4a3 3 0 0 1 3 3v6", "M5 3h4", "M15 21h4"]),
    usbc: svg([{ t: "rect", a: { x: 6, y: 9, width: 12, height: 6, rx: 3 } }, "M12 4v5", "M9 19h6"]),
    wireless: svg(["M5 11a10 10 0 0 1 14 0", "M8 14a6 6 0 0 1 8 0", { t: "circle", a: { cx: 12, cy: 17.5, r: 1, fill: "currentColor", stroke: "none" } }]),
    airplay: svg(["M5 17H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1h-1", "M12 14l5 6H7l5-6z"]),
    sidecar: svg([{ t: "rect", a: { x: 3, y: 6, width: 11, height: 12, rx: 1.5 } }, "M17 9a4 4 0 0 1 0 6", "M19.5 7a7 7 0 0 1 0 10"]),
    // ---- Presentation / power states ----
    blackout: svg([{ t: "rect", a: { x: 3, y: 4.5, width: 18, height: 12, rx: 1 } }, "M3 4.5l18 12", "M9 20.5h6", "M12 16.5v4"]),
    moon: svg(["M19 14.5A7.5 7.5 0 0 1 9.5 5a6 6 0 1 0 9.5 9.5z"]),
    powerOff: svg(["M12 3v8", "M6.4 6.4a8 8 0 1 0 11.2 0"]),
    // ---- Lifecycle ----
    disconnect: svg([{ t: "rect", a: { x: 3, y: 4.5, width: 18, height: 12, rx: 1 } }, "M9 20.5h6", "M12 16.5v4", "M16 7l4 4m0-4l-4 4"]),
    reconnect: svg(["M4 12a8 8 0 0 1 13.7-5.6L20 8", "M20 4v4h-4", "M20 12a8 8 0 0 1-13.7 5.6L4 16", "M4 20v-4h4"]),
    reconnectAll: svg(["M5 13a6 6 0 0 1 10-4.4L17 10", "M17 6v4h-4", "M19 11a6 6 0 0 1-10 4.4L7 14", "M7 18v-4h4"]),
    // ---- Safety & recovery ----
    shield: svg(["M12 3l7 3v5c0 4.4-3 8-7 10-4-2-7-5.6-7-10V6l7-3z"]),
    shieldCheck: svg(["M12 3l7 3v5c0 4.4-3 8-7 10-4-2-7-5.6-7-10V6l7-3z", "M9 11.8l2 2 4-4.2"]),
    checkpoint: svg(["M6 21V4", "M6 4h10l-1.6 3L16 10H6"]),
    health: svg(["M3 12.5h4l2-5 3 9 2.5-5 1.5 1h5"]),
    warning: svg(["M12 4.5l9 15.5H3z", "M12 10v4.5", { t: "circle", a: { cx: 12, cy: 17.3, r: 0.6, fill: "currentColor", stroke: "none" } }]),
    countdown: svg([{ t: "circle", a: { cx: 12, cy: 13, r: 8 } }, "M12 13V8.5", "M9.5 3h5", "M18.5 6.5l1.5-1.5"]),
    circuitBreaker: svg([{ t: "circle", a: { cx: 12, cy: 12, r: 9 } }, "M13.5 6.5L9 13h4l-1.5 4.5"]),
    // ---- Scenes & automation ----
    scenes: svg(["M12 3l8 4-8 4-8-4 8-4z", "M4 12l8 4 8-4", "M4 16.5l8 4 8-4"]),
    keyboard: svg([{ t: "rect", a: { x: 3, y: 6, width: 18, height: 12, rx: 2 } }, "M7 10h.01M11 10h.01M15 10h.01M17 10h.01M7 13h.01M17 13h.01", "M9 15.5h6"]),
    command: svg(["M9 6a2 2 0 1 0-2 2h10a2 2 0 1 0-2-2v12a2 2 0 1 0 2-2H7a2 2 0 1 0 2 2V6z"]),
    terminal: svg([{ t: "rect", a: { x: 3, y: 5, width: 18, height: 14, rx: 2 } }, "M7 10l3 2-3 2", "M13 14h4"]),
    api: svg([{ t: "circle", a: { cx: 12, cy: 12, r: 8.5 } }, "M3.5 12h17", "M12 3.5c2.5 2.3 2.5 14.7 0 17c-2.5-2.3-2.5-14.7 0-17z"]),
    token: svg([{ t: "circle", a: { cx: 8, cy: 12, r: 4 } }, "M11.5 12H21", "M17 12v3", "M20 12v2.5"]),
    rules: svg(["M5 6h9", "M5 12h14", "M5 18h6", { t: "circle", a: { cx: 18, cy: 6, r: 2 } }, { t: "circle", a: { cx: 16, cy: 18, r: 2 } }]),
    // ---- Diagnostics / labs / misc ----
    labs: svg(["M9 3h6", "M10 3v6l-4.5 8a2 2 0 0 0 1.8 3h9.4a2 2 0 0 0 1.8-3L14 9V3", "M7.5 15h9"]),
    killSwitch: svg([{ t: "rect", a: { x: 4, y: 8, width: 16, height: 8, rx: 4 } }, { t: "circle", a: { cx: 8, cy: 12, r: 2, fill: "currentColor", stroke: "none" } }]),
    undo: svg(["M9 7L4 12l5 5", "M4 12h10a6 6 0 0 1 6 6v1"]),
    history: svg(["M4 12a8 8 0 1 1 2.3 5.6", "M4 19v-4h4", "M12 8v4.5l3 2"]),
    bundle: svg([{ t: "rect", a: { x: 4, y: 7, width: 16, height: 13, rx: 1.5 } }, "M4 10.5h16", "M3 7l2-3h14l2 3", "M10 14h4"]),
    identify: svg([{ t: "rect", a: { x: 3, y: 4.5, width: 18, height: 12, rx: 1 } }, "M9 20.5h6", "M12 16.5v4", "M12 8v5M10.5 8.6L12 8"]),
    ambiguous: svg([{ t: "rect", a: { x: 2.5, y: 6, width: 11, height: 8, rx: 1 } }, { t: "rect", a: { x: 10.5, y: 10, width: 11, height: 8, rx: 1 } }, "M19 8.2a1.6 1.6 0 0 1 1.6 1.6c0 1.1-1.6 1.2-1.6 2.4", { t: "circle", a: { cx: 19, cy: 14.6, r: 0.55, fill: "currentColor", stroke: "none" } }]),
    scan: svg([{ t: "circle", a: { cx: 11, cy: 11, r: 6.5 } }, "M11 6.5a4.5 4.5 0 0 0 0 9", "M16 16l4 4"]),
    tag: svg(["M4 4h7l9 9-7 7-9-9V4z", { t: "circle", a: { cx: 8, cy: 8, r: 1.3 } }]),
    contrast: svg([{ t: "circle", a: { cx: 12, cy: 12, r: 8.5 } }, "M12 3.5v17", "M12 8a4 4 0 0 1 0 8z", { t: "path", a: { d: "M12 8a4 4 0 0 0 0 8z", fill: "currentColor", stroke: "none" } }]),
    inputSource: svg([{ t: "rect", a: { x: 3, y: 5, width: 18, height: 14, rx: 2 } }, "M8 12h8", "M13 9l3 3-3 3"]),
    refresh: svg(["M20 6v4h-4", "M20 10A8 8 0 1 0 19 16"]),
    plug: svg(["M9 3v5", "M15 3v5", "M7 8h10v3a5 5 0 0 1-10 0V8z", "M12 16v5"]),
  };
  window.ODIconsExt = ext;
  // also fold into ODIcons so screens can pull everything from one map
  if (window.ODIcons) Object.assign(window.ODIcons, ext);
})();
