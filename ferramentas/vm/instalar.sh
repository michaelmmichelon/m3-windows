#!/usr/bin/env bash
# Conduz as telas que o M3 deixa para você na VM de teste: boot pelo CD, sem chave,
# edição Home e disco 0. Rode logo depois de iniciar o testar-vm.sh.
D="$(dirname "${BASH_SOURCE[0]}")/digitar.sh"
sleep 4
for i in 1 2 3 4 5 6 7 8; do bash "$D" --tecla ret; sleep 1; done   # "Press any key to boot from CD"
sleep 45
bash "$D" --tecla tab; sleep 1; bash "$D" --tecla ret; sleep 6    # "Não tenho uma chave de produto"
bash "$D" --tecla ret; sleep 25                                   # Windows 11 Home
bash "$D" --tecla alt-a; sleep 10                                 # disco 0 -> Avançar
echo "instalação iniciada"
