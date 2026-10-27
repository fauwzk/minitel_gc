// Interface d'administration du Minitel Magis Club
"use strict";

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

// ---------------------------------------------------------------- API
async function api(method, path, body, raw) {
  const opts = { method, headers: { "X-Minitel": "1" } };
  if (body !== undefined) {
    if (raw) { opts.body = body; }
    else { opts.body = JSON.stringify(body); opts.headers["Content-Type"] = "application/json"; }
  }
  const r = await fetch(path, opts);
  if (r.status === 401 && path !== "/api/connexion") { showLogin(); throw new Error("connexion requise"); }
  const type = r.headers.get("Content-Type") || "";
  const data = type.includes("json") ? await r.json() : await r.text();
  if (!r.ok) throw new Error((data && data.erreur) || ("erreur " + r.status));
  return data;
}

function toast(text, err) {
  const t = $("#toast");
  t.textContent = text;
  t.className = "toast" + (err ? " err" : "");
  t.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => (t.hidden = true), 4000);
}

function fmtSize(n) {
  if (n >= 1048576) return (n / 1048576).toFixed(1) + " Mo";
  if (n >= 1024) return Math.round(n / 1024) + " Ko";
  return n + " o";
}

// ---------------------------------------------------------------- connexion
function showLogin(msg) {
  $("#app").hidden = true;
  $("#login").hidden = false;
  $("#login-msg").textContent = msg || "";
  $("#pw").focus();
}

$("#login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    await api("POST", "/api/connexion", { mot_de_passe: $("#pw").value });
    $("#pw").value = "";
    start();
  } catch (err) {
    $("#login-msg").textContent = err.message;
    $("#login-msg").className = "msg err";
  }
});

$("#logout").addEventListener("click", async () => {
  await api("POST", "/api/deconnexion").catch(() => {});
  showLogin("Déconnecté.");
});

// ---------------------------------------------------------------- onglets
const tabs = {};
function showTab(name) {
  document.querySelectorAll(".tab").forEach((b) => b.classList.toggle("active", b.dataset.tab === name));
  document.querySelectorAll(".page").forEach((p) => (p.hidden = p.id !== "tab-" + name));
  if (tabs[name]) tabs[name]();
  try { localStorage.setItem("minitel-tab", name); } catch (e) { /* stockage indisponible */ }
}
document.querySelectorAll(".tab").forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));

// ---------------------------------------------------------------- terminaux
// Une session = un pseudo-terminal sur le Pi relie par WebSocket.
function openTerminal(kind, arg, el, stateEl, onEnd) {
  el.innerHTML = "";
  if (typeof Terminal === "undefined") {
    toast("Le terminal (xterm.js) n'a pas pu être chargé : rechargez la page.", true);
    return { term: null, ws: null, close: () => {} };
  }
  const term = new Terminal({
    cols: 80, rows: 24, cursorBlink: true, convertEol: false,
    fontFamily: '"JetBrains Mono", "Cascadia Mono", Consolas, monospace', fontSize: 15,
    theme: { background: "#000000", foreground: "#e8e8e8", cursor: "#f2b33d" },
  });
  let fit = null;
  if (kind === "shell") { fit = new FitAddon.FitAddon(); term.loadAddon(fit); }
  term.open(el);
  const proto = location.protocol === "https:" ? "wss://" : "ws://";
  const ws = new WebSocket(proto + location.host + "/ws/terminal/" + kind + (arg ? "/" + encodeURIComponent(arg) : ""));
  const setState = (txt, cls) => { if (stateEl) { stateEl.textContent = txt; stateEl.className = "pill " + (cls || ""); } };
  setState("connexion…", "warn");
  const sendSize = () => {
    if (fit && ws.readyState === 1) { fit.fit(); ws.send(JSON.stringify({ type: "taille", cols: term.cols, rows: term.rows })); }
  };
  ws.onopen = () => { setState("en cours", "ok"); term.focus(); sendSize(); };
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.type === "sortie") term.write(msg.data);
    else if (msg.type === "taille" && !fit) term.resize(msg.cols, msg.rows);
    else if (msg.type === "fin") {
      setState(msg.code === 0 ? "terminé" : "terminé (code " + msg.code + ")", msg.code === 0 ? "ok" : "err");
      term.write("\r\n\x1b[2m[session terminée]\x1b[0m\r\n");
      if (onEnd) onEnd(msg.code);
    }
  };
  let opened = false;
  ws.addEventListener("open", () => { opened = true; });
  ws.onclose = (ev) => {
    if (!opened) {
      setState("refusé", "err");
      term.write("\x1b[31mConnexion au terminal impossible (code " + ev.code + ").\x1b[0m\r\n" +
        "Rechargez la page et reconnectez-vous ; sinon, sur le Pi :\r\n" +
        "  journalctl -u minitel-web -n 30\r\n");
    } else if (stateEl && stateEl.textContent === "en cours") setState("fermé");
  };
  ws.onerror = () => setState("refusé", "err");
  term.onData((d) => { if (ws.readyState === 1) ws.send(JSON.stringify({ type: "entree", data: d })); });
  if (fit) { const ro = new ResizeObserver(sendSize); ro.observe(el); }
  return { term, ws, close: () => { try { ws.close(); } catch (e) { /* deja ferme */ } term.dispose(); } };
}

