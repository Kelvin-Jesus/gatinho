// Gatinho: o site. Eu moro fixo no canto da janela e acompanho a rolagem. A primeira frase da
// folha eu digito; o resto você escreve e eu digito junto. Às vezes eu apronto: derrubo uma letra,
// sento no texto, sento na tecla de baixar e saio deixando ela torta. Tudo se desfaz, e a tecla
// de baixar funciona com ou sem mim em cima (eu não pego clique nenhum).
import { carregarGato, DESENHO } from "./js/gato.js";
import { CODIGO_MAC, rotulo } from "./js/teclas.js";

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const reduzir = matchMedia("(prefers-reduced-motion: reduce)");
const estreito = matchMedia("(max-width: 760px)");
const PELAGENS = ["tuxedo", "laranja", "marrom", "siames", "calico", "preto", "branco", "cinza", "cinzabranco"];
const LARANJA = 1;
const PROPORCAO = DESENHO.ALTURA / DESENHO.LARGURA;

const anuncio = $("[data-anuncio]");
const anunciar = (t) => { anuncio.textContent = ""; requestAnimationFrame(() => { anuncio.textContent = t; }); };
let gato = null;

// ---------------------------------------------------------------- downloads
const sistema = (() => {
  const ua = navigator.userAgent;
  const pl = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || "";
  const celular = /Android|iPhone|iPad|iPod/i.test(ua) || (navigator.maxTouchPoints > 1 && /Mac/.test(pl));
  if (celular) return { so: "mac", celular: true };
  if (/Win/i.test(pl) || /Windows/i.test(ua)) return { so: "windows" };
  if (/Linux|X11/i.test(pl)) return { so: "linux" };
  return { so: "mac" };
})();

const NOMES = { mac: "Mac", windows: "Windows", linux: "Linux" };
const teclaDoSistema = $(`.placa [data-so="${sistema.so}"]`);
const instrucoes = Object.fromEntries($$("[data-instrucoes] [data-para]").map((p) => [p.dataset.para, p]));

function mostrarInstrucoes(so) {
  for (const [k, p] of Object.entries(instrucoes)) p.hidden = k !== so;
}

{
  const primeira = $("[data-baixar]");
  const nota = $("[data-baixar-nota]");
  if (sistema.celular) {
    primeira.href = "#casa";
    $("[data-baixar-rotulo]").textContent = "Onde eu moro";
    nota.textContent = "Eu moro em computador: Mac, Windows e Linux. De graça, código aberto.";
    $("[data-celular]").hidden = false;
  } else {
    primeira.href = teclaDoSistema.href;
    $("[data-baixar-rotulo]").textContent = `Me leva pro ${NOMES[sistema.so]}`;
    const outros = Object.keys(NOMES).filter((k) => k !== sistema.so).map((k) => NOMES[k]);
    nota.innerHTML = "";
    const link = document.createElement("a");
    link.href = "#casa";
    link.textContent = `${outros[0]} e no ${outros[1]}`;
    nota.append("De graça, código aberto. Também moro no ", link, ".");
  }
  teclaDoSistema.dataset.seu = "";
  const meta = $(".tecla-meta", teclaDoSistema);
  if (!sistema.celular) {
    const seu = document.createElement("span");
    seu.className = "visualmente-oculto";
    seu.textContent = " (o seu sistema)";
    meta.append(seu);
  }
  mostrarInstrucoes(sistema.so);

  // Passar por outra tecla mostra como é a instalação nela; sair da placa volta pro seu sistema.
  const placa = $("[data-placa]");
  for (const t of $$(".tecla", placa)) {
    t.addEventListener("pointerenter", () => mostrarInstrucoes(t.dataset.so));
    t.addEventListener("focus", () => mostrarInstrucoes(t.dataset.so));
  }
  placa.addEventListener("pointerleave", () => { if (!placa.contains(document.activeElement)) mostrarInstrucoes(sistema.so); });
  placa.addEventListener("focusout", (ev) => { if (!placa.contains(ev.relatedTarget)) mostrarInstrucoes(sistema.so); });

  // Tecla apertada pelo teclado também afunda.
  for (const t of $$(".tecla")) {
    t.addEventListener("keydown", (ev) => { if (ev.key === "Enter") t.classList.add("apertada"); });
    t.addEventListener("keyup", () => t.classList.remove("apertada"));
    t.addEventListener("blur", () => t.classList.remove("apertada"));
  }
}

