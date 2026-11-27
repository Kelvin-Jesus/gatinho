#!/usr/bin/env bash
# Abre o Gatinho numa tela virtual, digita, clica e tira prints em ./shots.
# Uso (dentro da imagem ci/linux.Dockerfile): ci/linux-smoke.sh <binário> <pasta-de-saída>
set -u
BIN=$1; OUT=$2; mkdir -p "$OUT"
export DISPLAY=:99 HOME=/tmp/home XDG_SESSION_TYPE=x11
mkdir -p $HOME
Xvfb :99 -screen 0 900x600x24 >/dev/null 2>&1 &
sleep 1
# Fundo cinza-azulado para enxergar a transparência.
convert -size 900x600 xc:'#5d7590' /tmp/bg.png && display -window root /tmp/bg.png >/dev/null 2>&1 &
sleep 1
# Gerenciador de janelas de verdade (respeita _NET_WM_STATE, decoração, foco).
if [ "${WM:-openbox}" = openbox ]; then openbox >/dev/null 2>&1 & sleep 1; fi
shot() { import -window root "$OUT/$1.png"; echo "print: $1"; }

"$BIN" > "$OUT/log.txt" 2>&1 &
PID=$!
sleep 1.5
WIN=$(xdotool search --name '^Gatinho$' | head -1)
echo "foco antes de digitar: $(xdotool getwindowfocus 2>/dev/null)"
echo "janela: $WIN $(xdotool getwindowgeometry $WIN | tr '\n' ' ')"
shot 1-parado

# Digitação: os eventos do XTEST chegam pelo XInput2 como teclado de verdade.
xdotool key --delay 60 a s d f j k l
shot 2-digitando

# Mouse se mexendo longe do gato: os olhos seguem.
xdotool mousemove 100 100; sleep 0.6
shot 3-olhando-mouse

# Menu (botão direito sobre o corpo).
eval $(xdotool getwindowgeometry --shell $WIN)
xdotool mousemove $((X + 165)) $((Y + 200)) click 3; sleep 0.4
xdotool mousemove $((X + 165)) $((Y + 100)); sleep 0.3
shot 4-menu
xdotool click 1; sleep 0.3   # clica na linha sob o mouse (pelagem/tamanho)
shot 5-depois-do-clique

# Arrastar pela barriga.
xdotool key Escape; sleep 0.2
eval $(xdotool getwindowgeometry --shell $WIN)
# Barriga do gato = ponto (155, 205) do desenho de 330 x 300.
BX=$((X + 155 * WIDTH / 330)); BY=$((Y + 205 * HEIGHT / 300))
xdotool mousemove $BX $BY mousedown 1 sleep 0.1 mousemove $((BX - 150)) $((BY - 60)) sleep 0.1 mousemove $((BX - 300)) $((BY - 120)) sleep 0.2 mouseup 1
sleep 0.4
echo "depois de arrastar: $(xdotool getwindowgeometry $WIN | tr '\n' ' ')"
shot 6-arrastado

# Com compositor: janela ARGB de verdade.
xcompmgr -c >/dev/null 2>&1 &
sleep 3
xdotool key --delay 80 h e l l o
shot 7-com-compositor

# Trava (Ctrl+Alt+L) e confere que o processo segue vivo.
xdotool key ctrl+alt+l; sleep 0.3
kill -0 $PID && echo "processo vivo" || { echo "o processo morreu"; cat "$OUT/log.txt"; exit 1; }
kill $PID; wait $PID 2>/dev/null
echo "--- log do app"; cat "$OUT/log.txt"
cat "$HOME/.config/gatinho/settings.json"; echo
# Falha se a janela não abriu ou o processo morreu.
[ -n "$WIN" ] || { echo "janela não encontrada"; exit 1; }
