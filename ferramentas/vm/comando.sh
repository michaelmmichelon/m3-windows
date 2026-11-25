#!/usr/bin/env bash
# Limpa a janela do PowerShell aberta na VM e digita um comando: comando.sh "comando"
D="$(dirname "${BASH_SOURCE[0]}")/digitar.sh"
bash "$D" "cls" enter; sleep 1
bash "$D" "$1" enter