// ---------------------------------------------------------------- achados (as 6 travessuras)
// A lista mora na margem; no celular e no tablet, uma cópia abre pelo contador da barra.
{
  const copia = $("[data-achados-copia]");
  copia.append($("[data-achados-lista]").cloneNode(true), $(".margem [data-arrumar]").cloneNode(true));
}
const vistos = new Set();
const NOME_ACHADO = Object.fromEntries($$(".margem [data-achado]").map((li) => [li.dataset.achado, $(".achado-nome", li).textContent]));

function achar(qual) {
  if (vistos.has(qual)) return;
  vistos.add(qual);
  for (const li of $$(`[data-achado="${qual}"]`)) li.dataset.visto = "";
  for (const n of $$("[data-achados-n]")) n.textContent = String(vistos.size);
  anunciar(`Travessura: ${NOME_ACHADO[qual]}. ${vistos.size} de 6.`);
}

// nova → ativa (eu estou lá, ou a bagunça está feita) → feita (desfeita)
const trav = { letra: "nova", texto: "nova", tecla: "nova", torta: false };
const arrumar = $$("[data-arrumar]");
function contarBagunca() {
  const tem = trav.letra === "ativa" || trav.texto === "ativa" || trav.tecla === "ativa" || trav.torta;
  for (const b of arrumar) b.hidden = !tem;
}

// ---------------------------------------------------------------- a frase que eu digito
const frase = $("[data-frase]");
const letra = $("[data-letra]");
const caracteres = [];
{
  // A frase inteira fica pra leitor de tela; a que aparece letra por letra é só visual.
  const inteira = frase.textContent;
  const visual = document.createElement("span");
  visual.setAttribute("aria-hidden", "true");
  for (const no of [...frase.childNodes]) {
    if (no === letra) { letra.classList.add("ch"); caracteres.push(letra); visual.append(letra); continue; }
    for (const c of no.textContent) {
      const s = document.createElement("span");
      s.className = "ch";
      s.textContent = c;
      caracteres.push(s);
      visual.append(s);
    }
  }
  const leitura = document.createElement("span");
  leitura.className = "visualmente-oculto";
  leitura.textContent = inteira;
  frase.replaceChildren(visual, leitura);
}

function codigoDe(c) {
  const base = c.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase();
  if (/^[A-Z]$/.test(base)) return CODIGO_MAC["Key" + base];
  if (/^[0-9]$/.test(base)) return CODIGO_MAC["Digit" + base];
  return { " ": CODIGO_MAC.Space, ".": CODIGO_MAC.Period, ",": CODIGO_MAC.Comma, "\n": CODIGO_MAC.Enter }[c];
}
function digitarNoGato(c) {
  if (!gato || pausado) return;
  const k = codigoDe(c);
  if (k === undefined) return;
  gato.tecla(k, rotulo(k, { key: c }), true, false);
  setTimeout(() => gato && gato.tecla(k, 0, false, false), 70);
}

let fraseProntaEm = 0;
function fraseFeita() {
  fraseProntaEm = performance.now();
  // No computador, a folha já fica pronta pra escrever. No celular, abrir o teclado sozinho atrapalha.
  if (!sistema.celular && !estreito.matches && document.activeElement === document.body) escrita.focus({ preventScroll: true });
}
function digitarFrase() {
  if (reduzir.matches) { caracteres.forEach((s) => s.classList.add("ok")); fraseFeita(); return; }
  let i = 0;
  const passo = () => {
    if (i >= caracteres.length) { fraseFeita(); return; }
    const s = caracteres[i++];
    s.classList.add("ok");
    digitarNoGato(s.textContent);
    const c = s.textContent;
    // Pausa maior depois de ponto, um tico depois de espaço, e uma variação pra parecer gente (ou gato).
    const espera = c === "." ? 380 : c === " " ? 70 : 42 + Math.random() * 46;
    setTimeout(passo, espera);
  };
  passo();
}

