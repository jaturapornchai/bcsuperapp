// video.html + timeline.json -> frames piped to ffmpeg -> bcsuperapp-demo.mp4 (1080p30, narration + click/key sfx, -14 LUFS).
// node render.mjs            full render
// node render.mjs 5 40 120   stills at those seconds -> check/t*.jpg
import { chromium } from "playwright";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
const FPS = 30, SR = 48000, tl = JSON.parse(fs.readFileSync("timeline.json", "utf8")), total = tl.at(-1).end;

// sfx.json (master-time "c" click / "k" key events from capture.mjs) -> sfx.wav, synthesized so no sample files are needed
function writeSfx() {
  const ev = JSON.parse(fs.readFileSync("sfx.json", "utf8")), n = Math.ceil((total + 1) * SR), buf = new Float32Array(n);
  let seed = 7; const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648) * 2 - 1;
  for (const e of ev) {
    const i0 = Math.round(e.t * SR), click = e.k === "c", amp = click ? 0.16 : 0.07 + 0.04 * Math.abs(rnd()), f = click ? 170 : 1100 + 500 * Math.abs(rnd());
    for (let j = 0; j < SR * 0.05 && i0 + j < n; j++) { const s = j / SR; // noise tick + short tone body, both decaying fast
      buf[i0 + j] += amp * (rnd() * Math.exp(-s / (click ? 0.004 : 0.003)) + 0.8 * Math.sin(2 * Math.PI * f * s) * Math.exp(-s / (click ? 0.018 : 0.008))); }
  }
  const out = Buffer.alloc(44 + n * 2);
  out.write("RIFF", 0); out.writeUInt32LE(36 + n * 2, 4); out.write("WAVEfmt ", 8); out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(SR, 24); out.writeUInt32LE(SR * 2, 28); out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34); out.write("data", 36); out.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) out.writeInt16LE(Math.round(Math.max(-1, Math.min(1, buf[i])) * 32767), 44 + i * 2);
  fs.writeFileSync("sfx.wav", out); console.log("sfx events", ev.length);
}

const browser = await chromium.launch({ channel: "chrome" });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
await page.goto("file:///" + path.resolve("video.html").replace(/\\/g, "/"));
await page.evaluate(async tl => { await document.fonts.ready; window.init(tl); await Promise.all([...document.images].map(i => i.decode().catch(() => {}))); }, tl);
const stills = process.argv.slice(2).map(Number);
if (stills.length) {
  page.on("console", m => m.type() === "warning" && console.log(m.text()));
  fs.mkdirSync("check", { recursive: true });
  for (const t of stills) { await page.evaluate(t => window.seek(t), t); await page.screenshot({ path: `check/t${t}.jpg`, type: "jpeg", quality: 85 }); }
} else {
  writeSfx();
  const ff = spawn("ffmpeg", ["-y", "-v", "error", "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "mjpeg", "-i", "-", "-i", "narration.wav", "-i", "sfx.wav",
    "-filter_complex", "[1:a]aresample=48000,aformat=channel_layouts=mono[n];[n][2:a]amix=inputs=2:normalize=0:duration=first,loudnorm=I=-14:TP=-1.5:LRA=11[a]",
    "-map", "0:v", "-map", "[a]", "-vf", "scale=in_range=pc:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p", "-color_range", "tv", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p", "-preset", "slow", "-crf", "18", "-g", "15", "-bf", "2", "-flags", "+cgop",
    "-c:a", "aac", "-b:a", "384k", "-ar", "48000", "-ac", "2", "-shortest", "-movflags", "+faststart", "bcsuperapp-demo.mp4"], { stdio: ["pipe", "inherit", "inherit"] });
  const n = Math.ceil(total * FPS);
  for (let f = 0; f < n; f++) {
    await page.evaluate(t => window.seek(t), f / FPS);
    const buf = await page.screenshot({ type: "jpeg", quality: 93 });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once("drain", r));
    if (f % 1800 === 0) console.log(`frame ${f}/${n}`);
  }
  ff.stdin.end(); await new Promise(r => ff.on("close", r));
}
await browser.close();