// ---------------------------------------------------------------- tableau de bord
function gauge(label, value, max, unit, hotAt) {
  const pct = max ? Math.min(100, Math.round((value / max) * 100)) : 0;
  const cls = hotAt && pct >= hotAt ? "hot" : hotAt && pct >= hotAt - 15 ? "warm" : "";
  return `<div class="gauge"><div class="lbl"><span>${label}</span><b>${esc(value)}${unit} / ${esc(max)}${unit}</b></div>
          <div class="bar"><i class="${cls}" style="width:${pct}%"></i></div></div>`;
}

async function loadInfo() {
  const box = $("#info");
  try {
    const i = await api("GET", "/api/info");
    const svc = Object.entries(i.services).map(([n, s]) =>
      `<li><span>${esc(n)}</span><span class="pill ${s === "active" ? "ok" : s === "inactive" ? "" : "err"}">${esc(s)}</span></li>`).join("");
    const t = i.temperature;
    const tools = i.outils;
    box.innerHTML = `
      <div class="card"><h2>Raspberry Pi</h2><dl class="kv">
        <dt>Modèle</dt><dd>${esc(i.modele)}</dd><dt>Nom</dt><dd>${esc(i.hote)}</dd>
        <dt>Système</dt><dd>${esc(i.systeme)}</dd><dt>Noyau</dt><dd>${esc(i.noyau)}</dd>
        <dt>Allumé depuis</dt><dd>${esc(i.allume_depuis)}</dd>
        <dt>Minitel</dt><dd>${tools.minitel ? "branché (/dev/ttyUSB0)" : "non détecté"}</dd></dl></div>
      <div class="card"><h2>Ressources</h2>
        ${gauge("Charge (1 min)", i.charge[0], i.processeurs, "", 90)}
        ${t !== null ? gauge("Température", t, 85, " °C", 80) : ""}
        ${gauge("Mémoire utilisée", i.memoire.totale - i.memoire.libre, i.memoire.totale, " Mo", 90)}
        ${gauge("Carte SD", Math.round(i.disque.utilise / 1024 * 10) / 10, Math.round(i.disque.total / 1024 * 10) / 10, " Go", 90)}</div>
      <div class="card"><h2>Réseau</h2><dl class="kv">
        <dt>Adresses</dt><dd>${esc(i.adresses.join("  ") || "aucune")}</dd>
        <dt>Wi-Fi</dt><dd>${esc(i.wifi || "non connecté")}</dd>
        <dt>Interface</dt><dd>http://${esc(location.host)}</dd></dl></div>
      <div class="card"><h2>Services</h2><ul class="services">${svc}</ul></div>
      <div class="card"><h2>Version du Minitel</h2><dl class="kv">
        <dt>Commit</dt><dd>${esc(i.depot ? i.depot.commit : "?")}</dd>
        <dt>Date</dt><dd>${esc(i.depot ? i.depot.date : "?")}</dd>
        <dt>Message</dt><dd>${esc(i.depot ? i.depot.message : "?")}</dd></dl></div>
      <div class="card"><h2>Outils</h2><ul class="services">
        <li><span>ImageMagick (photos)</span><span class="pill ${tools.imagemagick ? "ok" : "warn"}">${tools.imagemagick ? "présent" : "absent"}</span></li>
        <li><span>Scripts de mise à jour</span><span class="pill ${tools.scripts_maj ? "ok" : "warn"}">${tools.scripts_maj ? "activés" : "non activés"}</span></li>
        <li><span>Mise à jour du système</span><span class="pill ${tools.maj_systeme ? "ok" : "warn"}">${tools.maj_systeme ? "disponible" : "non installée"}</span></li></ul></div>`;
    $("#systeme-note").textContent = tools.maj_systeme ? "" : "Indisponible : lancez une fois sudo ./install_web.sh sur le Pi.";
  } catch (e) {
    box.innerHTML = `<div class="card"><p class="msg err">${esc(e.message)}</p></div>`;
  }
}
tabs.tableau = loadInfo;
$("#refresh-info").addEventListener("click", loadInfo);
$("#reboot").addEventListener("click", async () => {
  if (!confirm("Redémarrer le Raspberry Pi ? Le Minitel et cette page seront coupés une minute.")) return;
  await api("POST", "/api/redemarrer").catch((e) => toast(e.message, true));
  toast("Redémarrage en cours…");
});