// ---------------------------------------------------------------- a folha onde você escreve
const escrita = $("[data-escrita]");
let teclaValidaEm = 0;
function vazia() {
  const v = escrita.textContent.trim() === "";
  if (v && escrita.innerHTML !== "") escrita.innerHTML = "";
  escrita.toggleAttribute("data-vazia", v);
}
escrita.addEventListener("input", (ev) => {
  vazia();
  // No celular o teclado virtual não manda keydown com tecla de verdade: digito pelo caractere.
  if (performance.now() - teclaValidaEm < 120) return;
  if (ev.inputType === "deleteContentBackward") { digitarCodigo(CODIGO_MAC.Backspace); return; }
  if (ev.data) for (const c of ev.data.slice(-3)) digitarNoGato(c);
});
function digitarCodigo(k) {
  if (!gato || pausado) return;
  gato.tecla(k, 0, true, false);
  setTimeout(() => gato && gato.tecla(k, 0, false, false), 70);
}
// Colar só texto, sem formatação.
escrita.addEventListener("paste", (ev) => {
  ev.preventDefault();
  const t = (ev.clipboardData || window.clipboardData).getData("text/plain").slice(0, 2000);
  document.execCommand("insertText", false, t);
});

// ---------------------------------------------------------------- a letra que eu derrubo
const avisoLetra = $("[data-aviso-letra]");
const vagaLetra = $("[data-vaga-letra]");
const posLetra = { x: 0, y: 0, r: 0 };

function poseLetra(x, y, r) {
  posLetra.x = x; posLetra.y = y; posLetra.r = r;
  letra.style.transform = x || y || r ? `translate(${x}px, ${y}px) rotate(${r}deg)` : "";
}
/** Deitada na vaga do aviso, embaixo da folha. offsetLeft/Top ignoram o transform. */
function poseCaida() {
  const pai = letra.offsetParent;
  const rp = pai.getBoundingClientRect();
  const ox = rp.left + pai.clientLeft + letra.offsetLeft + letra.offsetWidth * 0.5;
  const oy = rp.top + pai.clientTop + letra.offsetTop + letra.offsetHeight * 0.85;
  const v = vagaLetra.getBoundingClientRect();
  const em = parseFloat(getComputedStyle(letra).fontSize);
  return { x: v.left + v.width / 2 - ox + em * 0.2, y: v.top + v.height / 2 - oy, r: -98 };
}
function reposicionarLetra() {
  if (trav.letra !== "ativa" || letra.classList.contains("arrastando")) return;
  const p = poseCaida();
  letra.style.transition = "none";
  poseLetra(p.x, p.y, p.r);
  letra.getBoundingClientRect();
  letra.style.transition = "";
}
addEventListener("resize", reposicionarLetra);
new ResizeObserver(reposicionarLetra).observe(escrita);

function derrubarLetra() {
  if (trav.letra !== "nova") return;
  trav.letra = "ativa";
  avisoLetra.hidden = false;
  letra.classList.add("caida");
  const p = poseCaida();
  requestAnimationFrame(() => poseLetra(p.x, p.y, p.r));
  achar("letra");
  contarBagunca();
}
function letraNoLugar(falar = true) {
  if (trav.letra !== "ativa") return;
  trav.letra = "feita";
  letra.classList.remove("arrastando");
  letra.classList.add("volta");
  poseLetra(0, 0, 0);
  avisoLetra.hidden = true;
  setTimeout(() => letra.classList.remove("caida", "volta"), 450);
  contarBagunca();
  if (falar) anunciar("Letra de volta no lugar");
}
$("[data-letra-volta]").addEventListener("click", () => letraNoLugar());

