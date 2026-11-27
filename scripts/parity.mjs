#!/usr/bin/env node
// Juiz de paridade: o gato do site (WebAssembly) desenha igual ao app nativo?
//
// Grava a cena "digitando" com o binário nativo (--record, relógio simulado) e reproduz
// a mesma sequência de eventos e o mesmo relógio no site/wasm/gatinho.wasm. Compara os
// quadros do trecho determinístico (antes da primeira piscada, que é sorteada) e falha
// se a diferença média passar de 2%.
//
// Uso: node scripts/parity.mjs [--native <binário>] [--wasm <arquivo>] [--out <dir>] [--scale 2]
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WASI } from 'node:wasi';
import { deflateSync, crc32 } from 'node:zlib';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const arg = (name, def) => {
  const i = process.argv.indexOf(name);
  return i > 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
};
const nativeBin = arg('--native', join(root, '.build/release/Gatinho'));
const wasmPath = arg('--wasm', join(root, 'site/wasm/gatinho.wasm'));
const outDir = arg('--out', mkdtempSync(join(tmpdir(), 'gatinho-parity-')));
const SCALE = Number(arg('--scale', '2'));
const BG = [0xf7, 0xee, 0xdf];
const FPS = 30, SUB = 4;
const LIMIT = 0.02; // 2%
mkdirSync(outDir, { recursive: true });

// ---- Lado nativo -----------------------------------------------------------
const rawPath = join(outDir, 'digitando-nativo.rgba');
execFileSync(nativeBin, ['--record', 'digitando', rawPath, '--scale', String(SCALE), '--bg', 'F7EEDF'], { stdio: 'pipe' });
const W = Math.floor(330 * SCALE), H = Math.floor(300 * SCALE);
const native = readFileSync(rawPath);
const frameBytes = W * H * 4;
const nativeFrames = native.length / frameBytes;

// ---- Lado wasm -------------------------------------------------------------
const _emit = process.emitWarning; process.emitWarning = (w, ...a) => (String(w).includes('WASI') ? undefined : _emit.call(process, w, ...a)); // node:wasi ainda é experimental
const wasi = new WASI({ version: 'preview1', args: [], env: {} });
const mod = await WebAssembly.compile(readFileSync(wasmPath));
const inst = await WebAssembly.instantiate(mod, { wasi_snapshot_preview1: wasi.wasiImport });
wasi.initialize(inst);
const g = inst.exports;

// A mesma cena do Recorder.swift ("digitando").
const MAC = { a: 0, s: 1, d: 2, f: 3, h: 4, g: 5, z: 6, x: 7, c: 8, v: 9, b: 11, q: 12, w: 13, e: 14, r: 15,
  y: 16, t: 17, o: 31, u: 32, i: 34, p: 35, l: 37, j: 38, k: 40, n: 45, m: 46, ' ': 49 };
const cues = [];
const typing = (text, from, gap) => [...text].forEach((ch, i) => {
  const code = MAC[ch]; if (code === undefined) return;
  const t = from + i * gap;
  const label = ch === ' ' ? 0x2423 : ch.toUpperCase().codePointAt(0);
  cues.push({ at: t, run: () => g.gato_tecla(code, label, 1, 0) });
  cues.push({ at: t + gap * 0.6, run: () => g.gato_tecla(code, 0, 0, 0) });
});
typing('oi gatinho', 0.6, 0.2);
typing('bom dia', 3.4, 0.17);
cues.push({ at: 5.4, run: () => g.gato_botao(0, 1) });
cues.push({ at: 5.55, run: () => g.gato_botao(0, 0) });
for (let i = 0; i < 10; i++) cues.push({ at: 5.9 + i * 0.06, run: () => g.gato_rolar(-3) });
cues.sort((a, b) => a.at - b.at);
const pointer = (t) => t < 5 ? [520, 120]
  : [520 - 300 * Math.sin(Math.min(t - 5, 2.5) / 2.5 * Math.PI), 120 + 140 * Math.sin((t - 5) * 1.3)];

// O sim usa o relógio de parede no init (primeira piscada = init + 2 s), igual ao nativo.
let t = Date.now() / 1000 - 978307200;
const LARANJA = 1;
g.gato_iniciar(LARANJA, SCALE, t);
// Ponteiro e janela em pixels de tela: o wasm usa screenScale = escala.
const frame = (tt, p) => g.gato_quadro(tt, p[0] * SCALE, p[1] * SCALE, 0, 0, 330 * SCALE, 300 * SCALE);
for (let i = 0; i < 60; i++) { t += 1 / 60; frame(t, pointer(0)); }
const begin = t;
const firstBlink = 1.0; // init + 2 s − 1 s de aquecimento
const deterministic = Math.floor(firstBlink * FPS) - 1;

