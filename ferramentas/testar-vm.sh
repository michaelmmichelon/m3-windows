#!/usr/bin/env bash
#
# Testa o M3 Windows numa VM QEMU dentro do WSL (UEFI + TPM 2.0 + KVM).
# O pendrive do M3 vira um disco USB virtual com o autounattend.xml e a pasta m3.
#
#   1) Gere o pendrive numa pasta:   powershell -File gerar-pendrive.ps1 -Destino saida\pendrive
#   2) wsl -d archlinux -u root -- bash /mnt/c/PROJETOS/m3-windows/ferramentas/testar-vm.sh "/mnt/d/.../Win11_25H2_BrazilianPortuguese_x64.iso"
#      ... testar-vm.sh "<ISO do Windows>" /mnt/c/PROJETOS/m3-windows/saida/m3-windows-vm.iso    # como no Proxmox (2º CD)
#      wsl -d archlinux -u root -- bash /mnt/c/PROJETOS/m3-windows/ferramentas/testar-vm.sh disco   # já instalado
#      wsl -d archlinux -u root -- bash /mnt/c/PROJETOS/m3-windows/ferramentas/testar-vm.sh zerar   # apaga a VM
#
# No início aparece "Press any key to boot from CD or DVD": aperte uma tecla na janela.
#
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM=/var/tmp/m3win-vm
OVMF=/usr/share/edk2/x64
PENDRIVE_DIR="$RAIZ/saida/pendrive"

[[ $EUID -eq 0 ]] || { echo "Rode como root"; exit 1; }
[[ -e /dev/kvm ]] || { echo "Sem /dev/kvm."; exit 1; }

if [[ ${1:-} == zerar ]]; then pkill -f "swtpm.*$VM" 2>/dev/null || true; rm -rf "$VM"; echo "VM apagada."; exit 0; fi

pacman -S --needed --noconfirm qemu-desktop edk2-ovmf swtpm mtools dosfstools socat >/dev/null

mkdir -p "$VM/tpm"
[[ -f $VM/disco.qcow2 ]] || qemu-img create -f qcow2 "$VM/disco.qcow2" 64G >/dev/null
[[ -f $VM/OVMF_VARS.fd ]] || cp "$OVMF/OVMF_VARS.4m.fd" "$VM/OVMF_VARS.fd"

# TPM 2.0 por software (exigido pelo Windows 11)
pkill -f "swtpm.*$VM" 2>/dev/null || true
swtpm socket --tpm2 --tpmstate dir="$VM/tpm" --ctrl type=unixio,path="$VM/tpm/sock" --daemon
sleep 1

MIDIA=()
if [[ ${1:-} != disco ]]; then
    ISO=${1:?Informe o caminho da ISO do Windows 11}
    [[ -f $ISO ]] || { echo "ISO não encontrada: $ISO"; exit 1; }
    MIDIA=(-drive "file=$ISO,media=cdrom,readonly=on,if=none,id=cd" -device ide-cd,drive=cd,bus=ide.1,bootindex=0)
    if [[ ${2:-} == *.iso ]]; then
        # Modo Proxmox: a ISO do M3 (gerar-pendrive.ps1 -Destino x.iso) entra como 2º CD
        [[ -f $2 ]] || { echo "ISO do M3 não encontrada: $2"; exit 1; }
        MIDIA+=(-drive "file=$2,media=cdrom,readonly=on,if=none,id=cdm3" -device ide-cd,drive=cdm3,bus=ide.2)
    else
        [[ -f $PENDRIVE_DIR/autounattend.xml ]] || { echo "Gere o pendrive antes em $PENDRIVE_DIR (gerar-pendrive.ps1)."; exit 1; }
        # Pendrive virtual FAT32 com o conteúdo gerado
        rm -f "$VM/pendrive.img"
        truncate -s 64M "$VM/pendrive.img"
        mkfs.fat -F 32 -n M3WIN "$VM/pendrive.img" >/dev/null
        mcopy -s -i "$VM/pendrive.img" "$PENDRIVE_DIR"/* ::/
        MIDIA+=(-drive "file=$VM/pendrive.img,format=raw,if=none,id=pen" -device usb-storage,drive=pen,removable=on)
    fi
fi

if [[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
    TELA=(-display gtk,zoom-to-fit=on)
else
    TELA=(-display none -vnc 127.0.0.1:1)
    echo "WSLg indisponível: tela em VNC localhost:5901."
fi

rm -f "$VM/monitor.sock"
exec qemu-system-x86_64 \
    -name "M3 Windows" \
    -enable-kvm -machine q35,smm=on \
    -cpu host,hv_relaxed,hv_vapic,hv_spinlocks=0x1fff,hv_time \
    -smp 4 -m 6G \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF/OVMF_CODE.secboot.4m.fd" \
    -drive if=pflash,format=raw,file="$VM/OVMF_VARS.fd" \
    -chardev socket,id=chrtpm,path="$VM/tpm/sock" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
    -drive file="$VM/disco.qcow2",if=none,id=hd,format=qcow2,discard=unmap -device ide-hd,drive=hd,bus=ide.0,bootindex=1 \
    -device qemu-xhci -device usb-tablet \
    "${MIDIA[@]}" \
    -nic user,model=e1000e \
    -vga std "${TELA[@]}" \
    -monitor unix:"$VM/monitor.sock",server,nowait