letra.addEventListener("pointerdown", (ev) => {
  if (trav.letra !== "ativa") return;
  ev.preventDefault();
  letra.setPointerCapture(ev.pointerId);
  letra.classList.add("arrastando");
  const ini = { x: ev.clientX, y: ev.clientY, px: posLetra.x, py: posLetra.y, r: posLetra.r };
  const r0 = Math.max(1, Math.hypot(ini.px, ini.py));
  const mover = (e) => {
    const x = ini.px + e.clientX - ini.x, y = ini.py + e.clientY - ini.y;
    poseLetra(x, y, ini.r * Math.min(1, Math.hypot(x, y) / r0)); // endireita chegando perto
  };
  const soltar = () => {
    letra.removeEventListener("pointermove", mover);
    letra.classList.remove("arrastando");
    if (Math.hypot(posLetra.x, posLetra.y) < 40) letraNoLugar();
    else if (trav.letra === "ativa") { const p = poseCaida(); poseLetra(p.x, p.y, p.r); } // longe: volta pra vaga
  };
  letra.addEventListener("pointermove", mover);
  letra.addEventListener("pointerup", soltar, { once: true });
  letra.addEventListener("pointercancel", soltar, { once: true });
});

// ---------------------------------------------------------------- a tecla torta
const avisoTorto = $("[data-aviso-torto]");
const avisoBotao = $("[data-aviso-botao]");
function entortar() {
  if (trav.torta) return;
  trav.torta = true;
  teclaDoSistema.classList.add("torta");
  avisoTorto.hidden = false;
  achar("torta");
  contarBagunca();
}
function endireitar(falar = true) {
  if (!trav.torta) return;
  trav.torta = false;
  teclaDoSistema.classList.add("endireitando");
  teclaDoSistema.classList.remove("torta");
  setTimeout(() => teclaDoSistema.classList.remove("endireitando"), 260);
  avisoTorto.hidden = true;
  contarBagunca();
  if (falar) anunciar("Tecla no lugar");
}
$("[data-endireitar]").addEventListener("click", () => endireitar());

// ---------------------------------------------------------------- pelagens (funciona sem o gato vivo)
const parado = $("[data-parado]");
const pelagemNome = $("[data-pelagem-nome]");
$("[data-pelagens]").addEventListener("change", (ev) => {
  const i = Number(ev.target.value);
  parado.src = `media/pelagens/${PELAGENS[i]}.webp`;
  pelagemNome.textContent = $(".visualmente-oculto", ev.target.closest("label")).textContent.toLocaleLowerCase("pt-BR");
  if (gato) gato.pelagem = i;
});

// ---------------------------------------------------------------- onde eu estou
const gatoEl = $("[data-gato]");
const canvas = $("canvas", gatoEl);
const folha = $(".folha");
const paragrafo = $("[data-paragrafo]");
const avisoParagrafo = $("[data-aviso-paragrafo]");

let pausado = reduzir.matches;
let spot = "canto";
let voo = null;
let pendente = { spot: null, desde: 0 };
let fixo = true;
let petting = false;
let ronronouDesde = 0;
let ultimaTransform = "";
let ligadoEm = 0;
const ninho = $("[data-ninho]");

function visivel(r) {
  return Math.max(0, Math.min(r.bottom, innerHeight) - Math.max(r.top, 0)) / Math.max(1, r.height);
}

/** Onde eu fico em cada lugar, em px da viewport, e a escala do desenho (k = px por ponto). */
function alvo(nome) {
  if (nome === "canto") {
    // O ninho já leva em conta a margem, a faixa e a área segura do aparelho.
    const r = ninho.getBoundingClientRect();
    return { x: r.left, y: r.top, k: r.width / DESENHO.LARGURA, fixo: true };
  }
  if (nome === "paragrafo") {
    const r = paragrafo.getBoundingClientRect();
    const w = Math.min(r.width * (estreito.matches ? 0.6 : 0.46), 280), h = w * PROPORCAO;
    return { x: r.right - w * 0.92, y: r.top + r.height * 0.55 - h * 0.62, k: w / DESENHO.LARGURA, fixo: false };
  }
  if (nome === "tecla") {
    // Sentado em cima da face da tecla, do lado direito: o nome do sistema continua à vista e a
    // tecla fica afundada embaixo de mim.
    const r = $(".tecla-topo", teclaDoSistema).getBoundingClientRect();
    const w = Math.min(r.width * 0.42, r.height * 1.06, 124), h = w * PROPORCAO; // a legenda de baixo fica à vista
    return { x: r.right - w * 0.98, y: r.bottom - h * 0.96, k: w / DESENHO.LARGURA, fixo: false };
  }
  return null;
}

