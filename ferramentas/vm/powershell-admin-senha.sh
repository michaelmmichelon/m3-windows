#!/usr/bin/env bash
# Abre um PowerShell como administrador a partir de uma conta comum (o UAC pede a senha
# do administrador de teste): powershell-admin-senha.sh <senha>
D="$(dirname "${BASH_SOURCE[0]}")/digitar.sh"
bash "$D" --tecla meta_l-r; sleep 2
bash "$D" "powershell -noexit"
bash "$D" --tecla ctrl-shift-ret; sleep 5
bash "$D" "${1:?senha}" enter; sleep 7
