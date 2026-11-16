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

Write-Host "`n  M3 WINDOWS - preparar pendrive de instalação`n" -ForegroundColor Cyan

# ------------------------------------------------------------------ destino
if (-not $Destino) {
    Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } |
        ForEach-Object { Write-Host ("    {0}:  {1}  ({2:N1} GB)" -f $_.DriveLetter, $_.FileSystemLabel, ($_.Size / 1GB)) }
    $Destino = Read-Host "`nLetra do pendrive (ex.: E) ou uma pasta [.\saida\pendrive]"
    if ([string]::IsNullOrWhiteSpace($Destino)) { $Destino = Join-Path $Raiz 'saida\pendrive' }
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