// ---------------------------------------------------------------- terminal
let shellSession = null;
$("#term-open").addEventListener("click", () => {
  if (shellSession) shellSession.close();
  shellSession = openTerminal("shell", null, $("#term-shell"), $("#term-state"));
});
tabs.terminal = () => { if (!shellSession) $("#term-open").click(); else shellSession.term.focus(); };

// ---------------------------------------------------------------- mises a jour
let majSession = null;
$("#git-check").addEventListener("click", async () => {
  const box = $("#git-result");
  box.innerHTML = '<p class="msg">Interrogation du serveur…</p>';
  try {
    const r = await api("POST", "/api/git/verifier");
    if (r.erreur) { box.innerHTML = `<p class="msg err">${esc(r.erreur)}</p>`; return; }
    const local = r.modifications_locales ? `<p class="msg">${r.modifications_locales} fichier(s) modifié(s) sur le Pi.</p>` : "";
    box.innerHTML = r.a_venir.length
      ? `<p class="msg ok">${r.a_venir.length} nouveauté(s) disponible(s) :</p><ul class="commits">${r.a_venir.map((c) =>
          `<li><code>${esc(c.commit)}</code><span class="muted">${esc(c.date)}</span><span>${esc(c.message)}</span></li>`).join("")}</ul>${local}`
      : `<p class="msg ok">Le Minitel est à jour.</p>${local}`;
  } catch (e) { box.innerHTML = `<p class="msg err">${esc(e.message)}</p>`; }
});
function runMaj(kind, title) {
  if (majSession) majSession.close();
  $("#maj-title").textContent = title;
  majSession = openTerminal(kind, null, $("#term-maj"), $("#maj-state"), () => loadInfo());
}
$("#run-maj").addEventListener("click", () => runMaj("maj", "Mise à jour du Minitel"));
$("#run-systeme").addEventListener("click", () => {
  if (confirm("Mettre à jour tous les paquets du système (apt) ? Cela peut prendre plusieurs minutes.")) runMaj("systeme", "Mise à jour du système");
});

// ---------------------------------------------------------------- MICRO-BASIC
const BAS_STATEMENTS = ["PRINT", "LET", "INPUT", "GOTO", "GOSUB", "RETURN", "IF", "THEN", "ELSE", "FOR", "TO", "NEXT",
  "WHILE", "WEND", "CLEAR", "CLS", "BEEP", "LOCATE", "INVERT", "NORMAL", "PAUSE", "END", "STOP", "REM",
  "PINMODE", "OUT", "POKE", "GPIOOUT", "TOGGLE", "PULSE", "PWM", "PWMSTOP", "FREQ", "SETADC"];
