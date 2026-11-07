// macOS browser identifiers do not reliably distinguish Intel from Apple silicon.
// Let Mac visitors choose; Windows visitors can download the x64 installer directly.
const RELEASE = "https://github.com/sarankumar1325/scrawl/releases/latest/download/";
const DOWNLOADS = "downloads.html";
document.querySelectorAll("[data-buy]").forEach((link) => {
  link.href = /Windows/i.test(navigator.userAgent)
    ? RELEASE + "Scrawl-Windows-x64-setup.exe" : DOWNLOADS;
});

// Copy the MCP command
document.querySelectorAll("[data-copy]").forEach((btn) => {
  btn.addEventListener("click", async () => {
    const text = document.querySelector(btn.dataset.copy)?.textContent ?? "";
    try {
      await navigator.clipboard.writeText(text);
      btn.textContent = "Copied";
    } catch {
      btn.textContent = "Press ⌘C";
      getSelection().selectAllChildren(document.querySelector(btn.dataset.copy));
    }
    setTimeout(() => (btn.textContent = "Copy"), 1800);
  });
});

// Effects below are ports of free React Bits components (reactbits.dev) to plain JS.
// Each stays off for people who prefer reduced motion; the page reads fine without them.
const motionOK = !matchMedia("(prefers-reduced-motion: reduce)").matches;
const finePointer = matchMedia("(hover: hover) and (pointer: fine)").matches;
const canObserve = "IntersectionObserver" in window;
const once = (el, threshold, fn) => {
  if (!el) return;
  if (!canObserve) return fn();
  new IntersectionObserver((entries, obs) => {
    if (entries[0].isIntersecting) { fn(); obs.disconnect(); }
  }, { threshold }).observe(el);
};

