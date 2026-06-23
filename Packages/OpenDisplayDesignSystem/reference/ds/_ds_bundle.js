/* @ds-bundle: {"format":3,"namespace":"OpenDisplayDesignSystem_1a53d9","components":[{"name":"Button","sourcePath":"components/controls/Button.jsx"},{"name":"Checkbox","sourcePath":"components/controls/Checkbox.jsx"},{"name":"IconButton","sourcePath":"components/controls/IconButton.jsx"},{"name":"SegmentedControl","sourcePath":"components/controls/SegmentedControl.jsx"},{"name":"Select","sourcePath":"components/controls/Select.jsx"},{"name":"Slider","sourcePath":"components/controls/Slider.jsx"},{"name":"Stepper","sourcePath":"components/controls/Stepper.jsx"},{"name":"Switch","sourcePath":"components/controls/Switch.jsx"},{"name":"DisplayTile","sourcePath":"components/display/DisplayTile.jsx"},{"name":"Badge","sourcePath":"components/feedback/Badge.jsx"},{"name":"InlineBanner","sourcePath":"components/feedback/InlineBanner.jsx"},{"name":"Card","sourcePath":"components/layout/Card.jsx"},{"name":"Divider","sourcePath":"components/layout/Divider.jsx"},{"name":"Row","sourcePath":"components/layout/Row.jsx"}],"sourceHashes":{"assets/od-icons.js":"878599194f1f","components/controls/Button.jsx":"04555a51340a","components/controls/Checkbox.jsx":"4606dfc7c282","components/controls/IconButton.jsx":"6fd7cc7056dc","components/controls/SegmentedControl.jsx":"506fd8018593","components/controls/Select.jsx":"e9d8b13d8b5f","components/controls/Slider.jsx":"4439314c1462","components/controls/Stepper.jsx":"7dbb66a6cab2","components/controls/Switch.jsx":"5a05f75b5f25","components/display/DisplayTile.jsx":"f830e2914228","components/feedback/Badge.jsx":"0f8fe5186ab0","components/feedback/InlineBanner.jsx":"9f1f0c743eb4","components/layout/Card.jsx":"67974f96a065","components/layout/Divider.jsx":"eb8a412a73fe","components/layout/Row.jsx":"48f264e34fa9","ui_kits/menubar/MenuBarPopover.js":"a344c74a26b4","ui_kits/settings/SettingsWindow.jsx":"6f393855f0f8"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.OpenDisplayDesignSystem_1a53d9 = window.OpenDisplayDesignSystem_1a53d9 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// assets/od-icons.js
try { (() => {
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
      return h("svg", {
        width: size,
        height: size,
        viewBox: vb || "0 0 24 24",
        fill: "none",
        stroke: "currentColor",
        strokeWidth: props.weight || 1.6,
        strokeLinecap: "round",
        strokeLinejoin: "round",
        style: props.style,
        "aria-hidden": "true"
      }, paths.map(function (d, i) {
        if (typeof d === "string") return h("path", {
          key: i,
          d: d
        });
        return h(d.t, Object.assign({
          key: i
        }, d.a));
      }));
    };
  }
  window.ODIcons = {
    monitor: svg(["M3 4.5h18v12H3z", "M9 20.5h6", "M12 16.5v4"]),
    monitorLines: svg(["M3 4.5h18v12H3z", "M9 20.5h6", "M12 16.5v4", "M6.5 8h7", "M6.5 11h4"]),
    sunDim: svg([{
      t: "circle",
      a: {
        cx: 12,
        cy: 12,
        r: 3
      }
    }, "M12 5.5v1M12 17.5v1M5.5 12h1M17.5 12h1"]),
    sunMax: svg([{
      t: "circle",
      a: {
        cx: 12,
        cy: 12,
        r: 4
      }
    }, "M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M18.4 5.6L17 7M7 17l-1.4 1.4"]),
    speaker: svg(["M4 9.5v5h3l4 3.5V6L7 9.5z"]),
    speakerWave: svg(["M4 9.5v5h3l4 3.5V6L7 9.5z", "M15 9.5a4 4 0 0 1 0 5", "M17.5 7.5a7 7 0 0 1 0 9"]),
    gear: svg([{
      t: "circle",
      a: {
        cx: 12,
        cy: 12,
        r: 3
      }
    }, "M19 12a7 7 0 0 0-.1-1.2l1.7-1.3-1.6-2.8-2 .8a7 7 0 0 0-2-1.2l-.3-2.1H9.3L9 4.3a7 7 0 0 0-2 1.2l-2-.8L3.4 7.5l1.7 1.3A7 7 0 0 0 5 12c0 .4 0 .8.1 1.2l-1.7 1.3 1.6 2.8 2-.8a7 7 0 0 0 2 1.2l.3 2.1h3.4l.3-2.1a7 7 0 0 0 2-1.2l2 .8 1.6-2.8-1.7-1.3c.1-.4.1-.8.1-1.2z"]),
    info: svg([{
      t: "circle",
      a: {
        cx: 12,
        cy: 12,
        r: 9
      }
    }, "M12 11v5", {
      t: "circle",
      a: {
        cx: 12,
        cy: 8,
        r: 0.6,
        fill: "currentColor",
        stroke: "none"
      }
    }]),
    chevronRight: svg(["M9.5 6l6 6-6 6"]),
    chevronDown: svg(["M6 9.5l6 6 6-6"]),
    mirror: svg(["M12 3v18", "M9 7L4 12l5 5", "M15 7l5 5-5 5"]),
    rotate: svg(["M4 12a8 8 0 1 1 2.3 5.6", "M4 19v-4h4"]),
    plus: svg(["M12 5v14M5 12h14"]),
    lock: svg([{
      t: "rect",
      a: {
        x: 5,
        y: 11,
        width: 14,
        height: 9,
        rx: 2
      }
    }, "M8 11V8a4 4 0 0 1 8 0v3"]),
    bolt: svg(["M13 3L5 14h6l-1 7 8-11h-6l1-7z"]),
    eject: svg(["M6 14h12L12 6 6 14z", "M6 18h12"]),
    arrows: svg(["M7 8L4 11l3 3", "M4 11h16", "M17 16l3-3-3-3", "M20 13H4"]),
    sparkles: svg(["M12 4l1.4 4.6L18 10l-4.6 1.4L12 16l-1.4-4.6L6 10l4.6-1.4z", "M18 15l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7z"]),
    display2: svg([{
      t: "rect",
      a: {
        x: 2.5,
        y: 5,
        width: 13,
        height: 9,
        rx: 1.5
      }
    }, {
      t: "rect",
      a: {
        x: 15,
        y: 8,
        width: 6.5,
        height: 5,
        rx: 1
      }
    }, "M7 18h4"]),
    check: svg(["M5 12.5l4.5 4.5L19 7"])
  };
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "assets/od-icons.js", error: String((e && e.message) || e) }); }

// components/controls/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * macOS-style push button. Default `accent` is the filled system-blue
 * button; `secondary` is the neutral bezeled button; `plain` is borderless.
 */
