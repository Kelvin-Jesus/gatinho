# Gatinho

Gato de mesa para macOS (SwiftUI + AppKit), com animações no estilo do LittleOne:

- **Digita junto:** cada tecla é apertada pela pata do lado certo, a tecla acende e um "keycap" sobe com a letra.
- **Segura o mouse:** a pata direita vai para o mouse quando você o usa; os botões acendem e a rodinha gira com o scroll.
- **Olhos seguem o ponteiro:** as pupilas ficam redondas quando o ponteiro chega perto.
- **Sonha acordado** depois de 15 s parado e **dorme** depois de 40 s (pálpebras pesando, rabo no chão, Zs e bolha de ronco). Ao voltar, balança a cabeça.
- **Carinho:** clique e segure na cabeça; ele fecha os olhos, abaixa as orelhas, ronrona e solta corações.

## Rodar

```bash
./build.sh && open Gatinho.app
```

Só precisa das Command Line Tools (sem Xcode). Na primeira vez, o macOS pede **Acessibilidade** para o gato ver o teclado. Ao recompilar, a assinatura muda e pode ser preciso remover e adicionar o Gatinho de novo em Ajustes > Privacidade e Segurança > Acessibilidade.

## Usar

- Arraste o corpo para mover. Clique e segure a cabeça para carinho.
- Clique direito no gato (ou o ícone de gato na barra de menus): pelagem (9), tamanho, opacidade, mostrar teclas, travar.
- `⌃⌥L` trava/destrava: travado, os cliques atravessam o gato.

## Privacidade

Teclas ficam em memória só enquanto estão apertadas. Nada é gravado nem enviado. Campos de senha bloqueiam o monitor do sistema.

## Conferir o desenho

```bash
swift build && "$(swift build --show-bin-path)/Gatinho" --snapshot estados.png
```
