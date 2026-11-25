#!/usr/bin/env bash
# Captura a tela da VM de teste: tela.sh <destino.png>
SOCK=/var/tmp/m3win-vm/monitor.sock
rm -f /var/tmp/m3win-vm/tela.png
{ echo 'screendump /var/tmp/m3win-vm/tela.png -f png'; sleep 2; } | socat - UNIX-CONNECT:$SOCK >/dev/null
cp /var/tmp/m3win-vm/tela.png "${1:?destino}" && echo "ok $1"