function Button({
  variant = "secondary",
  size = "md",
  destructive = false,
  disabled = false,
  icon = null,
  children,
  style = {},
  ...rest
}) {
  const heights = {
    sm: 20,
    md: 24,
    lg: 28
  };
  const pads = {
    sm: "0 8px",
    md: "0 12px",
    lg: "0 14px"
  };
  const fontSizes = {
    sm: 11,
    md: 13,
    lg: 13
  };
  const base = {
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    gap: 5,
    height: heights[size],
    padding: pads[size],
    fontFamily: "var(--font-text)",
    fontSize: fontSizes[size],
    fontWeight: "var(--weight-regular)",
    lineHeight: 1,
    borderRadius: "var(--radius-sm)",
    border: "none",
    cursor: disabled ? "default" : "pointer",
    opacity: disabled ? 0.4 : 1,
    whiteSpace: "nowrap",
    userSelect: "none",
    transition: "filter var(--dur-fast) var(--ease-out), background var(--dur-fast) var(--ease-out)",
    WebkitFontSmoothing: "antialiased"
  };
  const variants = {
    accent: {
      background: destructive ? "var(--red)" : "var(--accent)",
      color: "var(--accent-fg)",
      fontWeight: "var(--weight-medium)",
      boxShadow: "0 0.5px 1px rgba(0,0,0,0.18), inset 0 0.5px 0 rgba(255,255,255,0.25)"
    },
    secondary: {
      background: "var(--card-bg)",
      color: destructive ? "var(--red)" : "var(--label-primary)",
      boxShadow: "var(--shadow-control)"
    },
    plain: {
      background: "transparent",
      color: destructive ? "var(--red)" : "var(--accent)"
    }
  };
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    disabled: disabled,
    style: {
      ...base,
      ...variants[variant],
      ...style
    },
    onMouseDown: e => !disabled && (e.currentTarget.style.filter = "brightness(0.93)"),
    onMouseUp: e => e.currentTarget.style.filter = "",
    onMouseLeave: e => e.currentTarget.style.filter = ""
  }, rest), icon, children);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Button.jsx", error: String((e && e.message) || e) }); }

// components/controls/Checkbox.jsx
try { (() => {
/**
 * macOS checkbox. Filled system-blue with a white check when on.
 * Controlled via `checked` / `onChange`. Optional `label`.
 */
function Checkbox({
  checked = false,
  disabled = false,
  onChange,
  label,
  style = {}
}) {
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 6,
      fontFamily: "var(--font-text)",
      fontSize: 13,
      color: "var(--label-primary)",
      cursor: disabled ? "default" : "pointer",
      opacity: disabled ? 0.4 : 1,
      userSelect: "none",
      ...style
    }
  }, /*#__PURE__*/React.createElement("button", {
    type: "button",
    role: "checkbox",
    "aria-checked": checked,
    disabled: disabled,
    onClick: () => !disabled && onChange && onChange(!checked),
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      width: 14,
      height: 14,
      flex: "none",
      padding: 0,
      borderRadius: "var(--radius-xs)",
      border: checked ? "none" : "0.5px solid var(--border-control)",
      background: checked ? "var(--accent)" : "var(--card-bg)",
      boxShadow: checked ? "none" : "var(--shadow-control)",
      color: "var(--accent-fg)",
      cursor: disabled ? "default" : "pointer"
    }
  }, checked && /*#__PURE__*/React.createElement("svg", {
    width: "10",
    height: "10",
    viewBox: "0 0 10 10",
    fill: "none"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M2 5.2L4 7.2L8 2.8",
    stroke: "currentColor",
    strokeWidth: "1.6",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }))), label);
}
Object.assign(__ds_scope, { Checkbox });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Checkbox.jsx", error: String((e && e.message) || e) }); }

// components/controls/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Borderless square glyph button — toolbar/header affordance (gear, info,
 * add). Shows a soft fill on hover and a tinted state when `active`.
 */