function aplicarPose(p, emFixo) {
  if (emFixo !== fixo) { fixo = emFixo; gatoEl.classList.toggle("solto", !fixo); ultimaTransform = ""; }
  const x = emFixo ? p.x : p.x + scrollX, y = emFixo ? p.y : p.y + scrollY;
  const t = `translate3d(${x.toFixed(1)}px, ${y.toFixed(1)}px, 0) scale(${p.k.toFixed(4)})`;
  if (t !== ultimaTransform) { gatoEl.style.transform = t; ultimaTransform = t; }
}

function escolher() {
  // Só apronto depois de uns segundos na página, e nunca enquanto você escreve.
  const agora = performance.now();
  if (agora - ligadoEm < 4000 || agora - teclaValidaEm < 2500) return "canto";
  if (trav.tecla === "nova" || spot === "tecla") {
    const fica = spot === "tecla";
    if (visivel(teclaDoSistema.getBoundingClientRect()) >= (fica ? 0.25 : 0.98)) return "tecla";
  }
  if (trav.texto === "nova" || spot === "paragrafo") {
    if (visivel(paragrafo.getBoundingClientRect()) >= (spot === "paragrafo" ? 0.3 : 0.9)) return "paragrafo";
  }
  return "canto";
}

/** Ao sair de cima do texto, a travessura acabou; de cima da tecla, saio e deixo ela torta. */
function sair(de, entortando = true) {
  if (de === "paragrafo" && trav.texto === "ativa") { trav.texto = "feita"; avisoParagrafo.hidden = true; }
  if (de === "tecla" && trav.tecla === "ativa") {
    trav.tecla = "feita";
    teclaDoSistema.classList.remove("apertada");
    avisoBotao.hidden = true;
    if (entortando) entortar();
  }
  contarBagunca();
}
function chegar(em) {
  if (em === "paragrafo" && trav.texto === "nova") { trav.texto = "ativa"; avisoParagrafo.hidden = false; achar("texto"); }
  if (em === "tecla" && trav.tecla === "nova") {
    trav.tecla = "ativa";
    teclaDoSistema.classList.add("apertada");
    avisoBotao.hidden = false;
    achar("tecla");
  }
  contarBagunca();
}

function voar(de, novo, dur, arco) {
  voo = { de, ini: performance.now(), dur, arco };
  if (reduzir.matches) { voo = null; const a = alvo(novo); aplicarPose(a, a.fixo); }
}
function irPara(novo, entortando = true) {
  if (novo === spot) return;
  sair(spot, entortando);
  spot = novo;
  gatoEl.dataset.spot = novo;
  const r = gatoEl.getBoundingClientRect();
  const a = alvo(novo);
  const dist = Math.hypot(a.x - r.left, a.y - r.top);
  voar({ x: r.left, y: r.top, k: r.width / DESENHO.LARGURA }, novo, Math.min(760, 420 + dist / 4), Math.min(64, 16 + dist / 10));
  chegar(novo);
}

function seguir(agora) {
  const a = alvo(spot);
  if (!voo) { aplicarPose(a, a.fixo); return; }
  const p = Math.min(1, (agora - voo.ini) / voo.dur);
  const e = 1 - Math.pow(1 - p, 3.2); // sai rápido e pousa devagar
  aplicarPose({
    x: voo.de.x + (a.x - voo.de.x) * e,
    y: voo.de.y + (a.y - voo.de.y) * e - Math.sin(Math.PI * p) * voo.arco,
    k: voo.de.k + (a.k - voo.de.k) * e,
  }, true);
  if (p >= 1) { voo = null; aplicarPose(a, a.fixo); }
}

function decidir(agora) {
  if (petting || voo || pausado || !gatoEl.classList.contains("chegou")) return;
  const quer = escolher();
  if (quer === spot) { pendente.spot = null; return; }
  if (pendente.spot !== quer) { pendente = { spot: quer, desde: agora }; return; }
  if (agora - pendente.desde > 220) { pendente.spot = null; irPara(quer); }
}

