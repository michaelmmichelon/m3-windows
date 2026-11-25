#Requires -Version 5.1
<#
    M3 Windows - prepara o pendrive de instalação

    1. Grave a ISO OFICIAL do Windows 11 (pt-BR) no pendrive com o Rufus ou a
       Ferramenta de Criação de Mídia da Microsoft.
       No Rufus, DESMARQUE todas as opções da janela "Personalização do Windows".
    2. Rode este script e informe a letra do pendrive:

        powershell -ExecutionPolicy Bypass -File .\gerar-pendrive.ps1

    Ele grava no pendrive o autounattend.xml e a pasta \m3 (otimização + papel de parede).
    Sem pendrive, informe uma pasta e copie o conteúdo dela para a raiz do pendrive depois.

    Máquina virtual (Proxmox, Hyper-V, VirtualBox): informe um arquivo .iso como destino.
    Sai uma ISO pequena para colocar como SEGUNDO CD da VM, junto com a ISO do Windows:

        powershell -ExecutionPolicy Bypass -File .\gerar-pendrive.ps1 -Destino .\saida\m3-windows-vm.iso
#>
param(
    [string]$Destino,
    [string]$Usuario,
    [string]$NomePC,
    [Nullable[bool]]$RemoverOneDrive,
    [Nullable[bool]]$DesligarIntegridadeMemoria,
    [SecureString]$Senha
)
$ErrorActionPreference = 'Stop'
$Raiz = $PSScriptRoot

function Perguntar-SimNao([string]$pergunta, [bool]$padrao) {
    $sufixo = if ($padrao) { '[S/n]' } else { '[s/N]' }
    $r = Read-Host "$pergunta $sufixo"
    if ([string]::IsNullOrWhiteSpace($r)) { return $padrao }
    return ($r -match '^[sS]')
}
function Base64Unicode([string]$texto) {
    [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($texto))
}
function Gravar([string]$caminho, [string]$conteudo, [bool]$bom) {
    [IO.File]::WriteAllText($caminho, $conteudo, (New-Object Text.UTF8Encoding($bom)))
}
function Criar-Iso([string]$pasta, [string]$arquivo, [string]$rotulo) {
    # Usa o IMAPI2, que já vem no Windows (nenhum programa extra)
    if (-not ('M3.GravadorIso' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices.ComTypes;
namespace M3 {
    public static class GravadorIso {
        public static void Gravar(object fluxo, string arquivo) {
            IStream s = (IStream)fluxo;
            byte[] buf = new byte[1024 * 1024];
            IntPtr lidoPtr = System.Runtime.InteropServices.Marshal.AllocHGlobal(4);
            try {
                using (FileStream fs = File.Create(arquivo)) {
                    while (true) {
                        s.Read(buf, buf.Length, lidoPtr);
                        int lido = System.Runtime.InteropServices.Marshal.ReadInt32(lidoPtr);
                        if (lido <= 0) break;
                        fs.Write(buf, 0, lido);
                    }
                }
            } finally { System.Runtime.InteropServices.Marshal.FreeHGlobal(lidoPtr); }
        }
    }
}
'@
    }
    $img = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $img.FileSystemsToCreate = 3          # ISO 9660 + Joliet
    $img.VolumeName = $rotulo
    $img.Root.AddTree($pasta, $false)     # conteúdo da pasta na raiz da ISO
    $resultado = $img.CreateResultImage()
    $fluxo = $resultado.ImageStream
    [M3.GravadorIso]::Gravar($fluxo, $arquivo)
    # Solta os arquivos que o IMAPI deixa abertos, para a pasta temporária poder ser apagada
    foreach ($o in $fluxo, $resultado, $img) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($o) }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
}

Write-Host "`n  M3 WINDOWS - preparar pendrive de instalação`n" -ForegroundColor Cyan

# ------------------------------------------------------------------ destino
if (-not $Destino) {
    Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } |
        ForEach-Object { Write-Host ("    {0}:  {1}  ({2:N1} GB)" -f $_.DriveLetter, $_.FileSystemLabel, ($_.Size / 1GB)) }
    Write-Host "`n    Para máquina virtual (Proxmox etc.), digite um nome terminado em .iso"
    $Destino = Read-Host "Letra do pendrive (ex.: E), uma pasta ou um arquivo .iso [.\saida\pendrive]"
    if ([string]::IsNullOrWhiteSpace($Destino)) { $Destino = Join-Path $Raiz 'saida\pendrive' }
}
$ArquivoIso = $null
if ($Destino -match '\.iso$') {
    # Monta os arquivos numa pasta temporária e empacota no fim
    $ArquivoIso = [IO.Path]::GetFullPath($Destino)
    New-Item -ItemType Directory -Force -Path (Split-Path $ArquivoIso) | Out-Null
    $Destino = Join-Path $env:TEMP ("m3win-iso-" + [guid]::NewGuid().ToString('N'))
}
if ($Destino -match '^[A-Za-z]:?$') { $Destino = $Destino.Substring(0, 1).ToUpper() + ':\' }
$EhPendrive = $Destino -match '^[A-Z]:\\$'
if ($EhPendrive) {
    $temInstalador = (Test-Path (Join-Path $Destino 'sources\install.wim')) -or
                     (Test-Path (Join-Path $Destino 'sources\install.esd')) -or
                     (Test-Path (Join-Path $Destino 'sources\install.swm'))
    if (-not $temInstalador) {
        throw "O pendrive $Destino não tem o instalador do Windows (sources\install.wim). Grave a ISO nele primeiro (Rufus ou Ferramenta de Criação de Mídia)."
    }
} else {
    New-Item -ItemType Directory -Force -Path $Destino | Out-Null
}

# ------------------------------------------------------------------ conta e opções
while (-not ($Usuario -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,19}$')) {
    if ($Usuario) { Write-Host '    Use só letras, números, ponto, - ou _ (até 20 caracteres).' -ForegroundColor Yellow }
    $Usuario = Read-Host 'Nome de usuário'
}
if (-not $Senha) {
    while ($true) {
        $s1 = Read-Host 'Senha' -AsSecureString
        $s2 = Read-Host 'Repita a senha' -AsSecureString
        $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
        $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
        if ($p1 -and $p1 -ceq $p2) { $Senha = $s1; break }
        Write-Host '    As senhas não conferem (ou estão vazias).' -ForegroundColor Yellow
    }
}
$SenhaTexto = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Senha))
if (-not $SenhaTexto) { throw 'A senha não pode ser vazia.' }