function IconButton({
  size = 24,
  active = false,
  disabled = false,
  label,
  children,
  style = {},
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    "aria-label": label,
    disabled: disabled,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: "inline-flex",
      alignItems: "center",
      justifyContent: "center",
      width: size,
      height: size,
      padding: 0,
      border: "none",
      borderRadius: "var(--radius-sm)",
      background: active ? "var(--accent-tint)" : hover && !disabled ? "var(--fill-quaternary)" : "transparent",
      color: active ? "var(--accent)" : "var(--label-secondary)",
      cursor: disabled ? "default" : "pointer",
      opacity: disabled ? 0.4 : 1,
      transition: "background var(--dur-fast) var(--ease-out)",
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/controls/SegmentedControl.jsx
try { (() => {
/**
 * macOS segmented control. `options` is an array of { value, label } or
 * strings; the selected segment gets a raised white pill.
 */
function SegmentedControl({
  options = [],
  value,
  onChange,
  size = "md",
  disabled = false,
  style = {}
}) {
  const opts = options.map(o => typeof o === "string" ? {
    value: o,
    label: o
  } : o);
  const h = size === "sm" ? 20 : 24;
  return /*#__PURE__*/React.createElement("div", {
    role: "tablist",
    style: {
      display: "inline-flex",
      height: h,
      padding: 2,
      gap: 2,
      background: "var(--fill-tertiary)",
      borderRadius: "var(--radius-sm)",
      opacity: disabled ? 0.4 : 1,
      ...style
    }
  }, opts.map((o, i) => {
    const selected = o.value === value;
    return /*#__PURE__*/React.createElement("button", {
      key: o.value,
      type: "button",
      role: "tab",
      "aria-selected": selected,
      disabled: disabled,
      onClick: () => !disabled && onChange && onChange(o.value),
      style: {
        position: "relative",
        display: "inline-flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 4,
        padding: "0 10px",
        height: h - 4,
        border: "none",
        borderRadius: "var(--radius-xs)",
        fontFamily: "var(--font-text)",
        fontSize: size === "sm" ? 11 : 12,
        fontWeight: selected ? "var(--weight-medium)" : "var(--weight-regular)",
        color: "var(--label-primary)",
        background: selected ? "var(--card-bg)" : "transparent",
        boxShadow: selected ? "0 0.5px 1.5px rgba(0,0,0,0.16), 0 0 0 0.5px rgba(0,0,0,0.04)" : "none",
        cursor: disabled ? "default" : "pointer",
        transition: "background var(--dur-base) var(--ease-standard)",
        whiteSpace: "nowrap"
      }
    }, o.label);
  }));
}
Object.assign(__ds_scope, { SegmentedControl });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/SegmentedControl.jsx", error: String((e && e.message) || e) }); }

// components/controls/Select.jsx
try { (() => {
/**
 * macOS pop-up button (Select). Renders a native-feeling bezeled control
 * with the up/down chevrons. Uses a real <select> underneath for behavior.
 */
function Select({
  value,
  onChange,
  options = [],
  size = "md",
  disabled = false,
  style = {}
}) {
  const opts = options.map(o => typeof o === "string" ? {
    value: o,
    label: o
  } : o);
  const h = size === "sm" ? 20 : size === "lg" ? 28 : 24;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      display: "inline-flex",
      alignItems: "center",
      height: h,
      minWidth: 90,
      background: "var(--card-bg)",
      borderRadius: "var(--radius-sm)",
      boxShadow: "var(--shadow-control)",
      opacity: disabled ? 0.4 : 1,
      ...style
    }
  }, /*#__PURE__*/React.createElement("select", {
    value: value,
    disabled: disabled,
    onChange: e => onChange && onChange(e.target.value),
    style: {
      appearance: "none",
      WebkitAppearance: "none",
      border: "none",
      outline: "none",
      background: "transparent",
      height: h,
      padding: "0 24px 0 9px",
      width: "100%",
      fontFamily: "var(--font-text)",
      fontSize: size === "sm" ? 11 : 13,
      color: "var(--label-primary)",
      cursor: disabled ? "default" : "pointer"
    }
  }, opts.map(o => /*#__PURE__*/React.createElement("option", {
    key: o.value,
    value: o.value
  }, o.label))), /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    style: {
      position: "absolute",
      right: 5,
      top: "50%",
      transform: "translateY(-50%)",
      display: "flex",
      flexDirection: "column",
      alignItems: "center",
      justifyContent: "center",
      width: 15,
      height: 15,
      borderRadius: 3,
      background: "var(--accent)",
      color: "var(--accent-fg)",
      pointerEvents: "none",
      lineHeight: 0.6,
      fontSize: 8
    }
  }, /*#__PURE__*/React.createElement("span", null, "\u25B2"), /*#__PURE__*/React.createElement("span", null, "\u25BC")));
}
Object.assign(__ds_scope, { Select });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Select.jsx", error: String((e && e.message) || e) }); }

// components/controls/Slider.jsx
try { (() => {
/**
 * macOS slider with filled track. Controlled value in [min,max].
 * Optional leading/trailing glyphs (e.g. small/large brightness icons).
 */
function Slider({
  value = 50,
  min = 0,
  max = 100,
  step = 1,
  disabled = false,
  onChange,
  leading = null,
  trailing = null,
  style = {}
}) {
  const pct = Math.max(0, Math.min(100, (value - min) / (max - min) * 100));
  const trackRef = React.useRef(null);
  const setFromClientX = clientX => {
    const el = trackRef.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const r = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    let v = min + r * (max - min);
    v = Math.round(v / step) * step;
    onChange && onChange(Math.max(min, Math.min(max, v)));
  };
  const onPointerDown = e => {
    if (disabled) return;
    setFromClientX(e.clientX);
    const move = ev => setFromClientX(ev.clientX);
    const up = () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8,
      opacity: disabled ? 0.4 : 1,
      ...style
    }
  }, leading, /*#__PURE__*/React.createElement("div", {
    ref: trackRef,
    onPointerDown: onPointerDown,
    style: {
      position: "relative",
      flex: 1,
      height: 18,
      display: "flex",
      alignItems: "center",
      cursor: disabled ? "default" : "pointer"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: 0,
      right: 0,
      height: 4,
      borderRadius: "var(--radius-pill)",
      background: "var(--fill-secondary)"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: 0,
      width: `${pct}%`,
      height: 4,
      borderRadius: "var(--radius-pill)",
      background: "var(--accent)"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      position: "absolute",
      left: `${pct}%`,
      width: 18,
      height: 18,
      transform: "translateX(-50%)",
      borderRadius: "var(--radius-pill)",
      background: "#ffffff",
      boxShadow: "0 0.5px 2px rgba(0,0,0,0.32), 0 0 0 0.5px rgba(0,0,0,0.06)"
    }
  })), trailing);
}
Object.assign(__ds_scope, { Slider });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Slider.jsx", error: String((e && e.message) || e) }); }

// components/controls/Stepper.jsx
try { (() => {
/**
 * macOS stepper — paired up/down increment control. Pair with a value
 * label to its left. Controlled via `onStep(+1|-1)`.
 */
function Stepper({
  onStep,
  disabled = false,
  style = {}
}) {
  const seg = (dir, glyph) => /*#__PURE__*/React.createElement("button", {
    type: "button",
    "aria-label": dir > 0 ? "Increase" : "Decrease",
    disabled: disabled,
    onClick: () => !disabled && onStep && onStep(dir),
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      width: 18,
      height: 11,
      padding: 0,
      border: "none",
      background: "var(--card-bg)",
      color: "var(--label-secondary)",
      fontSize: 7,
      lineHeight: 1,
      cursor: disabled ? "default" : "pointer"
    },
    onMouseDown: e => !disabled && (e.currentTarget.style.background = "var(--fill-secondary)"),
    onMouseUp: e => e.currentTarget.style.background = "var(--card-bg)",
    onMouseLeave: e => e.currentTarget.style.background = "var(--card-bg)"
  }, glyph);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "inline-flex",
      flexDirection: "column",
      borderRadius: "var(--radius-xs)",
      overflow: "hidden",
      boxShadow: "var(--shadow-control)",
      opacity: disabled ? 0.4 : 1,
      ...style
    }
  }, seg(1, "▲"), /*#__PURE__*/React.createElement("span", {
    style: {
      height: 0.5,
      background: "var(--separator)"
    }
  }), seg(-1, "▼"));
}
Object.assign(__ds_scope, { Stepper });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Stepper.jsx", error: String((e && e.message) || e) }); }

// components/controls/Switch.jsx
try { (() => {
/**
 * macOS toggle switch. Controlled via `checked` / `onChange`.
 * Track turns system-green when on, matching System Settings.
 */
function Switch({
  checked = false,
  disabled = false,
  onChange,
  size = "md",
  style = {}
}) {
  const dims = size === "sm" ? {
    w: 30,
    h: 18,
    k: 14
  } : {
    w: 38,
    h: 23,
    k: 19
  };
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    role: "switch",
    "aria-checked": checked,
    disabled: disabled,
    onClick: () => !disabled && onChange && onChange(!checked),
    style: {
      position: "relative",
      width: dims.w,
      height: dims.h,
      flex: "none",
      padding: 0,
      border: "none",
      borderRadius: "var(--radius-pill)",
      background: checked ? "var(--green)" : "var(--fill-primary)",
      cursor: disabled ? "default" : "pointer",
      opacity: disabled ? 0.4 : 1,
      transition: "background var(--dur-base) var(--ease-standard)",
      WebkitTapHighlightColor: "transparent",
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: "absolute",
      top: "50%",
      left: checked ? dims.w - dims.k - 2 : 2,
      width: dims.k,
      height: dims.k,
      transform: "translateY(-50%)",
      borderRadius: "var(--radius-pill)",
      background: "#ffffff",
      boxShadow: "0 1px 2px rgba(0,0,0,0.28), 0 0 1px rgba(0,0,0,0.18)",
      transition: "left var(--dur-base) var(--ease-standard)"
    }
  }));
}
Object.assign(__ds_scope, { Switch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/controls/Switch.jsx", error: String((e && e.message) || e) }); }

// components/display/DisplayTile.jsx
try { (() => {
/**
 * Visual monitor representation for the Arrangement canvas. Draws a bezeled
 * screen (with a thin "menu bar" strip when `main`) on a stand, labeled with
 * the display name. Selectable, with a system-blue ring when `selected`.
 */
function DisplayTile({
  name = "Display",
  width = 132,
  ratio = 16 / 10,
  main = false,
  mirrored = false,
  selected = false,
  onClick,
  style = {}
}) {
  const screenH = Math.round(width / ratio);
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    style: {
      display: "inline-flex",
      flexDirection: "column",
      alignItems: "center",
      cursor: onClick ? "pointer" : "default",
      userSelect: "none",
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width,
      height: screenH,
      borderRadius: 6,
      padding: 3,
      background: "#0b0b0c",
      boxShadow: selected ? "0 0 0 2.5px var(--accent), 0 6px 16px rgba(0,0,0,0.28)" : "0 4px 12px rgba(0,0,0,0.22)",
      transition: "box-shadow var(--dur-fast) var(--ease-out)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: "relative",
      width: "100%",
      height: "100%",
      borderRadius: 3,
      overflow: "hidden",
      background: mirrored ? "repeating-linear-gradient(135deg,#2b4a6b,#2b4a6b 6px,#244362 6px,#244362 12px)" : "linear-gradient(160deg,#1f6dd6 0%,#1857b0 60%,#15498f 100%)",
      display: "flex",
      flexDirection: "column"
    }
  }, main && /*#__PURE__*/React.createElement("div", {
    style: {
      height: "16%",
      minHeight: 4,
      background: "rgba(255,255,255,0.22)",
      backdropFilter: "blur(2px)"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      font: "var(--weight-medium) 10px/1 var(--font-text)",
      color: "rgba(255,255,255,0.9)"
    }
  }, mirrored ? "Mirrored" : ""))), /*#__PURE__*/React.createElement("div", {
    style: {
      width: width * 0.12,
      height: width * 0.07,
      background: "#a8a8ad"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      width: width * 0.34,
      height: 3,
      borderRadius: 2,
      background: "#b8b8bd"
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 6,
      display: "flex",
      alignItems: "center",
      gap: 5,
      font: "var(--weight-regular) var(--text-subhead)/1 var(--font-text)",
      color: "var(--label-primary)"
    }
  }, name, main && /*#__PURE__*/React.createElement("span", {
    style: {
      font: "var(--weight-medium) var(--text-caption)/1 var(--font-text)",
      color: "var(--label-secondary)"
    }
  }, "\xB7 Main")));
}
Object.assign(__ds_scope, { DisplayTile });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/display/DisplayTile.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Badge.jsx
try { (() => {
/**
 * Small status pill. `tone` maps to the semantic palette; `solid` fills
 * the pill, otherwise it's a soft tint with colored text.
 */
function Badge({
  tone = "neutral",
  solid = false,
  children,
  style = {}
}) {
  const colors = {
    neutral: "var(--label-secondary)",
    accent: "var(--accent)",
    green: "var(--green)",
    orange: "var(--orange)",
    red: "var(--red)"
  };
  const c = colors[tone] || colors.neutral;
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline-flex",
      alignItems: "center",
      gap: 4,
      height: 16,
      padding: "0 6px",
      borderRadius: "var(--radius-xs)",
      font: "var(--weight-medium) var(--text-caption)/1 var(--font-text)",
      letterSpacing: "0.01em",
      background: solid ? c : "color-mix(in srgb, " + (tone === "neutral" ? "var(--fill-primary)" : c) + " 14%, transparent)",
      color: solid ? "#fff" : tone === "neutral" ? "var(--label-secondary)" : c,
      whiteSpace: "nowrap",
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Badge.jsx", error: String((e && e.message) || e) }); }

// components/feedback/InlineBanner.jsx
try { (() => {
/**
 * Inline confirmation / recovery banner for potentially disruptive actions
 * (resolution change, disconnect). Shows a message and action buttons, e.g.
 * "Keep changes / Revert" with an optional countdown. `tone` colors the rail.
 */
function InlineBanner({
  tone = "accent",
  icon = null,
  title,
  message,
  countdown = null,
  actions = null,
  style = {}
}) {
  const tones = {
    accent: "var(--accent)",
    orange: "var(--orange)",
    red: "var(--red)",
    green: "var(--green)"
  };
  const rail = tones[tone] || tones.accent;
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "flex-start",
      gap: 9,
      padding: "10px 12px",
      background: "var(--card-bg)",
      borderRadius: "var(--radius-md)",
      boxShadow: "var(--shadow-card)",
      borderLeft: `2.5px solid ${rail}`,
      ...style
    }
  }, icon && /*#__PURE__*/React.createElement("div", {
    style: {
      color: rail,
      marginTop: 1,
      flex: "none"
    }
  }, icon), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: "var(--weight-semibold) var(--text-body)/1.3 var(--font-text)",
      color: "var(--label-primary)"
    }
  }, title), message && /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 1,
      font: "var(--weight-regular) var(--text-subhead)/1.35 var(--font-text)",
      color: "var(--label-secondary)"
    }
  }, message), actions && /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 6,
      marginTop: 8
    }
  }, actions)), countdown != null && /*#__PURE__*/React.createElement("div", {
    style: {
      flex: "none",
      font: "var(--weight-medium) var(--text-subhead)/1 var(--font-mono)",
      color: "var(--label-secondary)",
      fontVariantNumeric: "tabular-nums"
    }
  }, countdown, "s"));
}
Object.assign(__ds_scope, { InlineBanner });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/InlineBanner.jsx", error: String((e && e.message) || e) }); }