function tirarDaqui(nome) {
  if (spot !== nome) return;
  sair(nome);   // vira "feita" antes, senão eu volto pro mesmo lugar
  irPara("canto");
}
$("[data-tirar-paragrafo]").addEventListener("click", () => tirarDaqui("paragrafo"));
$("[data-tirar-botao]").addEventListener("click", () => tirarDaqui("tecla"));

const arrumarTudo = () => {
  letraNoLugar(false);
  if (spot === "paragrafo" || spot === "tecla") irPara("canto", false); // arrumando, não entorto nada
  sair("paragrafo", false);
  sair("tecla", false);
  endireitar(false);
  contarBagunca();
  anunciar("Tudo arrumado");
};
for (const b of arrumar) b.addEventListener("click", arrumarTudo);

// ---------------------------------------------------------------- pausa
const botaoPausa = $("[data-pausa]");
function pausar(v) {
  pausado = v;
  botaoPausa.setAttribute("aria-pressed", String(v));
  $("[data-pausa-rotulo]", botaoPausa).firstChild.textContent = v ? "Soltar" : "Pausar"; // " o gato" some na faixa estreita
  if (v) dizerAgora("pausado");
  else if (!gato) dizerAgora("parado no ninho");
  estadoDia = "";
}
botaoPausa.addEventListener("click", () => pausar(!pausado));

// ---------------------------------------------------------------- o diário, ao vivo
const entradas = Object.fromEntries($$(".entrada[data-estado]").map((el) => {
  const hora = $(".hora-texto", el);
  return [el.dataset.estado, { el, hora, original: hora.textContent }];
}));
let ultimaEntrada = "teclado";
let humorAntes = 0, acordouEm = -1e9;
let estadoDia = "";
const agoraEl = $("[data-agora]");
const AGORA = {
  digitando: "digitando junto", mouse: "de olho no seu mouse", carinho: "ganhando carinho",
  bolinha: "brincando de bolinha", sonhando: "sonhando acordado", dormindo: "dormindo", voltou: "me espreguiçando",
};
function dizerAgora(t) { agoraEl.textContent = `agora: ${t}`; }

function marcarDia(agora) {
  const h = gato.humor;
  if (humorAntes === 2 && h === 0) acordouEm = agora;
  humorAntes = h;
  const e = petting ? "carinho"
    : h === 2 ? "dormindo"
    : h === 1 ? "sonhando"
    : agora - acordouEm < 2500 ? "voltou"
    : gato.temBolinha ? "bolinha"
    : ultimaEntrada === "mouse" ? "mouse" : "digitando";
  if (e === estadoDia) return;
  for (const v of Object.values(entradas)) {
    if (v.el.hasAttribute("aria-current")) { v.el.removeAttribute("aria-current"); v.hora.textContent = v.original; }
  }
  const novo = entradas[e];
  novo.el.setAttribute("aria-current", "true");
  novo.hora.textContent = "agora";
  dizerAgora(AGORA[e]);
  estadoDia = e;
}

// ---------------------------------------------------------------- teclado, mouse e toque
function pontoNoDesenho(ev) {
  const r = gatoEl.getBoundingClientRect();
  return { x: (ev.clientX - r.left) / r.width * DESENHO.LARGURA, y: (ev.clientY - r.top) / r.height * DESENHO.ALTURA };
}
function sobreOGato(ev) {
  if (!gato || pausado) return false;
  const r = gatoEl.getBoundingClientRect();
  return ev.clientX >= r.left && ev.clientX <= r.right && ev.clientY >= r.top && ev.clientY <= r.bottom;
}

