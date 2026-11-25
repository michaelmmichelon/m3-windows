#!/usr/bin/env bash
# Manda um comando ao monitor do QEMU da VM de teste: monitor.sh "info status" | "system_reset"
{ echo "$*"; sleep 1; } | socat - UNIX-CONNECT:/var/tmp/m3win-vm/monitor.sock | tr -d '\r' | grep -a -v '^(qemu)\|QEMU' | tail -3