if (-not $NomePC) { $NomePC = Read-Host 'Nome do computador [M3-PC]' }
if ([string]::IsNullOrWhiteSpace($NomePC)) { $NomePC = 'M3-PC' }
if ($NomePC -notmatch '^[A-Za-z0-9-]{1,15}$' -or $NomePC -match '^\d+$') {
    throw 'Nome do computador inválido: use letras, números e -, até 15 caracteres.'
}

if ($null -eq $RemoverOneDrive) { $RemoverOneDrive = Perguntar-SimNao 'Remover o OneDrive?' $false }
if ($null -eq $DesligarIntegridadeMemoria) {
    Write-Host '    Integridade de Memória (VBS): desligar dá alguns % de FPS em certos jogos,'
    Write-Host '    mas tira uma camada de proteção contra drivers maliciosos.'
    $DesligarIntegridadeMemoria = Perguntar-SimNao 'Desligar a Integridade de Memória?' $false
}

# ------------------------------------------------------------------ gravar arquivos
$PastaM3 = Join-Path $Destino 'm3'
New-Item -ItemType Directory -Force -Path $PastaM3 | Out-Null

$xml = Get-Content (Join-Path $Raiz 'modelo\autounattend.xml') -Raw -Encoding UTF8
$xml = $xml.Replace('{{USUARIO}}', $Usuario).Replace('{{NOME_PC}}', $NomePC.ToUpper())
$xml = $xml.Replace('{{SENHA_AUTOLOGON}}', (Base64Unicode ($SenhaTexto + 'Password')))
Gravar (Join-Path $Destino 'autounattend.xml') $xml $false

$cu = Get-Content (Join-Path $Raiz 'modelo\criar-usuario.ps1') -Raw -Encoding UTF8
$cu = $cu.Replace('{{USUARIO}}', $Usuario).Replace('{{SENHA_B64}}', (Base64Unicode $SenhaTexto))
Gravar (Join-Path $PastaM3 'criar-usuario.ps1') $cu $true
$SenhaTexto = $null

Copy-Item (Join-Path $Raiz 'm3\*') $PastaM3 -Force
$config = [ordered]@{
    RemoverOneDrive            = [bool]$RemoverOneDrive
    DesligarIntegridadeMemoria = [bool]$DesligarIntegridadeMemoria
} | ConvertTo-Json
Gravar (Join-Path $PastaM3 'config.json') $config $false

if ($ArquivoIso) {
    try {
        Criar-Iso $Destino $ArquivoIso 'M3WIN'
    } catch {
        throw "Não deu para gravar $ArquivoIso (ele está aberto numa VM ou em outro programa?). $($_.Exception.Message)"
    } finally {
        # A pasta temporária tem a senha: apaga sempre, mesmo com erro (com novas tentativas
        # se algo ainda segurar um arquivo)
        for ($t = 1; $t -le 5 -and (Test-Path $Destino); $t++) {
            Remove-Item $Destino -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $Destino) { Start-Sleep -Seconds 1; [GC]::Collect() }
        }
        if (Test-Path $Destino) { Write-Host "    ! Apague à mão a pasta temporária: $Destino" -ForegroundColor Yellow }
    }
    Write-Host "`n==> Pronto!" -ForegroundColor Cyan
    Write-Host "    ISO do M3: $ArquivoIso ($([math]::Round((Get-Item $ArquivoIso).Length / 1MB, 1)) MB)"
    Write-Host '    Na VM: ISO do Windows no 1º CD e esta ISO num 2º CD. Inicie pela ISO do Windows;'
    Write-Host '    você só escolhe a edição e o disco; o resto é automático.'
    Write-Host '    Atenção: a senha fica nesta ISO (codificada, não criptografada). Apague-a depois.' -ForegroundColor Yellow
    return
}

Write-Host "`n==> Pronto!" -ForegroundColor Cyan
if ($EhPendrive) {
    Write-Host "    Pendrive $Destino preparado. Inicie o PC por ele (UEFI) e instale normalmente:"
} else {
    Write-Host "    Arquivos em $Destino. Copie TODO o conteúdo para a raiz do pendrive do Windows."
    Write-Host '    Depois, inicie o PC pelo pendrive e instale normalmente:'
}
Write-Host '    você só escolhe a edição e o disco; o resto é automático.'
Write-Host '    Atenção: a senha fica no pendrive (codificada, não criptografada). Apague o'
Write-Host '    autounattend.xml e a pasta m3 do pendrive depois de instalar.' -ForegroundColor Yellow