const CONTROLE = "a[href], button, input, select, textarea, label, summary, [contenteditable]";
const presas = new Map();
addEventListener("keydown", (ev) => {
  if (ev.isComposing || ev.key === "Unidentified" || ev.keyCode === 229) return;
  teclaValidaEm = performance.now();
  // Tecla de letra com a página à toa: vai pra folha, que é onde se escreve aqui.
  const alvoEv = ev.target instanceof Element ? ev.target : null;
  if (alvoEv && !alvoEv.closest(CONTROLE) && ev.key.length === 1 && /\S/.test(ev.key)
    && !ev.ctrlKey && !ev.metaKey && !ev.altKey && visivel(folha.getBoundingClientRect()) > 0.3) {
    escrita.focus({ preventScroll: true });
    const fim = document.createRange();
    fim.selectNodeContents(escrita);
    fim.collapse(false);
    getSelection().removeAllRanges();
    getSelection().addRange(fim);
  }
  if (!gato || pausado) return;
  ultimaEntrada = "teclado";
  const c = CODIGO_MAC[ev.code] ?? 0xffff;
  if (c === 57) { gato.modificador(57); return; } // Caps Lock: um toque, como no app
  presas.set(ev.code, c);
  gato.tecla(c, rotulo(c, ev), true, ev.repeat);
});
addEventListener("keyup", (ev) => {
  if (!gato) return;
  const c = CODIGO_MAC[ev.code] ?? 0xffff;
  if (c === 57) { if (!pausado) gato.modificador(57); return; }
  presas.delete(ev.code);
  gato.tecla(c, 0, false, false);
});
addEventListener("blur", () => {
  if (!gato) return;
  for (const c of presas.values()) gato.tecla(c, 0, false, false);
  presas.clear();
});

// Eu não pego clique nenhum (pointer-events: none). Aqui, na captura, a página decide se o toque
// é meu: primeiro a bolinha, depois a cabeça (carinho). Em cima de link ou botão, clique rápido
// continua sendo do link: é assim que baixar nunca fica preso embaixo de mim.
const raiz = document.documentElement;
const BOTAO = { 0: 0, 2: 1, 1: 2 }; // JS → app: esquerdo, direito, meio
let carinho = null;
let engolir = false, engolirAte = 0, engolirToque = false;

addEventListener("pointermove", (ev) => {
  if (!gato) return;
  if (ev.pointerType === "mouse") ultimaEntrada = "mouse";
  const p = pontoNoDesenho(ev);
  gato.ponteiro = p;
  if (petting && ev.pointerId === carinho.id) {
    if (Math.hypot(ev.clientX - carinho.x, ev.clientY - carinho.y) > 8) carinho.moveu = true;
    if (ev.buttons === 0) fimDoCarinho(ev);
    else gato.carinho(1, p);
    return;
  }
  raiz.classList.toggle("mao-no-gato", ev.pointerType === "mouse" && sobreOGato(ev) && gato.naCabeca(p));
}, { passive: true });

addEventListener("pointerdown", (ev) => {
  engolir = false;
  engolirToque = false;
  if (!gato) return;
  if (!pausado && ev.pointerType === "mouse" && BOTAO[ev.button] !== undefined) gato.botao(BOTAO[ev.button], true);
  if (ev.button !== 0 || petting || !sobreOGato(ev)) return;
  const p = pontoNoDesenho(ev);
  const emControle = ev.target instanceof Element && ev.target.closest(CONTROLE) !== null;
  if (gato.cutucar(p)) {
    achar("bolinha");
    if (!emControle) { ev.preventDefault(); engolir = true; engolirToque = ev.pointerType === "touch"; }
    return;
  }
  if (!gato.naCabeca(p)) return;
  if (!emControle) { ev.preventDefault(); engolirToque = ev.pointerType === "touch"; }
  petting = true;
  carinho = { id: ev.pointerId, x: ev.clientX, y: ev.clientY, t: performance.now(), moveu: false };
  ronronouDesde = 0;
  raiz.classList.add("fazendo-carinho");
  gato.carinho(0, p);
}, { capture: true });

