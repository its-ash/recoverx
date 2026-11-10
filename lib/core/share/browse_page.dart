/// HTML for the LAN browse view served by `BrowseServer`.
///
/// Self-contained (no CDN): the computer may not have internet access.
/// Item data is only ever inserted with `textContent` / attributes, never
/// as HTML, because names and paths come from the examined device.
library;

const _style = '''
:root{--bg:#f6f7f9;--surface:#fff;--muted:#eef0f3;--border:#e1e4e8;--text:#14171c;--sub:#5b6472;--accent:#4f46e5;--onaccent:#fff;--danger:#d92d20;--warn:#b54708;--info:#0b6bcb;--ok:#067647;--radius:14px}
@media (prefers-color-scheme:dark){:root{--bg:#0d0f12;--surface:#16191e;--muted:#1f232a;--border:#2a2f37;--text:#eef0f3;--sub:#9aa3b2;--accent:#818cf8;--onaccent:#0d0f12;--danger:#f97066;--warn:#fdb022;--info:#53b1fd;--ok:#47cd89}}
*{box-sizing:border-box}html,body{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
button,input,select{font:inherit;color:inherit}
.btn{border:1px solid var(--border);background:var(--surface);padding:8px 14px;border-radius:999px;cursor:pointer;text-decoration:none;color:var(--text);display:inline-flex;align-items:center;gap:6px}
.btn.primary{background:var(--accent);border-color:var(--accent);color:var(--onaccent)}
.field{border:1px solid var(--border);background:var(--surface);padding:9px 14px;border-radius:999px;outline:none}
.field:focus{border-color:var(--accent)}
''';

/// PIN form shown before a session cookie is set.
String loginPageHtml({String? error}) => '''
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RecoverX</title><style>$_style
main{max-width:360px;margin:12vh auto;padding:28px;background:var(--surface);border:1px solid var(--border);border-radius:var(--radius)}
h1{margin:0 0 6px;font-size:22px}p{color:var(--sub);margin:0 0 18px}
input{width:100%;text-align:center;letter-spacing:.4em;font-size:24px;padding:12px;border-radius:12px}
.err{color:var(--danger);margin:12px 0 0}button{width:100%;justify-content:center;margin-top:14px}
</style></head><body><main>
<h1>RecoverX</h1><p>Enter the PIN shown on the phone.</p>
<form method="post" action="/login" autocomplete="off">
<input class="field" name="pin" inputmode="numeric" pattern="[0-9]*" maxlength="6" autofocus required>
<button class="btn primary" type="submit">Open</button>
</form>
${error == null ? '' : '<p class="err">${_escape(error)}</p>'}
</main></body></html>
''';

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

