// script.json -> ElevenLabs narration (per scene, cached by text) -> narration.wav + timeline.json (scene times + subtitle chunks).
// Key is read at run time from %LOCALAPPDATA%\BotPress\elevenlabs.key (never printed). Voice = Kanya (Thai female, picked by an STT round-trip test).
import fs from "node:fs";
import { createHash } from "node:crypto";
const VOICE = "B4NdgwdU97lHqA8Udh2D", MODEL = "eleven_v4", SETTINGS = { stability: 0.4, similarity_boost: 0.75 };
const BPS = 96000, LEAD = 0.5, TAIL = 0.9, END = 3, MAXSUB = 44; // pcm_48000 mono s16 / s of silence before+after each scene / outro hold
const key = fs.readFileSync(`${process.env.LOCALAPPDATA}/BotPress/elevenlabs.key`, "utf8").trim();
const scenes = JSON.parse(fs.readFileSync("script.json", "utf8"));

// "{shown|spoken}" pairs and "[tags]" -> words of {d: shown, s: spoken}
const words = say => say.replace(/\[[^\]]*\]\s*/g, "").replace(/\{([^|}]*)\|([^}]*)\}/g, (_, d, s) => `\u0001${d}\u0002${s}\u0003`)
  .split(/ +(?![^\u0001]*\u0003)/).filter(Boolean).map(w => ({ d: w.replace(/\u0001([^\u0002]*)\u0002[^\u0003]*\u0003/g, "$1"), s: w.replace(/\u0001[^\u0002]*\u0002([^\u0003]*)\u0003/g, "$1") }));
const spoken = say => say.replace(/\{[^|}]*\|([^}]*)\}/g, "$1");

async function speak(text, prev) {
  for (let i = 0; ; i++) {
    const r = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${VOICE}/with-timestamps?output_format=pcm_48000`, {
      method: "POST", headers: { "xi-api-key": key, "Content-Type": "application/json; charset=utf-8" },
      body: JSON.stringify({ text, model_id: MODEL, language_code: "th", voice_settings: SETTINGS, ...(prev.length ? { previous_request_ids: prev.slice(-3) } : {}) }) });
    if ((r.status === 429 || r.status >= 500) && i < 4) { await new Promise(s => setTimeout(s, 2000 * 2 ** i)); continue; }
    if (r.status === 400 && prev.length) { prev = []; continue; }
    if (!r.ok) throw new Error(`ElevenLabs ${r.status}: ${(await r.text()).slice(0, 300)}`);
    const j = await r.json();
    return { pcm: Buffer.from(j.audio_base64, "base64"), al: j.alignment, id: r.headers.get("request-id") };
  }
}

fs.mkdirSync("tts", { recursive: true });
const pcms = [], timeline = [], ids = [];
let t = 0;
for (const sc of scenes) {
  const text = spoken(sc.say), c = `tts/${createHash("sha1").update([MODEL, VOICE, JSON.stringify(SETTINGS), text].join("|")).digest("hex").slice(0, 16)}`;
  if (!fs.existsSync(`${c}.json`)) {
    const g = await speak(text, ids);
    fs.writeFileSync(`${c}.pcm`, g.pcm); fs.writeFileSync(`${c}.json`, JSON.stringify({ id: g.id, al: g.al }));
    console.log("tts", sc.id, text.length, "chars");
  }
  const { id, al } = JSON.parse(fs.readFileSync(`${c}.json`, "utf8")), pcm = fs.readFileSync(`${c}.pcm`);
  ids.push(id);
  const dur = pcm.length / BPS, v0 = t + LEAD, chars = al.characters.join("");
  // subtitle chunks: greedy word packing, timed by finding each chunk's spoken text in the alignment
  const subs = []; let cur = [], cursor = 0;
  const flush = () => {
    if (!cur.length) return;
    const s = cur.map(w => w.s).join(" "), i = chars.indexOf(cur[0].s, cursor), j = i < 0 ? -1 : i + s.length - 1;
    const a = i < 0 ? null : al.character_start_times_seconds[i], b = j < 0 || j >= chars.length ? null : al.character_end_times_seconds[j];
    subs.push({ text: cur.map(w => w.d).join(" "), a: a == null ? null : v0 + a, b: b == null ? null : v0 + b });
    if (j > 0) cursor = j; cur = [];
  };
  for (const w of words(sc.say)) { if ((cur.map(x => x.d).join(" ") + " " + w.d).length > MAXSUB) flush(); cur.push(w); }
  flush();
  // word cue times (scene-relative) so capture + graphics can sync to a spoken word: cue(scene, "text")
  const cues = []; { let c = 0; for (const w of words(sc.say)) { const i = chars.indexOf(w.s, c); if (i >= 0) { cues.push({ d: w.d, a: +(LEAD + al.character_start_times_seconds[i]).toFixed(2), b: +(LEAD + (al.character_end_times_seconds[i + w.s.length - 1] ?? al.character_start_times_seconds[i])).toFixed(2) }); c = i + w.s.length; } } }
  subs.forEach((s, k) => { s.a ??= k ? subs[k - 1].b : v0; s.b ??= subs[k + 1]?.a ?? v0 + dur; }); // fill any unmatched chunk from neighbours
  subs.forEach((s, k) => { if (subs[k + 1]?.a != null) s.b = Math.max(s.b, subs[k + 1].a - 0.05); });
  const len = LEAD + dur + TAIL + (sc.type === "cta" ? END : 0);
  pcms.push(Buffer.alloc(Math.round(LEAD * 48000) * 2), pcm, Buffer.alloc(Math.round((len - LEAD - dur) * 48000) * 2));
  timeline.push({ ...sc, start: t, end: t + len, vStart: v0, vEnd: v0 + dur, subs, cues });
  t += len;
}
const all = Buffer.concat(pcms), h = Buffer.alloc(44);
h.write("RIFF", 0); h.writeUInt32LE(36 + all.length, 4); h.write("WAVEfmt ", 8); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
h.writeUInt32LE(48000, 24); h.writeUInt32LE(BPS, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write("data", 36); h.writeUInt32LE(all.length, 40);
fs.writeFileSync("narration.wav", Buffer.concat([h, all]));
fs.writeFileSync("timeline.json", JSON.stringify(timeline, null, 1));
console.log("total", t.toFixed(1), "s");