function fimDoCarinho(ev) {
  if (!petting || ev.pointerId !== carinho.id) return;
  // Segurou, alisou ou eu ronronei: foi carinho, e o clique não vale. Toque rápido é clique.
  if (carinho.moveu || ronronouDesde || performance.now() - carinho.t > 450) engolir = true;
  petting = false;
  carinho = null;
  raiz.classList.remove("fazendo-carinho");
  gato.carinho(2);
  // Carinho de verdade me tira de cima do que eu estiver bagunçando.
  const ganhou = ronronouDesde && performance.now() - ronronouDesde > 700;
  const onde = spot;
  if (ganhou && (onde === "paragrafo" || onde === "tecla")) setTimeout(() => tirarDaqui(onde), 350);
}
addEventListener("pointerup", (ev) => {
  if (gato && ev.pointerType === "mouse" && BOTAO[ev.button] !== undefined) gato.botao(BOTAO[ev.button], false);
  fimDoCarinho(ev);
  engolirAte = engolir ? performance.now() + 500 : 0;
  engolir = false;
}, { capture: true });
addEventListener("pointercancel", (ev) => { fimDoCarinho(ev); engolir = false; }, { capture: true });
addEventListener("click", (ev) => {
  if (!engolirAte || performance.now() > engolirAte) return;
  engolirAte = 0;
  ev.preventDefault();
  ev.stopPropagation();
}, { capture: true });
addEventListener("dragstart", (ev) => { if (petting) ev.preventDefault(); }, { capture: true });
addEventListener("touchstart", (ev) => {
  if (engolirToque) { ev.preventDefault(); engolirToque = false; }
}, { capture: true, passive: false });
addEventListener("wheel", (ev) => {
  if (!gato || pausado) return;
  ultimaEntrada = "mouse";
  gato.rolar(-ev.deltaY * (ev.deltaMode === 0 ? 0.15 : 1.5));
}, { passive: true });

// ---------------------------------------------------------------- laço
let custos = [], rodando = false;

function quadro(agora) {
  if (document.hidden) { rodando = false; return; }
  requestAnimationFrame(quadro);
  decidir(agora);
  seguir(agora);

  // A letra: uns segundos depois de eu terminar a frase, se você ainda estiver olhando pra ela.
  if (trav.letra === "nova" && fraseProntaEm && !pausado && agora - fraseProntaEm > 7000
    && visivel(frase.getBoundingClientRect()) > 0.9) derrubarLetra();

  if (!gato || pausado) return;
  const a = performance.now();
  gato.quadro();
  custos.push(performance.now() - a);
  // Se a máquina não aguenta, desenho com menos pixels (o desenho é vetorial, só fica mais macio).
  if (custos.length === 40) {
    custos.sort((x, y) => x - y);
    if (custos[20] > 11 && gato.escala > 1.25) gato.escala = Math.max(1.25, gato.escala - 0.25);
    custos = [];
  }
  // Ronronar aqui é só o desenho (a cabeça vibrando). Som, só no app.
  if (gato.ronronando && !ronronouDesde) ronronouDesde = performance.now();
  if (petting && ronronouDesde) achar("ronronou");
  marcarDia(agora);
}
function ligar() {
  if (rodando) return;
  rodando = true;
  requestAnimationFrame(quadro);
}
document.addEventListener("visibilitychange", () => { if (!document.hidden) ligar(); });

/** A única entrada da página: eu pulo de fora da janela pro meu canto. */
function chegarNoCanto() {
  const a = alvo("canto");
  const de = { x: innerWidth + 24, y: a.y - a.k * DESENHO.ALTURA * 0.5, k: a.k };
  aplicarPose(de, true);
  gatoEl.classList.add("chegou");
  ligadoEm = performance.now();
  if (reduzir.matches) aplicarPose(a, true);
  else voar(de, "canto", 680, 72);
  ligar();
  setTimeout(digitarFrase, reduzir.matches ? 0 : 760);
}

async function iniciar() {
  let k = alvo("canto").k;
  if ("WebAssembly" in window) {
    try {
      const escala = Math.min(2.5, Math.max(1.25, Math.round(k * (devicePixelRatio || 1) * 4) / 4));
      gato = await Promise.race([
        carregarGato("wasm/gatinho.wasm", canvas, { pelagem: LARANJA, escala }),
        new Promise((_, falha) => setTimeout(() => falha(new Error("demorou")), 6000)),
      ]);
      const escolhida = $("[data-pelagens] input:checked");
      if (escolhida) gato.pelagem = Number(escolhida.value);
      gato.quadro();
      gatoEl.classList.add("vivo");
    } catch {
      gato = null; // fico na foto, mas as travessuras continuam
    }
  }
  pausar(pausado);
  chegarNoCanto();
}

raiz.classList.add("js");
iniciar();