// components/layout/Card.jsx
try { (() => {
/**
 * Grouped "inset" container — the white rounded card that holds a list of
 * setting rows, as in System Settings. Optional `title` renders a small
 * group header above the card.
 */
function Card({
  title,
  footnote,
  children,
  padded = false,
  style = {}
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      ...style
    }
  }, title && /*#__PURE__*/React.createElement("div", {
    style: {
      font: "var(--weight-regular) var(--text-subhead)/1.3 var(--font-text)",
      color: "var(--label-secondary)",
      padding: "0 10px 6px"
    }
  }, title), /*#__PURE__*/React.createElement("div", {
    style: {
      background: "var(--card-bg)",
      borderRadius: "var(--radius-md)",
      boxShadow: "var(--shadow-card)",
      overflow: "hidden",
      padding: padded ? "var(--space-6)" : 0
    }
  }, children), footnote && /*#__PURE__*/React.createElement("div", {
    style: {
      font: "var(--weight-regular) var(--text-footnote)/1.35 var(--font-text)",
      color: "var(--label-secondary)",
      padding: "6px 10px 0"
    }
  }, footnote));
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/Card.jsx", error: String((e && e.message) || e) }); }

// components/layout/Divider.jsx
try { (() => {
/** Hairline separator between rows. Inset from the left to clear leading glyphs. */
function Divider({
  inset = 11,
  style = {}
}) {
  return /*#__PURE__*/React.createElement("div", {
    role: "separator",
    style: {
      height: 0.5,
      marginLeft: inset,
      background: "var(--separator)",
      ...style
    }
  });
}
Object.assign(__ds_scope, { Divider });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/Divider.jsx", error: String((e && e.message) || e) }); }

// components/layout/Row.jsx
try { (() => {
/**
 * Settings row: leading label (+ optional secondary line) on the left,
 * a trailing control (children) on the right. Hoverable when `onClick`.
 */
function Row({
  label,
  secondary,
  leading = null,
  children,
  onClick,
  selected = false,
  height,
  style = {}
}) {
  const [hover, setHover] = React.useState(false);
  const interactive = !!onClick;
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: "flex",
      alignItems: "center",
      gap: 9,
      minHeight: height || "var(--row-h-lg)",
      padding: "5px 11px",
      background: selected ? "var(--accent-tint)" : interactive && hover ? "var(--row-hover)" : "transparent",
      cursor: interactive ? "pointer" : "default",
      transition: "background var(--dur-fast) var(--ease-out)",
      ...style
    }
  }, leading, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      minWidth: 0,
      flex: 1
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      font: "var(--weight-regular) var(--text-body)/1.25 var(--font-text)",
      color: "var(--label-primary)",
      overflow: "hidden",
      textOverflow: "ellipsis",
      whiteSpace: "nowrap"
    }
  }, label), secondary && /*#__PURE__*/React.createElement("span", {
    style: {
      font: "var(--weight-regular) var(--text-subhead)/1.3 var(--font-text)",
      color: "var(--label-secondary)",
      overflow: "hidden",
      textOverflow: "ellipsis",
      whiteSpace: "nowrap"
    }
  }, secondary)), children != null && /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 6,
      flex: "none"
    }
  }, children));
}
Object.assign(__ds_scope, { Row });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/layout/Row.jsx", error: String((e && e.message) || e) }); }