// Count Up: the price counts to $29 while its ring is drawn
const ticket = document.querySelector(".ticket");
const price = document.querySelector("[data-count-to]");
if (motionOK && price && canObserve) price.textContent = "0";
once(ticket, 0.5, () => {
  ticket.classList.add("is-visible");
  if (!motionOK || !price) return;
  const to = Number(price.dataset.countTo);
  const start = performance.now();
  const tick = (now) => {
    const t = Math.min(1, (now - start) / 900);
    price.textContent = Math.round(to * (1 - (1 - t) ** 3));
    if (t < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
});

// The closing headline's pen scrawl draws when the section comes into view
const finalSection = document.querySelector(".final");
once(finalSection, 0.35, () => finalSection.classList.add("is-in"));

// The "real recording" pen note draws its arrow when the GIF comes into view
const proof = document.querySelector(".proof");
once(proof, 0.4, () => proof.classList.add("is-drawn"));

// Sticky buy pill: shows once the hero is gone, hides again at the pricing card and the closing section
const sticky = document.querySelector(".sticky-buy");
if (sticky && canObserve) {
  const seen = new Map();
  const update = () => {
    const show = seen.get("hero") === false && !seen.get("pricing") && !seen.get("final");
    sticky.classList.toggle("is-shown", show);
    sticky.inert = !show;
  };
  const watch = (el, key) => el && new IntersectionObserver((entries) => {
    seen.set(key, entries[0].isIntersecting);
    update();
  }, { threshold: 0 }).observe(el);
  watch(document.querySelector(".hero"), "hero");
  watch(document.querySelector("#pricing"), "pricing");
  watch(document.querySelector(".final"), "final");
}

if (motionOK) {
  // Blur Text: the headline resolves word by word; the intro follows quickly
  const blurWords = (el, firstMs, stepMs) => {
    if (!el) return;
    let word = 0;
    const delay = () => `${firstMs + stepMs * word++}ms`;
    for (const node of [...el.childNodes]) {
      if (node.nodeType === Node.TEXT_NODE) {
        const frag = document.createDocumentFragment();
        for (const part of node.textContent.split(/(\s+)/)) {
          if (!part.trim()) { frag.append(part); continue; }
          const span = document.createElement("span");
          span.className = "bw";
          span.style.animationDelay = delay();
          span.textContent = part;
          frag.append(span);
        }
        node.replaceWith(frag);
      } else if (node.classList?.contains("inked")) {
        node.classList.add("bw"); // a pen-marked word stays one piece
        node.style.animationDelay = delay();
      }
    }
  };
  blurWords(document.querySelector(".hero__title"), 50, 55);
  blurWords(document.querySelector(".hero__lede"), 450, 12);

  // The hero tells the story in order: an empty board, the agent's prompt types itself,
  // create_board, then add_elements, and only then does the diagram draw onto the board,
  // zone by zone. "Done" and the pen notes come last.
  const term = document.querySelector(".term");
  const typed = term?.querySelector(".term__typed");
  const markup = document.querySelector(".window--hero .markup");
  const stage = document.querySelector(".hero__stage");
  if (term && typed && markup && stage) {
    const text = typed.dataset.type;
    const [createStep, addStep, doneStep] = term.querySelectorAll("[data-step]");

    // Blank-canvas panels over the diagram's regions, in drawing order (percent of the screenshot)
    const regions = [
      [4, 7.5, 36, 6],      // title
      [4, 13.5, 22.5, 54],  // edge zone
      [26.5, 13.5, 28.7, 54], // application zone
      [55.2, 13.5, 20.8, 54], // data zone
      [4, 67.5, 72, 25],    // design brief
    ];
    const cover = document.createElement("div");
    cover.className = "board-cover";
    cover.setAttribute("aria-hidden", "true");
    const panels = regions.map(([l, t, w, h]) => {
      const panel = document.createElement("i");
      panel.style.cssText = `left:${l}%;top:${t}%;width:${w}%;height:${h}%`;
      cover.append(panel);
      return panel;
    });
    markup.querySelector("img").after(cover);
    markup.classList.add("is-waiting");
    term.classList.add("is-typing");
    typed.textContent = "";

    const drawBoard = () => {
      panels.forEach((panel, n) => setTimeout(() => panel.classList.add("is-off"), 150 + n * 430));
      const drawn = 150 + panels.length * 430 + 350;
      setTimeout(() => doneStep.classList.add("is-shown"), drawn);
      setTimeout(() => markup.classList.remove("is-waiting"), drawn + 300);
    };

    once(stage, 0.3, () => {
      let i = 0;
      const type = () => {
        typed.textContent = text.slice(0, ++i);
        if (i < text.length) return setTimeout(type, 28 + Math.random() * 30);
        setTimeout(() => createStep.classList.add("is-shown"), 450);
        setTimeout(() => { addStep.classList.add("is-shown"); drawBoard(); }, 1050);
      };
      setTimeout(type, Math.max(400, 2500 - performance.now())); // after the terminal slides in
    });
  }

  // Scroll Expand: the hero window starts leaning back and flattens toward you as you scroll
  const heroWindow = document.querySelector(".window--hero");
  if (heroWindow) {
    let queued = false;
    const lean = () => {
      queued = false;
      const top = heroWindow.getBoundingClientRect().top;
      const p = Math.min(1, Math.max(0, top / (innerHeight * 0.9)));
      heroWindow.style.setProperty("--lift", `${(p * 9).toFixed(2)}deg`);
    };
    lean();
    addEventListener("scroll", () => { if (!queued) { queued = true; requestAnimationFrame(lean); } }, { passive: true });
    addEventListener("resize", lean);
  }

  // Rotating Text: the diagram the agent is asked for keeps changing
  document.querySelectorAll(".rotator").forEach((rot) => {
    const words = rot.dataset.words.split("|");
    let n = 0;
    setInterval(() => {
      const old = rot.querySelector("span:not(.rotator__sizer):not(.is-out)");
      n = (n + 1) % words.length;
      const next = document.createElement("span");
      next.className = "is-in";
      next.textContent = words[n];
      old?.classList.add("is-out");
      setTimeout(() => old?.remove(), 420); // a timer, not animationend: hidden tabs skip animation events
      rot.append(next);
    }, 2600);
  });

  // Scroll Velocity: the prompt marquee drifts, and speeds up with your scrolling
  document.querySelectorAll("[data-velocity]").forEach((marquee) => {
    const track = marquee.querySelector(".marquee__track");
    track.append(...[...track.children].map((li) => {
      const copy = li.cloneNode(true);
      copy.setAttribute("aria-hidden", "true");
      return copy;
    }));
    const dir = marquee.dataset.direction === "right" ? 1 : -1;
    let x = null, boost = 0, lastY = scrollY, last = performance.now();
    const frame = (now) => {
      const dt = Math.min(64, now - last);
      last = now;
      boost += (Math.abs(scrollY - lastY) * 0.6 - boost) * 0.08;
      lastY = scrollY;
      const half = track.scrollWidth / 2;
      if (x === null) x = dir > 0 ? -half : 0;
      x += dir * (0.03 + boost * 0.004) * dt;
      if (dir < 0 && -x >= half) x += half;
      if (dir > 0 && x >= 0) x -= half;
      track.style.transform = `translate3d(${x}px, 0, 0)`;
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  });

  // Fade Content: sections rise in as they scroll into view; bento cards stagger
  if (canObserve) {
    const reveal = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (!e.isIntersecting) continue;
        e.target.classList.add("is-in");
        reveal.unobserve(e.target);
      }
    }, { threshold: 0.12 });
    document.querySelectorAll(".section__head, .split__text, .proof, .tools, .card, .compare__table, .ticket, .assure, .faq").forEach((el) => {
      if (el.classList.contains("card")) el.style.transitionDelay = `${[...el.parentElement.children].indexOf(el) * 70}ms`;
      el.classList.add("reveal");
      reveal.observe(el);
    });
  }

  // Click Spark: short coral strokes burst from each click
  document.addEventListener("click", (e) => {
    if (!e.detail) return; // keyboard "clicks" have no position
    for (let i = 0; i < 8; i++) {
      const s = document.createElement("i");
      s.className = "spark";
      s.style.left = `${e.clientX}px`;
      s.style.top = `${e.clientY}px`;
      s.style.setProperty("--a", `${i * 45}deg`);
      s.addEventListener("animationend", () => s.remove());
      document.body.append(s);
    }
  });
}