const BAS_FUNCS = ["RND", "MKEY", "SIN", "COS", "TAN", "ABS", "SQR", "INT", "PI", "EXP", "LOG", "IN", "ADC", "TEMP", "PEEK",
  "INPUT", "OUTPUT", "PULLUP", "PULLDOWN", "PU", "PD", "ANALOG"];
const BAS_OPS = ["AND", "OR", "NOT", "EQ", "NEQ", "GT", "LT", "GE", "LE", "PLUS", "MOINS", "MINUS", "FOIS", "MUL", "DIV", "MOD"];
const words = (l) => new RegExp("(?:" + l.join("|") + ")\\b", "i");

CodeMirror.defineSimpleMode("microbasic", {
  start: [
    { regex: /^\s*\d+/, token: "linenum", sol: true },
    { regex: /REM\b.*/i, token: "comment" },
    { regex: /"(?:[^"])*"?/, token: "string" },
    { regex: words(BAS_STATEMENTS), token: "keyword" },
    { regex: words(BAS_OPS), token: "operator" },
    { regex: words(BAS_FUNCS), token: "builtin" },
    { regex: /\d+(?:\.\d+)?/, token: "number" },
    { regex: /[-+*/=<>^]+/, token: "operator" },
    { regex: /[A-Za-z][A-Za-z0-9_$]*/, token: "variable" },
  ],
});

