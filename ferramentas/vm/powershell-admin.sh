#!/usr/bin/env bash
# Abre um PowerShell como administrador na VM de teste (Win+R, Ctrl+Shift+Enter, confirma o UAC)
D="$(dirname "${BASH_SOURCE[0]}")/digitar.sh"
bash "$D" --tecla meta_l-r; sleep 2
bash "$D" "powershell -noexit"
bash "$D" --tecla ctrl-shift-ret; sleep 4
bash "$D" --tecla left; sleep 1
bash "$D" --tecla ret; sleep 6
