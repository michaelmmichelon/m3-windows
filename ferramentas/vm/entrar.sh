#!/usr/bin/env bash
# Entra na VM de teste: entrar.sh <senha>
D="$(dirname "${BASH_SOURCE[0]}")/digitar.sh"
bash "$D" --tecla spc; sleep 3
bash "$D" "${1:?senha}" enter; sleep 25