const editor = CodeMirror.fromTextArea($("#bas-editor"), {
  mode: "microbasic", lineNumbers: true, gutters: ["lint-gutter", "CodeMirror-linenumbers"],
  indentUnit: 2, tabSize: 2, lineWrapping: false, autofocus: false,
});
// Le MICRO-BASIC lit ses programmes en majuscules : on tape en majuscules
// (sauf entre guillemets, ou le texte affiche garde sa casse)
editor.on("beforeChange", (cm, change) => {
  if (change.origin !== "+input" && change.origin !== "paste") return;
  const line = cm.getLine(change.from.line).slice(0, change.from.ch);
  const inString = (line.match(/"/g) || []).length % 2 === 1;
  if (!inString && change.origin === "+input") change.update(change.from, change.to, change.text.map((t) => t.toUpperCase()));
});

let basCurrent = null;   // nom du programme ouvert
let basSaved = "";       // texte enregistre, pour reperer les modifications

function setDirty() {
  const dirty = editor.getValue() !== basSaved;
  $("#bas-dirty").textContent = dirty ? "modifié" : basCurrent ? "enregistré" : "";
  $("#bas-dirty").className = "pill " + (dirty ? "warn" : "ok");
}

// Verification : numeros, sauts vers des lignes inexistantes, boucles
function lint() {
  const problems = [];
  const nums = new Map();
  let fors = 0, nexts = 0, whiles = 0, wends = 0;
  editor.eachLine((h) => {
    const i = h.lineNo(), text = h.text.trim();
    if (!text) return;
    const m = text.match(/^(\d+)\s*(.*)$/);
    if (!m) { problems.push({ line: i, level: "err", msg: "pas de numéro de ligne" }); return; }
    const n = Number(m[1]);
    if (nums.has(n)) problems.push({ line: i, level: "warn", msg: `numéro ${n} déjà utilisé (ligne ${nums.get(n) + 1}) : la dernière gagne` });
    nums.set(n, i);
    const body = m[2].replace(/"[^"]*"?/g, '""');
    const first = (body.match(/^[A-Za-z]+/) || [""])[0].toUpperCase();
    if (/^FOR\b/i.test(body)) fors++;
    if (/^NEXT\b/i.test(body)) nexts++;
    if (/^WHILE\b/i.test(body)) whiles++;
    if (/^WEND\b/i.test(body)) wends++;
    // une affectation s'ecrit avec = ou EQ (A EQ 0)
    if (first && !BAS_STATEMENTS.includes(first) && !/^[A-Za-z][A-Za-z0-9_]*\s*(=|EQ\b)/i.test(body))
      problems.push({ line: i, level: "warn", msg: `instruction inconnue : ${first}` });
    if (!body) problems.push({ line: i, level: "warn", msg: "ligne vide : elle efface ce numéro" });
  });
  editor.eachLine((h) => {
    const body = h.text.replace(/^\s*\d+\s*/, "").replace(/"[^"]*"?/g, '""');
    for (const m of body.matchAll(/\b(GOTO|GOSUB)\s+(\d+)\b/gi)) {
      if (!nums.has(Number(m[2]))) problems.push({ line: h.lineNo(), level: "err", msg: `${m[1].toUpperCase()} ${m[2]} : cette ligne n'existe pas` });
    }
  });
  if (fors !== nexts) problems.push({ line: 0, level: "warn", msg: `${fors} FOR pour ${nexts} NEXT` });
  if (whiles !== wends) problems.push({ line: 0, level: "warn", msg: `${whiles} WHILE pour ${wends} WEND` });

  editor.clearGutter("lint-gutter");
  for (const p of problems) {
    const mark = document.createElement("span");
    mark.className = "lint-mark " + p.level;
    mark.textContent = "●";
    mark.title = p.msg;
    editor.setGutterMarker(p.line, "lint-gutter", mark);
  }
  const box = $("#bas-lint");
  box.innerHTML = problems.length
    ? problems.map((p) => `<div class="${p.level}" data-line="${p.line}">ligne ${p.line + 1} : ${esc(p.msg)}</div>`).join("")
    : (editor.getValue().trim() ? '<div class="ok">Aucun problème repéré.</div>' : "");
  return problems;
}
$("#bas-lint").addEventListener("click", (e) => {
  const l = e.target.dataset.line;
  if (l !== undefined) { editor.setCursor(Number(l), 0); editor.focus(); }
});
let lintTimer = null;
editor.on("change", () => { setDirty(); clearTimeout(lintTimer); lintTimer = setTimeout(lint, 300); });

async function loadBasList() {
  const ul = $("#bas-list");
  try {
    const list = await api("GET", "/api/basic");
    ul.innerHTML = list.length ? list.map((p) =>
      `<li data-name="${esc(p.nom)}" class="${p.nom === basCurrent ? "active" : ""}"><span>${esc(p.nom)}</span><small>${fmtSize(p.taille)}</small></li>`).join("")
      : '<li class="muted">Aucun programme</li>';
  } catch (e) { ul.innerHTML = `<li class="msg err">${esc(e.message)}</li>`; }
}
$("#bas-list").addEventListener("click", (e) => {
  const li = e.target.closest("li[data-name]");
  if (li) openBas(li.dataset.name);
});

function confirmLose() {
  return editor.getValue() === basSaved || confirm("Le programme ouvert n'est pas enregistré. Continuer quand même ?");
}

async function openBas(name) {
  if (!confirmLose()) return;
  try {
    const text = await api("GET", "/api/basic/" + encodeURIComponent(name));
    basCurrent = name; basSaved = text;
    $("#bas-name").value = name;
    editor.setValue(text);
    editor.clearHistory();
    setDirty(); lint(); loadBasList();
  } catch (e) { toast(e.message, true); }
}

async function saveBas() {
  const name = $("#bas-name").value.trim().toUpperCase();
  $("#bas-name").value = name;
  if (!/^[A-Z0-9_-]{1,40}$/.test(name)) { toast("Nom invalide : lettres, chiffres, - et _ (40 au plus).", true); return false; }
  if (lint().some((p) => p.level === "err" && /numéro de ligne/.test(p.msg))) { toast("Chaque ligne doit commencer par son numéro.", true); return false; }
  try {
    const r = await api("PUT", "/api/basic/" + encodeURIComponent(name), editor.getValue(), true);
    basCurrent = name; basSaved = r.texte;
    if (editor.getValue() !== r.texte) { const c = editor.getCursor(); editor.setValue(r.texte); editor.setCursor(c); }
    setDirty(); loadBasList();
    toast("Enregistré : " + name + ".bas");
    return true;
  } catch (e) { toast(e.message, true); return false; }
}
$("#bas-save").addEventListener("click", saveBas);
document.addEventListener("keydown", (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key === "s" && !$("#tab-basic").hidden) { e.preventDefault(); saveBas(); }
});

$("#bas-new").addEventListener("click", () => {
  if (!confirmLose()) return;
  basCurrent = null; basSaved = "";
  $("#bas-name").value = "";
  editor.setValue('10 REM NOUVEAU PROGRAMME\n20 PRINT "BONJOUR DEPUIS LE MINITEL !"\n30 END\n');
  setDirty(); lint(); loadBasList();
  $("#bas-name").focus();
});

$("#bas-import").addEventListener("change", async (e) => {
  const f = e.target.files[0];
  e.target.value = "";
  if (!f || !confirmLose()) return;
  basCurrent = null; basSaved = "";
  $("#bas-name").value = f.name.replace(/\.[^.]*$/, "").toUpperCase().replace(/[^A-Z0-9_-]/g, "_").slice(0, 40);
  editor.setValue(await f.text());
  setDirty(); lint();
  toast("Importé : vérifiez puis enregistrez.");
});

$("#bas-download").addEventListener("click", () => {
  const name = ($("#bas-name").value || "PROGRAMME").toUpperCase();
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([editor.getValue()], { type: "text/plain" }));
  a.download = name + ".bas";
  a.click();
  URL.revokeObjectURL(a.href);
});

