# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Site: HTML/CSS puro em `site/`, publicado no GitHub Pages por GitHub Actions. O app em si é Swift (macOS, Linux, Windows).

## Users

Qualquer pessoa que cai no link do projeto: quer ver o gato em ação, entender em segundos o que ele faz e baixar pro próprio computador. Devs curiosos são público secundário; a parte técnica fica mais abaixo.

## Product Purpose

Gatinho é um gato de mesa que mora no canto da tela e reage ao que você faz: digita junto, pata por pata; pega o mouse quando você pega o seu; cochila e dorme no teclado quando você some; acorda atordoado quando você volta. Dá pra fazer carinho segurando o clique na cabeça. Sucesso é a pessoa instalar e deixar ele lá.

## Positioning

Roda nativo no computador (não numa aba do navegador), nos três sistemas, com o mesmo gato desenhado por um rasterizador próprio em Swift. Inspirado no gatinho do LittleOne (xiaozhilittleone.com), crédito explícito.

## Operating Context

Fica sempre visível no canto da tela enquanto a pessoa trabalha. Menu por clique direito (Mac também na barra de menus, Windows na bandeja). Atalho de travar: ⌃⌥L no Mac, Ctrl+Alt+L nos outros.

## Capabilities and Constraints

- Nove pelagens; tamanho, transparência, letrinhas das teclas, travar no lugar.
- Sonha acordado com 15 s sem uso e dorme com 40 s.
- Privacidade: lê as teclas só enquanto estão apertadas, nada vai pra disco nem sai da máquina.
- Mac: pede permissão de Acessibilidade. Linux Wayland: usuário no grupo `input`. Windows: ícone na bandeja.
- Binários vêm do CI (GitHub Releases). O app do Mac do CI não é notarizado pela Apple.

## Brand Commitments

- Nome: Gatinho. Texto em português do Brasil, primeira pessoa, informal ("pra", "dá pra"), sem cara de IA.
- O gato desenhado pelo próprio app é o único personagem; pelagens reais do app.

## Evidence on Hand

- `docs/digitando.gif`, `docs/carinho.gif`, `docs/soneca.gif`: cenas gravadas pelo próprio app (`--record`).
- `docs/pelagens.png`: grade com as 9 pelagens.
- `Gatinho --record <cena>` gera quadros novos a qualquer momento.
- Não há depoimentos, número de downloads nem imprensa. Não inventar.

## Product Principles

1. O gato aparece antes de qualquer explicação.
2. Instalar tem que parecer fácil, e o que é chato (permissões) é dito com franqueza.
3. Privacidade do teclado é explicada sem letra miúda.
4. Tom de projeto pessoal feito com carinho, não de produto vendendo.
