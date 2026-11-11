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
  var hazeIntroUntil = performance.now() + 2800;   // the headline shimmers for a moment after load

  var INNER = { x: 104, y: 132, w: 112, h: 184 };
  var shown = reduced ? limit : 0;   // displayed level, eases toward the limit
  var heat = 0.75;
  var pot = $("#pot");
  var fxT = { boil0: -1e9, disco0: -1e9, face0: -1e9 };   // easter egg start times (ms)
  var ptr = { cx: 0, cy: 0, lcx: 0, lcy: 0, x: -999, y: -999, vx: 0, vy: 0, on: false, dirty: false };
  var plug = { state: "rest", floor: 20, led: "off" };   // rest: never plugged; in; out (on battery)
  var topUp = false, discharging = false;
  var capEl = $("#jar-cap"), shimmer = $("#shimmer"), foamG = $("#foam"), faceG = $("#face"), eyeR = $("#eye-r");
  var discoG = $("#disco"), discoBand = $("#disco-band"), specksG = $("#specks");
  var idle = { boil: true, disco: true, face: true };   // true forces one reset write
  function potTarget() { return topUp ? 100 : limit; }
  // 0..1 envelope for a timed effect: fades in over `a` s, holds, fades out over `b` s
  function envelope(t0, total, a, b) {
    var t = (performance.now() - t0) / 1000;
    if (t < 0 || t > total) return 0;
    return reduced ? 1 : Math.max(0, Math.min(1, t / a, (total - t) / b));
  }

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
      wisps.push({ node: w, col: c, t: (k * 0.5 + ci * 0.17) % 1, sway: Math.random() * 6.28, ox: 0, oy: 0, vx: 0, vy: 0, puff: 0, lean: 0 });
    }
  });
  // Foam for the boil-over: blobs along the rim and drips down the sides
  var foam = [[100, 7, 2], [114, 10, -1], [130, 12, 1], [148, 13, -2], [166, 13, 1], [184, 12, -1], [200, 11, 2], [216, 8, 0], [124, 8, -9], [158, 9, -10], [192, 8, -8]].map(function (f) {
    return { node: el("circle", { cx: f[0], cy: 117 + f[2], r: 0 }, foamG), r: f[1] };
  });
  var drips = [[89, 64], [99, 30], [221, 40], [231, 72]].map(function (d) {
    return { node: el("rect", { x: d[0] - 4.5, y: 120, width: 9, height: 0, rx: 4.5 }, foamG), len: d[1] };
  });
  // Disco specks that orbit the jar
  var specks = [];
  for (var sp = 0; sp < 12; sp++) specks.push(el("circle", { r: 2.5 + (sp % 3), cx: 0, cy: 0, opacity: 0 }, specksG));
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
    var boil = envelope(fxT.boil0, 4.4, 0.7, 1.3);
    var disco = envelope(fxT.disco0, 6.5, 0.5, 0.9);
    // liquid
    var amp = (reduced ? 0.6 : 0.8 + h3 * 4.2) + boil * 4;
    liquid.setAttribute("d", liquidPath(shown, amp, time));
    var ty = INNER.y + INNER.h * (1 - shown / 100);
    tick.setAttribute("y1", ty); tick.setAttribute("y2", ty);
    tick.style.opacity = shown > 98 ? 0 : 0.9;
    if (disco > 0.02) {
      var hue = (time * 150) % 360;
      gA.setAttribute("stop-color", "hsl(" + hue.toFixed(0) + " 90% 58%)");
      gB.setAttribute("stop-color", "hsl(" + ((hue + 90) % 360).toFixed(0) + " 95% 72%)");
    } else {
      gA.setAttribute("stop-color", hexLerp("#ffa53d", "#e3412a", h3));
      gB.setAttribute("stop-color", hexLerp("#ffe08a", "#ff9a3c", h3));
    }
    glow.setAttribute("opacity", (0.2 + h * 0.75).toFixed(3));
    heroEl.style.setProperty("--heat", h.toFixed(3));

    // flames
    flames.forEach(function (f) {
      var flick = reduced ? 1 : 1 + 0.16 * Math.sin(time * f.f + f.ph) + 0.08 * Math.sin(time * f.f * 2.3 + f.ph);
      var sy = (0.28 + h * 0.95) * flick * (1 - f.edge * 0.35) * (1 + boil * 0.45);
      var sx = 0.75 + h * 0.35;
      f.node.setAttribute("transform", "translate(" + f.x + " 364) scale(" + sx.toFixed(3) + " " + sy.toFixed(3) + ")");
      f.node.setAttribute("opacity", (0.55 + h * 0.45).toFixed(2));
    });

    // steam: rises, bends toward the cursor, puffs away from a quick swipe
    var life = (4.4 - h * 2.8) * (1 - boil * 0.45);
    wisps.forEach(function (w) {
      var intensity = Math.max(boil, clamp((h - w.col.th) / 0.22, 0, 1) * (0.3 + 0.7 * h));
      if (reduced) {
        w.t = (w.t < 0.5 ? 0.35 : 0.7);
      } else {
        w.t += dt / life;
        if (w.t >= 1) w.t -= 1;
      }
      var t = w.t;
      var sway = Math.sin(time * 1.3 + w.sway) * (2 + h * 3);
      var x = w.col.x + sway;
      var y = 90 - t * (40 + h * 22 + boil * 20);
      var s = 0.8 + t * 0.5 + h * 0.15 + boil * 0.3;
      if (!reduced) {
        var gx = 0, gy = 0, lean = 0;
        if (ptr.on) {
          var dx = ptr.x - x, dy = ptr.y - (y - 27 * s), d = Math.sqrt(dx * dx + dy * dy);
          if (d < 120) {
            var f = 1 - d / 120; f *= f;
            lean = clamp(dx / 60, -1, 1) * 26 * f;
            gx = dx * 0.22 * f; gy = dy * 0.08 * f;
          }
          if (d < 46 && w.puff < 0.35 && ptr.vx * ptr.vx + ptr.vy * ptr.vy > 200000) {
            w.vx += clamp(ptr.vx * 0.14, -260, 260); w.vy += clamp(ptr.vy * 0.14, -260, 260); w.puff = 1;
          }
        }
        w.vx += ((gx - w.ox) * 60 - w.vx * 8) * dt;
        w.vy += ((gy - w.oy) * 60 - w.vy * 8) * dt;
        w.ox = clamp(w.ox + w.vx * dt, -70, 70); w.oy = clamp(w.oy + w.vy * dt, -70, 70);
        w.lean += (lean - w.lean) * Math.min(1, dt * 6);
        w.puff = Math.max(0, w.puff - dt * 1.1);
      }
      var p = w.puff;
      w.node.setAttribute("transform", "translate(" + (x + w.ox).toFixed(2) + " " + (y + w.oy).toFixed(2) + ") skewX(" + (-w.lean).toFixed(2) + ") scale(" + (s * (1 + p * 0.7)).toFixed(3) + ")");
      w.node.setAttribute("opacity", (Math.sin(Math.PI * t) * intensity * 0.75 * (1 - p * 0.55) * (1 - morphM)).toFixed(3));
      w.node.setAttribute("stroke-width", (3.5 + h * 4 + p * 3).toFixed(2));
    });

    // bubbles (only near the boil)
    var rate = reduced ? 0 : Math.max(0, h - 0.8) / 0.2 * 14 + boil * 30;
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

    // charging shimmer: a soft band of light that climbs the liquid while the plug charges
    if (plug.led === "orange") {
      var span = 316 - ty + 54, k = reduced ? 0.5 : (time * 0.7) % 1;
      shimmer.setAttribute("y", (316 - k * span).toFixed(1));
      shimmer.setAttribute("opacity", (reduced ? 0.5 : Math.sin(Math.PI * k) * 0.85).toFixed(2));
    } else shimmer.setAttribute("opacity", 0);

    // boil-over: foam on the rim, drips down the sides, the lid rattles (idle frames skip the writes)
    if (boil > 0 || idle.boil) {
      idle.boil = boil > 0;
      foam.forEach(function (f, i) {
        f.node.setAttribute("r", (boil * f.r * (1 + (reduced ? 0 : 0.12 * Math.sin(time * 9 + i * 1.7)))).toFixed(2));
      });
      drips.forEach(function (d, i) {
        d.node.setAttribute("height", (clamp(boil * 1.6 - 0.25 - i * 0.05, 0, 1) * d.len).toFixed(1));
      });
      capEl.setAttribute("transform", boil > 0.01 && !reduced
        ? "translate(" + (Math.sin(time * 47) * 1.6 * boil).toFixed(2) + " " + (-Math.abs(Math.sin(time * 23)) * 5 * boil).toFixed(2) + ")"
        : (boil > 0.01 ? "translate(0 -4)" : ""));
    }

    // disco pot: a mirror ball drops in and specks of light circle the jar
    if (disco > 0 || idle.disco) {
      idle.disco = disco > 0;
      discoG.setAttribute("opacity", disco.toFixed(3));
      discoG.setAttribute("transform", "translate(160 " + (-50 + 74 * Math.min(1, disco * 1.4)).toFixed(1) + ")");
      discoBand.setAttribute("rx", (Math.abs(Math.cos(time * 2.4)) * 13 + 1).toFixed(2));
      specks.forEach(function (s, i) {
        var a = time * (0.9 + (i % 3) * 0.25) + i * 0.52;
        s.setAttribute("cx", (160 + Math.cos(a) * (120 + (i % 4) * 14)).toFixed(1));
        s.setAttribute("cy", (210 + Math.sin(a * 1.3) * (110 - (i % 3) * 20)).toFixed(1));
        s.setAttribute("fill", "hsl(" + ((i * 30 + time * 120) % 360).toFixed(0) + " 95% 65%)");
        s.setAttribute("opacity", (disco * 0.85).toFixed(2));
      });
    }

    // cooked just right: the jar shows a face and winks
    var face = envelope(fxT.face0, 2.8, 0.25, 0.4);
    if (face > 0 || idle.face) {
      idle.face = face > 0;
      faceG.setAttribute("opacity", face.toFixed(3));
      var ft = (performance.now() - fxT.face0) / 1000;
      eyeR.setAttribute("transform", "translate(0 238) scale(1 " + (reduced ? 0.15 : (ft > 1 && ft < 1.35 ? 0.12 : 1)) + ") translate(0 -238)");
    }

    // heat haze on the headline near the boil
    var introHaze = performance.now() < hazeIntroUntil;
    if (!reduced && (shown >= 91 || introHaze || boil > 0)) {
      heroTitle.classList.add("hazy");
      var hs = Math.max((shown - 90) / 10, boil, introHaze ? 0.85 * Math.min(1, (hazeIntroUntil - performance.now()) / 700) : 0);
      hazeMap.setAttribute("scale", (hs * 3.2).toFixed(2));
      hazeNoise.setAttribute("baseFrequency", "0.006 " + (0.028 + Math.sin(time * 2.2) * 0.006).toFixed(4));
      hazeNoise.setAttribute("seed", String(Math.floor(time * 6) % 50));
    } else if (heroTitle.classList.contains("hazy")) {
      heroTitle.classList.remove("hazy");
    }    if (morphM > 0) updLapText();
  }

  // Level of the liquid: eases to the limit, or charges / drains when the plug is used
  function stepLevel(dt) {
    var tg = potTarget();
    if (plug.state === "in") {
      if (shown < tg) shown = Math.min(tg, shown + dt * (shown < 80 ? 9 : 5));
      else if (shown > tg) shown = Math.max(tg, shown - dt * 4);
      return;
    }
    if (plug.state === "out") {
      var fl = Math.min(tg, plug.floor);
      if (shown > fl) shown = Math.max(fl, shown - dt * (plug.rate || 4));
      return;
    }
    shown += (tg - shown) * Math.min(1, dt * (shown < 5 ? 2.2 : 5.5));
    if (Math.abs(tg - shown) < 0.02) shown = tg;
  }

  // Pointer position in pot coordinates, read once per frame before any writes
  function readPointer(dt) {
    if (ptr.dirty) {
      var r = pot.getBoundingClientRect(), k = 320 / (r.width || 320);
      if (ptr.on && dt > 0) {
        ptr.vx = lerp(ptr.vx, (ptr.cx - ptr.lcx) * k / dt, 0.6);
        ptr.vy = lerp(ptr.vy, (ptr.cy - ptr.lcy) * k / dt, 0.6);
      }
      ptr.x = (ptr.cx - r.left) * k; ptr.y = (ptr.cy - r.top) * k;
      ptr.lcx = ptr.cx; ptr.lcy = ptr.cy; ptr.dirty = false;
    } else {
      ptr.vx *= Math.exp(-dt * 12); ptr.vy *= Math.exp(-dt * 12);
    }
  }

  // Animation loop, runs only while the hero is on screen
  var heroVisible = true, running = false, lastT = 0, clock = 0;
  function frame(ts) {
    if (!running) return;
    var dt = lastT ? Math.min(0.05, (ts - lastT) / 1000) : 0.016;
    lastT = ts; clock += dt;
    readPointer(dt);
    stepLevel(dt);
    drawPot(dt, clock);
    updatePlugLed();
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

  // The knob dial, arc and number tween with a cubic ease-in-out. A drag and the intro set them 1:1.
  var knobV = limit, knobRaf = 0, knobTween = null;
  var inOut = function (t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; };
  var outCubic = function (t) { return 1 - Math.pow(1 - t, 3); };
  function paintKnob(v) {
    knobV = v;
    knobBody.setAttribute("transform", "rotate(" + angleOf(v).toFixed(2) + " 120 120)");
    knobArc.setAttribute("d", v > 20.05 ? arcPath(91, angleOf(20), angleOf(v)) : "");
    readNum.textContent = Math.round(v);
  }
  function renderKnob(v, source) {
    var st = STATES.find(function (s) { return v <= s.max; });
    readName.textContent = st.name;
    readNote.textContent = st.note;
    knob.setAttribute("aria-valuenow", v);
    knob.setAttribute("aria-valuetext", v + "%, " + st.name.toLowerCase());
    presets.forEach(function (b) { b.setAttribute("aria-pressed", String(+b.dataset.limit === v)); });
    cancelAnimationFrame(knobRaf);
    if (reduced || source === "knob" || source === "demo" || source === "init" || Math.abs(v - knobV) < 0.01) {
      knobTween = null; paintKnob(v);
    } else {
      // a retarget mid-tween keeps moving (ease-out); a fresh move eases in and out
      var from = knobV, ease = knobTween ? outCubic : inOut, t0 = performance.now();
      var dur = clamp(320 + Math.abs(v - from) * 4, 350, 520);
      knobTween = true;
      (function step(now) {
        var t = clamp((now - t0) / dur, 0, 1);
        paintKnob(from + (v - from) * ease(t));
        if (t < 1) knobRaf = requestAnimationFrame(step); else knobTween = null;
      })(t0);
    }
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

  // Intro: on first load the knob turns by itself for about 3 seconds (80 → 100 → 45 → 80) to show
  // what it does. Any touch, key, wheel or scroll stops it at once. Skipped with reduced motion.
  (function knobIntro() {
    if (reduced) { setTimeout(function () { afterIntro(); }, 900); return; }
    var keys = [[0, 80], [650, 100], [1050, 100], [1800, 45], [2100, 45], [2750, 80]];
    var start = 0, raf = 0, stopped = false;
    function ease(t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }
    function stop() {
      if (stopped) return;
      stopped = true; cancelAnimationFrame(raf);
      ["pointerdown", "keydown", "wheel", "touchstart"].forEach(function (n) { window.removeEventListener(n, stop, true); });
    }
    ["pointerdown", "keydown", "wheel", "touchstart"].forEach(function (n) { window.addEventListener(n, stop, { capture: true, passive: true }); });
    function frame(now) {
      if (stopped) return;
      if (!start) start = now;
      var t = now - start;
      for (var i = 1; i < keys.length; i++) {
        if (t <= keys[i][0]) {
          var a = keys[i - 1], b = keys[i];
          setLimit(a[1] + (b[1] - a[1]) * ease((t - a[0]) / (b[0] - a[0])), "demo");
          raf = requestAnimationFrame(frame);
          return;
        }
      }
      setLimit(80, "demo");
      stop();
      afterIntro();   // only when the sweep finished without any interaction
    }
    setTimeout(function () {
      if (stopped || window.scrollY > 200) { stop(); return; }   // only when the hero is in view
      raf = requestAnimationFrame(frame);
    }, 450);
  })();

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
     TERMINAL: a typed demo, then a shell you can type into
     ========================================================= */
  var termEl = $("#term"), termBody = $("#term-body"), termForm = $("#term-form"), termInput = $("#term-input"), termCaret = $("#term-caret");
  var script = termBody.textContent.split("\n");
  function lineNode(text, cls) {
    var span = document.createElement("span");
    if (!cls && text.indexOf("$ ") === 0) {
      var p = document.createElement("span"); p.className = "prompt"; p.textContent = "$ ";
      var c = document.createElement("span"); c.className = "cmd"; c.textContent = text.slice(2);
      span.appendChild(p); span.appendChild(c);
    } else { span.className = cls || "out"; span.textContent = text; }
    return span;
  }
  function renderStatic() {
    termBody.textContent = "";
    script.forEach(function (l, i) { termBody.appendChild(lineNode(l)); if (i < script.length - 1) termBody.appendChild(document.createTextNode("\n")); });
  }
  var stopDemo = function () {};
  if (reduced || !("IntersectionObserver" in window)) {
    renderStatic();
  } else {
    var code = document.createElement("code");
    var caret = document.createElement("span"); caret.className = "caret";
    var termTimer = null, termActive = false, li = 0, ci = 0;
    var resetTerm = function () { termBody.textContent = ""; code = document.createElement("code"); termBody.appendChild(code); li = 0; ci = 0; };
    var tickTerm = function () {
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
    };
    resetTerm();
    var termIO = new IntersectionObserver(function (es) {
      var vis = es[0].isIntersecting;
      if (vis && !termActive) { termActive = true; tickTerm(); }
      else if (!vis && termActive) { termActive = false; clearTimeout(termTimer); }
    }, { threshold: 0.3 });
    termIO.observe(termBody);
    stopDemo = function () { termActive = false; clearTimeout(termTimer); termIO.disconnect(); renderStatic(); };
  }

  // ---- interactive shell ----
  var shellLive = false, hist = [], hpos = 0, draft = "";
  function print(lines, cls) {
    lines.forEach(function (l) {
      if (termBody.childNodes.length) termBody.appendChild(document.createTextNode("\n"));
      termBody.appendChild(lineNode(l, cls));
    });
    termBody.scrollTop = termBody.scrollHeight;
  }
  function takeOver() {
    if (shellLive) return;
    shellLive = true;
    stopDemo();
    termEl.classList.add("live");
    termBody.setAttribute("aria-label", "simmerctl session");
    termBody.setAttribute("aria-live", "polite");
    print(["", "Your turn. This demo does not touch your Mac. Type help to start."], "note");
  }
  var pad = function (s, n) { s = String(s); while (s.length < n) s += " "; return s; };
  var lpad = function (s, n) { s = String(s); while (s.length < n) s = " " + s; return s; };
  var row = function (k, v) { return pad(k, Math.max(12, k.length + 2)) + v; };
  var hhmm = function (d) { return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2); };
  var SUBS = ["status", "version", "limit", "topup", "discharge", "pause", "led", "set", "energy", "sleep-report", "charger", "conflicts", "help"];
  var ONOFF = ["on", "off"];
  var LEDARGS = ["system", "smart", "off", "custom", "blink", "charging", "limit", "sailing", "discharging", "heat", "topup"];
  var PATTERNS_CLI = { green: ["blinkGreen", "Blink green"], orange: ["blinkOrange", "Blink orange"], alternate: ["alternate", "Green / orange"], heartbeat: ["heartbeat", "Heartbeat"], level: ["level", "Blink the charge level"] };
  var KEYS = ["sailing", "sailing-level", "heat", "heat-threshold", "auto-discharge", "keep-limit", "limit", "desk-mode", "desk-limit", "smart-topup"];
  var USAGE = "Run 'simmerctl help' for the full list.";
  function onOff(v) {
    v = (v || "").toLowerCase();
    if (["on", "true", "yes", "1", "enable", "enabled", "start"].indexOf(v) >= 0) return true;
    if (["off", "false", "no", "0", "disable", "disabled", "stop"].indexOf(v) >= 0) return false;
    return null;
  }
  function suggest(w, list) {
    var best = null, bd = 3;
    list.forEach(function (c) {
      if (c.indexOf(w) === 0 && w.length > 1) { best = best || c; bd = 0; return; }
      var a = w, b = c, m = [], i, j;   // small edit distance
      for (i = 0; i <= a.length; i++) { m[i] = [i]; }
      for (j = 1; j <= b.length; j++) m[0][j] = j;
      for (i = 1; i <= a.length; i++) for (j = 1; j <= b.length; j++) m[i][j] = Math.min(m[i - 1][j] + 1, m[i][j - 1] + 1, m[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      if (m[a.length][b.length] < bd) { bd = m[a.length][b.length]; best = c; }
    });
    return best;
  }
  function err(msg) { return { err: true, lines: ["simmerctl: " + msg, USAGE] }; }
  function batteryPct() { return Math.round(reduced || (!running && plug.state !== "out") ? potTarget() : shown); }
  function status() {
    var pct = batteryPct(), tg = potTarget();
    var st, pw, flags;
    if (plug.state === "out") { st = "On Battery"; pw = "adapter n/a, system 9.4 W, battery -9.4 W (discharging)"; flags = "charging allowed, adapter enabled"; }
    else if (discharging) { st = "Discharging"; pw = "adapter 0.0 W, system 14.2 W, battery -14.2 W (discharging)"; flags = "charging inhibited, adapter disabled"; }
    else if (pct < tg) { st = topUp ? "Top Up" : "Charging"; pw = "adapter 62.0 W, system 14.0 W, battery +48.0 W (charging)"; flags = "charging allowed, adapter enabled"; }
    else { st = "Charge Limit Reached"; pw = "adapter 19.1 W, system 18.6 W, battery 0.0 W (idle)"; flags = "charging inhibited, adapter enabled"; }
    var out = [row("Battery:", pct + "% (hardware " + Math.max(0, pct - 0.6).toFixed(1) + "%)"), row("State:", st),
      row("Limit:", tg + "%" + (topUp ? " (top up)" : "")), row("Temp:", "31.0 °C"), row("Power:", pw)];
    if (plug.state !== "out") out.push(row("Adapter:", "96W USB-C Power Adapter, 94 W"));
    return out.concat([row("Health:", "92.0% (5750 / 6249 mAh)"), row("Cycles:", "111"), row("Flags:", flags), row("Backend:", "chte, helper 1.0.0")]);
  }
  // Real usage lines, limited to what this demo answers
  var USAGE_ROWS = [["Status"], ["status [--json]", "battery, charging state and power flow"], ["version", "helper and CLI version"], [],
    ["Charging"], ["limit <20-100>", "set the charge limit"], ["topup on|off", "charge to 100% once"], ["discharge on|off", "run from battery down to the limit while plugged in"], ["pause", "set the limit to the current percentage"], [],
    ["Hardware"], ["led system|smart|off|custom", "MagSafe LED mode"], ["led <state> <color>", "custom color for one state (switches to custom)"], ["led blink <pattern> [repeats]", "play a MagSafe LED notification"], ["    patterns: green orange alternate heartbeat level"], [],
    ["Insights"], ["energy [--json]", "apps using the most energy"], ["sleep-report [--days N] [--json]", "battery drain and wakes during sleep"], ["charger [--json]", "can the charger keep up? cable and hub limits"], ["conflicts [--json]", "other charge limiters, leftover helpers"], [],
    ["Settings"], ["set <key> <value>", "for example: set sailing on, set heat-threshold 35"]];
  function table(rows, w) { return rows.map(function (r) { return pad(r[0], w[0]) + r.slice(1).map(function (c, i) { return lpad(c, w[i + 1]); }).join(""); }); }
  function ctl(a) {
    var sub = (a[0] || "").toLowerCase(), r = a.slice(1), b;
    var toggle = function (on, off) {
      b = r[0] ? onOff(r[0]) : true;
      return b === null ? err("expected on|off, got '" + r[0] + "'") : [b ? on : off];
    };
    switch (sub) {
      case "": case "help": case "-h": case "--help":
        return ["usage: simmerctl <command> [arguments]", ""].concat(USAGE_ROWS.map(function (u) { return u.length < 2 ? (u[0] || "") : "  " + pad(u[0], 36) + u[1]; }));
      case "status": return status();
      case "version": case "--version": return ["simmerctl 1.0.0", "helper 1.0.0"];
      case "limit":
        var v = parseInt((r[0] || "").replace(/%$/, ""), 10);
        if (!/^\d+%?$/.test(r[0] || "") || !(v >= 20 && v <= 100)) return err("limit must be an integer in 20...100");
        setLimit(v, "term");
        return ["Charge limit set to " + v + "%"];
      case "topup": case "top-up":
        var res = toggle("Top up started", "Top up stopped"); if (!res.err) setTopUp(b); return res;
      case "discharge":
        res = toggle("Discharge started", "Discharge stopped"); if (!res.err) discharging = b; return res;
      case "pause": setLimit(batteryPct(), "term"); return ["Charge limit set to the current percentage"];
      case "led":
        var m = (r[0] || "").toLowerCase();
        if (m === "blink" || m === "notify") {
          var pat = PATTERNS_CLI[(r[1] || "").toLowerCase()];
          if (!pat) return err("pattern must be one of: green, orange, alternate, heartbeat, level");
          var n = r[2] ? parseInt(r[2], 10) : 3; if (!(n >= 1 && n <= 10)) return err("repeats must be an integer in 1...10");
          var btn = $('[data-blink="' + pat[0] + '"]'); if (btn) btn.click();
          return ["MagSafe LED: " + pat[1] + " x" + n];
        }
        var modes = { system: "system", smart: "smart", off: "alwaysOff", custom: "custom" };
        if (modes[m]) { var mb = $('[data-group="mode"] [data-v="' + m + '"]'); if (mb) mb.click(); return ["MagSafe LED: " + modes[m]]; }
        if (LEDARGS.indexOf(m) > 4) {
          var col = (r[1] || "").toLowerCase();
          if (["system", "off", "green", "orange", "blink-slow", "blink-fast"].indexOf(col) < 0) return err("color must be one of: system, off, green, orange, blink-slow, blink-fast");
          return ["MagSafe LED (custom): " + m + " = " + col];
        }
        return err("led mode must be system, smart, off, custom, or <state> <color>");
      case "set":
        if (r.length < 2) return err("set <key> <value>");
        var key = r[0].toLowerCase();
        if (KEYS.indexOf(key) < 0) return err("unknown key '" + r[0] + "'");
        if (key === "limit") { res = ctl(["limit", r[1]]); if (res.err) return res; }
        return [key + " = " + r[1]];
      case "energy":
        return ["Energy use (last 60 s, total 11.8 W)  updated " + hhmm(new Date())].concat(table([["APP", "NOW", "1 H", "CPU", "WAKE/s"],
          ["WindowServer", "2.86 W", "2.41 W", "14%", "310"], ["Safari", "2.12 W", "2.74 W", "11%", "240"], ["Xcode", "1.65 W", "3.08 W", "9%", "85"],
          ["Music", "0.41 W", "0.39 W", "2%", "60"], ["Terminal", "0.18 W", "0.12 W", "1%", "12"]], [32, 8, 8, 7, 8]), ["Simmer's own helper: 0.012 W, 0.1% CPU."]);
      case "charger":
        return ["Your 96 W charger has plenty of power", row("Charger:", "96W USB-C Power Adapter (USB-C PD)"), row("Rating:", "excellent"),
          "  - The charger offers 94 W (20 V × 4.7 A).", "  - It uses USB Power Delivery and supports 5 V, 9 V, 15 V, 20 V.",
          "  - Your Mac uses 19 W now.", "  - The highest use in recent history was 61 W."];
      case "sleep-report": case "sleepreport":
        var day = function (n, t) { return new Date(Date.now() - n * 864e5).toLocaleDateString(undefined, { year: "2-digit", month: "numeric", day: "numeric" }) + ", " + t; };
        return ["Sleep in the last 7 days (newest last)", pad("START", 18) + lpad("LENGTH", 9) + lpad("CHARGE", 12) + lpad("%/H", 6) + "  POWER  WAKES  REASON"]
          .concat(table([[day(3, "23:41"), "7h 12m", "80%→78%", "0.3", "  batt ", "4", "  Clamshell Sleep"], [day(2, "00:15"), "6h 48m", "80%→80%", "0.0", "  AC   ", "2", "  Idle Sleep"],
            [day(1, "22:58"), "8h 03m", "76%→73%", "0.4", "  batt ", "5", "  Clamshell Sleep"]], [18, 9, 12, 6, 7, 6, 0]),
          ["On battery: 15h 15m asleep, 5% used (0.33%/h).", "Most common wake reasons:", "      6  Maintenance wake", "      3  Bluetooth"]);
      case "conflicts": return ["No conflicts: no other charge limiter, leftover helper or macOS Charge Limit found."];
      case "boil":
        findEgg("chef");
        return ["simmerctl: refusing to boil.", "Simmer is made for simmering. Even 100% is only a rolling boil.", "Try: simmerctl limit 80"];
    }
    var s = suggest(sub, SUBS);
    return { err: true, lines: ["simmerctl: unknown command '" + a[0] + "'", s ? "Did you mean 'simmerctl " + s + "'?" : USAGE] };
  }
  function exec(line) {
    var w = line.split(/\s+/), c0 = w[0].toLowerCase();
    if (c0 === "clear") return "clear";
    if (c0 === "help" || c0 === "?") {
      return ["This is a demo terminal. Nothing here touches your Mac.", "Try one of these:",
        "  simmerctl status          battery, charging state and power flow", "  simmerctl limit 60        set the charge limit (it turns the knob at the top)",
        "  simmerctl topup on        charge to 100% once", "  simmerctl led blink heartbeat", "  simmerctl energy          also: charger, sleep-report, conflicts",
        "  simmerctl help            the full command list", "  clear                     clear the screen", "Use the up and down arrows for history, and Tab to complete.", "Psst: simmerctl has one secret command. Think hot."];
    }
    if (c0 === "sudo") {
      if (/simmer/i.test(line)) { findEgg("chef"); return ["Password: ********", "Nice try, chef. Simmer's helper already runs as root,", "so you never need sudo. The app itself never runs as root."]; }
      return { err: true, lines: ["sudo: this demo has no root. Try: simmerctl status"] };
    }
    if (c0 === "open" && /simmer:\/\//i.test(line)) { if (/topup/i.test(line)) setTopUp(true); return []; }
    if (c0 === "simmer") return { err: true, lines: ["zsh: command not found: simmer", "The command-line tool is called simmerctl. Try: simmerctl status"] };
    if (c0 !== "simmerctl") {
      var hint = SUBS.indexOf(c0) >= 0 ? "Did you mean 'simmerctl " + line + "'?" : "This demo knows simmerctl, help and clear.";
      return { err: true, lines: ["zsh: command not found: " + w[0], hint] };
    }
    return ctl(w.slice(1));
  }
  function updCaret() {
    termCaret.style.setProperty("--col", termInput.selectionStart || 0);
    termCaret.style.setProperty("--sl", termInput.scrollLeft + "px");
  }
  function complete() {
    var v = termInput.value, w = v.split(" "), last = w[w.length - 1].toLowerCase(), list;
    if (w.length === 1) list = ["simmerctl", "help", "clear"];
    else if (w[0] !== "simmerctl") return false;
    else if (w.length === 2) list = SUBS;
    else {
      var s = w[1].toLowerCase();
      if (s === "led" && w.length === 3) list = LEDARGS;
      else if (s === "led" && w[2] === "blink" && w.length === 4) list = Object.keys(PATTERNS_CLI);
      else if (s === "set" && w.length === 3) list = KEYS;
      else if ((s === "topup" || s === "discharge") && w.length === 3) list = ONOFF;
      else if (s === "set" && w.length === 4) list = ONOFF;
      else return false;
    }
    var m = list.filter(function (c) { return c.indexOf(last) === 0; });
    if (!m.length) return false;
    var common = m.reduce(function (a, c) { var i = 0; while (i < a.length && a[i] === c[i]) i++; return a.slice(0, i); });
    w[w.length - 1] = m.length === 1 ? m[0] + " " : common;
    if (m.length > 1 && common === last) { takeOver(); print(["$ " + v]); print([m.join("  ")]); }
    termInput.value = w.join(" ");
    return true;
  }
  termForm.addEventListener("submit", function (e) {
    e.preventDefault();
    takeOver();
    var v = termInput.value.trim();
    termInput.value = ""; updCaret();
    if (v) { hist.push(v); if (hist.length > 50) hist.shift(); }
    hpos = hist.length; draft = "";
    var out = v ? exec(v) : [];
    if (out === "clear") { termBody.textContent = ""; return; }
    print(["$ " + v]);
    if (out.err) print(out.lines, "err"); else print(out);
  });
  termInput.addEventListener("keydown", function (e) {
    if (e.key === "ArrowUp" || e.key === "ArrowDown") {
      if (!hist.length) return;
      e.preventDefault();
      if (hpos === hist.length) draft = termInput.value;
      hpos = clamp(hpos + (e.key === "ArrowUp" ? -1 : 1), 0, hist.length);
      termInput.value = hpos === hist.length ? draft : hist[hpos];
      var n = termInput.value.length; termInput.setSelectionRange(n, n);
    } else if (e.key === "Tab" && !e.shiftKey && termInput.value) {
      if (complete()) e.preventDefault();   // with nothing to complete, Tab moves focus as usual
    } else if (e.key === "l" && e.ctrlKey) {
      e.preventDefault(); takeOver(); termBody.textContent = "";
    } else if (e.key.length === 1 || e.key === "Enter") takeOver();
    requestAnimationFrame(updCaret);
  });
  ["input", "select", "click", "keyup", "focus"].forEach(function (n) { termInput.addEventListener(n, updCaret); });
  termEl.addEventListener("click", function (e) {
    if (e.target === termInput || String(window.getSelection())) return;
    termInput.focus({ preventScroll: true });
  });

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

  /* =========================================================
     HERO EXTRAS: cursor steam, the charger plug, top up
     ========================================================= */
  // Steam follows the cursor (mouse and pen) or a finger (touchmove)
  heroEl.addEventListener("pointermove", function (e) {
    if (e.pointerType === "touch") return;
    if (!ptr.on) { ptr.lcx = e.clientX; ptr.lcy = e.clientY; }
    ptr.cx = e.clientX; ptr.cy = e.clientY; ptr.on = true; ptr.dirty = true;
  });
  heroEl.addEventListener("pointerleave", function () { ptr.on = false; });
  heroEl.addEventListener("touchmove", function (e) {
    var t = e.touches[0]; if (!t) return;
    if (!ptr.on) { ptr.lcx = t.clientX; ptr.lcy = t.clientY; }
    ptr.cx = t.clientX; ptr.cy = t.clientY; ptr.on = true; ptr.dirty = true;
  }, { passive: true });
  heroEl.addEventListener("touchend", function () { ptr.on = false; }, { passive: true });

  var stoveFx = $("#stove-fx");
  var fxMsgUntil = 0, quiet = false;   // quiet: the first-load plug demo makes no announcements
  function say(text, cls, hold) {
    if (quiet || (performance.now() < fxMsgUntil && !hold)) return;   // a boil-over message wins for a moment
    stoveFx.textContent = text;
    stoveFx.className = "stove-fx" + (cls ? " " + cls : "");
    if (hold) fxMsgUntil = performance.now() + hold;
  }

  function setTopUp(on) {
    topUp = on;
    if (reduced) { shown = potTarget(); drawPot(0, 0); updatePlugLed(); }
  }

  var plugLayer = $("#plug-layer"), plugG = $("#plug"), cableP = $("#cable"), socketEl = $("#jar-socket"), spark = $("#spark");
  // The socket is on the jar, or on the side of the laptop deck. The plug is a little smaller next to the laptop.
  var SOCK_J = { x: 236, y: 290, a: 0 }, SOCK_L = { x: 303, y: 290, a: 0 }, SOCK = SOCK_J, REST = { x: 266, y: 336, a: 26 };
  var pose = { x: REST.x, y: REST.y, a: REST.a, s: 1 }, drag = null, poseRaf = 0;
  function plugScale() { return SOCK === SOCK_L ? 0.78 : 1; }
  function renderPlug() {
    plugG.setAttribute("transform", "translate(" + pose.x.toFixed(2) + " " + pose.y.toFixed(2) + ") rotate(" + pose.a.toFixed(2) + ") scale(" + pose.s.toFixed(3) + ")");
    var r = pose.a * Math.PI / 180, c = Math.cos(r), s = Math.sin(r);
    var tx = pose.x + c * 42 * pose.s, ty = pose.y + s * 42 * pose.s;
    cableP.setAttribute("d", "M" + tx.toFixed(1) + " " + ty.toFixed(1) + "C" + (tx + c * 38).toFixed(1) + " " + (ty + s * 38).toFixed(1) + " 296 388 344 386L440 388");
  }
  function restart(node, cls) { node.classList.remove(cls); node.getBoundingClientRect(); node.classList.add(cls); }
  // Tween the plug to a pose. The snap eases in (the magnet pulls harder up close) and settles with a tiny bounce.
  function movePlug(to, ms, ease, done) {
    cancelAnimationFrame(poseRaf);
    var ts = plugScale();
    if (reduced || !ms) { pose.x = to.x; pose.y = to.y; pose.a = to.a; pose.s = ts; renderPlug(); if (done) done(); return; }
    var from = { x: pose.x, y: pose.y, a: pose.a, s: pose.s }, t0 = performance.now();
    (function step(now) {
      var t = clamp((now - t0) / ms, 0, 1), e = ease(t);   // rAF time can be a little before t0
      pose.x = lerp(from.x, to.x, e); pose.y = lerp(from.y, to.y, e); pose.a = lerp(from.a, to.a, Math.min(1, t * 1.6)); pose.s = lerp(from.s, ts, t);
      renderPlug();
      if (t < 1) poseRaf = requestAnimationFrame(step); else if (done) done();
    })(t0);
  }
  var snapEase = function (t) { return t < 0.72 ? Math.pow(t / 0.72, 2.4) : 1 - 0.06 * Math.sin((t - 0.72) / 0.28 * Math.PI); };
  var outEase = function (t) { var u = t - 1; return 1 + 2.2 * u * u * u + 1.2 * u * u; };
  function plugIn() {
    plugLayer.classList.add("snapping");
    spark.setAttribute("cx", SOCK.x); spark.setAttribute("cy", SOCK.y);
    movePlug(SOCK, 260, snapEase, function () {
      plugLayer.classList.remove("snapping");
      plug.state = "in"; plug.led = "";
      plugG.setAttribute("aria-pressed", "true");
      plugG.setAttribute("aria-label", "Charger plug, plugged in. Press Enter to unplug.");
      plugLayer.classList.add("in");
      if (!reduced) { restart(spark, "go"); restart(pot, "jolt"); }
      updatePlugLed();
    });
  }
  function unplug(animate) {
    plug.state = "out"; plug.floor = Math.max(20, Math.round(potTarget()) - 22);
    plugG.setAttribute("aria-pressed", "false");
    plugG.setAttribute("aria-label", "Charger plug. Press Enter to plug it into the jar.");
    plugLayer.classList.remove("in");
    updatePlugLed();
    if (animate) movePlug(REST, 520, outEase);
  }
  function togglePlug() { if (plug.state === "in") unplug(true); else plugIn(); }

  function updatePlugLed() {
    var st = "off", tg = potTarget();
    if (plug.state === "in") st = shown < tg - 0.3 ? "orange" : (shown > tg + 0.6 ? "blink" : "green");
    if (st === plug.led) return;
    var was = plug.led;
    plug.led = st;
    plugLayer.setAttribute("data-led", st);
    if (st === "orange") say("Plugged in and charging to " + tg + "%.", "is-charge");
    else if (st === "green") say("At " + tg + "%, charging pauses. The charger runs the Mac and the battery rests.", "is-limit");
    else if (st === "blink") say("Above the limit: the battery runs the Mac down to " + tg + "%.", "is-charge");
    else if (was) say("Unplugged. The Mac runs on its battery.", "");
    if (reduced && plug.state === "in") drawPot(0, 0);
  }

  plugG.addEventListener("pointerdown", function (e) {
    if (e.button > 0) return;
    e.preventDefault();
    plugG.setPointerCapture(e.pointerId);
    cancelAnimationFrame(poseRaf);
    var rect = plugLayer.getBoundingClientRect(), k = 320 / rect.width;
    drag = { rect: rect, k: k, dx: pose.x - (e.clientX - rect.left) * k, dy: pose.y - (e.clientY - rect.top) * k, sx: e.clientX, sy: e.clientY, moved: false };
    plugLayer.classList.add("dragging");
  });
  plugG.addEventListener("pointermove", function (e) {
    if (!drag) return;
    if (!drag.moved && Math.abs(e.clientX - drag.sx) + Math.abs(e.clientY - drag.sy) < 5) return;
    drag.moved = true;
    var nx = (e.clientX - drag.rect.left) * drag.k + drag.dx, ny = (e.clientY - drag.rect.top) * drag.k + drag.dy;
    var d = Math.hypot(nx - SOCK.x, ny - SOCK.y);
    if (plug.state === "in") {
      if (d < 22) { pose.x = SOCK.x + (nx - SOCK.x) * 0.22; pose.y = SOCK.y + (ny - SOCK.y) * 0.22; renderPlug(); return; }   // the magnet holds
      unplug(false);
    }
    var m = d < 40 ? 1 - d / 40 : 0;
    pose.x = lerp(nx, SOCK.x, m * 0.55); pose.y = lerp(ny, SOCK.y, m * 0.55);
    pose.a = lerp(pose.a, d < 70 ? 0 : clamp((ny - SOCK.y) * 0.4, -40, 40), 0.25);
    socketEl.classList.toggle("near", d < 70);
    renderPlug();
  });
  function endDrag() {
    if (!drag) return;
    var moved = drag.moved; drag = null;
    plugLayer.classList.remove("dragging"); socketEl.classList.remove("near");
    if (!moved) { togglePlug(); return; }
    var d = Math.hypot(pose.x - SOCK.x, pose.y - SOCK.y);
    if (plug.state === "in") movePlug(SOCK, 180, outEase);
    else if (d < 40) plugIn();
    else movePlug(REST, 560, outEase);
  }
  // touch-action is not reliable on SVG children: stop the page from scrolling while the plug is dragged
  plugG.addEventListener("touchstart", function (e) { e.preventDefault(); }, { passive: false });
  plugG.addEventListener("pointerup", endDrag);
  plugG.addEventListener("pointercancel", endDrag);
  plugG.addEventListener("keydown", function (e) {
    if (e.key === "Enter" || e.key === " ") { e.preventDefault(); togglePlug(); }
  });
  renderPlug();

  // The knob always wins: turning it while unplugged shows the limit again
  limitListeners.push(function (v, src) {
    if (src === "init" || src === "demo") return;
    topUp = false;
    if (plug.state === "out") plug.state = "rest";
    updatePlugLed();
  });

  /* =========================================================
     JAR <-> LAPTOP: tap the jar and it becomes a laptop on a desk
     ========================================================= */
  var potWrap = $(".pot-wrap"), potToggle = $("#pot-toggle");
  var jarG = $("#jar-g"), stoveBack = $("#stove-back"), stoveFront = $("#stove-front"), lapG = $("#laptop-g"), lapLid = $("#lap-lid");
  var lapScreen = $("#lap-screen"), lapDeck = $("#lap-deck"), lapShadow = $("#lap-shadow");
  var lapPct = $("#lap-pct"), lapState = $("#lap-state"), lapMenu = $("#lap-menu-text");
  var morphM = 0, morphRaf = 0, lapText = "";
  var JAR_R = [90, 118, 140, 212, 34], LID_R = [46, 112, 228, 158, 11];
  function sub(m, a, b) { return clamp((m - a) / (b - a), 0, 1); }
  function backOut(t) { var c = 1.6, u = t - 1; return 1 + (c + 1) * u * u * u + c * u * u; }
  function drawMorph(m) {
    morphM = m;
    var j = inOut(sub(m, 0.05, 0.75)), sc = 1 - 0.6 * j;
    jarG.setAttribute("transform", m > 0 ? "translate(" + lerp(160, 110, j).toFixed(2) + " " + lerp(214, 197, j).toFixed(2) + ") scale(" + sc.toFixed(4) + ") translate(-160 -214)" : "");
    var st = 1 - inOut(sub(m, 0, 0.45));
    [stoveBack, stoveFront].forEach(function (g) {
      g.setAttribute("opacity", st.toFixed(3));
      g.setAttribute("transform", st < 1 ? "translate(0 " + (22 * (1 - st)).toFixed(2) + ")" : "");
    });
    lapG.setAttribute("opacity", m > 0 ? 1 : 0);
    var k = inOut(sub(m, 0.1, 0.7));
    ["x", "y", "width", "height", "rx"].forEach(function (a, i) { lapLid.setAttribute(a, lerp(JAR_R[i], LID_R[i], k).toFixed(2)); });
    lapLid.setAttribute("opacity", sub(m, 0.06, 0.3).toFixed(3));
    lapScreen.setAttribute("opacity", inOut(sub(m, 0.55, 0.92)).toFixed(3));
    var d = sub(m, 0.45, 0.95);
    lapDeck.setAttribute("opacity", Math.min(1, d * 3).toFixed(3));
    lapDeck.setAttribute("transform", "translate(0 272) scale(1 " + Math.max(0.001, backOut(d)).toFixed(4) + ") translate(0 -272)");
    lapShadow.setAttribute("opacity", inOut(sub(m, 0.5, 1)).toFixed(3));
    socketEl.setAttribute("opacity", (1 - sub(m, 0, 0.25)).toFixed(3));
    potWrap.classList.toggle("is-laptop", m > 0.15);
  }
  // Text on the laptop screen follows the charge, the knob and the plug
  function updLapText() {
    var pct = Math.round(reduced ? potTarget() : shown), tg = potTarget();
    var s = plug.led === "orange" ? "Charging to " + tg + "%" : plug.led === "green" ? "Held at " + tg + "%" : plug.led === "blink" ? "Down to " + tg + "%"
      : plug.state === "out" ? "On battery" : "Limit " + tg + "%";
    var key = pct + "|" + s;
    if (key === lapText) return;
    lapText = key;
    lapPct.textContent = pct + "%";
    lapMenu.textContent = "Simmer " + pct + "%";
    lapState.textContent = s;
    lapG.classList.toggle("charging", plug.led === "orange");
  }
  function setLaptop(on) {
    var to = on ? 1 : 0, from = morphM, t0 = performance.now(), dur = 950 * Math.abs(to - from);
    potToggle.setAttribute("aria-pressed", String(on));
    potToggle.setAttribute("aria-label", on ? "Show as jar" : "Show as laptop");
    SOCK = on ? SOCK_L : SOCK_J;
    if (plug.state === "in") movePlug(SOCK, reduced ? 0 : 900, inOut);
    else if (!drag) movePlug(REST, reduced ? 0 : 500, inOut);   // only the plug size changes
    hideHint(hintJar);
    cancelAnimationFrame(morphRaf);
    if (reduced || !dur) { drawMorph(to); updLapText(); drawPot(0, 0); return; }
    (function step(now) {
      var t = clamp((now - t0) / dur, 0, 1);
      drawMorph(lerp(from, to, t));
      if (!running) { updLapText(); }
      if (t < 1) morphRaf = requestAnimationFrame(step);
    })(t0);
  }
  potToggle.addEventListener("click", function () { setLaptop(potToggle.getAttribute("aria-pressed") !== "true"); });
  drawMorph(0);

  /* ---------- First load: the plug shows what it does, then two hints ---------- */
  var hintPlug = $("#hint-plug"), hintJar = $("#hint-jar"), demo = { on: false, t: [] };
  function showHint(h, ms) { h.classList.add("show"); demo.t.push(setTimeout(function () { hideHint(h); }, ms)); }
  function hideHint(h) { h.classList.remove("show"); }
  var CANCEL = ["pointerdown", "keydown", "wheel", "touchstart"];
  function cancelDemo(e) {
    CANCEL.forEach(function (n) { window.removeEventListener(n, cancelDemo, true); });
    demo.t.forEach(clearTimeout); demo.t = [];
    hideHint(hintPlug); hideHint(hintJar);
    if (!demo.on) return;
    demo.on = false; quiet = false; plug.rate = 4;
    if (e && e.target && plugG.contains(e.target)) return;   // the visitor grabs the plug: let the drag take over
    if (plug.state !== "rest") { unplug(false); plug.state = "rest"; say("", ""); }
    movePlug(REST, 420, outEase);
  }
  function afterIntro() {
    if (window.scrollY > 200 || demo.on) return;
    CANCEL.forEach(function (n) { window.addEventListener(n, cancelDemo, { capture: true, passive: true }); });
    if (reduced) {   // no motion: only the hints
      showHint(hintPlug, 5000);
      demo.t.push(setTimeout(function () { showHint(hintJar, 4500); }, 5400));
      return;
    }
    demo.on = true; quiet = true;
    showHint(hintPlug, 5600);
    plug.state = "out"; plug.floor = limit - 14; plug.rate = 14;   // drains a little on the way, so it can charge
    movePlug({ x: SOCK.x + 28, y: SOCK.y + 12, a: 16 }, 950, inOut, function () { if (demo.on) { plug.rate = 4; plugIn(); } });
    demo.t.push(setTimeout(function () {
      if (!demo.on) return;
      unplug(false); plug.state = "rest";
      movePlug(REST, 700, outEase);
    }, 3500));
    demo.t.push(setTimeout(function () {
      if (!demo.on) return;
      demo.on = false; quiet = false; say("", "");
      showHint(hintJar, 4500);
    }, 4300));
  }

  /* =========================================================
     EASTER EGGS
     ========================================================= */
  var EGGS = {   // name, what you did, riddle for the hint list
    boil: ["Boil-over", "You held the knob at 100% until the jar boiled over. Your battery feels that way every day on the charger.", "Crank the heat all the way up, and wait a moment."],
    disco: ["Disco pot", "Up, up, down, down, left, right, left, right, B, A. The jar has moves.", "Old gamers know the code: ↑↑↓↓←→←→BA."],
    chef: ["Head chef", "You asked the terminal for something it would not do. Simmer said no, politely.", "The terminal has a secret command. Think hot."],
    cooked: ["Cooked just right", "Three knocks on the logo. Not too soft, not too firm: like a charge held at 80%.", "Knock on the logo, three times."]
  };
  var EGG_IDS = Object.keys(EGGS);
  var found = [];
  try { found = JSON.parse(localStorage.getItem("simmer-eggs") || "[]").filter(function (id) { return EGGS[id]; }); } catch (e) { found = []; }
  var EGG_SVG = '<svg viewBox="0 0 24 24" aria-hidden="true"><path class="egg-shell" d="M12 2.6c-4 0-7 6.4-7 11a7 7 0 0 0 14 0c0-4.6-3-11-7-11Z"/><path class="egg-spot" d="M9 12.5a1.3 1.3 0 1 0 0 .1ZM14.6 9.4a1 1 0 1 0 0 .1ZM14 16a1.4 1.4 0 1 0 0 .1Z"/></svg>';
  var toast = null, toastTimer = 0;
  var eggBtn = $("#egg-btn"), eggPop = $("#egg-pop"), eggChip = $("#egg-chip");
  // The nav button, the footer chip and the hint list all show the count
  function renderChip() {
    var n = found.length, all = EGG_IDS.length;
    eggBtn.setAttribute("aria-label", "Hidden eggs: " + n + " of " + all + " found");
    $(".egg-count", eggBtn).textContent = n + "/" + all;
    eggBtn.classList.toggle("has-found", n > 0);
    eggChip.innerHTML = EGG_SVG + "<span>" + all + " hidden eggs, " + n + " found</span>";
    var list = $(".egg-list", eggPop);
    list.textContent = "";
    EGG_IDS.forEach(function (id) {
      var li = document.createElement("li"), got = found.indexOf(id) >= 0;
      li.className = got ? "got" : "";
      li.innerHTML = '<span class="egg-mark" aria-hidden="true"></span><span><b></b><i></i></span>';
      $("b", li).textContent = got ? EGGS[id][0] + " (found)" : "Not found yet";
      $("i", li).textContent = EGGS[id][2];
      list.appendChild(li);
    });
  }
  function togglePop(open, from) {
    open = open === undefined ? eggPop.hidden : open;
    eggPop.hidden = !open;
    [eggBtn, eggChip].forEach(function (b) { b.setAttribute("aria-expanded", String(open)); });
    if (open) { eggPop.classList.toggle("from-foot", from === eggChip); $(".egg-pop-close", eggPop).focus(); }
  }
  eggBtn.addEventListener("click", function () { togglePop(undefined, eggBtn); });
  eggChip.addEventListener("click", function () { togglePop(undefined, eggChip); });
  $(".egg-pop-close", eggPop).addEventListener("click", function () { togglePop(false); eggBtn.focus(); });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape" && !eggPop.hidden) { togglePop(false); eggBtn.focus(); } });
  document.addEventListener("click", function (e) { if (!eggPop.hidden && !eggPop.contains(e.target) && !eggBtn.contains(e.target) && !eggChip.contains(e.target)) togglePop(false); });
  function findEgg(id) {
    var fresh = found.indexOf(id) < 0;
    if (fresh) { found.push(id); try { localStorage.setItem("simmer-eggs", JSON.stringify(found)); } catch (e) {} }
    if (!toast) {
      toast = document.createElement("div");
      toast.className = "egg-toast";
      toast.setAttribute("role", "status");
      toast.innerHTML = '<span class="egg-badge">' + EGG_SVG + '</span><div class="egg-copy"><p class="egg-kicker"></p><p class="egg-name"></p><p class="egg-desc"></p></div>' +
        '<button type="button" class="egg-close" aria-label="Close">' + '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button>';
      document.body.appendChild(toast);
      $(".egg-close", toast).addEventListener("click", hideToast);
      document.addEventListener("keydown", function (e) { if (e.key === "Escape") hideToast(); });
    }
    $(".egg-kicker", toast).textContent = fresh ? "Hidden easter egg found!" : "Easter egg, found again";
    $(".egg-name", toast).innerHTML = "";
    $(".egg-name", toast).appendChild(document.createTextNode(EGGS[id][0] + " "));
    var count = document.createElement("span");
    count.textContent = "(" + found.length + " of " + EGG_IDS.length + ")";
    $(".egg-name", toast).appendChild(count);
    $(".egg-desc", toast).textContent = EGGS[id][1];
    toast.classList.remove("show");
    toast.getBoundingClientRect();
    toast.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(hideToast, 6500);
    renderChip();
    if (!reduced) requestAnimationFrame(function () {
      var r = $(".egg-badge", toast).getBoundingClientRect();
      burst(r.left + r.width / 2, r.top + r.height / 2, id === "cooked");
    });
  }
  function hideToast() { if (toast) toast.classList.remove("show"); }
  // A burst of steam puffs and brand-coloured bits (pasta strands for the logo egg)
  function burst(x, y, pasta) {
    var box = document.createElement("div");
    box.className = "egg-burst";
    box.style.left = x + "px"; box.style.top = y + "px";
    var colors = ["#ffd35c", "#ff9a3c", "#ee6b33", "#c2416b", "#fff6ec"];
    for (var i = 0; i < 26; i++) {
      var p = document.createElement("i");
      var kind = i % 4 === 0 ? "puff" : (pasta && i % 2 ? "pasta" : "bit");
      var a = (-170 + Math.random() * 160) * Math.PI / 180, dist = 70 + Math.random() * (kind === "puff" ? 70 : 150);
      p.className = kind;
      p.style.setProperty("--dx", (Math.cos(a) * dist).toFixed(0) + "px");
      p.style.setProperty("--dy", (Math.sin(a) * dist).toFixed(0) + "px");
      p.style.setProperty("--r", (Math.random() * 540 - 270).toFixed(0) + "deg");
      p.style.setProperty("--d", (0.75 + Math.random() * 0.6).toFixed(2) + "s");
      if (kind !== "puff") p.style.background = colors[i % colors.length];
      box.appendChild(p);
    }
    document.body.appendChild(box);
    setTimeout(function () { box.remove(); }, 1600);
  }
  renderChip();

  // (a) Boil-over: hold the limit at 100% for 3 seconds
  var boilTimer = 0, teaseTimer = 0;
  limitListeners.push(function (v, src) {
    clearTimeout(boilTimer); clearTimeout(teaseTimer);
    if (v === 100 && src !== "demo" && src !== "init") {
      teaseTimer = setTimeout(function () { readNote.textContent = "Careful… hold it here and it may boil over."; }, 500);
      boilTimer = setTimeout(boilOver, 1500);
    }
  });
  function boilOver() {
    fxT.boil0 = performance.now();
    say("Battery at a rolling boil! Turn the knob down a notch.", "is-warn", 4400);
    setTimeout(function () { findEgg("boil"); }, reduced ? 0 : 900);
    setTimeout(function () { fxMsgUntil = 0; plug.led = ""; say("", ""); updatePlugLed(); if (reduced) drawPot(0, 0); }, 4500);
    if (reduced) drawPot(0, 0);
  }
  // (b) Konami code: a disco pot
  var KON = ["ArrowUp", "ArrowUp", "ArrowDown", "ArrowDown", "ArrowLeft", "ArrowRight", "ArrowLeft", "ArrowRight", "b", "a"], kpos = 0;
  document.addEventListener("keydown", function (e) {
    var tg = e.target && e.target.tagName;
    if (tg === "INPUT" || tg === "TEXTAREA" || tg === "SELECT") return;
    var k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
    if (k === KON[kpos]) {
      if (++kpos === KON.length) {
        kpos = 0;
        fxT.disco0 = performance.now();
        heroEl.classList.add("disco");
        setTimeout(function () { heroEl.classList.remove("disco"); if (reduced) drawPot(0, 0); }, 6500);
        if (reduced) drawPot(0, 0);
        findEgg("disco");
      }
    } else kpos = k === "ArrowUp" ? (kpos === 2 ? 2 : 1) : 0;
  });
  // (d) Five quick taps on the nav logo: the jar winks, cooked just right
  var taps = [];
  $(".brand").addEventListener("click", function () {
    var n = performance.now();
    taps = taps.filter(function (t) { return n - t < 1600; });
    taps.push(n);
    if (taps.length < 3) return;
    taps = [];
    restart($(".brand"), "spin");
    fxT.face0 = n;
    if (reduced) { drawPot(0, 0); setTimeout(function () { drawPot(0, 0); }, 2900); }
    findEgg("cooked");
  });
  // (c) is in the terminal: "simmerctl boil" or "sudo simmer..."

  /* =========================================================
     YOUR REAL BATTERY (browsers with navigator.getBattery)
     ========================================================= */
  (function realBattery() {
    var box = $("#real-batt"), txt = $("#real-batt-text");
    var uad = navigator.userAgentData;
    var mac = uad && uad.platform ? uad.platform === "macOS" : /Mac/.test(navigator.platform || "");
    if (!box || !mac || typeof navigator.getBattery !== "function") return;
    navigator.getBattery().then(function (b) {
      var queued = false;
      function render() {
        queued = false;
        var pct = Math.round(b.level * 100), s;
        var how = b.charging && b.chargingTime > 0 && isFinite(b.chargingTime) ? "and charging" : "and plugged in";
        if (!b.charging) s = "Your Mac is at " + pct + "% on battery. Plugged in, Simmer would stop at " + limit + "% (your knob setting).";
        else if (pct > limit) s = "Your Mac is at " + pct + "% " + how + ". Simmer would have stopped at " + limit + "% (your knob setting).";
        else if (pct === limit) s = "Your Mac is at " + pct + "% " + how + ". Simmer would hold it right here (your knob setting).";
        else s = "Your Mac is at " + pct + "% " + how + ". Simmer would stop at " + limit + "% (your knob setting).";
        txt.textContent = s;
        box.classList.toggle("on-ac", b.charging);
        box.hidden = false;
      }
      var later = function () { if (!queued) { queued = true; requestAnimationFrame(render); } };
      b.addEventListener("levelchange", later);
      b.addEventListener("chargingchange", later);
      limitListeners.push(later);
      render();
    }).catch(function () {});
  })();

  /* =========================================================
     TEN YEARS IN TEN SECONDS
     ========================================================= */
  (function race() {
    var box = $("#race"); if (!box) return;
    var yr = $("#race-year"), out = $("#race-out"), btn = $("#race-play"), btnLabel = $("#race-play-label"), gap = $("#race-gap");
    var K = [20 / Math.pow(5, 0.75), 9 / Math.pow(5, 0.75)];   // illustrative: 20% vs 9% lost after 5 years
    var health = function (k, t) { return 100 - k * Math.pow(t, 0.75); };
    var X = function (t) { return 40 + t / 10 * 268; }, Y = function (hh) { return 14 + (100 - hh) / 40 * 150; };
    var jars = ["full", "sim"].map(function (n, i) {
      return { k: K[i], lost: $("#rl-" + n), liq: $("#rq-" + n), line: $("#rk-" + n), num: $("#rh-" + n), path: $("#rc-" + n), dot: $("#rd-" + n) };
    });
    var head = $("#rc-head"), grid = $("#race-grid");
    [100, 90, 80, 70, 60].forEach(function (hh) {
      el("line", { x1: 40, x2: 308, y1: Y(hh), y2: Y(hh), class: "c-grid" }, grid);
      el("text", { x: 32, y: Y(hh) + 4, "text-anchor": "end", class: "c-axis" }, grid).textContent = hh + "%";
    });
    [0, 2, 4, 6, 8, 10].forEach(function (t) {
      el("text", { x: X(t), y: 188, "text-anchor": "middle", class: "c-axis" }, grid).textContent = t === 0 ? "Year 0" : String(t);
    });
    function curve(k, t1) {
      var d = "";
      for (var i = 0; i <= 50; i++) { var t = t1 * i / 50; d += (i ? "L" : "M") + X(t).toFixed(1) + " " + Y(health(k, t)).toFixed(1); }
      return d;
    }
    $("#rc-full-bg").setAttribute("d", curve(K[0], 10));
    $("#rc-sim-bg").setAttribute("d", curve(K[1], 10));
    var t = reduced ? 10 : 0, playing = false, raf = 0, last = 0;
    function render() {
      var hs = jars.map(function (j) {
        var hh = health(j.k, t), lostH = (100 - hh) / 100 * 112;
        j.lost.setAttribute("y", 30); j.lost.setAttribute("height", lostH.toFixed(2));
        j.liq.setAttribute("y", (30 + lostH).toFixed(2)); j.liq.setAttribute("height", (112 - lostH + 10).toFixed(2));
        j.line.setAttribute("y1", (30 + lostH).toFixed(2)); j.line.setAttribute("y2", (30 + lostH).toFixed(2));
        j.num.textContent = Math.round(hh);
        j.path.setAttribute("d", curve(j.k, t));
        j.dot.setAttribute("cx", X(t).toFixed(1)); j.dot.setAttribute("cy", Y(hh).toFixed(1));
        return hh;
      });
      head.setAttribute("x1", X(t).toFixed(1)); head.setAttribute("x2", X(t).toFixed(1));
      yr.value = t; paintRange(yr);
      var ys = t < 9.95 ? t.toFixed(1) : "10";
      out.textContent = "Year " + ys;
      var diff = Math.round(hs[1]) - Math.round(hs[0]);
      gap.textContent = t < 0.05 ? "Both start at 100% health." : (diff < 1 ? "Year " + ys + ": about the same so far." : "Year " + ys + ": the Mac held at 80% keeps " + diff + " points more of its capacity.");
      yr.setAttribute("aria-valuetext", "Year " + ys + ": " + Math.round(hs[0]) + "% health always at 100%, " + Math.round(hs[1]) + "% held at 80%");
    }
    function setBtn() {
      box.classList.toggle("playing", playing);
      btnLabel.textContent = playing ? "Pause" : (t >= 10 ? "Replay" : "Play");
      btn.setAttribute("aria-label", playing ? "Pause" : (t >= 10 ? "Replay ten years" : "Play ten years"));
    }
    function loop(ts) {
      if (!playing) return;
      var dt = last ? Math.min(0.05, (ts - last) / 1000) : 0; last = ts;
      t = Math.min(10, t + dt);
      render();
      if (t >= 10) { stop(); return; }
      raf = requestAnimationFrame(loop);
    }
    function play() {
      if (reduced) { t = t >= 10 ? 0 : 10; render(); setBtn(); return; }   // no animation: jump to the end, or back
      if (t >= 10) t = 0;
      playing = true; last = 0; setBtn();
      raf = requestAnimationFrame(loop);
    }
    function stop() { playing = false; cancelAnimationFrame(raf); setBtn(); }
    btn.addEventListener("click", function () { if (playing) stop(); else play(); });
    yr.addEventListener("input", function () { stop(); t = +yr.value; render(); setBtn(); });
    if ("IntersectionObserver" in window) {
      var auto = !reduced;
      new IntersectionObserver(function (es) {
        var vis = es[0].isIntersecting;
        if (vis && auto) { auto = false; setTimeout(play, 400); }
        else if (!vis && playing) stop();
      }, { threshold: 0.45 }).observe(box);
    }
    render(); setBtn();
  })();

  /* =========================================================
     TOUR: the sticky screenshot follows the step in focus
     ========================================================= */
  (function tour() {
    var steps = $$(".tour-step"), shots = $$(".tour-shot"), rails = $$(".tour-rail span");
    if (!steps.length) return;
    var active = -1;
    function activate(i) {
      if (i === active) return;
      active = i;
      steps.forEach(function (s, j) { s.classList.toggle("is-active", j === i); });
      shots.forEach(function (s, j) { s.classList.toggle("is-active", j === i); s.classList.toggle("is-past", j < i); });
      rails.forEach(function (r, j) { r.classList.toggle("on", j <= i); });
    }
    activate(0);
    if (!("IntersectionObserver" in window)) return;
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) activate(+e.target.dataset.step); });
    }, { rootMargin: "-48% 0px -48% 0px" });
    steps.forEach(function (s) { io.observe(s); });
  })();

  /* ---------- Bento: "Details" shows the one-line tips inline (keyboard and touch) ---------- */
  $$(".bento-more").forEach(function (b) {
    b.addEventListener("click", function () {
      var open = b.getAttribute("aria-expanded") !== "true";
      b.setAttribute("aria-expanded", String(open));
      b.textContent = open ? "Hide details" : "Details";
      b.closest(".bento-g").classList.toggle("open", open);
    });
  });

  /* =========================================================
     SPOTLIGHT + TILT on cards and screenshots (fine pointers only)
     ========================================================= */
  if (!reduced && matchMedia("(hover: hover) and (pointer: fine)").matches) {
    $$(".bento-g, .install-card, .tour-frame").forEach(function (node) {
      var max = node.matches(".bento-g") ? 3 : 6, rect = null, sy = 0, mx = 0, my = 0, queued = false;
      node.classList.add("spot");
      function paint() {
        queued = false;
        if (!rect || sy !== window.scrollY) { rect = node.getBoundingClientRect(); sy = window.scrollY; }
        var px = clamp((mx - rect.left) / rect.width, 0, 1), py = clamp((my - rect.top) / rect.height, 0, 1);
        node.style.setProperty("--mx", (px * 100).toFixed(1) + "%");
        node.style.setProperty("--my", (py * 100).toFixed(1) + "%");
        node.style.setProperty("--rx", ((0.5 - py) * max).toFixed(2) + "deg");
        node.style.setProperty("--ry", ((px - 0.5) * max).toFixed(2) + "deg");
      }
      node.addEventListener("pointerenter", function () { rect = null; node.classList.add("spot-on"); });
      node.addEventListener("pointermove", function (e) {
        mx = e.clientX; my = e.clientY;
        if (!queued) { queued = true; requestAnimationFrame(paint); }
      });
      node.addEventListener("pointerleave", function () {
        node.classList.remove("spot-on");
        node.style.setProperty("--rx", "0deg"); node.style.setProperty("--ry", "0deg");
      });
    });
  }

  /* =========================================================
     SCROLL REVEALS: CSS scroll-driven where supported, else IntersectionObserver
     ========================================================= */
  (function reveals() {
    if (reduced) return;
    var targets = $$(".tour-head, .kit-head, .bento-g, .try-box, .race, .tour-step, .install-card, .steps > li");
    targets.forEach(function (n) { n.classList.add("rv"); });
    $$(".group-icon").forEach(function (n) { n.classList.add("rv-par"); });
    if (window.CSS && CSS.supports && CSS.supports("animation-timeline: view()")) return;
    root.classList.add("no-sda");
    if (!("IntersectionObserver" in window)) { targets.forEach(function (n) { n.classList.add("in"); }); return; }
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
    }, { rootMargin: "0px 0px -6% 0px" });
    targets.forEach(function (n) { io.observe(n); });
  })();

  /* =========================================================
     TIME OF DAY: the background tint follows the local clock
     ========================================================= */
  (function timeOfDay() {
    // hour, phase, [r, g, b, alpha]
    var K = [[0, "night", [86, 84, 196, 0.16]], [5, "night", [86, 84, 196, 0.16]], [6.5, "dawn", [255, 138, 150, 0.2]], [9, "day", [255, 214, 150, 0.12]],
             [16, "day", [255, 214, 150, 0.12]], [18, "golden hour", [255, 150, 40, 0.22]], [19.6, "dusk", [196, 84, 170, 0.2]], [21.5, "night", [86, 84, 196, 0.16]], [24, "night", [86, 84, 196, 0.16]]];
    var cap = $("#tod-cap");
    function apply() {
      var d = new Date(), h = d.getHours() + d.getMinutes() / 60, i = 1;
      while (i < K.length - 1 && K[i][0] <= h) i++;
      var a = K[i - 1], b = K[i], f = (h - a[0]) / (b[0] - a[0] || 1);
      var c = a[2].map(function (v, j) { return lerp(v, b[2][j], f); });
      root.style.setProperty("--tod", "rgba(" + c.slice(0, 3).map(Math.round).join(",") + "," + c[3].toFixed(3) + ")");
      if (cap) { cap.hidden = false; cap.textContent = "Background tinted for your local time: " + (f < 0.5 ? a[1] : b[1]) + "."; }
    }
    apply();
    setInterval(apply, 5 * 60 * 1000);
  })();

  /* ---------------- Start ---------------- */
  setLimit(80, "init");
  drawPot(0, 0);
  if (!reduced) startLoop();
})();