/// Results browser: search, filters, lazy thumbnail grid, viewer.
const browsePageHtml = '''
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RecoverX · Results</title><style>$_style
header{position:sticky;top:0;z-index:5;background:color-mix(in srgb,var(--bg) 88%,transparent);backdrop-filter:blur(12px);border-bottom:1px solid var(--border);padding:12px 20px}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
h1{font-size:18px;margin:0 12px 0 0}
#q{flex:1;min-width:200px}
.chips{display:flex;gap:6px;flex-wrap:wrap;margin-top:10px}
.chip{border:1px solid var(--border);background:var(--surface);padding:5px 12px;border-radius:999px;cursor:pointer;font-size:13px}
.chip.on{background:var(--accent);border-color:var(--accent);color:var(--onaccent)}
#count{color:var(--sub);font-size:13px;margin-left:auto}
.note{color:var(--sub);font-size:12px;padding:8px 20px 0}
#grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:12px;padding:16px 20px 40px}
.card{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);overflow:hidden;cursor:pointer;transition:transform .12s,box-shadow .12s;display:flex;flex-direction:column}
.card:hover{transform:translateY(-2px);box-shadow:0 8px 24px rgba(0,0,0,.12)}
.thumb{aspect-ratio:1;background:var(--muted);display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:600;color:var(--sub);position:relative;overflow:hidden}
.thumb img{width:100%;height:100%;object-fit:cover}
.thumb .play{position:absolute;inset:auto auto 8px 8px;background:rgba(0,0,0,.6);color:#fff;border-radius:999px;padding:2px 8px;font-size:11px}
.meta{padding:8px 10px 10px}
.name{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sub{color:var(--sub);font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tags{display:flex;gap:4px;flex-wrap:wrap;margin-top:6px}
.tag{font-size:10.5px;font-weight:600;padding:1px 7px;border-radius:999px;background:var(--muted);color:var(--sub)}
.tag.explicit{color:#fff;background:var(--danger)}.tag.suggestive{color:#fff;background:var(--warn)}
.thumb.blur img{filter:blur(14px);transform:scale(1.15)}
.thumb .veil{position:absolute;inset:auto 8px 8px auto;background:rgba(0,0,0,.6);color:#fff;border-radius:999px;padding:2px 8px;font-size:11px}
.stage{position:relative}
.stage.blur img,.stage.blur video{filter:blur(36px)}
.reveal{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;color:#fff;background:rgba(0,0,0,.35);text-align:center;padding:20px}
.tag.trashed{color:var(--danger)}.tag.renamed{color:var(--warn)}.tag.hidden{color:var(--info)}.tag.carved{color:var(--accent)}.tag.damaged{color:var(--warn)}
#sentinel{height:1px}
.empty{color:var(--sub);text-align:center;padding:60px 20px;grid-column:1/-1}
dialog{border:none;border-radius:var(--radius);padding:0;background:var(--surface);color:var(--text);width:min(1100px,96vw);max-height:94vh}
dialog::backdrop{background:rgba(0,0,0,.7)}
.viewer{display:grid;grid-template-columns:minmax(0,1fr) 320px;max-height:94vh}
@media (max-width:800px){.viewer{grid-template-columns:1fr;overflow:auto}}
.stage{background:#000;display:flex;align-items:center;justify-content:center;min-height:300px;max-height:94vh}
.stage img,.stage video{max-width:100%;max-height:94vh;display:block}
.stage audio{width:90%}
.stage .none{color:#9aa3b2;padding:40px;text-align:center}
.side{padding:16px;overflow:auto;max-height:94vh}
.side h2{font-size:16px;margin:0 0 4px;word-break:break-all}
dl{display:grid;grid-template-columns:auto 1fr;gap:6px 12px;font-size:12.5px;margin:14px 0}
dt{color:var(--sub)}dd{margin:0;word-break:break-all}
.mono{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px}
.actions{display:flex;gap:6px;flex-wrap:wrap}
.warn{font-size:12px;color:var(--sub);border-left:3px solid var(--warn);padding:4px 10px;margin-top:12px}
.nav{display:flex;gap:6px;margin-bottom:12px}
</style></head><body>
<header>
  <div class="row">
    <h1>RecoverX</h1>
    <input id="q" class="field" type="search" placeholder="Search name, path, app">
    <select id="sort" class="field">
      <option value="newest">Newest first</option><option value="oldest">Oldest first</option>
      <option value="largest">Largest first</option><option value="smallest">Smallest first</option>
      <option value="name">Name</option><option value="type">Type</option>
    </select>
    <button id="reload" class="btn" title="Reload results">Reload</button>
    <a class="btn" href="/downloads/report.json" title="SHA-256 of every file downloaded from this phone (JSON)">Download log</a>
    <a class="btn" href="/downloads/manifest.csv" title="Same log as CSV">CSV</a>
    <a class="btn" href="/logout">Sign out</a>
  </div>
  <div class="chips" id="views"></div>
  <div class="chips" id="cats"></div>
</header>
<div class="note"><span id="count"></span> · Read-only view of the phone. Every download is SHA-256 hashed as it is sent and listed in the Download log.</div>
<main id="grid"></main><div id="sentinel"></div>
<dialog id="dlg"><div class="viewer"><div class="stage" id="stage"></div><div class="side" id="side"></div></div></dialog>
<script>
"use strict";
const PAGE = 120;
const VIEWS = [["all","All"],["flagged","Flagged"],["trashed","Trash"],["hidden","Hidden"],["renamed","Renamed"],["carved","Carved"],["cache","Cache"],["truncated","Damaged"],["sensitive","Sensitive"]];
const CATS = [["image","Photos"],["video","Videos"],["audio","Audio"],["document","Documents"],["archive","Archives"],["data","App data"],["other","Other"]];
const REASON = {renamed:"Renamed",hidden:"Hidden",trashed:"Trash",cache:"Cache",carved:"Carved"};
const BROWSER_IMG = /^image\\/(jpeg|png|gif|webp|bmp|avif|heic|heif)\$/;
let all = [], list = [], shown = 0, view = "all", cats = new Set(), current = -1;

const \$ = (id) => document.getElementById(id);
function el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
function fileUrl(it, dl) { return "/file?id=" + encodeURIComponent(it.id) + (dl ? "&download=1" : ""); }
function bytes(n) { const u = ["B","KB","MB","GB","TB"]; let i = 0; while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; } return (i ? n.toFixed(1) : n) + " " + u[i]; }
function when(it) { return it.taken || it.modified; }
function fmtDate(s) { if (!s) return ""; const d = new Date(s); return d.toLocaleString(); }

function matchesView(it, v) {
  switch (v) {
    case "all": return true;
    case "flagged": return it.reasons.length > 0;
    case "truncated": return it.integrity === "truncated";
    case "sensitive": return flagged(it);
    default: return it.reasons.includes(v);
  }
}

function apply() {
  const q = \$("q").value.trim().toLowerCase();
  const sort = \$("sort").value;
  list = all.filter((it) => matchesView(it, view) && (cats.size === 0 || cats.has(it.category)) &&
    (!q || it.path.toLowerCase().includes(q) || it.name.toLowerCase().includes(q) ||
      (it.app || "").toLowerCase().includes(q) || it.type.toLowerCase().includes(q)));
  const byDate = (a, b) => (when(b) || "").localeCompare(when(a) || "");
  const cmp = { newest: byDate, oldest: (a, b) => byDate(b, a), largest: (a, b) => b.size - a.size,
    smallest: (a, b) => a.size - b.size, name: (a, b) => a.name.localeCompare(b.name), type: (a, b) => a.type.localeCompare(b.type) }[sort];
  list.sort(cmp);
  \$("count").textContent = list.length.toLocaleString() + " of " + all.length.toLocaleString() + " items";
  \$("grid").replaceChildren();
  shown = 0;
  if (!list.length) \$("grid").append(el("div", "empty", all.length ? "Nothing matches." : "No results yet. Run a scan on the phone."));
  more();
}

// ── Sensitive content (on-device check in the app) ──
// Flagged items stay blurred until revealed; reveals last for this page.
const LEVEL = {explicit: "Explicit", suggestive: "Suggestive"};
const revealed = new Set();
const thumbsById = new Map();
function flagged(it) { return !!(it.sensitive && it.sensitive.level !== "safe"); }
let BLUR = true;   // app setting "Blur flagged items" (/api/config)
function hiddenItem(it) { return BLUR && flagged(it) && !revealed.has(it.id); }
function reveal(it) {
  revealed.add(it.id);
  const t = thumbsById.get(it.id);
  if (t) { t.classList.remove("blur"); t.querySelector(".veil")?.remove(); }
}

function card(it, idx) {
  const c = el("div", "card");
  const t = el("div", "thumb");
  thumbsById.set(it.id, t);
  if (hiddenItem(it)) { t.classList.add("blur"); t.append(el("span", "veil", "Hidden")); }
  if (BROWSER_IMG.test(it.mime)) {
    const img = new Image(); img.loading = "lazy"; img.decoding = "async"; img.alt = ""; img.src = fileUrl(it);
    img.onerror = () => { img.remove(); t.textContent = it.ext.toUpperCase(); };
    t.append(img);
  } else {
    t.append(el("span", "label", it.ext.toUpperCase()));
  }
  if (it.category === "video") {
    const play = el("span", "play", "▶ Video");
    t.append(play);
    t._item = it; t._play = play;
    const cached = thumbCache.get(it.id);
    if (cached) showThumb(t, cached); else if (!thumbCache.has(it.id)) thumbObserver.observe(t);
  }
  const m = el("div", "meta");
  m.append(el("div", "name", it.name));
  m.append(el("div", "sub", [bytes(it.size), it.app, fmtDate(when(it))].filter(Boolean).join(" · ")));
  const tags = el("div", "tags");
  if (flagged(it)) tags.append(el("span", "tag " + it.sensitive.level, LEVEL[it.sensitive.level]));
  for (const r of it.reasons) tags.append(el("span", "tag " + r, REASON[r] || r));
  if (it.integrity === "truncated") tags.append(el("span", "tag damaged", "Damaged"));
  if (tags.childElementCount) m.append(tags);
  c.append(t, m);
  c.onclick = () => open(idx);
  return c;
}

// ── Video thumbnails ──
// Made in this browser: load the video's metadata (HTTP Range), seek to ~10%,
// draw the frame on a canvas. The phone only serves bytes; nothing is stored
// there. At most THUMB_JOBS videos load at once so the phone is not swamped.
const THUMB_JOBS = 3;
const thumbCache = new Map();   // id -> {url, duration} | null (cannot decode)
const thumbQueue = [];
let thumbActive = 0;
const thumbObserver = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (!e.isIntersecting) continue;
    thumbObserver.unobserve(e.target);
    thumbQueue.push(e.target);
  }
  pumpThumbs();
}, { rootMargin: "300px" });

function pumpThumbs() {
  while (thumbActive < THUMB_JOBS && thumbQueue.length) {
    const t = thumbQueue.shift();
    if (!t.isConnected) continue;   // filtered away before its turn
    thumbActive++;
    videoThumb(t._item)
      .then((r) => { if (r && t.isConnected) showThumb(t, r); })
      .finally(() => { thumbActive--; pumpThumbs(); });
  }
}

function videoThumb(it) {
  if (thumbCache.has(it.id)) return Promise.resolve(thumbCache.get(it.id));
  return new Promise((resolve) => {
    const v = document.createElement("video");
    v.muted = true; v.preload = "metadata"; v.playsInline = true;
    let done = false;
    const finish = (r) => {
      if (done) return;
      done = true; clearTimeout(timer);
      v.removeAttribute("src"); v.load();   // drop the connection
      thumbCache.set(it.id, r);
      resolve(r);
    };
    const timer = setTimeout(() => finish(null), 20000);
    v.onloadedmetadata = () => {
      const d = v.duration;
      v.currentTime = isFinite(d) && d > 0 ? Math.min(1.5, d * 0.1) : 0;
    };
    v.onseeked = () => {
      try {
        const w = 360, vw = v.videoWidth || 16, vh = v.videoHeight || 9;
        if (!v.videoWidth) return finish(null);   // audio-only or undecodable
        const c = document.createElement("canvas");
        c.width = w; c.height = Math.round(w * vh / vw);
        c.getContext("2d").drawImage(v, 0, 0, c.width, c.height);
        finish({ url: c.toDataURL("image/jpeg", 0.75), duration: isFinite(v.duration) ? v.duration : null });
      } catch (e) { finish(null); }
    };
    v.onerror = () => finish(null);
    v.src = fileUrl(it);
  });
}

function fmtDur(s) {
  s = Math.round(s);
  const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = String(s % 60).padStart(2, "0");
  return h ? h + ":" + String(m).padStart(2, "0") + ":" + sec : m + ":" + sec;
}

function showThumb(t, r) {
  const img = new Image(); img.alt = ""; img.src = r.url;
  t.querySelector(".label")?.remove();
  t.prepend(img);
  if (r.duration) t._play.textContent = "▶ " + fmtDur(r.duration);
}

function more() {
  const end = Math.min(list.length, shown + PAGE);
  const frag = document.createDocumentFragment();
  for (let i = shown; i < end; i++) frag.append(card(list[i], i));
  \$("grid").append(frag);
  shown = end;
}

new IntersectionObserver((e) => { if (e[0].isIntersecting && shown < list.length) more(); }, { rootMargin: "800px" }).observe(\$("sentinel"));

function open(idx) {
  current = idx;
  const it = list[idx];
  const stage = \$("stage"), side = \$("side");
  stage.querySelectorAll("video,audio").forEach((m) => m.pause());
  stage.replaceChildren(); side.replaceChildren();
  const hide = hiddenItem(it);
  stage.classList.toggle("blur", hide);
  if (it.mime.startsWith("image/")) {
    const img = new Image(); img.src = fileUrl(it); img.alt = it.name;
    img.onerror = () => stage.replaceChildren(el("div", "none", "This browser cannot show " + it.type + ". Download it to view."));
    stage.append(img);
  } else if (it.mime.startsWith("video/")) {
    const v = document.createElement("video"); v.controls = !hide; v.autoplay = !hide; v.preload = "metadata";
    const th = thumbCache.get(it.id); if (th) v.poster = th.url;
    v.src = fileUrl(it);
    v.onerror = () => stage.replaceChildren(el("div", "none", "This browser cannot play " + it.type + ". Download it and open it in VLC."));
    stage.append(v);
  } else if (it.mime.startsWith("audio/")) {
    const a = document.createElement("audio"); a.controls = true; a.autoplay = true; a.src = fileUrl(it);
    stage.append(a);
  } else {
    stage.append(el("div", "none", it.type + " · no preview"));
  }
  if (hide) {
    const veil = el("div", "reveal");
    veil.append(el("strong", null, LEVEL[it.sensitive.level] + " content"),
      el("div", null, "Flagged by the on-device check for review. It can be wrong."));
    const show = el("button", "btn primary", "Show");
    show.onclick = () => { reveal(it); open(idx); };
    veil.append(show);
    stage.append(veil);
  }

  const nav = el("div", "nav");
  const prev = el("button", "btn", "← Prev"); prev.disabled = idx === 0; prev.onclick = () => open(idx - 1);
  const next = el("button", "btn", "Next →"); next.disabled = idx >= list.length - 1; next.onclick = () => open(idx + 1);
  const close = el("button", "btn", "Close"); close.onclick = () => \$("dlg").close();
  nav.append(prev, next, close);
  side.append(nav, el("h2", null, it.name), el("div", "sub", it.type + " · " + bytes(it.size)));

  const dl = el("dl");
  const row = (k, v, mono) => { if (v == null || v === "") return; dl.append(el("dt", null, k)); dl.append(el("dd", mono ? "mono" : null, String(v))); };
  row("Real type", it.type + " (." + it.ext + ")");
  row("MIME", it.mime, true);
  row("Size", bytes(it.size) + " (" + it.size.toLocaleString() + " bytes)");
  row("Name on disk", it.diskName);
  row(it.offset != null ? "Carved from" : "Path", it.path, true);
  if (it.offset != null) row("Byte offset", it.offset + " (0x" + it.offset.toString(16) + ")", true);
  row("App / folder", it.app);
  row("Flags", it.reasons.map((r) => REASON[r] || r).join(", "));
  row("Integrity", it.integrity);
  row("Match", it.confidence);
  if (it.sensitive) {
    const s = it.sensitive;
    row("Content check", (LEVEL[s.level] || "Not flagged") + " · explicit " + Math.round(s.explicit * 100) +
      "%, suggestive " + Math.round(s.suggestive * 100) + "%" + (s.frames > 1 ? " (" + s.frames + " frames)" : ""));
  }
  row("File modified", fmtDate(it.modified));
  for (const [k, v] of Object.entries(it.meta || {})) row(k, v);
  dl.append(el("dt", null, "SHA-256"));
  const hashCell = el("dd", "mono");
  const hashBtn = el("button", "btn", "Compute");
  hashBtn.onclick = async () => {
    hashBtn.disabled = true; hashBtn.textContent = "Hashing…";
    try {
      const r = await fetch("/api/hash?id=" + encodeURIComponent(it.id), { cache: "no-store" });
      if (!r.ok) throw new Error(r.status);
      hashCell.textContent = (await r.json()).sha256;
    } catch (e) { hashBtn.disabled = false; hashBtn.textContent = "Retry"; }
  };
  hashCell.append(hashBtn);
  dl.append(hashCell);
  side.append(dl);

  const actions = el("div", "actions");
  const o = el("a", "btn", "Open in new tab"); o.href = fileUrl(it); o.target = "_blank"; o.rel = "noopener";
  const d = el("a", "btn primary", "Download"); d.href = fileUrl(it, true);
  actions.append(o, d);
  side.append(actions, el("div", "warn",
    "Each download is SHA-256 hashed on the phone as it is sent and listed in the Download log. " +
    "Check your copy with: shasum -a 256 <file> (macOS/Linux) or certutil -hashfile <file> SHA256 (Windows)."));
  if (!\$("dlg").open) \$("dlg").showModal();
}

\$("dlg").addEventListener("close", () => { \$("stage").querySelectorAll("video,audio").forEach((m) => m.pause()); \$("stage").replaceChildren(); });
\$("dlg").addEventListener("click", (e) => { if (e.target === \$("dlg")) \$("dlg").close(); });
document.addEventListener("keydown", (e) => {
  if (!\$("dlg").open) return;
  if (e.key === "ArrowRight" && current < list.length - 1) open(current + 1);
  if (e.key === "ArrowLeft" && current > 0) open(current - 1);
});

function chips(host, items, isOn, onTap) {
  host.replaceChildren();
  for (const [k, label] of items) {
    const b = el("button", "chip" + (isOn(k) ? " on" : ""), label);
    b.onclick = () => { onTap(k); render(); apply(); };
    host.append(b);
  }
}
function render() {
  const count = (fn) => all.filter(fn).length;
  chips(\$("views"), VIEWS.map(([k, l]) => [k, l + " " + count((it) => matchesView(it, k)).toLocaleString()]),
    (k) => k === view, (k) => { view = k; });
  chips(\$("cats"), CATS.filter(([k]) => all.some((it) => it.category === k)).map(([k, l]) => [k, l + " " + count((it) => it.category === k).toLocaleString()]),
    (k) => cats.has(k), (k) => { cats.has(k) ? cats.delete(k) : cats.add(k); });
}

async function load() {
  const r = await fetch("/api/items", { cache: "no-store" });
  if (r.status === 401) { location.href = "/"; return; }
  all = await r.json();
  try { BLUR = (await (await fetch("/api/config", { cache: "no-store" })).json()).blur !== false; } catch (e) { BLUR = true; }
  render(); apply();
}

let timer;
\$("q").addEventListener("input", () => { clearTimeout(timer); timer = setTimeout(apply, 200); });
\$("sort").addEventListener("change", apply);
\$("reload").addEventListener("click", load);
load();
</script></body></html>
''';