const results = [];
let worst = null;
for (let f = 0; f < nativeFrames; f++) {
  let ptr = 0;
  for (let s = 0; s < SUB; s++) {
    t += 1 / (FPS * SUB);
    const local = t - begin;
    g.gato_relogio(t);
    while (cues.length && cues[0].at <= local) cues.shift().run();
    ptr = frame(t, pointer(local));
  }
  if (g.gato_largura() !== W || g.gato_altura() !== H) throw new Error(`wasm desenhou ${g.gato_largura()}x${g.gato_altura()}, nativo ${W}x${H}`);
  const wasmPx = new Uint8Array(g.memory.buffer, ptr, frameBytes);
  const nat = native.subarray(f * frameBytes, (f + 1) * frameBytes);
  // Compõe o wasm (transparente, sem pré-multiplicar) sobre o mesmo fundo creme.
  const comp = new Uint8Array(frameBytes);
  let sum = 0, off = 0;
  for (let i = 0; i < frameBytes; i += 4) {
    const a = wasmPx[i + 3] / 255;
    let d = 0;
    for (let c = 0; c < 3; c++) {
      const v = Math.round(wasmPx[i + c] * a + BG[c] * (1 - a));
      comp[i + c] = v;
      d = Math.max(d, Math.abs(v - nat[i + c]));
      sum += Math.abs(v - nat[i + c]);
    }
    comp[i + 3] = 255;
    if (d > 8) off++;
  }
  const mean = sum / (W * H * 3 * 255);
  const r = { f, local: (f + 1) / FPS, mean, off: off / (W * H) };
  results.push(r);
  if (f <= deterministic && (!worst || mean > worst.mean)) worst = { ...r, comp, nat: Buffer.from(nat) };
}

// ---- PNG de diferença (nativo | wasm | diferença ×8) ------------------------
function png(rgba, w, h) {
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td) >>> 0);
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  const raw = Buffer.alloc((w * 4 + 1) * h);
  const src = Buffer.from(rgba.buffer, rgba.byteOffset, rgba.length);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; src.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4); }
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}
const strip = Buffer.alloc(W * 3 * H * 4);
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  const i = (y * W + x) * 4;
  const put = (col, r, gg, b) => { const o = (y * W * 3 + col * W + x) * 4; strip[o] = r; strip[o + 1] = gg; strip[o + 2] = b; strip[o + 3] = 255; };
  put(0, worst.nat[i], worst.nat[i + 1], worst.nat[i + 2]);
  put(1, worst.comp[i], worst.comp[i + 1], worst.comp[i + 2]);
  const d = Math.min(255, 8 * Math.max(...[0, 1, 2].map((c) => Math.abs(worst.comp[i + c] - worst.nat[i + c]))));
  put(2, 255 - d, 255 - d, 255);
}
const diffPath = join(outDir, 'paridade-diferenca.png');
writeFileSync(diffPath, png(strip, W * 3, H));

// ---- Relatório -------------------------------------------------------------
const pct = (x) => (x * 100).toFixed(3) + '%';
const det = results.slice(0, deterministic + 1);
const detMean = det.reduce((s, r) => s + r.mean, 0) / det.length;
const allMean = results.reduce((s, r) => s + r.mean, 0) / results.length;
console.log(`wasm: ${wasmPath} (${(readFileSync(wasmPath).length / 1e6).toFixed(1)} MB)`);
console.log(`cena digitando ${W}x${H}, ${results.length} quadros`);
console.log(`trecho determinístico (quadros 0–${deterministic}): média ${pct(detMean)}, pior quadro ${worst.f} = ${pct(worst.mean)} (${pct(worst.off)} dos pixels com desvio > 8/255)`);
console.log(`cena inteira (inclui piscadas e partículas sorteadas): média ${pct(allMean)}, pior ${pct(Math.max(...results.map((r) => r.mean)))}`);
console.log(`diferença: ${diffPath}`);
const ok = detMean < LIMIT && worst.mean < LIMIT;
console.log(ok ? 'PASSOU (< 2%)' : 'FALHOU (≥ 2%)');
process.exit(ok ? 0 : 1);
