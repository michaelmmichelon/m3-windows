#!/usr/bin/env bash
# Digita na VM de teste pelo monitor do QEMU (teclado da VM em ABNT2).
#   digitar.sh "texto" [enter]      |      digitar.sh --tecla ctrl-alt-del
# Aspas e ! não funcionam (teclas mortas no ABNT2): monte os comandos sem eles.
SOCK=/var/tmp/m3win-vm/monitor.sock
cmds=()
if [[ $1 == --tecla ]]; then
    cmds+=("sendkey $2")
else
    txt=$1
    for ((i = 0; i < ${#txt}; i++)); do
        c=${txt:i:1}
        case "$c" in
            [a-z0-9]) k=$c ;;
            [A-Z]) k="shift-${c,,}" ;;
            ' ') k=spc ;;
            '-') k=minus ;;
            '.') k=dot ;;
            ',') k=comma ;;
            '/') k=ro ;;
            '\') k=less ;;
            '|') k=shift-less ;;
            ';') k=slash ;;
            ':') k=shift-slash ;;
            '#') k=shift-3 ;;
            '$') k=shift-4 ;;
            '*') k=kp_multiply ;;
            '(') k=shift-9 ;;
            ')') k=shift-0 ;;
            '_') k=shift-minus ;;
            '=') k=equal ;;
            '>') k=shift-dot ;;
            '<') k=shift-comma ;;
            '+') k=shift-equal ;;
            '[') k=bracket_right ;;      # ABNT2: [ fica onde o US tem ]
            '{') k=shift-bracket_right ;;
            ']') k=backslash ;;          # ABNT2: ] fica onde o US tem \
            '}') k=shift-backslash ;;
            *) echo "caractere sem mapa: $c"; exit 1 ;;
        esac
        cmds+=("sendkey $k")
    done
    [[ ${2:-} == enter ]] && cmds+=("sendkey ret")
fi
{ for c in "${cmds[@]}"; do echo "$c"; sleep 0.05; done; sleep 0.5; } | socat - UNIX-CONNECT:$SOCK >/dev/null