// ui_kits/menubar/MenuBarPopover.js
try { (() => {
/* OpenDisplay — menu-bar popover (primary surface).
   Composes DS primitives + ODIcons. Registers window.MenuBarPopover. */
(function () {
  const {
    Slider,
    Switch,
    SegmentedControl,
    IconButton,
    Badge,
    Button
  } = window.OpenDisplayDesignSystem_1a53d9;
  const I = window.ODIcons;
  const h = React.createElement;
  const SECTION = {
    font: "var(--weight-semibold) 11px/1 var(--font-text)",
    letterSpacing: "0.03em",
    textTransform: "uppercase",
    color: "var(--label-tertiary)",
    padding: "2px 8px 6px"
  };
  function GlyphTile({
    icon,
    tone
  }) {
    return h("div", {
      style: {
        width: 28,
        height: 28,
        flex: "none",
        borderRadius: 7,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        background: tone === "accent" ? "var(--accent)" : "var(--fill-secondary)",
        color: tone === "accent" ? "var(--accent-fg)" : "var(--label-secondary)"
      }
    }, h(icon, {
      size: 17
    }));
  }
  function Chip({
    children,
    on,
    onClick
  }) {
    return h("button", {
      type: "button",
      onClick,
      style: {
        display: "inline-flex",
        alignItems: "center",
        gap: 4,
        height: 22,
        padding: "0 8px",
        borderRadius: 6,
        border: "none",
        cursor: "pointer",
        font: "var(--weight-medium) 11px/1 var(--font-text)",
        background: on ? "var(--accent-tint)" : "var(--fill-tertiary)",
        color: on ? "var(--accent)" : "var(--label-secondary)"
      }
    }, children);
  }
  function SliderRow({
    icon,
    hi,
    value,
    onChange,
    sub
  }) {
    return h("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 9,
        padding: "5px 8px"
      }
    }, h("span", {
      style: {
        color: "var(--label-secondary)",
        flex: "none"
      }
    }, h(icon, {
      size: 15
    })), h("div", {
      style: {
        flex: 1
      }
    }, h(Slider, {
      value,
      onChange,
      trailing: hi ? h("span", {
        style: {
          color: "var(--label-tertiary)"
        }
      }, h(hi, {
        size: 15
      })) : null
    })), h("span", {
      style: {
        width: 30,
        textAlign: "right",
        flex: "none",
        font: "var(--weight-regular) 11px/1 var(--font-text)",
        color: "var(--label-secondary)",
        fontVariantNumeric: "tabular-nums"
      }
    }, sub));
  }
  function DisplayBlock({
    d,
    expanded,
    onToggle,
    update,
    mirror
  }) {
    return h("div", {
      style: {
        borderRadius: 9,
        background: expanded ? "var(--card-bg)" : "transparent",
        boxShadow: expanded ? "var(--shadow-card)" : "none",
        transition: "background var(--dur-fast)",
        marginBottom: 2
      }
    },
    // header
    h("button", {
      type: "button",
      onClick: onToggle,
      style: {
        width: "100%",
        display: "flex",
        alignItems: "center",
        gap: 9,
        padding: "7px 8px",
        background: "transparent",
        border: "none",
        cursor: "pointer",
        textAlign: "left",
        borderRadius: 9
      }
    }, h(GlyphTile, {
      icon: d.main ? I.monitorLines : I.monitor,
      tone: d.main ? "accent" : "neutral"
    }), h("div", {
      style: {
        flex: 1,
        minWidth: 0
      }
    }, h("div", {
      style: {
        font: "var(--weight-semibold) 13px/1.25 var(--font-text)",
        color: "var(--label-primary)",
        whiteSpace: "nowrap",
        overflow: "hidden",
        textOverflow: "ellipsis"
      }
    }, d.name), h("div", {
      style: {
        font: "var(--weight-regular) 11px/1.3 var(--font-text)",
        color: "var(--label-secondary)"
      }
    }, d.res + " · " + d.hz + " Hz")), d.main ? h(Badge, {
      tone: "accent",
      solid: true
    }, "Main") : mirror ? h(Badge, {
      tone: "neutral"
    }, "Mirrored") : h("span", {
      style: {
        width: 7,
        height: 7,
        borderRadius: 99,
        background: "var(--green)",
        flex: "none"
      }
    }), h("span", {
      style: {
        color: "var(--label-tertiary)",
        display: "flex",
        transform: expanded ? "rotate(90deg)" : "none",
        transition: "transform var(--dur-fast)"
      }
    }, h(I.chevronRight, {
      size: 15
    }))), expanded && h("div", {
      style: {
        padding: "0 2px 8px"
      }
    }, h(SliderRow, {
      icon: I.sunDim,
      hi: I.sunMax,
      value: d.brightness,
      onChange: v => update({
        brightness: v
      }),
      sub: d.brightness + "%"
    }), d.audio && h(SliderRow, {
      icon: I.speaker,
      hi: I.speakerWave,
      value: d.volume,
      onChange: v => update({
        volume: v
      }),
      sub: d.volume + "%"
    }), h("div", {
      style: {
        display: "flex",
        flexWrap: "wrap",
        gap: 6,
        padding: "6px 8px 2px"
      }
    }, h(Chip, {
      on: d.hdr,
      onClick: () => update({
        hdr: !d.hdr
      })
    }, [h(I.bolt, {
      key: "i",
      size: 12
    }), " HDR"]), h(Chip, {
      on: d.trueTone,
      onClick: () => update({
        trueTone: !d.trueTone
      })
    }, "True Tone"), h(Chip, {}, [d.res]), h(Chip, {}, [d.hz + " Hz"]))));
  }
  window.MenuBarPopover = function MenuBarPopover() {
    const [displays, setDisplays] = React.useState([{
      id: "a",
      name: "Studio Display",
      res: "2056 × 1329",
      hz: 60,
      brightness: 78,
      volume: 40,
      audio: true,
      hdr: true,
      trueTone: true,
      main: true
    }, {
      id: "b",
      name: "Built-in Retina",
      res: "1800 × 1169",
      hz: 120,
      brightness: 64,
      volume: 55,
      audio: true,
      hdr: false,
      trueTone: true,
      main: false
    }, {
      id: "c",
      name: "LG UltraFine 4K",
      res: "2560 × 1440",
      hz: 60,
      brightness: 50,
      volume: 0,
      audio: false,
      hdr: false,
      trueTone: false,
      main: false
    }]);
    const [expanded, setExpanded] = React.useState("a");
    const [mirror, setMirror] = React.useState(false);
    const [preset, setPreset] = React.useState("work");
    const update = (id, patch) => setDisplays(ds => ds.map(d => d.id === id ? {
      ...d,
      ...patch
    } : d));
    return h("div", {
      style: {
        width: 320,
        background: "var(--panel-bg)",
        WebkitBackdropFilter: "var(--blur-thick)",
        backdropFilter: "var(--blur-thick)",
        borderRadius: "var(--radius-xl)",
        boxShadow: "var(--shadow-popover)",
        padding: 8,
        fontFamily: "var(--font-text)",
        boxSizing: "border-box"
      }
    },
    // header
    h("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 8,
        padding: "4px 6px 8px"
      }
    }, h("img", {
      src: "../../assets/opendisplay-icon.svg",
      width: 22,
      height: 22,
      alt: ""
    }), h("div", {
      style: {
        flex: 1
      }
    }, h("div", {
      style: {
        font: "var(--weight-semibold) 14px/1 var(--font-text)",
        color: "var(--label-primary)"
      }
    }, "Displays"), h("div", {
      style: {
        font: "var(--weight-regular) 11px/1.3 var(--font-text)",
        color: "var(--label-secondary)"
      }
    }, displays.length + " connected")), h(IconButton, {
      label: "Add virtual display"
    }, h(I.plus, {
      size: 16
    })), h(IconButton, {
      label: "Settings"
    }, h(I.gear, {
      size: 16
    }))), h("div", {
      style: SECTION
    }, "Displays"), displays.map(d => h(DisplayBlock, {
      key: d.id,
      d,
      mirror,
      expanded: expanded === d.id,
      onToggle: () => setExpanded(expanded === d.id ? null : d.id),
      update: patch => update(d.id, patch)
    })), h("div", {
      style: {
        height: 0.5,
        background: "var(--separator)",
        margin: "8px 6px"
      }
    }),
    // presets
    h("div", {
      style: SECTION
    }, "Preset"), h("div", {
      style: {
        padding: "0 6px 8px"
      }
    }, h(SegmentedControl, {
      value: preset,
      onChange: setPreset,
      size: "md",
      options: [{
        value: "work",
        label: "Work"
      }, {
        value: "movie",
        label: "Movie"
      }, {
        value: "present",
        label: "Present"
      }],
      style: {
        width: "100%",
        display: "flex"
      }
    })),
    // footer actions
    h("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 8,
        padding: "2px 6px 4px"
      }
    }, h("button", {
      type: "button",
      onClick: () => setMirror(m => !m),
      style: {
        display: "inline-flex",
        alignItems: "center",
        gap: 6,
        height: 26,
        padding: "0 10px",
        borderRadius: 7,
        border: "none",
        cursor: "pointer",
        background: mirror ? "var(--accent-tint)" : "var(--fill-tertiary)",
        color: mirror ? "var(--accent)" : "var(--label-primary)",
        font: "var(--weight-medium) 12px/1 var(--font-text)"
      }
    }, h(I.mirror, {
      size: 14
    }), "Mirror"), h("div", {
      style: {
        flex: 1
      }
    }), h(Button, {
      variant: "plain"
    }, "Display Settings…")));
  };
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/menubar/MenuBarPopover.js", error: String((e && e.message) || e) }); }

