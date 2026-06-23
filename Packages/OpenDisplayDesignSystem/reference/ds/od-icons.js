/* OpenDisplay UI-kit glyphs.
   NOTE: macOS ships SF Symbols, which cannot be redistributed. These are
   minimal line substitutes (1.6px stroke, rounded) used only inside the UI
   kits. In production, swap for the matching SF Symbol. Registered globally
   as window.ODIcons so any kit screen can use them without bundling. */
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
  window.ODIcons = {
    monitor: svg(["M3 4.5h18v12H3z", "M9 20.5h6", "M12 16.5v4"]),
    monitorLines: svg(["M3 4.5h18v12H3z", "M9 20.5h6", "M12 16.5v4", "M6.5 8h7", "M6.5 11h4"]),
    sunDim: svg([{ t: "circle", a: { cx: 12, cy: 12, r: 3 } }, "M12 5.5v1M12 17.5v1M5.5 12h1M17.5 12h1"]),
    sunMax: svg([{ t: "circle", a: { cx: 12, cy: 12, r: 4 } }, "M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M18.4 5.6L17 7M7 17l-1.4 1.4"]),
    speaker: svg(["M4 9.5v5h3l4 3.5V6L7 9.5z"]),
    speakerWave: svg(["M4 9.5v5h3l4 3.5V6L7 9.5z", "M15 9.5a4 4 0 0 1 0 5", "M17.5 7.5a7 7 0 0 1 0 9"]),
    gear: svg([{ t: "circle", a: { cx: 12, cy: 12, r: 3 } }, "M19 12a7 7 0 0 0-.1-1.2l1.7-1.3-1.6-2.8-2 .8a7 7 0 0 0-2-1.2l-.3-2.1H9.3L9 4.3a7 7 0 0 0-2 1.2l-2-.8L3.4 7.5l1.7 1.3A7 7 0 0 0 5 12c0 .4 0 .8.1 1.2l-1.7 1.3 1.6 2.8 2-.8a7 7 0 0 0 2 1.2l.3 2.1h3.4l.3-2.1a7 7 0 0 0 2-1.2l2 .8 1.6-2.8-1.7-1.3c.1-.4.1-.8.1-1.2z"]),
    info: svg([{ t: "circle", a: { cx: 12, cy: 12, r: 9 } }, "M12 11v5", { t: "circle", a: { cx: 12, cy: 8, r: 0.6, fill: "currentColor", stroke: "none" } }]),
    chevronRight: svg(["M9.5 6l6 6-6 6"]),
    chevronDown: svg(["M6 9.5l6 6 6-6"]),
    mirror: svg(["M12 3v18", "M9 7L4 12l5 5", "M15 7l5 5-5 5"]),
    rotate: svg(["M4 12a8 8 0 1 1 2.3 5.6", "M4 19v-4h4"]),
    plus: svg(["M12 5v14M5 12h14"]),
    lock: svg([{ t: "rect", a: { x: 5, y: 11, width: 14, height: 9, rx: 2 } }, "M8 11V8a4 4 0 0 1 8 0v3"]),
    bolt: svg(["M13 3L5 14h6l-1 7 8-11h-6l1-7z"]),
    eject: svg(["M6 14h12L12 6 6 14z", "M6 18h12"]),
    arrows: svg(["M7 8L4 11l3 3", "M4 11h16", "M17 16l3-3-3-3", "M20 13H4"]),
    sparkles: svg(["M12 4l1.4 4.6L18 10l-4.6 1.4L12 16l-1.4-4.6L6 10l4.6-1.4z", "M18 15l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7z"]),
    display2: svg([{ t: "rect", a: { x: 2.5, y: 5, width: 13, height: 9, rx: 1.5 } }, { t: "rect", a: { x: 15, y: 8, width: 6.5, height: 5, rx: 1 } }, "M7 18h4"]),
    check: svg(["M5 12.5l4.5 4.5L19 7"]),
  };
})();