$("#bas-delete").addEventListener("click", async () => {
  if (!basCurrent || !confirm(`Supprimer ${basCurrent}.bas du Raspberry Pi ?`)) return;
  try {
    await api("DELETE", "/api/basic/" + encodeURIComponent(basCurrent));
    toast(basCurrent + ".bas supprimé");
    basCurrent = null; basSaved = ""; $("#bas-name").value = ""; editor.setValue("");
    setDirty(); lint(); loadBasList();
  } catch (e) { toast(e.message, true); }
});

// Renumerotation de 10 en 10, GOTO et GOSUB compris
$("#bas-renum").addEventListener("click", () => {
  const lines = [];
  editor.eachLine((h) => {
    const m = h.text.trim().match(/^(\d+)\s*(.*)$/);
    if (m) lines.push({ old: Number(m[1]), body: m[2] });
  });
  if (!lines.length) return;
  lines.sort((a, b) => a.old - b.old);
  const map = new Map(lines.map((l, i) => [l.old, (i + 1) * 10]));
  const fix = (body) => body.split(/("[^"]*"?)/).map((part, i) =>
    i % 2 ? part : part.replace(/\b(GOTO|GOSUB)(\s+)(\d+)\b/gi, (all, kw, sp, n) => map.has(Number(n)) ? kw + sp + map.get(Number(n)) : all)).join("");
  editor.setValue(lines.map((l) => map.get(l.old) + " " + fix(l.body)).join("\n") + "\n");
  toast("Renuméroté de 10 en 10 (GOTO et GOSUB mis à jour).");
});

// Execution : le vrai interpreteur du Pi, dans un terminal 80 x 24
let basSession = null;
$("#bas-run").addEventListener("click", async () => {
  if (editor.getValue() !== basSaved || !basCurrent) { if (!(await saveBas())) return; }
  if (basSession) basSession.close();
  $("#bas-run-card").hidden = false;
  basSession = openTerminal("basic", basCurrent, $("#term-basic"), $("#bas-run-state"));
  $("#bas-run-card").scrollIntoView({ behavior: "smooth" });
});
$("#bas-run-close").addEventListener("click", () => {
  if (basSession) basSession.close();
  basSession = null;
  $("#bas-run-card").hidden = true;
});
tabs.basic = () => { loadBasList(); setTimeout(() => editor.refresh(), 0); };

// ---------------------------------------------------------------- photos
async function loadPhotos() {
  const grid = $("#ph-grid");
  try {
    const list = await api("GET", "/api/photos");
    grid.innerHTML = list.length ? list.map((p) => {
      const url = "/api/photos/" + encodeURIComponent(p.nom);
      return `<div class="photo"><img loading="lazy" src="${url}" alt="${esc(p.nom)}">
        <div class="meta"><div title="${esc(p.nom)}">${esc(p.nom)}</div><small>${fmtSize(p.taille)}</small></div>
        <div class="actions"><button class="ghost" data-preview="${esc(p.nom)}">Rendu Minitel</button>
        <button class="danger ghost" data-delete="${esc(p.nom)}">Supprimer</button></div></div>`;
    }).join("") : '<p class="muted">Aucune photo pour l’instant.</p>';
  } catch (e) { grid.innerHTML = `<p class="msg err">${esc(e.message)}</p>`; }
}
tabs.photos = loadPhotos;