if (motionOK && finePointer) {
  // Magnet: buttons lean toward the cursor, then settle back
  const magnets = [...document.querySelectorAll(".btn:not(.btn--block)")];
  magnets.forEach((b) => b.classList.add("magnet"));
  let pending = false;
  addEventListener("pointermove", (e) => {
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => {
      pending = false;
      for (const b of magnets) {
        const r = b.getBoundingClientRect();
        const near = e.clientX > r.left - 40 && e.clientX < r.right + 40 && e.clientY > r.top - 40 && e.clientY < r.bottom + 40;
        b.style.setProperty("--mag-x", near ? `${(e.clientX - (r.left + r.width / 2)) * 0.18}px` : "0px");
        b.style.setProperty("--mag-y", near ? `${(e.clientY - (r.top + r.height / 2)) * 0.28}px` : "0px");
      }
    });
  }, { passive: true });

  // Spotlight Card + Border Glow (Magic Bento): light and edge glow follow the pointer
  const lightUp = (el) => el.addEventListener("pointermove", (e) => {
    const r = el.getBoundingClientRect();
    el.style.setProperty("--sx", `${e.clientX - r.left}px`);
    el.style.setProperty("--sy", `${e.clientY - r.top}px`);
  });
  document.querySelectorAll(".ticket, .tools > div, .card").forEach((el) => {
    el.classList.add("spot");
    lightUp(el);
  });
  // The bento's edge glow follows the cursor across every card, like Magic Bento
  document.querySelectorAll(".bento").forEach((bento) => bento.addEventListener("pointermove", (e) => {
    for (const card of bento.children) {
      const r = card.getBoundingClientRect();
      card.style.setProperty("--sx", `${e.clientX - r.left}px`);
      card.style.setProperty("--sy", `${e.clientY - r.top}px`);
    }
  }));

  // Tilted Card: windows lean a few degrees toward the cursor
  document.querySelectorAll(".tilt").forEach((card) => {
    card.addEventListener("pointermove", (e) => {
      const r = card.getBoundingClientRect();
      const px = (e.clientX - r.left) / r.width - 0.5;
      const py = (e.clientY - r.top) / r.height - 0.5;
      card.style.setProperty("--ry", `${px * 5}deg`);
      card.style.setProperty("--rx", `${-py * 4}deg`);
    });
    card.addEventListener("pointerleave", () => {
      card.style.setProperty("--ry", "0deg");
      card.style.setProperty("--rx", "0deg");
    });
  });

  // Dot Field: dots near the cursor swell and turn coral. The hero's dots sit on the page's
  // own 22px grid; the closing section's dots sit on that section's grid.
  document.querySelectorAll(".dot-field").forEach((field) => {
    const host = field.parentElement;
    const pageGrid = !field.classList.contains("dot-field--dark");
    const ctx = field.getContext("2d");
    const GAP = 22, RADIUS = 150;
    let px = 0, py = 0, strength = 0, target = 0, running = false;
    const pen = getComputedStyle(document.documentElement).getPropertyValue("--pen").trim() || "#e5484d";

    const resize = () => {
      const dpr = Math.min(devicePixelRatio || 1, 2);
      field.width = host.offsetWidth * dpr;
      field.height = host.offsetHeight * dpr;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    const draw = () => {
      strength += (target - strength) * 0.12;
      ctx.clearRect(0, 0, field.width, field.height);
      const r = host.getBoundingClientRect();
      const ox = pageGrid ? r.left + scrollX : 0, oy = pageGrid ? r.top + scrollY : 0;
      const x0 = Math.floor((ox + px - RADIUS) / GAP), x1 = Math.ceil((ox + px + RADIUS) / GAP);
      const y0 = Math.floor((oy + py - RADIUS) / GAP), y1 = Math.ceil((oy + py + RADIUS) / GAP);
      ctx.fillStyle = pen;
      for (let gx = x0; gx <= x1; gx++) {
        for (let gy = y0; gy <= y1; gy++) {
          const x = gx * GAP + GAP / 2 - ox, y = gy * GAP + GAP / 2 - oy;
          const d = Math.hypot(x - px, y - py);
          if (d >= RADIUS) continue;
          const e = (1 - d / RADIUS) ** 2 * strength;
          ctx.globalAlpha = 0.12 + 0.65 * e;
          ctx.beginPath();
          ctx.arc(x, y, 1 + 2.4 * e, 0, Math.PI * 2);
          ctx.fill();
        }
      }
      if (target === 0 && strength < 0.01) {
        running = false;
        ctx.clearRect(0, 0, field.width, field.height);
        return;
      }
      requestAnimationFrame(draw);
    };
    resize();
    addEventListener("resize", resize);
    host.addEventListener("pointermove", (e) => {
      const r = host.getBoundingClientRect();
      px = e.clientX - r.left;
      py = e.clientY - r.top;
      target = 1;
      if (!running) { running = true; requestAnimationFrame(draw); }
    });
    host.addEventListener("pointerleave", () => (target = 0));
  });
}