// ui_kits/settings/SettingsWindow.jsx
try { (() => {
/* OpenDisplay — Settings window kit. Registers window.SettingsWindow.
   Uses DS primitives + ODIcons. JSX (loaded via Babel in index.html). */
const {
  Card,
  Row,
  Divider,
  Switch,
  Select,
  SegmentedControl,
  Button,
  Badge,
  Slider,
  DisplayTile,
  InlineBanner,
  IconButton,
  Checkbox
} = window.OpenDisplayDesignSystem_1a53d9;
const I = window.ODIcons;
const DISPLAYS = [{
  id: "studio",
  name: "Studio Display",
  res: "2056 × 1329",
  native: "5120 × 2880",
  hz: [60],
  rot: 0,
  main: true,
  hdr: true,
  trueTone: true,
  brightness: 78,
  kind: "external"
}, {
  id: "builtin",
  name: "Built-in Retina",
  res: "1800 × 1169",
  native: "3456 × 2234",
  hz: [120, 60],
  rot: 0,
  main: false,
  hdr: true,
  trueTone: true,
  brightness: 64,
  kind: "builtin"
}, {
  id: "lg",
  name: "LG UltraFine 4K",
  res: "2560 × 1440",
  native: "3840 × 2160",
  hz: [60],
  rot: 0,
  main: false,
  hdr: false,
  trueTone: false,
  brightness: 50,
  kind: "external"
}];
function TitleBar({
  title
}) {
  const dot = c => ({
    width: 12,
    height: 12,
    borderRadius: 99,
    background: c
  });
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      height: 38,
      padding: "0 14px",
      gap: 8,
      borderBottom: "0.5px solid var(--separator)",
      flex: "none"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: dot("#ff5f57")
  }), /*#__PURE__*/React.createElement("span", {
    style: dot("#febc2e")
  }), /*#__PURE__*/React.createElement("span", {
    style: dot("#28c840")
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      textAlign: "center",
      marginLeft: -52,
      font: "var(--weight-semibold) 13px/1 var(--font-text)",
      color: "var(--label-primary)"
    }
  }, title));
}
function SidebarItem({
  icon,
  label,
  sub,
  active,
  badge,
  onClick
}) {
  const [hover, setHover] = React.useState(false);
  return /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => setHover(false),
    style: {
      display: "flex",
      alignItems: "center",
      gap: 8,
      width: "100%",
      textAlign: "left",
      padding: "5px 8px",
      border: "none",
      borderRadius: 7,
      cursor: "pointer",
      background: active ? "var(--accent)" : hover ? "var(--row-hover)" : "transparent",
      color: active ? "var(--accent-fg)" : "var(--label-primary)"
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: "flex",
      flex: "none",
      width: 22,
      height: 22,
      alignItems: "center",
      justifyContent: "center",
      borderRadius: 5,
      background: active ? "rgba(255,255,255,0.22)" : "var(--fill-tertiary)",
      color: active ? "var(--accent-fg)" : "var(--label-secondary)"
    }
  }, React.createElement(icon, {
    size: 14
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: "block",
      font: "var(--weight-regular) 13px/1.2 var(--font-text)",
      whiteSpace: "nowrap",
      overflow: "hidden",
      textOverflow: "ellipsis"
    }
  }, label), sub && /*#__PURE__*/React.createElement("span", {
    style: {
      display: "block",
      font: "var(--weight-regular) 11px/1.2 var(--font-text)",
      color: active ? "rgba(255,255,255,0.8)" : "var(--label-secondary)"
    }
  }, sub)), badge);
}
function ArrangeCanvas({
  displays,
  selected,
  setSelected,
  mirror
}) {
  return /*#__PURE__*/React.createElement(Card, {
    title: "Arrangement",
    footnote: "Drag displays to rearrange. The bar marks the main display; drag it to move the menu bar."
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: "26px 16px 20px",
      display: "flex",
      gap: 30,
      alignItems: "flex-end",
      justifyContent: "center",
      background: "linear-gradient(180deg,#f6f7f9,#eceef1)"
    }
  }, displays.map(d => /*#__PURE__*/React.createElement(DisplayTile, {
    key: d.id,
    name: d.name.split(" ").slice(-1)[0] === "Display" ? "Studio" : d.name,
    width: d.kind === "builtin" ? 118 : 150,
    main: d.main,
    mirrored: mirror && !d.main,
    selected: selected === d.id,
    onClick: () => setSelected(d.id)
  }))));
}
function DisplayDetail({
  d,
  patch
}) {
  const [mode, setMode] = React.useState("default");
  const [pending, setPending] = React.useState(null); // {label, prev}
  const [count, setCount] = React.useState(0);
  React.useEffect(() => {
    if (!pending) return;
    if (count <= 0) {
      revert();
      return;
    }
    const t = setTimeout(() => setCount(c => c - 1), 1000);
    return () => clearTimeout(t);
  }, [pending, count]);
  function applyRisky(label) {
    setPending({
      label
    });
    setCount(12);
  }
  function keep() {
    setPending(null);
  }
  function revert() {
    setPending(null);
  }
  const scaled = ["1280 × 832", "1496 × 967", d.res, "2304 × 1496", d.native];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 16
    }
  }, pending && /*#__PURE__*/React.createElement(InlineBanner, {
    tone: "orange",
    icon: React.createElement(I.info, {
      size: 18
    }),
    title: "Keep changed display setting?",
    message: pending.label + " — reverting automatically if not confirmed.",
    countdown: count,
    actions: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Button, {
      variant: "accent",
      size: "sm",
      onClick: keep
    }, "Keep Changes"), /*#__PURE__*/React.createElement(Button, {
      variant: "secondary",
      size: "sm",
      onClick: revert
    }, "Revert"))
  }), /*#__PURE__*/React.createElement(Card, {
    title: "Resolution",
    footnote: "\u201CDefault\u201D picks the best balance of space and clarity. Scaled resolutions use HiDPI rendering."
  }, /*#__PURE__*/React.createElement(Row, {
    label: "Resolution"
  }, /*#__PURE__*/React.createElement(SegmentedControl, {
    value: mode,
    onChange: setMode,
    options: [{
      value: "default",
      label: "Default"
    }, {
      value: "scaled",
      label: "Scaled"
    }]
  })), mode === "scaled" && /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Row, {
    label: "Scaled size",
    secondary: "Larger text \u2194 More space"
  }, /*#__PURE__*/React.createElement(Select, {
    value: d.res,
    onChange: v => applyRisky("Resolution → " + v),
    options: scaled
  }))), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Row, {
    label: "Refresh Rate"
  }, /*#__PURE__*/React.createElement(Select, {
    value: d.hz[0] + " Hz",
    onChange: () => {},
    options: d.hz.map(x => x + " Hz")
  }))), /*#__PURE__*/React.createElement(Card, {
    title: "Appearance"
  }, /*#__PURE__*/React.createElement(Row, {
    label: "Brightness",
    leading: React.createElement(I.sunMax, {
      size: 15
    })
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 168
    }
  }, /*#__PURE__*/React.createElement(Slider, {
    value: d.brightness,
    onChange: v => patch({
      brightness: v
    })
  }))), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Row, {
    label: "High Dynamic Range",
    secondary: d.hdr ? "Supported" : "Not supported on this display"
  }, /*#__PURE__*/React.createElement(Switch, {
    checked: d.hdr,
    disabled: !d.hdr,
    onChange: v => patch({
      hdr: v
    })
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Row, {
    label: "True Tone"
  }, /*#__PURE__*/React.createElement(Switch, {
    checked: d.trueTone,
    onChange: v => patch({
      trueTone: v
    })
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Row, {
    label: "Rotation"
  }, /*#__PURE__*/React.createElement(Select, {
    value: ["Standard", "90°", "180°", "270°"][d.rot],
    onChange: v => applyRisky("Rotation → " + v),
    options: ["Standard", "90°", "180°", "270°"]
  }))), /*#__PURE__*/React.createElement(Card, {
    title: "Use as"
  }, /*#__PURE__*/React.createElement(Row, {
    label: "Use as main display",
    secondary: "Menu bar and Dock appear here"
  }, /*#__PURE__*/React.createElement(Switch, {
    checked: d.main,
    onChange: () => {}
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Row, {
    label: "Color Profile"
  }, /*#__PURE__*/React.createElement(Select, {
    value: "Apple Display (P3)",
    onChange: () => {},
    options: ["Apple Display (P3)", "sRGB IEC61966-2.1", "Adobe RGB (1998)"]
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      gap: 8,
      paddingTop: 2
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    icon: React.createElement(I.eject, {
      size: 13
    }),
    destructive: true
  }, "Disconnect display"), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "plain"
  }, "Save as Preset\u2026")));
}
function SettingsWindow() {
  const [displays, setDisplays] = React.useState(DISPLAYS);
  const [view, setView] = React.useState("studio"); // display id or "arrange"
  const [selected, setSelected] = React.useState("studio");
  const [mirror, setMirror] = React.useState(false);
  const patch = (id, p) => setDisplays(ds => ds.map(d => d.id === id ? {
    ...d,
    ...p
  } : d));
  const current = displays.find(d => d.id === (view === "arrange" ? selected : view));
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width: 760,
      height: 560,
      display: "flex",
      flexDirection: "column",
      background: "var(--content-bg)",
      borderRadius: "var(--radius-2xl)",
      overflow: "hidden",
      boxShadow: "var(--shadow-window)",
      fontFamily: "var(--font-text)"
    }
  }, /*#__PURE__*/React.createElement(TitleBar, {
    title: "Displays"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: "flex",
      minHeight: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 210,
      flex: "none",
      background: "var(--sidebar-bg)",
      borderRight: "0.5px solid var(--separator)",
      padding: 10,
      display: "flex",
      flexDirection: "column",
      gap: 2,
      overflowY: "auto"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      font: "var(--weight-semibold) 11px/1 var(--font-text)",
      color: "var(--label-tertiary)",
      textTransform: "uppercase",
      letterSpacing: "0.03em",
      padding: "2px 8px 6px"
    }
  }, "Connected"), displays.map(d => /*#__PURE__*/React.createElement(SidebarItem, {
    key: d.id,
    icon: d.kind === "builtin" ? I.monitorLines : I.monitor,
    label: d.name,
    sub: d.res,
    active: view === d.id,
    badge: d.main ? /*#__PURE__*/React.createElement(Badge, {
      tone: view === d.id ? "neutral" : "accent",
      solid: view !== d.id
    }, "Main") : null,
    onClick: () => {
      setView(d.id);
      setSelected(d.id);
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 0.5,
      background: "var(--separator)",
      margin: "8px 4px"
    }
  }), /*#__PURE__*/React.createElement(SidebarItem, {
    icon: I.arrows,
    label: "Arrange Displays",
    active: view === "arrange",
    onClick: () => setView("arrange")
  }), /*#__PURE__*/React.createElement(SidebarItem, {
    icon: I.display2,
    label: "Add Virtual Display",
    onClick: () => {}
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 7,
      padding: "6px 8px",
      color: "var(--label-secondary)",
      font: "var(--weight-regular) 11px/1.3 var(--font-text)"
    }
  }, React.createElement(I.sparkles, {
    size: 13
  }), " OpenDisplay 1.4 \xB7 open source")), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      overflowY: "auto",
      padding: "18px 22px",
      background: "var(--window-bg)"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: 460,
      margin: "0 auto"
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      gap: 10,
      marginBottom: 14
    }
  }, /*#__PURE__*/React.createElement("h1", {
    style: {
      margin: 0,
      font: "var(--weight-bold) 22px/1.1 var(--font-display)",
      letterSpacing: "var(--tracking-tight)",
      color: "var(--label-primary)"
    }
  }, view === "arrange" ? "Arrange Displays" : current.name), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), view !== "arrange" && /*#__PURE__*/React.createElement(Badge, {
    tone: "green"
  }, "Connected")), view === "arrange" ? /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      flexDirection: "column",
      gap: 16
    }
  }, /*#__PURE__*/React.createElement(ArrangeCanvas, {
    displays: displays,
    selected: selected,
    setSelected: setSelected,
    mirror: mirror
  }), /*#__PURE__*/React.createElement(Card, null, /*#__PURE__*/React.createElement(Row, {
    label: "Mirror Displays",
    secondary: "Show the same image on all displays"
  }, /*#__PURE__*/React.createElement(Switch, {
    checked: mirror,
    onChange: setMirror
  })), /*#__PURE__*/React.createElement(Divider, null), /*#__PURE__*/React.createElement(Row, {
    label: "Identify displays",
    secondary: "Flash a number on each screen"
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "sm"
  }, "Identify")))) : /*#__PURE__*/React.createElement(DisplayDetail, {
    d: current,
    patch: p => patch(current.id, p)
  })))));
}
window.SettingsWindow = SettingsWindow;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/settings/SettingsWindow.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Checkbox = __ds_scope.Checkbox;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.SegmentedControl = __ds_scope.SegmentedControl;

__ds_ns.Select = __ds_scope.Select;

__ds_ns.Slider = __ds_scope.Slider;

__ds_ns.Stepper = __ds_scope.Stepper;

__ds_ns.Switch = __ds_scope.Switch;

__ds_ns.DisplayTile = __ds_scope.DisplayTile;

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.InlineBanner = __ds_scope.InlineBanner;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.Divider = __ds_scope.Divider;

__ds_ns.Row = __ds_scope.Row;

})();
