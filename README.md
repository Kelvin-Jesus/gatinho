# Gatinho

Gato de mesa para macOS, Linux e Windows, todo em Swift, com animações no estilo do LittleOne:

- **Digita junto:** cada tecla é apertada pela pata do lado certo, a tecla acende e um "keycap" sobe com a letra.
- **Segura o mouse:** a pata direita vai para o mouse quando você o usa; os botões acendem e a rodinha gira com o scroll.
- **Olhos seguem o ponteiro:** as pupilas ficam redondas quando o ponteiro chega perto.
- **Sonha acordado** depois de 15 s parado e **dorme** depois de 40 s (pálpebras pesando, rabo no chão, Zs e bolha de ronco). Ao voltar, balança a cabeça.
- **Carinho:** clique e segure na cabeça; ele fecha os olhos, abaixa as orelhas, ronrona e solta corações.

## Como está organizado

- `Sources/GatinhoCore`: o gato inteiro (simulação, desenho, pelagens, menu, preferências) e um rasterizador por software. Só usa Foundation.
- `Sources/Gatinho/Mac`: janela SwiftUI, menu na barra de menus, `NSEvent` para teclado e mouse.
- `Sources/Gatinho/Linux`: janela X11 (transparente com compositor, recortada por XShape sem ele), XInput2 para teclado e mouse globais, `/dev/input` no Wayland, menu desenhado dentro da janela.
- `Sources/Gatinho/Windows`: janela em camadas (`UpdateLayeredWindow`), ganchos `WH_KEYBOARD_LL`/`WH_MOUSE_LL`, menu nativo e ícone na bandeja.

## Rodar no Mac

```bash
./build.sh && open Gatinho.app
```

Só precisa das Command Line Tools (sem Xcode). Na primeira vez, o macOS pede **Acessibilidade** para o gato ver o teclado. Ao recompilar, a assinatura muda e pode ser preciso remover e adicionar o Gatinho de novo em Ajustes > Privacidade e Segurança > Acessibilidade.

## Rodar no Linux

Precisa do Swift e dos cabeçalhos do X11 para compilar:

```bash
sudo apt install libx11-dev libxext-dev libxi-dev
swift build -c release --static-swift-stdlib
.build/release/Gatinho
```

O binário com `--static-swift-stdlib` roda em outra máquina sem Swift instalado. No Wayland (GNOME, KDE), o gato roda pelo XWayland e lê o teclado em `/dev/input`, que exige estar no grupo `input`:

```bash
sudo usermod -aG input $USER
```

Depois disso, saia e entre de novo na sessão. Sem o grupo, o gato só vê o que acontece sobre janelas X11. Preferências ficam em `~/.config/gatinho/settings.json`. Para forçar a escala da tela: `GATINHO_SCALE=2`.

## Rodar no Windows

Com o Swift para Windows instalado (`winget install Swift.Toolchain`):

```powershell
swift build -c release
.build\release\Gatinho.exe
```

Para levar a outra máquina, copie junto as DLLs do Swift (o workflow `build` monta esse pacote). Preferências ficam em `%APPDATA%\Gatinho\settings.json`.

## Usar

- Arraste o corpo para mover. Clique e segure a cabeça para carinho.
- Clique direito no gato: pelagem (9), tamanho, opacidade, mostrar teclas, travar. No Mac também pelo ícone na barra de menus; no Windows, pelo ícone na bandeja.
- No Linux o menu abre dentro da janela do gato: clique esquerdo avança a opção, direito volta, `Esc` fecha.
- `⌃⌥L` no Mac, `Ctrl+Alt+L` no Linux e no Windows: trava e destrava. Travado, os cliques atravessam o gato.

## Privacidade

Teclas ficam em memória só enquanto estão apertadas. Nada é gravado nem enviado. Campos de senha bloqueiam o monitor do sistema.

## Conferir sem abrir janela

```bash
Gatinho --snapshot estados.png   # grade com 9 estados, desenhada pelo rasterizador por software
Gatinho --check-smooth           # falha se o rabo ou a respiração pularem entre quadros
Gatinho --benchmark              # tempo de um quadro em software
```

`ci/linux-smoke.sh` abre o gato numa tela virtual (Xvfb), digita, abre o menu, arrasta e tira prints. O workflow `.github/workflows/build.yml` compila e testa os 3 sistemas.

## Conferir o desenho

```bash
swift build && "$(swift build --show-bin-path)/Gatinho" --snapshot estados.png
```
