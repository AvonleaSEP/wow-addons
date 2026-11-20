// Biggest hits, from the game's combat log file.
//
// WoW Forever hides single hit numbers from addons, but the game still
// writes every hit to Logs\WoWCombatLog*.txt while combat logging is on
// (Damage Bar switches it on at login). This reads today's lines, keeps
// your own hits (melee, ranged and spells; not your pet's), and:
//   * prints the biggest hit today and the biggest per ability;
//   * writes DamageBar\Hits.lua, which Damage Bar loads, so its biggest-hit
//     box shows them after a /reload.
//
//   node tools/biggest-hits.js            today
//   node tools/biggest-hits.js 11/19      another day (month/day)
//
// Paths can be changed with WOW_LOGS and HITS_OUT.

const fs = require("fs");
const path = require("path");

const LOGS = process.env.WOW_LOGS || "G:\\BattleNet\\World of Warcraft\\_forever_\\Logs";
const OUT = process.env.HITS_OUT || path.join(__dirname, "..", "DamageBar", "Hits.lua");

const now = new Date();
const want = process.argv[2] || `${now.getMonth() + 1}/${now.getDate()}`;
const [wm, wd] = want.split("/").map(Number);

// a combat log line's fields (commas, with quoted names that can hold commas)
function fields(s) {
  const out = [];
  let cur = "", q = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '"') q = !q;
    else if (c === "," && !q) { out.push(cur); cur = ""; }
    else cur += c;
  }
  out.push(cur);
  return out;
}

const isGuid = (v) => /^(Player|Creature|Pet|Vehicle|GameObject)-|^0000000000000000$/.test(v || "");
const MINE = 0x1; // source flags: "mine"

const hits = {}; // ability -> { amount, crit, when, target }
let best = null;

function note(spell, amount, crit, when, target) {
  const h = hits[spell];
  if (!h || amount > h.amount) hits[spell] = { amount, crit, when, target };
  if (!best || amount > best.amount) best = { spell, amount, crit, when, target };
}

function readFile(file) {
  const text = fs.readFileSync(file, "utf8");
  for (const raw of text.split(/\r?\n/)) {
    // "11/19/2026 21:30:01.1234-5  SPELL_DAMAGE,..." or "11/19 21:30:01.123  SPELL_DAMAGE,..."
    const m = raw.match(/^(\d+)\/(\d+)(?:\/\d+)? (\d+:\d+:\d+)\S*\s+(.*)$/);
    if (!m || Number(m[1]) !== wm || Number(m[2]) !== wd) continue;
    const f = fields(m[4]);
    const ev = f[0];
    if (ev !== "SWING_DAMAGE" && ev !== "SPELL_DAMAGE" && ev !== "RANGE_DAMAGE") continue;
    // event, source guid / name / flags / raid flags, dest guid / name / flags / raid flags
    if (!/^Player-/.test(f[1])) continue;
    if (!(parseInt(f[3], 16) & MINE)) continue;
    const target = f[6];
    let i = 9, spell = "Auto Attack";
    if (ev !== "SWING_DAMAGE") { spell = f[10]; i = 12; } // spell id, name, school
    if (isGuid(f[i])) {
      // advanced logging: unit info before the amounts (16 or 17 fields by
      // client). It ends "x, y, map, facing, level": find x and y (decimals)
      // followed by a whole-number map and a decimal facing.
      const dec = (v) => /^-?\d+\.\d+$/.test(v || "");
      const int = (v) => /^-?\d+$/.test(v || "");
      let k = i + 2, end = -1;
      for (; k + 4 < f.length; k++) {
        if (dec(f[k]) && dec(f[k + 1]) && int(f[k + 2]) && dec(f[k + 3]) && int(f[k + 4])) { end = k + 5; break; }
      }
      if (end < 0) continue;
      i = end;
    }
    const amount = Number(f[i]);
    if (!Number.isFinite(amount) || amount <= 0) continue;
    // amount, [base amount], overkill, school, resisted, blocked, absorbed, critical, ...
    const rest = f.length - i;
    const critAt = i + (rest >= 11 ? 7 : 6);
    const crit = f[critAt] === "1";
    note(spell, amount, crit, m[3], target);
  }
}

let files = [];
try {
  files = fs.readdirSync(LOGS).filter((n) => /^WoWCombatLog.*\.txt$/i.test(n)).map((n) => path.join(LOGS, n));
} catch (e) {
  console.error("Can't read the Logs folder: " + LOGS);
  process.exit(1);
}
if (files.length === 0) {
  console.log("No combat log file yet. Damage Bar switches logging on at login; /reload, fight, then run this again.");
  process.exit(0);
}
for (const f of files) readFile(f);

const date = `${now.getFullYear()}-${String(wm).padStart(2, "0")}-${String(wd).padStart(2, "0")}`;
if (!best) {
  console.log(`No hits of yours in the combat log for ${want}.`);
} else {
  console.log(`Biggest hit ${want}: ${best.amount} ${best.spell}${best.crit ? " (crit)" : ""} on ${best.target} at ${best.when}`);
  const list = Object.entries(hits).sort((a, b) => b[1].amount - a[1].amount);
  for (const [spell, h] of list) console.log(`  ${spell.padEnd(22)} ${String(h.amount).padStart(7)}${h.crit ? " crit" : ""}`);
}

// for Damage Bar: DamageBarHits = { day = "YYYY-MM-DD", hits = { [spell] = { amount, crit } } }
const lua = (s) => '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
let out = "-- written by tools/biggest-hits.js from the combat log; Damage Bar reads it at login\n";
out += `DamageBarHits = { day = ${lua(date)}, hits = {\n`;
for (const [spell, h] of Object.entries(hits)) {
  out += `  [${lua(spell)}] = { amount = ${h.amount}, crit = ${h.crit ? "true" : "false"} },\n`;
}
out += "} }\n";
fs.writeFileSync(OUT, out);
console.log("Wrote " + OUT + " (Damage Bar shows it after a /reload).");