async function uploadPhotos(files) {
  const msg = $("#ph-msg");
  let ok = 0;
  for (const f of files) {
    const name = f.name.replace(/[^A-Za-z0-9_. -]/g, "_").slice(-80);
    msg.className = "msg";
    msg.textContent = `Envoi de ${name} (${fmtSize(f.size)})…`;
    try { await api("PUT", "/api/photos/" + encodeURIComponent(name), f, true); ok++; }
    catch (e) { msg.className = "msg err"; msg.textContent = `${name} : ${e.message}`; }
  }
  if (ok) { msg.className = "msg ok"; msg.textContent = `${ok} photo(s) envoyée(s).`; }
  loadPhotos();
}
$("#ph-input").addEventListener("change", (e) => { uploadPhotos([...e.target.files]); e.target.value = ""; });
const drop = $("#ph-drop");
["dragenter", "dragover"].forEach((t) => drop.addEventListener(t, (e) => { e.preventDefault(); drop.classList.add("over"); }));
["dragleave", "drop"].forEach((t) => drop.addEventListener(t, (e) => { e.preventDefault(); drop.classList.remove("over"); }));
drop.addEventListener("drop", (e) => uploadPhotos([...e.dataTransfer.files].filter((f) => f.type.startsWith("image/"))));

$("#ph-grid").addEventListener("click", async (e) => {
  const del = e.target.dataset.delete, prev = e.target.dataset.preview;
  if (del && confirm(`Supprimer ${del} ?`)) {
    await api("DELETE", "/api/photos/" + encodeURIComponent(del)).catch((err) => toast(err.message, true));
    loadPhotos();
  }
  if (prev) {
    $("#ph-preview").hidden = false;
    $("#ph-preview-title").textContent = "Rendu sur le Minitel : " + prev;
    const scr = $("#ph-preview-screen");
    scr.textContent = "Conversion…";
    try {
      const rows = await api("GET", "/api/photos/" + encodeURIComponent(prev) + "/minitel");
      scr.innerHTML = rows.map((r) => r.map(([c, inv]) => inv ? `<span class="inv">${esc(c)}</span>` : esc(c)).join("")).join("\n");
    } catch (err) { scr.textContent = err.message; }
    $("#ph-preview").scrollIntoView({ behavior: "smooth" });
  }
});
$("#ph-preview-close").addEventListener("click", () => ($("#ph-preview").hidden = true));

// ---------------------------------------------------------------- reglages
$("#pw-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const msg = $("#pw-msg");
  try {
    await api("POST", "/api/mot-de-passe", { ancien: $("#pw-old").value, nouveau: $("#pw-new").value });
    msg.className = "msg ok";
    msg.textContent = "Mot de passe changé : reconnectez-vous.";
    setTimeout(() => showLogin("Mot de passe changé."), 1500);
  } catch (err) { msg.className = "msg err"; msg.textContent = err.message; }
  $("#pw-old").value = ""; $("#pw-new").value = "";
});

// ---------------------------------------------------------------- demarrage
window.addEventListener("beforeunload", (e) => {
  if (editor.getValue() !== basSaved) { e.preventDefault(); e.returnValue = ""; }
});

function start() {
  $("#login").hidden = true;
  $("#app").hidden = false;
  let tab = "tableau";
  try { tab = localStorage.getItem("minitel-tab") || tab; } catch (e) { /* stockage indisponible */ }
  if (tab === "terminal") tab = "tableau"; // pas de session ouverte d'office
  showTab(tab);
  setDirty();
}

(async () => {
  try {
    const s = await api("GET", "/api/etat");
    if (s.connecte) start();
    else showLogin(s.mot_de_passe ? "" : "Aucun mot de passe : sur le Pi, tapez sudo -u minitel python3 web/admin.py --mot-de-passe");
  } catch (e) { showLogin(e.message); }
})();
