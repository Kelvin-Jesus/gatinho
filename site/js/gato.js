// O gato da página: o GatinhoCore do app compilado pra WebAssembly (Sources/GatinhoWeb/main.swift).
// Aqui só entram o relógio, os eventos e a cópia dos pixels pro <canvas>.
import { criarWasi } from "./wasi.js";

const LARGURA = 330, ALTURA = 300; // espaço do desenho, em pontos (Geo.size)
const REFERENCIA = 978307200;      // 1/1/2001, o zero do relógio do Swift

/** Relógio em segundos, no mesmo zero do `Date().timeIntervalSinceReferenceDate` do app. */
export const relogio = () => (performance.timeOrigin + performance.now()) / 1000 - REFERENCIA;

async function instanciar(url, imports) {
  if (WebAssembly.instantiateStreaming) {
    try { return (await WebAssembly.instantiateStreaming(fetch(url), imports)).instance; }
    catch { /* servidor sem application/wasm: tenta do jeito simples */ }
  }
  const r = await fetch(url);
  if (!r.ok) throw new Error(`wasm: HTTP ${r.status}`);
  return (await WebAssembly.instantiate(await r.arrayBuffer(), imports)).instance;
}

export async function carregarGato(url, canvas, opcoes = {}) {
  const wasi = criarWasi();
  const instancia = await instanciar(url, wasi.imports);
  wasi.ligar(instancia);
  return new Gato(instancia.exports, canvas, opcoes);
}

class Gato {
  constructor(e, canvas, { pelagem = 1, escala = 2 } = {}) {
    this.e = e;
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.s = escala;
    this.ponteiro = { x: LARGURA / 2, y: ALTURA * 1.4 }; // em pontos do desenho
    e.gato_iniciar(pelagem, escala, relogio());
    this.ajustar();
  }

  ajustar() {
    const w = this.e.gato_largura(), h = this.e.gato_altura();
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
    this.imagem = this.ctx.createImageData(w, h);
  }

  get escala() { return this.s; }
  set escala(s) { this.s = s; this.e.gato_escala(s); this.ajustar(); }

  /** Anima até agora e desenha um quadro. */
  quadro() {
    const { e, s } = this;
    const ptr = e.gato_quadro(relogio(), this.ponteiro.x * s, this.ponteiro.y * s, 0, 0, LARGURA * s, ALTURA * s);
    const n = this.imagem.data.length;
    this.imagem.data.set(new Uint8Array(e.memory.buffer, ptr, n));
    this.ctx.putImageData(this.imagem, 0, 0);
  }

  // Eventos: o relógio vai antes, pra cada evento cair no instante certo.
  tecla(codigo, letra, apertou, repetiu) { this.e.gato_relogio(relogio()); this.e.gato_tecla(codigo, letra, apertou ? 1 : 0, repetiu ? 1 : 0); }
  modificador(codigo) { this.e.gato_relogio(relogio()); this.e.gato_modificador(codigo); }
  botao(b, apertou) { this.e.gato_relogio(relogio()); this.e.gato_botao(b, apertou ? 1 : 0); }
  rolar(dy) { this.e.gato_relogio(relogio()); this.e.gato_rolar(dy); }
  carinho(fase, p) { this.e.gato_relogio(relogio()); this.e.gato_carinho(fase, p ? p.x : 0, p ? p.y : 0); }
  naCabeca(p) { return this.e.gato_na_cabeca(p.x, p.y) === 1; }
  /** Cutuca a bolinha de lã, se ela estiver ali (ela quica). Devolve se acertou. */
  cutucar(p) { this.e.gato_relogio(relogio()); return this.e.gato_cutucar ? this.e.gato_cutucar(p.x, p.y) === 1 : false; }
  get temBolinha() { return this.e.gato_tem_bolinha ? this.e.gato_tem_bolinha() === 1 : false; }
  get ronronando() { return this.e.gato_ronronando() === 1; }
  /** 0 acordado, 1 sonhando acordado, 2 dormindo. */
  get humor() { return this.e.gato_humor(); }
  set pelagem(i) { this.e.gato_pelagem(i); }
}

export const DESENHO = { LARGURA, ALTURA };
