// WASI preview1 mínimo: só o que o gato usa de verdade (relógio, aleatório, console).
// Qualquer outra chamada devolve ENOSYS e o Swift segue sem ela.
const ENOSYS = 52;
const EBADF = 8;

export function criarWasi() {
  let memoria = null;
  const dv = () => new DataView(memoria.buffer);
  const bytes = () => new Uint8Array(memoria.buffer);
  const texto = new TextDecoder();
  const saida = { 1: "", 2: "" };

  const conhecidas = {
    args_sizes_get(argc, bufSize) { dv().setUint32(argc, 0, true); dv().setUint32(bufSize, 0, true); return 0; },
    args_get() { return 0; },
    environ_sizes_get(n, bufSize) { dv().setUint32(n, 0, true); dv().setUint32(bufSize, 0, true); return 0; },
    environ_get() { return 0; },
    clock_res_get(_id, out) { dv().setBigUint64(out, 1000n, true); return 0; },
    clock_time_get(id, _precisao, out) {
      // 0 = tempo real (desde 1970), 1 = monotônico. Os dois em nanossegundos.
      const ms = id === 0 ? performance.timeOrigin + performance.now() : performance.now();
      dv().setBigUint64(out, BigInt(Math.round(ms * 1e6)), true);
      return 0;
    },
    random_get(ptr, len) {
      const alvo = bytes().subarray(ptr, ptr + len);
      for (let i = 0; i < len; i += 65536) crypto.getRandomValues(alvo.subarray(i, Math.min(len, i + 65536)));
      return 0;
    },
    fd_write(fd, iovs, n, escritos) {
      const d = dv();
      let total = 0;
      for (let i = 0; i < n; i++) {
        const p = d.getUint32(iovs + i * 8, true), l = d.getUint32(iovs + i * 8 + 4, true);
        if (fd === 1 || fd === 2) saida[fd] += texto.decode(bytes().subarray(p, p + l));
        total += l;
      }
      d.setUint32(escritos, total, true);
      for (const f of [1, 2]) {
        const linhas = saida[f].split("\n");
        saida[f] = linhas.pop();
        for (const l of linhas) (f === 1 ? console.log : console.warn)("[gato]", l);
      }
      return fd <= 2 ? 0 : EBADF;
    },
    fd_fdstat_get(fd, out) {
      if (fd > 2) return EBADF;
      const d = dv();
      d.setUint8(out, 2); // dispositivo de caractere
      d.setUint16(out + 2, 0, true);
      d.setBigUint64(out + 8, 0n, true);
      d.setBigUint64(out + 16, 0n, true);
      return 0;
    },
    fd_prestat_get() { return EBADF; }, // nenhuma pasta aberta: o gato não lê disco
    fd_close() { return 0; },
    sched_yield() { return 0; },
    proc_exit(codigo) { throw new Error(`o gato saiu (código ${codigo})`); },
  };

  const imports = new Proxy(conhecidas, {
    get(alvo, nome) { return nome in alvo ? alvo[nome] : () => ENOSYS; },
    has() { return true; },
  });

  return {
    imports: { wasi_snapshot_preview1: imports },
    ligar(instancia) {
      memoria = instancia.exports.memory;
      if (instancia.exports._initialize) instancia.exports._initialize();
    },
  };
}
