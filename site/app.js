/* Simmer website: interactive parts. No dependencies. */
(function () {
  "use strict";

  var SVGNS = "http://www.w3.org/2000/svg";
  var reduceMQ = matchMedia("(prefers-reduced-motion: reduce)");
  var reduced = reduceMQ.matches;
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); };
  var clamp = function (v, a, b) { return Math.max(a, Math.min(b, v)); };
  var lerp = function (a, b, t) { return a + (b - a) * t; };
  function el(name, attrs, parent) {
    var n = document.createElementNS(SVGNS, name);
    for (var k in attrs) n.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(n);
    return n;
  }

  /* ---------------- Theme ---------------- */
  var root = document.documentElement;
  var themeBtn = $("#theme-toggle");
  function syncThemeButton() {
    var dark = root.getAttribute("data-theme") === "dark";
    // Screenshots follow the page theme, not only the system setting.
    $$("source[data-dark]").forEach(function (s) { s.media = dark ? "all" : "not all"; });
    themeBtn.setAttribute("aria-label", dark ? "Switch to light theme" : "Switch to dark theme");
  }
  themeBtn.addEventListener("click", function () {
    var next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    try { localStorage.setItem("simmer-theme", next); } catch (e) {}
    syncThemeButton();
  });
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", function (e) {
    var saved = null;
    try { saved = localStorage.getItem("simmer-theme"); } catch (err) {}
    if (!saved) { root.setAttribute("data-theme", e.matches ? "dark" : "light"); syncThemeButton(); }
  });
  syncThemeButton();

  /* ---------------- Nav border on scroll ---------------- */
  var nav = $(".nav");
  var onScroll = function () { nav.classList.toggle("scrolled", window.scrollY > 8); };
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* ---------------- Shared limit ---------------- */
  var limit = 80;
  var limitListeners = [];
  function setLimit(v, source) {
    v = clamp(Math.round(v), 20, 100);
    if (v === limit && source !== "init") return;
    limit = v;
    limitListeners.forEach(function (fn) { fn(v, source); });
  }

  /* ---------------- Range fill (WebKit) ---------------- */
  function paintRange(input) {
    var p = (input.value - input.min) / (input.max - input.min) * 100;
    input.style.setProperty("--p", p + "%");
  }
  $$('input[type="range"]').forEach(function (r) { paintRange(r); r.addEventListener("input", function () { paintRange(r); }); });

  /* =========================================================
     HERO: the pot and the knob
     ========================================================= */
  var stove = $("#stove");
  var heroEl = $(".hero");
  var heroTitle = $("#hero-title");
  var liquid = $("#liquid");
  var tick = $("#limit-tick");
  var steamG = $("#steam");
  var flamesG = $("#flames");
  var bubblesG = $("#bubbles");
  var glow = $("#glow");
  var gA = $("#g-fill-a"), gB = $("#g-fill-b");
  var hazeNoise = $("#haze-noise"), hazeMap = $("#haze-map");

  var INNER = { x: 104, y: 132, w: 112, h: 184 };
  var shown = reduced ? limit : 0;   // displayed level, eases toward the limit
  var heat = 0.75;

  // Flames
  var flames = [];
  for (var i = 0; i < 9; i++) {
    var fx = 92 + i * 17;
    var p = el("path", { d: "M-7 0C-7-10-2-16 0-30C2-16 7-10 7 0Z" }, flamesG);
    flames.push({ node: p, x: fx, ph: Math.random() * 6.28, f: 7 + Math.random() * 6, edge: Math.abs(i - 4) / 4 });
  }
  // Steam wisps: two puffs per column, staggered
  var wispCols = [
    { x: 160, th: 0.18 }, { x: 134, th: 0.42 }, { x: 186, th: 0.42 }, { x: 112, th: 0.78 }, { x: 208, th: 0.78 }
  ];
  var wisps = [];
  wispCols.forEach(function (c, ci) {
    for (var k = 0; k < 2; k++) {
      var w = el("path", { d: "M0 0c9-9-9-18 0-27s-9-18 0-27", "stroke-width": 6, opacity: 0 }, steamG);
      wisps.push({ node: w, col: c, t: (k * 0.5 + ci * 0.17) % 1, sway: Math.random() * 6.28 });
    }
  });
  // Bubbles
  var bubbles = [];
  for (var b = 0; b < 16; b++) {
    var c = el("circle", { r: 3, cx: 160, cy: 400, fill: "rgba(255,255,255,.55)", opacity: 0 }, bubblesG);
    bubbles.push({ node: c, alive: false, x: 0, y: 0, v: 0, r: 0 });
  }
  var bubbleClock = 0;

  function hexLerp(a, b, t) {
    var pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16);
    var r = Math.round(lerp(pa >> 16, pb >> 16, t)), g = Math.round(lerp((pa >> 8) & 255, (pb >> 8) & 255, t)), bl = Math.round(lerp(pa & 255, pb & 255, t));
    return "#" + ((1 << 24) + (r << 16) + (g << 8) + bl).toString(16).slice(1);
  }

  function liquidPath(level, amp, time) {
    var y = INNER.y + INNER.h * (1 - level / 100);
    var d = "M98 " + (y + Math.sin(time * 2.1) * amp).toFixed(2);
    for (var x = 98; x <= 222; x += 6) {
      var yy = y + Math.sin(x * 0.09 + time * 3.1) * amp + Math.sin(x * 0.05 - time * 1.7) * amp * 0.6;
      d += "L" + x + " " + yy.toFixed(2);
    }
    return d + "L222 330L98 330Z";
  }

  function drawPot(dt, time) {
    var h = clamp((shown - 20) / 80, 0, 1);
    heat = h;
    var h3 = h * h * h;
    // liquid
    var amp = reduced ? 0.6 : 0.8 + h3 * 4.2;
    liquid.setAttribute("d", liquidPath(shown, amp, time));
    var ty = INNER.y + INNER.h * (1 - shown / 100);
    tick.setAttribute("y1", ty); tick.setAttribute("y2", ty);
    tick.style.opacity = shown > 98 ? 0 : 0.9;
    gA.setAttribute("stop-color", hexLerp("#ffa53d", "#e3412a", h3));
    gB.setAttribute("stop-color", hexLerp("#ffe08a", "#ff9a3c", h3));
    glow.setAttribute("opacity", (0.2 + h * 0.75).toFixed(3));
    heroEl.style.setProperty("--heat", h.toFixed(3));

    // flames
    flames.forEach(function (f) {
      var flick = reduced ? 1 : 1 + 0.16 * Math.sin(time * f.f + f.ph) + 0.08 * Math.sin(time * f.f * 2.3 + f.ph);
      var sy = (0.28 + h * 0.95) * flick * (1 - f.edge * 0.35);
      var sx = 0.75 + h * 0.35;
      f.node.setAttribute("transform", "translate(" + f.x + " 364) scale(" + sx.toFixed(3) + " " + sy.toFixed(3) + ")");
      f.node.setAttribute("opacity", (0.55 + h * 0.45).toFixed(2));
    });

    // steam
    var life = 4.4 - h * 2.8;
    wisps.forEach(function (w) {
      var intensity = clamp((h - w.col.th) / 0.22, 0, 1) * (0.3 + 0.7 * h);
      if (reduced) {
        w.t = (w.t < 0.5 ? 0.35 : 0.7);
      } else {
        w.t += dt / life;
        if (w.t >= 1) w.t -= 1;
      }
      var t = w.t;
      var sway = Math.sin(time * 1.3 + w.sway) * (2 + h * 3);
      var y = 90 - t * (40 + h * 22);
      var s = 0.8 + t * 0.5 + h * 0.15;
      w.node.setAttribute("transform", "translate(" + (w.col.x + sway).toFixed(2) + " " + y.toFixed(2) + ") scale(" + s.toFixed(3) + ")");
      w.node.setAttribute("opacity", (Math.sin(Math.PI * t) * intensity * 0.75).toFixed(3));
      w.node.setAttribute("stroke-width", (3.5 + h * 4).toFixed(2));
    });

    // bubbles (only near the boil)
    var rate = reduced ? 0 : Math.max(0, h - 0.8) / 0.2 * 14;
    bubbleClock += dt * rate;
    while (bubbleClock >= 1) {
      bubbleClock -= 1;
      var free = bubbles.find(function (x) { return !x.alive; });
      if (free) { free.alive = true; free.x = 112 + Math.random() * 96; free.y = 314; free.v = 26 + Math.random() * 40; free.r = 1.6 + Math.random() * 3.2; }
    }
    bubbles.forEach(function (bb) {
      if (!bb.alive) { bb.node.setAttribute("opacity", 0); return; }
      bb.y -= bb.v * dt * (0.6 + h);
      bb.x += Math.sin(bb.y * 0.12) * 0.25;
      if (bb.y < ty + 4) { bb.alive = false; bb.node.setAttribute("opacity", 0); return; }
      bb.node.setAttribute("cx", bb.x.toFixed(1)); bb.node.setAttribute("cy", bb.y.toFixed(1)); bb.node.setAttribute("r", bb.r.toFixed(1));
      bb.node.setAttribute("opacity", 0.75);
    });

    // heat haze on the headline near the boil
    if (!reduced && shown >= 91) {
      heroTitle.classList.add("hazy");
      var hs = (shown - 90) / 10;
      hazeMap.setAttribute("scale", (hs * 3.2).toFixed(2));
      hazeNoise.setAttribute("baseFrequency", "0.006 " + (0.028 + Math.sin(time * 2.2) * 0.006).toFixed(4));
      hazeNoise.setAttribute("seed", String(Math.floor(time * 6) % 50));
    } else if (heroTitle.classList.contains("hazy")) {
      heroTitle.classList.remove("hazy");
    }
  }

  // Animation loop, runs only while the hero is on screen
  var heroVisible = true, running = false, lastT = 0, clock = 0;
  function frame(ts) {
    if (!running) return;
    var dt = lastT ? Math.min(0.05, (ts - lastT) / 1000) : 0.016;
    lastT = ts; clock += dt;
    shown += (limit - shown) * Math.min(1, dt * (shown < 5 ? 2.2 : 5.5));
    if (Math.abs(limit - shown) < 0.02) shown = limit;
    drawPot(dt, clock);
    requestAnimationFrame(frame);
  }
  function startLoop() {
    if (running || reduced) return;
    running = true; lastT = 0; requestAnimationFrame(frame);
  }
  function stopLoop() { running = false; }
  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (es) {
      heroVisible = es[0].isIntersecting;
      if (heroVisible && !document.hidden) startLoop(); else stopLoop();
    }).observe(stove);
  }
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) stopLoop(); else if (heroVisible) startLoop();
  });

  // Knob
  var knob = $("#knob");
  var knobBody = $("#knob-body");
  var knobArc = $("#knob-arc");
  var scaleG = $("#knob-scale");
  var A0 = -135, A1 = 135;
  var angleOf = function (v) { return A0 + (v - 20) / 80 * (A1 - A0); };
  function polar(r, deg) { var a = deg * Math.PI / 180; return [120 + r * Math.sin(a), 120 - r * Math.cos(a)]; }
  function arcPath(r, a0, a1) {
    var p0 = polar(r, a0), p1 = polar(r, a1);
    return "M" + p0[0].toFixed(2) + " " + p0[1].toFixed(2) + "A" + r + " " + r + " 0 " + (a1 - a0 > 180 ? 1 : 0) + " 1 " + p1[0].toFixed(2) + " " + p1[1].toFixed(2);
  }
  // scale: ticks, the "below the macOS floor" arc, labels
  el("path", { d: arcPath(99, angleOf(20), angleOf(79)), class: "scale-floor" }, scaleG);
  for (var v = 20; v <= 100; v += 5) {
    var major = v % 20 === 0;
    var a = polar(major ? 75 : 78, angleOf(v)), z = polar(major ? 86 : 84, angleOf(v));
    el("line", { x1: a[0], y1: a[1], x2: z[0], y2: z[1], class: "scale-tick" + (major ? " major" : "") }, scaleG);
    if (major) {
      var lp = polar(111, angleOf(v));
      var t = el("text", { x: lp[0].toFixed(1), y: lp[1].toFixed(1), class: "scale-label", "data-v": v }, scaleG);
      t.textContent = String(v);
    }
  }

  var STATES = [
    { max: 45, name: "Barely warm", note: "The lowest wear, for a Mac that almost never leaves the desk." },
    { max: 74, name: "A low simmer", note: "A calm everyday spot for a Mac that is mostly plugged in." },
    { max: 85, name: "A gentle simmer", note: "The sweet spot for a Mac that stays plugged in: plenty of charge, far less wear." },
    { max: 99, name: "Close to the boil", note: "Good for a long day away from a socket. Wear goes up as the charge nears full." },
    { max: 100, name: "A rolling boil", note: "Where a Mac on a charger usually sits all day. Full and warm is how cells age fastest." }
  ];
  var readNum = $("#readout-num"), readName = $("#readout-name"), readNote = $("#readout-note");
  var presets = $$(".presets button");

  function renderKnob(v) {
    knobBody.setAttribute("transform", "rotate(" + angleOf(v).toFixed(2) + " 120 120)");
    knobArc.setAttribute("d", v > 20 ? arcPath(91, angleOf(20), angleOf(v)) : "");
    var st = STATES.find(function (s) { return v <= s.max; });
    readNum.textContent = v;
    readName.textContent = st.name;
    readNote.textContent = st.note;
    knob.setAttribute("aria-valuenow", v);
    knob.setAttribute("aria-valuetext", v + "%, " + st.name.toLowerCase());
    presets.forEach(function (b) { b.setAttribute("aria-pressed", String(+b.dataset.limit === v)); });
    if (reduced) { shown = v; drawPot(0, 0); }
  }
  limitListeners.push(renderKnob);

  var dragging = false, lastAngle = angleOf(limit);
  function valueFromPointer(e) {
    var r = knob.getBoundingClientRect();
    var dx = e.clientX - (r.left + r.width / 2), dy = e.clientY - (r.top + r.height / 2);
    var ang = Math.atan2(dx, -dy) * 180 / Math.PI;
    if (ang < A0 || ang > A1) ang = (lastAngle > 0) ? A1 : A0;   // dead zone at the bottom
    lastAngle = ang;
    return 20 + (ang - A0) / (A1 - A0) * 80;
  }
  knob.addEventListener("pointerdown", function (e) {
    var target = e.target;
    if (target.classList && target.classList.contains("scale-label")) { setLimit(+target.getAttribute("data-v"), "knob"); return; }
    dragging = true;
    knob.setPointerCapture(e.pointerId);
    lastAngle = angleOf(limit);
    setLimit(valueFromPointer(e), "knob");
    e.preventDefault();
  });
  knob.addEventListener("pointermove", function (e) { if (dragging) setLimit(valueFromPointer(e), "knob"); });
  ["pointerup", "pointercancel"].forEach(function (n) { knob.addEventListener(n, function () { dragging = false; }); });
  knob.addEventListener("keydown", function (e) {
    var d = { ArrowUp: 1, ArrowRight: 1, ArrowDown: -1, ArrowLeft: -1, PageUp: 10, PageDown: -10 }[e.key];
    if (d) { setLimit(limit + d, "knob"); e.preventDefault(); }
    else if (e.key === "Home") { setLimit(20, "knob"); e.preventDefault(); }
    else if (e.key === "End") { setLimit(100, "knob"); e.preventDefault(); }
  });
  presets.forEach(function (b) { b.addEventListener("click", function () { setLimit(+b.dataset.limit, "preset"); }); });

  /* =========================================================
     CHARGE SIMULATOR
     ========================================================= */
  var sim = { sailing: true, drift: 5, heat: true, autoDischarge: false, topUp: false };
  var STEP_H = 1 / 6, N = 144;

  function simulate(o) {
    var out = { w: [], g: [], temp: [], heatBands: [], restarts: 0, hot: 0 };
    var pct = 62, gp = 62, temp = 30, latched = false, paused = false, topUp = false, wasCharging = false;
    var heatStart = -1;
    for (var i = 0; i <= N; i++) {
      var h = i * STEP_H;
      out.w.push(pct); out.g.push(gp); out.temp.push(temp);
      if (i === N) break;
      var plugged = !((h >= 8 && h < 9.5) || (h >= 17.5 && h < 19.5));
      var heavy = h >= 9.5 && h < 12;
      if (o.topUp && Math.abs(h - 15) < 1e-6) topUp = true;
      if (!plugged) topUp = false;
      var target = topUp ? 100 : o.limit;

      if (o.heat && !topUp) {
        if (!paused && temp >= 35) paused = true;
        else if (paused && temp < 33) paused = false;
      } else paused = false;
      var wantsDischarge = o.autoDischarge && !topUp && pct > target;

      var charging = false, discharging = false, state;
      if (!plugged) { state = "battery"; pct -= 3.2; }
      else if (wantsDischarge) { state = "discharge"; discharging = true; pct = Math.max(target, pct - 3); }
      else if (topUp) { charging = pct < 100; state = "topup"; }
      else if (paused) { state = "heat"; pct -= 0.22; }
      else if (pct >= target) { if (o.sailing) latched = true; state = "limit"; pct -= 0.22; }
      else if (o.sailing && latched && pct > target - o.drift) { state = "sailing"; pct -= 0.22; }
      else { latched = false; charging = true; state = "charging"; }

      if (charging) {
        var rate = pct < 80 ? 5 : (pct < 95 ? 2.6 : 1.2);
        pct = Math.min(pct + rate, target);
        if (pct >= 100) { pct = 100; topUp = false; }
        if (!wasCharging && plugged) out.restarts++;
      }
      wasCharging = charging;
      // heat-pause bands
      if (state === "heat" && heatStart < 0) heatStart = h;
      if (state !== "heat" && heatStart >= 0) { out.heatBands.push([heatStart, h]); heatStart = -1; }

      // temperature
      var T = 29 + (charging ? 4 : 0) + (heavy ? 7.5 : 0) + (state === "battery" ? 1.5 : 0) + (discharging ? 1 : 0);
      temp += (T - temp) * 0.3;
      if (charging) out.hot = Math.max(out.hot, temp);

      // the same day without a limit
      if (!plugged) gp -= 3.2;
      else if (gp < 100) gp = Math.min(100, gp + (gp < 80 ? 5 : (gp < 95 ? 2.6 : 1.2)));
      pct = clamp(pct, 0, 100); gp = clamp(gp, 0, 100);
    }
    if (heatStart >= 0) out.heatBands.push([heatStart, 24]);
    out.boilW = out.w.slice(0, N).filter(function (x) { return x >= 95; }).length * STEP_H;
    out.boilG = out.g.slice(0, N).filter(function (x) { return x >= 95; }).length * STEP_H;
    return out;
  }

  var chartBox = $("#sim-chart"), svg = $("#chart-svg");
  var cur = null, animFrom = null, animStart = 0, drawn = false, reveal = reduced ? "done" : "pending";
  var fmtH = function (x) { var r = Math.round(x * 10) / 10; return (r % 1 === 0 ? r.toFixed(0) : r.toFixed(1)); };

  function renderChart(data) {
    var W = Math.max(280, chartBox.clientWidth);
    var narrow = W < 520;
    var M = { l: 36, r: 8, t: 14 };
    var HM = narrow ? 220 : 290, GAP = 30, HT = narrow ? 64 : 76, AX = 26;
    var H = M.t + HM + GAP + HT + AX;
    var PW = W - M.l - M.r;
    var x = function (h) { return M.l + h / 24 * PW; };
    var y = function (p) { return M.t + (1 - p / 100) * HM; };
    var tTop = M.t + HM + GAP;
    var yt = function (c) { return tTop + (1 - (c - 25) / 20) * HT; };
    svg.setAttribute("viewBox", "0 0 " + W + " " + H);
    svg.setAttribute("width", W); svg.setAttribute("height", H);
    while (svg.firstChild) svg.removeChild(svg.firstChild);

    var defs = el("defs", {}, svg);
    var lg = el("linearGradient", { id: "c-grad", gradientUnits: "userSpaceOnUse", x1: 0, y1: y(100), x2: 0, y2: y(0) }, defs);
    el("stop", { offset: 0, "stop-color": "#e3412a" }, lg);
    el("stop", { offset: 0.45, "stop-color": "#ff8c2e" }, lg);
    el("stop", { offset: 1, "stop-color": "#ffc94a" }, lg);
    var ag = el("linearGradient", { id: "c-area", x1: 0, y1: 0, x2: 0, y2: 1 }, defs);
    el("stop", { offset: 0, "stop-color": "#ff8c2e", "stop-opacity": 0.28 }, ag);
    el("stop", { offset: 1, "stop-color": "#ff8c2e", "stop-opacity": 0 }, ag);

    // on-battery bands
    [[8, 9.5], [17.5, 19.5]].forEach(function (r) {
      el("rect", { x: x(r[0]), y: M.t, width: x(r[1]) - x(r[0]), height: tTop + HT - M.t, class: "c-unplugged" }, svg);
    });
    // heat pause bands
    data.heatBands.forEach(function (r) {
      el("rect", { x: x(r[0]), y: M.t, width: Math.max(2, x(r[1]) - x(r[0])), height: tTop + HT - M.t, class: "c-heat" }, svg);
    });
    // grid
    [0, 25, 50, 75, 100].forEach(function (p) {
      el("line", { x1: M.l, x2: W - M.r, y1: y(p), y2: y(p), class: "c-grid" }, svg);
      var t = el("text", { x: M.l - 8, y: y(p) + 4, "text-anchor": "end", class: "c-axis" }, svg); t.textContent = p + "%";
    });
    // sailing band
    if (sim.sailing) {
      el("rect", { x: M.l, y: y(sim.limit), width: PW, height: y(sim.limit - sim.drift) - y(sim.limit), class: "c-band" }, svg);
    }
    // limit line
    el("line", { x1: M.l, x2: W - M.r, y1: y(sim.limit), y2: y(sim.limit), class: "c-limit" }, svg);
    var lt = el("text", { x: W - M.r - 4, y: y(sim.limit) + (sim.limit > 90 ? 16 : -7), "text-anchor": "end", class: "c-tag c-tag-limit" }, svg);
    lt.textContent = "Limit " + sim.limit + "%";

    function pathOf(arr, fy) {
      var d = "";
      for (var i = 0; i < arr.length; i++) d += (i ? "L" : "M") + x(i * STEP_H).toFixed(1) + " " + fy(arr[i]).toFixed(1);
      return d;
    }
    var ghost = el("path", { d: pathOf(data.g, y), class: "c-ghost" }, svg);
    var gt = el("text", { x: x(2.2), y: y(100) - 6, class: "c-tag c-tag-muted" }, svg);
    gt.textContent = "Without a limit";
    el("path", { d: pathOf(data.w, y) + "L" + x(24) + " " + y(0) + "L" + x(0) + " " + y(0) + "Z", class: "c-area" }, svg);
    var line = el("path", { d: pathOf(data.w, y), class: "c-line" }, svg);

    // temperature strip
    [25, 35, 45].forEach(function (c) {
      if (c === 35) el("line", { x1: M.l, x2: W - M.r, y1: yt(c), y2: yt(c), class: "c-thresh" }, svg);
      else el("line", { x1: M.l, x2: W - M.r, y1: yt(c), y2: yt(c), class: "c-grid" }, svg);
      var t = el("text", { x: M.l - 8, y: yt(c) + 4, "text-anchor": "end", class: "c-axis" }, svg); t.textContent = c + "°";
    });
    el("path", { d: pathOf(data.temp, yt), class: "c-temp" }, svg);
    var tt = el("text", { x: M.l + 4, y: tTop - 8, class: "c-tag c-tag-heat" }, svg);
    tt.textContent = "Battery temperature";

    // x axis
    [0, 6, 12, 18, 24].forEach(function (hh) {
      var t = el("text", { x: x(hh), y: H - 6, "text-anchor": hh === 0 ? "start" : (hh === 24 ? "end" : "middle"), class: "c-axis" }, svg);
      t.textContent = (hh < 10 ? "0" : "") + hh + ":00";
    });

    if (reveal === "pending") {
      var len = line.getTotalLength();
      line.style.strokeDasharray = len + " " + len;
      line.style.strokeDashoffset = len;
    }
    return line;
  }

  function lerpData(a, b, t) {
    var mix = function (x, y) { return x.map(function (v, i) { return lerp(v, y[i], t); }); };
    return { w: mix(a.w, b.w), g: mix(a.g, b.g), temp: mix(a.temp, b.temp), heatBands: b.heatBands };
  }

  function updateStats(d) {
    $("#st-boil-with").textContent = fmtH(d.boilW);
    $("#st-boil-without").textContent = fmtH(d.boilG);
    $("#st-restarts").textContent = d.restarts;
    $("#st-hot").textContent = d.hot ? d.hot.toFixed(1) + " °C" : "No charging";
  }

  function runSim(animate) {
    sim.limit = limit;
    var next = simulate(sim);
    updateStats(next);
    if (!cur || !animate || reduced || !drawn) { cur = next; renderChart(cur); return; }
    animFrom = cur; animStart = performance.now();
    var target = next;
    cur = next;
    (function step(ts) {
      var t = Math.min(1, (ts - animStart) / 320);
      var e = 1 - Math.pow(1 - t, 3);
      renderChart(t < 1 ? lerpData(animFrom, target, e) : target);
      if (t < 1 && cur === target) requestAnimationFrame(step);
    })(performance.now());
  }

  // controls
  var simLimit = $("#sim-limit"), simLimitOut = $("#sim-limit-out");
  var drift = $("#sim-drift"), driftOut = $("#sim-drift-out");
  simLimit.addEventListener("input", function () { setLimit(+simLimit.value, "sim"); });
  drift.addEventListener("input", function () { sim.drift = +drift.value; driftOut.textContent = drift.value + "%"; runSim(true); });
  $$("#sim .switch").forEach(function (sw) {
    sw.addEventListener("click", function () {
      var on = sw.getAttribute("aria-checked") !== "true";
      sw.setAttribute("aria-checked", String(on));
      sim[sw.dataset.key] = on;
      if (sw.dataset.key === "sailing") {
        $("#lg-sailing").hidden = !on;
        sw.closest(".ctl").classList.toggle("is-off", !on);
        drift.disabled = !on;
      }
      runSim(true);
    });
  });

  var simQueued = false;
  limitListeners.push(function (v, source) {
    if (source !== "sim") { simLimit.value = v; paintRange(simLimit); }
    simLimitOut.textContent = v + "%";
    if (!simQueued) { simQueued = true; requestAnimationFrame(function () { simQueued = false; runSim(true); }); }
  });

  // first draw, then animate the line in when it scrolls into view
  if ("IntersectionObserver" in window && !reduced) {
    var io = new IntersectionObserver(function (es) {
      if (!es[0].isIntersecting) return;
      io.disconnect();
      reveal = "running";
      var line = svg.querySelector(".c-line");
      if (line) {
        line.getBoundingClientRect();
        line.style.transition = "stroke-dashoffset 1.8s cubic-bezier(.5,0,.2,1)";
        line.style.strokeDashoffset = "0";
      }
      setTimeout(function () {
        reveal = "done"; drawn = true;
        var l = svg.querySelector(".c-line");
        if (l) { l.style.strokeDasharray = ""; l.style.transition = ""; }
      }, 1900);
    }, { threshold: 0.35 });
    io.observe(chartBox);
  } else { drawn = true; reveal = "done"; }

  var resizeT;
  window.addEventListener("resize", function () {
    clearTimeout(resizeT);
    resizeT = setTimeout(function () { if (cur) renderChart(cur); }, 120);
  });

  /* =========================================================
     TABS
     ========================================================= */
  $$("[data-tabs]").forEach(function (box) {
    var tabs = $$('[role="tab"]', box);
    function select(tab, focus) {
      tabs.forEach(function (t) {
        var on = t === tab;
        t.setAttribute("aria-selected", String(on));
        t.tabIndex = on ? 0 : -1;
        document.getElementById(t.getAttribute("aria-controls")).hidden = !on;
      });
      if (focus) tab.focus();
    }
    tabs.forEach(function (t, i) {
      t.addEventListener("click", function () { select(t); });
      t.addEventListener("keydown", function (e) {
        var j = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: tabs.length - 1 }[e.key];
        if (j === undefined) return;
        e.preventDefault();
        select(tabs[(j + tabs.length) % tabs.length], true);
      });
    });
  });

  /* Radio groups made of buttons (roving focus with arrow keys) */
  function radioGroup(group, onChange) {
    var items = $$('[role="radio"]', group);
    function pick(btn, focus) {
      items.forEach(function (b) { var on = b === btn; b.setAttribute("aria-checked", String(on)); b.tabIndex = on ? 0 : -1; });
      if (focus) btn.focus();
      onChange(btn);
    }
    items.forEach(function (b, i) {
      b.tabIndex = b.getAttribute("aria-checked") === "true" ? 0 : -1;
      b.addEventListener("click", function () { pick(b); });
      b.addEventListener("keydown", function (e) {
        var d = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
        if (!d) return;
        e.preventDefault();
        pick(items[(i + d + items.length) % items.length], true);
      });
    });
  }

  /* =========================================================
     POWER FLOW
     ========================================================= */
  var FLOW = {
    charging:  { a: "62.0 W", m: "14.0 W", b: "+48.0 W", bl: "Charging", aw: 62, bw: 48, bdir: 1, adapterOn: true,
                 cap: "The charger powers the Mac and charges the battery at the same time." },
    limit:     { a: "19.1 W", m: "18.6 W", b: "0.0 W", bl: "Resting", aw: 19, bw: 0, bdir: 0, adapterOn: true,
                 cap: "At the limit, the charger powers the Mac and the battery rests. Only charging pauses, not the power." },
    discharge: { a: "0.0 W", m: "14.2 W", b: "−14.2 W", bl: "Discharging", aw: 0, bw: 14, bdir: -1, adapterOn: false,
                 cap: "Simmer switches the adapter input off, so the battery runs the Mac down to the limit. The cable stays plugged in." },
    battery:   { a: "–", m: "9.4 W", b: "−9.4 W", bl: "Discharging", aw: 0, bw: 9, bdir: -1, adapterOn: false,
                 cap: "Unplugged, the battery runs the Mac as usual. Simmer keeps watching the sessions and the drain." }
  };
  var flowBox = $("#flow");
  function setFlow(mode) {
    var f = FLOW[mode];
    flowBox.dataset.mode = mode;
    $("#w-adapter").textContent = f.a;
    $("#w-mac").textContent = f.m;
    $("#w-battery").textContent = f.b;
    $("#w-battery-label").textContent = f.bl;
    $("#node-adapter").classList.toggle("dim", !f.adapterOn);
    $("#node-adapter span").textContent = mode === "battery" ? "Unplugged" : (mode === "discharge" ? "Switched off" : "Adapter");
    var wa = $("#wire-a"), wb = $("#wire-b");
    wa.classList.toggle("live", f.aw > 0);
    wa.style.setProperty("--dur", clamp(30 / Math.max(f.aw, 1), 0.35, 2) + "s");
    wb.classList.toggle("live", f.bw > 0);
    wb.classList.toggle("reverse", f.bdir < 0);
    wb.classList.toggle("green", f.bdir < 0);
    wb.style.setProperty("--dur", clamp(30 / Math.max(f.bw, 1), 0.35, 2) + "s");
    $("#flow-caption").textContent = f.cap;
  }
  radioGroup($("#flow .seg"), function (b) { setFlow(b.dataset.mode); });
  setFlow("limit");

  /* =========================================================
     MAGSAFE LED PREVIEW
     ========================================================= */
  var led = { mode: "smart", state: "limit" };
  var custom = { charging: "orange", limit: "green", sailing: "green", discharging: "blink-slow", heat: "blink-fast", topup: "orange" };
  var SMART = { charging: "orange", limit: "green", sailing: "green", discharging: "blink-slow", heat: "green", topup: "orange" };
  var STATE_NAMES = { charging: "charging", limit: "limit reached", sailing: "sailing", discharging: "discharging", heat: "heat protection", topup: "top up" };
  var COLOR_NAMES = { green: "green", orange: "orange", "blink-slow": "orange, slow blink", "blink-fast": "orange, fast blink", off: "off", system: "macOS decides" };
  var dot = $("#led-dot"), ledStatus = $("#led-status"), ledCustom = $("#led-custom"), ledColor = $("#led-color");
  var blinking = null;

  function paintDot(c) {
    dot.className = "led-dot";
    if (c === "green" || c === "orange") dot.classList.add(c);
    else if (c === "blink-slow" || c === "blink-fast") dot.classList.add("orange", c);
    else if (c === "system") dot.classList.add("system");
  }
  function renderLED() {
    var c, text;
    if (led.mode === "system") { c = "system"; text = "System mode: macOS controls the light."; }
    else if (led.mode === "off") { c = "off"; text = "Off: the light stays dark, also while charging."; }
    else {
      c = led.mode === "smart" ? SMART[led.state] : custom[led.state];
      var m = led.mode === "smart" ? "Smart" : "Custom";
      text = m + " mode, " + STATE_NAMES[led.state] + ": " + COLOR_NAMES[c] + ".";
    }
    ledCustom.hidden = led.mode !== "custom";
    ledColor.value = custom[led.state];
    if (!blinking) paintDot(c);
    ledStatus.textContent = text;
  }
  radioGroup($('[data-group="mode"]'), function (b) { led.mode = b.dataset.v; renderLED(); });
  radioGroup($('[data-group="state"]'), function (b) { led.state = b.dataset.v; renderLED(); });
  ledColor.addEventListener("change", function () { custom[led.state] = ledColor.value; renderLED(); });

  var PATTERNS = {
    blinkGreen: [["green", .4], ["off", .4]],
    blinkOrange: [["orange", .4], ["off", .4]],
    alternate: [["green", .4], ["orange", .4]],
    heartbeat: [["orange", .25], ["off", .25], ["orange", .25], ["off", .5]]
  };
  $$("[data-blink]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var name = btn.dataset.blink, steps = [], one, reps = 3;
      if (name === "level") {
        var n = clamp(Math.round(limit / 10), 1, 10);
        one = [];
        for (var i = 0; i < n; i++) one.push(["green", .3], ["off", .3]);
        one[one.length - 1] = ["off", 1];
        reps = 1;
        ledStatus.textContent = "Blink the charge level: " + n + " green blinks for " + limit + "%.";
      } else {
        one = PATTERNS[name];
        ledStatus.textContent = btn.textContent + ", three times. Then the light goes back to its mode.";
      }
      for (var r = 0; r < reps; r++) steps = steps.concat(one);
      if (blinking) clearTimeout(blinking);
      var k = 0;
      (function next() {
        if (k >= steps.length) { blinking = null; renderLED(); return; }
        paintDot(steps[k][0]);
        blinking = setTimeout(next, steps[k][1] * 1000);
        k++;
      })();
    });
  });
  renderLED();

  /* =========================================================
     TERMINAL
     ========================================================= */
  var termBody = $("#term-body");
  var script = termBody.textContent.split("\n");
  function lineNode(text) {
    var span = document.createElement("span");
    if (text.indexOf("$ ") === 0) {
      var p = document.createElement("span"); p.className = "prompt"; p.textContent = "$ ";
      var c = document.createElement("span"); c.className = "cmd"; c.textContent = text.slice(2);
      span.appendChild(p); span.appendChild(c);
    } else { span.className = "out"; span.textContent = text; }
    return span;
  }
  function renderStatic() {
    termBody.textContent = "";
    script.forEach(function (l, i) { termBody.appendChild(lineNode(l)); if (i < script.length - 1) termBody.appendChild(document.createTextNode("\n")); });
  }
  if (reduced || !("IntersectionObserver" in window)) {
    renderStatic();
  } else {
    var code = document.createElement("code");
    var caret = document.createElement("span"); caret.className = "caret";
    var termTimer = null, termActive = false, li = 0, ci = 0;
    function resetTerm() { termBody.textContent = ""; code = document.createElement("code"); termBody.appendChild(code); li = 0; ci = 0; }
    function tickTerm() {
      if (!termActive) return;
      if (li >= script.length) { termTimer = setTimeout(function () { resetTerm(); tickTerm(); }, 4200); return; }
      var line = script[li];
      if (line.indexOf("$ ") === 0) {
        if (ci === 0) {
          var span = lineNode("$ ");
          span.lastChild.textContent = "";
          code.appendChild(span);
          code.appendChild(caret);
          ci = 2;
          termTimer = setTimeout(tickTerm, 420);
          return;
        }
        var cmdSpan = code.querySelectorAll(".cmd");
        cmdSpan = cmdSpan[cmdSpan.length - 1];
        if (ci < line.length) {
          cmdSpan.textContent = line.slice(2, ci + 1);
          ci++;
          termTimer = setTimeout(tickTerm, 28 + Math.random() * 46);
          return;
        }
        code.removeChild(caret);
        code.appendChild(document.createTextNode("\n"));
        li++; ci = 0;
        termTimer = setTimeout(tickTerm, 260);
        return;
      }
      code.appendChild(lineNode(line));
      code.appendChild(document.createTextNode("\n"));
      li++;
      termTimer = setTimeout(tickTerm, 70);
    }
    resetTerm();
    new IntersectionObserver(function (es) {
      var vis = es[0].isIntersecting;
      if (vis && !termActive) { termActive = true; tickTerm(); }
      else if (!vis && termActive) { termActive = false; clearTimeout(termTimer); }
    }, { threshold: 0.3 }).observe(termBody);
  }

  /* =========================================================
     COPY
     ========================================================= */
  var copyBtn = $("#copy-brew"), copyLabel = $(".copy-label", copyBtn);
  copyLabel.setAttribute("aria-live", "polite");
  copyBtn.addEventListener("click", function () {
    var text = $("#brew-cmd").textContent.trim();
    var done = function () {
      copyBtn.classList.add("done"); copyLabel.textContent = "Copied";
      setTimeout(function () { copyBtn.classList.remove("done"); copyLabel.textContent = "Copy"; }, 2200);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, fallback);
    else fallback();
    function fallback() {
      var ta = document.createElement("textarea");
      ta.value = text; ta.setAttribute("readonly", ""); ta.style.position = "fixed"; ta.style.opacity = "0";
      document.body.appendChild(ta); ta.select();
      try { document.execCommand("copy"); done(); } catch (e) {}
      document.body.removeChild(ta);
    }
  });

  /* ---------------- Start ---------------- */
  setLimit(80, "init");
  drawPot(0, 0);
  if (!reduced) startLoop();
})();
