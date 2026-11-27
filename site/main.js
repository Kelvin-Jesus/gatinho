// Gatinho: botão de download do seu sistema, paralaxe da cidade,
// o gato dormindo quando você para de mexer e o botão de pausar.
(() => {
  const raiz = document.documentElement;
  const corpo = document.body;
  const reduzir = matchMedia("(prefers-reduced-motion: reduce)");

  // ---------- qual sistema ----------
  const ua = navigator.userAgent;
  const plataforma = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || "";
  const celular = /Android|iPhone|iPad|iPod/i.test(ua) || (navigator.maxTouchPoints > 1 && /Mac/.test(plataforma));
  let so = "mac";
  if (/Win/i.test(plataforma) || /Windows/i.test(ua)) so = "windows";
  else if (/Linux|X11/i.test(plataforma) && !/Android/i.test(ua)) so = "linux";

  const base = "https://github.com/Kelvin-Jesus/gatinho/releases/latest/download/";
  const downloads = {
    mac: { url: base + "Gatinho-macos.zip", rotulo: "Baixar pro Mac", nota: "Apple Silicon · .zip" },
    windows: { url: base + "Gatinho-windows.zip", rotulo: "Baixar pro Windows", nota: "Windows · .zip" },
    linux: { url: base + "Gatinho-linux-x86_64", rotulo: "Baixar pro Linux", nota: "x86_64 · executável" },
  };
  const d = downloads[so];
  const botao = document.querySelector("[data-baixar]");
  if (celular) {
    botao.href = "#baixar";
    document.querySelector("[data-baixar-rotulo]").textContent = "Ver downloads";
    document.querySelector("[data-baixar-nota]").textContent = "Mac, Windows e Linux";
    document.querySelector("[data-celular]").hidden = false;
  } else {
    botao.href = d.url;
    document.querySelector("[data-baixar-rotulo]").textContent = d.rotulo;
    document.querySelector("[data-baixar-nota]").textContent = d.nota;
    const cartao = document.querySelector(`[data-so="${so}"]`);
    if (cartao) cartao.classList.add("seu");
  }

  // ---------- pausar animações ----------
  const gifs = [...document.querySelectorAll("img[data-gif]")];
  const botaoPausa = document.querySelector("[data-pausa]");
  const rotuloPausa = document.querySelector("[data-pausa-rotulo]");
  let pausado = false;
  let dormindo = false;

  const srcDe = (img) => {
    const nome = img === gifs[0] && dormindo ? "soneca" : img.dataset.gif;
    return `img/${nome}${pausado ? "-parado.png" : ".gif"}`;
  };
  const atualizarGifs = () => gifs.forEach((img) => {
    const novo = srcDe(img);
    if (!img.src.endsWith(novo)) img.src = novo;
  });

  const lerPreferencia = () => {
    try { return localStorage.getItem("gatinho-pausado"); } catch { return null; }
  };
  const salvarPreferencia = (v) => {
    try { localStorage.setItem("gatinho-pausado", v ? "1" : "0"); } catch {}
  };

  const definirPausa = (v, salvar) => {
    pausado = v;
    corpo.classList.toggle("pausado", v);
    botaoPausa.setAttribute("aria-pressed", String(v));
    rotuloPausa.textContent = v ? "Tocar animações" : "Pausar animações";
    if (salvar) salvarPreferencia(v);
    atualizarGifs();
    if (v) { zerarParalaxe(); } else { agendarParalaxe(); }
  };
  botaoPausa.addEventListener("click", () => definirPausa(!pausado, true));

  // ---------- paralaxe ----------
  const camadas = [...document.querySelectorAll("[data-paralaxe]")];
  const cena = document.querySelector(".cena");
  let pedido = 0;
  const paralaxe = () => {
    pedido = 0;
    const y = Math.min(scrollY, cena.offsetHeight);
    for (const c of camadas) c.style.transform = `translate3d(0, ${(y * parseFloat(c.dataset.paralaxe)).toFixed(1)}px, 0)`;
  };
  const agendarParalaxe = () => {
    if (pausado || reduzir.matches || pedido) return;
    pedido = requestAnimationFrame(paralaxe);
  };
  const zerarParalaxe = () => camadas.forEach((c) => { c.style.transform = ""; });
  addEventListener("scroll", agendarParalaxe, { passive: true });

  // ---------- o gato dorme se você some ----------
  const DORMIR_DEPOIS = 40_000;
  const legenda = document.querySelector("[data-sono-legenda]");
  let timer = 0;
  const dormir = () => {
    if (pausado) return;
    dormindo = true;
    corpo.classList.add("dormindo");
    legenda.textContent = "Ele dormiu. Mexe o mouse que ele acorda.";
    atualizarGifs();
  };
  const acordar = () => {
    clearTimeout(timer);
    timer = setTimeout(dormir, DORMIR_DEPOIS);
    if (!dormindo) return;
    dormindo = false;
    corpo.classList.remove("dormindo");
    legenda.textContent = "";
    atualizarGifs();
  };
  ["pointermove", "pointerdown", "keydown", "scroll", "touchstart", "wheel"].forEach((ev) =>
    addEventListener(ev, acordar, { passive: true }));
  document.addEventListener("visibilitychange", () => { if (!document.hidden) acordar(); });

  // ---------- início ----------
  const salvo = lerPreferencia();
  definirPausa(salvo === null ? reduzir.matches : salvo === "1", false);
  acordar();
  raiz.classList.add("js");
})();
