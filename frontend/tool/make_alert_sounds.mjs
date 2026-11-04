// Synthesises the chat alert sounds in assets/sounds/ (original tones, no
// third-party audio). Run from frontend/:  node tool/make_alert_sounds.mjs
// Codes must match NotificationService.sounds.
import { mkdirSync, writeFileSync } from 'node:fs';

const RATE = 22050;

// Sine partials with a short attack and exponential decay.
function note(buf, { at, freq, dur, amp = 0.6, decay = 6, partials = [[1, 1]], attack = 0.004 }) {
  const start = Math.round(at * RATE);
  const n = Math.round(dur * RATE);
  for (let i = 0; i < n && start + i < buf.length; i++) {
    const t = i / RATE;
    const env = Math.min(1, t / attack) * Math.exp(-decay * t);
    let s = 0;
    for (const [mult, a] of partials) s += a * Math.sin(2 * Math.PI * freq * mult * t);
    buf[start + i] += amp * env * s;
  }
}

// Pitch glide (Hz from -> to) for pops and blips.
function glide(buf, { at, from, to, dur, amp = 0.6, decay = 20 }) {
  const start = Math.round(at * RATE);
  const n = Math.round(dur * RATE);
  let phase = 0;
  for (let i = 0; i < n && start + i < buf.length; i++) {
    const t = i / RATE;
    const f = from + (to - from) * (i / n);
    phase += (2 * Math.PI * f) / RATE;
    buf[start + i] += amp * Math.min(1, t / 0.003) * Math.exp(-decay * t) * Math.sin(phase);
  }
}

const SOUNDS = {
  ting: [1.0, (b) => note(b, { at: 0, freq: 1318.5, dur: 1.0, decay: 5, partials: [[1, 1], [2, 0.3], [3, 0.08]] })],
  pop: [0.25, (b) => { glide(b, { at: 0, from: 950, to: 320, dur: 0.09, decay: 25 }); glide(b, { at: 0.1, from: 1200, to: 500, dur: 0.07, amp: 0.35, decay: 30 }); }],
  chime: [1.2, (b) => { note(b, { at: 0, freq: 784, dur: 0.9, decay: 4.5, partials: [[1, 1], [2, 0.25]] }); note(b, { at: 0.16, freq: 1046.5, dur: 1.0, decay: 4, partials: [[1, 1], [2, 0.25]] }); }],
  marimba: [0.9, (b) => [523.25, 659.25, 783.99].forEach((f, i) => note(b, { at: i * 0.11, freq: f, dur: 0.6, decay: 9, partials: [[1, 1], [4, 0.15]] }))],
  bell: [1.8, (b) => note(b, { at: 0, freq: 880, dur: 1.8, amp: 0.5, decay: 2.5, partials: [[1, 1], [2.76, 0.4], [5.4, 0.2], [8.93, 0.08]] })],
  soft: [1.1, (b) => { note(b, { at: 0, freq: 440, dur: 1.1, decay: 3, attack: 0.06, partials: [[1, 1], [1.5, 0.35]] }); note(b, { at: 0.18, freq: 554.37, dur: 0.9, amp: 0.4, decay: 3.5, attack: 0.06 }); }],
  urgent: [1.05, (b) => [0, 0.13, 0.26, 0.6, 0.73, 0.86].forEach((at) => note(b, { at, freq: 1046.5, dur: 0.09, amp: 0.45, decay: 4, attack: 0.002, partials: [[1, 1], [3, 0.3], [5, 0.12]] }))],
  robot: [0.6, (b) => { glide(b, { at: 0, from: 600, to: 1300, dur: 0.12, decay: 6 }); glide(b, { at: 0.16, from: 1300, to: 800, dur: 0.12, decay: 6 }); glide(b, { at: 0.32, from: 900, to: 1500, dur: 0.14, amp: 0.5, decay: 8 }); }],
};

function wav(samples) {
  const data = Buffer.alloc(samples.length * 2);
  samples.forEach((s, i) => data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, s)) * 32767), i * 2));
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + data.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(RATE, 24); h.writeUInt32LE(RATE * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(data.length, 40);
  return Buffer.concat([h, data]);
}

mkdirSync('assets/sounds', { recursive: true });
for (const [code, [seconds, draw]] of Object.entries(SOUNDS)) {
  const buf = new Float64Array(Math.round(seconds * RATE));
  draw(buf);
  const peak = buf.reduce((m, s) => Math.max(m, Math.abs(s)), 0) || 1;
  const fade = Math.round(0.02 * RATE); // avoid a click at the cut-off
  for (let i = 0; i < buf.length; i++) {
    buf[i] = (buf[i] / peak) * 0.8 * Math.min(1, (buf.length - i) / fade);
  }
  writeFileSync(`assets/sounds/${code}.wav`, wav(buf));
  console.log(`${code}.wav ${seconds}s`);
}
