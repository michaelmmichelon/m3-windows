#Requires -Version 5.1
<#
    M3 Windows - instala os apps escolhidos e cuida do driver de vídeo

    Na instalação pelo pendrive roda sozinho no login depois do primeiro reinício (tarefa
    "\M3\M3 Windows - instalar apps"), com os apps escolhidos no gerar-pendrive.ps1.
    Também pode ser usado à mão, num Windows já instalado (pergunta quais apps):

        powershell -ExecutionPolicy Bypass -File .\m3-apps.ps1

    Usa o winget (Gerenciador de Pacotes do Windows): baixa sempre a versão oficial e atual.
    Driver de vídeo: Intel pelo winget; NVIDIA e AMD não estão no winget, então fica um
    atalho na área de trabalho para a página oficial (o Windows Update já instala um driver
    básico enquanto isso).
#>
param([switch]$Tarefa)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Base = Join-Path $env:ProgramData 'M3Windows'
$NomeTarefa = 'M3 Windows - instalar apps'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$Host.UI.RawUI.WindowTitle = 'M3 Windows - instalando apps'
New-Item -ItemType Directory -Force -Path $Base | Out-Null
Start-Transcript -Path (Join-Path $Base 'apps.log') -Append | Out-Null

function Etapa([string]$t) { Write-Host "`n==> $t" -ForegroundColor Cyan }
function Info([string]$t)  { Write-Host "    $t" }
function Aviso([string]$t) { Write-Host "    ! $t" -ForegroundColor Yellow }
function Sair([int]$codigo, [bool]$apagarTarefa) {
    if ($apagarTarefa) {
        Unregister-ScheduledTask -TaskPath '\M3\' -TaskName $NomeTarefa -Confirm:$false -ErrorAction SilentlyContinue
    }
    Stop-Transcript | Out-Null
    if ($Tarefa) {
        Write-Host "`n    Esta janela fecha em 30 segundos." -ForegroundColor DarkGray
        Start-Sleep -Seconds 30
    } else {
        Read-Host "`n    Enter para fechar" | Out-Null
    }
    exit $codigo
}

Write-Host "`n  M3 WINDOWS - apps e driver de vídeo`n" -ForegroundColor Cyan

# ------------------------------------------------------------------ o que instalar
$arqCatalogo = @((Join-Path $PSScriptRoot 'apps-catalogo.txt'), (Join-Path $Base 'apps-catalogo.txt')) |
    Where-Object { Test-Path $_ } | Select-Object -First 1
$Catalogo = @(Get-Content $arqCatalogo -Encoding UTF8 -ErrorAction SilentlyContinue |
    Where-Object { $_ -match '\|' -and $_ -notmatch '^\s*#' } |
    ForEach-Object { $p = $_ -split '\|'; [pscustomobject]@{ Id = $p[0].Trim(); Nome = $p[1].Trim(); Padrao = $p[2].Trim() -eq 's' } })

$Apps = @(); $DriverVideo = $true
$arqConfig = @((Join-Path $PSScriptRoot 'config.json'), (Join-Path $Base 'config.json')) |
    Where-Object { Test-Path $_ } | Select-Object -First 1
$cfg = $null
if ($arqConfig) { try { $cfg = Get-Content $arqConfig -Raw -Encoding UTF8 | ConvertFrom-Json } catch {} }
if ($cfg -and $null -ne $cfg.Apps) {
    $Apps = @($cfg.Apps | Where-Object { $_ })
    if ($null -ne $cfg.DriverVideo) { $DriverVideo = [bool]$cfg.DriverVideo }
} elseif (-not $Tarefa) {
    for ($i = 0; $i -lt $Catalogo.Count; $i++) {
        Write-Host ('    {0}) {1}{2}' -f ($i + 1), $Catalogo[$i].Nome, $(if ($Catalogo[$i].Padrao) { '  *' } else { '' }))
    }
    $r = Read-Host "`n    Quais instalar? Números separados por vírgula (Enter = os marcados com *, 0 = nenhum)"
    if ([string]::IsNullOrWhiteSpace($r)) { $Apps = @($Catalogo | Where-Object Padrao | ForEach-Object Id) }
    elseif ($r.Trim() -ne '0') {
        $Apps = @($r -split '[,; ]+' | Where-Object { $_ -match '^\d+$' } |
            ForEach-Object { $Catalogo[[int]$_ - 1].Id } | Where-Object { $_ })
    }
}

# ------------------------------------------------------------------ driver de vídeo
$Gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object PNPDeviceID)
$TemNvidia = [bool]($Gpus -match 'VEN_10DE')
$TemAmd = [bool]($Gpus -match 'VEN_1002')
$TemIntel = [bool]($Gpus -match 'VEN_8086')
if ($DriverVideo -and $TemIntel) { $Apps += 'Intel.IntelDriverAndSupportAssistant' }

if ($DriverVideo -and ($TemNvidia -or $TemAmd)) {
    Etapa 'Driver de vídeo'
    $desk = [Environment]::GetFolderPath('CommonDesktopDirectory')
    if ($TemNvidia) {
        "[InternetShortcut]`r`nURL=https://www.nvidia.com/pt-br/software/nvidia-app/`r`n" |
            Set-Content (Join-Path $desk 'Driver de vídeo NVIDIA.url') -Encoding ASCII
        Info 'Placa NVIDIA: atalho "Driver de vídeo NVIDIA" na área de trabalho (NVIDIA App, site oficial).'
    }
    if ($TemAmd) {
        "[InternetShortcut]`r`nURL=https://www.amd.com/pt/support/download/drivers.html`r`n" |
            Set-Content (Join-Path $desk 'Driver de vídeo AMD.url') -Encoding ASCII
        Info 'Placa AMD: atalho "Driver de vídeo AMD" na área de trabalho (AMD Software Adrenalin, site oficial).'
    }
    Info 'Até lá o Windows Update instala um driver básico; para jogos, instale o oficial.'
}

if ($Apps.Count -eq 0) {
    Info 'Nenhum app para instalar.'
    Sair 0 $true
}

# ------------------------------------------------------------------ internet e winget
Etapa 'Esperando a internet'
$online = $false
for ($i = 0; $i -lt 40; $i++) {     # até 10 min
    try {
        $null = Invoke-WebRequest -Uri 'https://cdn.winget.microsoft.com/cache/source.msix' -Method Head -UseBasicParsing -TimeoutSec 10
        $online = $true; break
    } catch {
        if ($i % 4 -eq 0) { Aviso 'Sem internet. Conecte o cabo ou o Wi-Fi (ícone de rede na barra de tarefas).' }
        Start-Sleep -Seconds 15
    }
}
if (-not $online) {
    Aviso 'Continuou sem internet. Os apps serão instalados no próximo login.'
    Sair 1 $false
}
Info 'Conectado.'

$winget = $null
for ($i = 0; $i -lt 12 -and -not $winget; $i++) {     # o winget pode demorar a aparecer numa conta nova
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        if ($i -eq 0) { Info 'Preparando o winget...' }
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 15
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    }
}
if (-not $winget) {
    Aviso 'O winget ainda não está disponível. Os apps serão instalados no próximo login.'
    Aviso 'Se continuar assim, atualize o "Instalador de Aplicativo" na Microsoft Store.'
    Sair 1 $false
}

# ------------------------------------------------------------------ instalar
Etapa "Instalando $($Apps.Count) app(s)"
$ok = @(); $falhou = @()
foreach ($id in $Apps) {
    $nome = ($Catalogo | Where-Object Id -eq $id | Select-Object -First 1).Nome
    if (-not $nome) { $nome = $id }
    Write-Host "    $nome..." -NoNewline
    $sucesso = $false
    for ($t = 1; $t -le 2 -and -not $sucesso; $t++) {
        # --source winget: todos os ids do catálogo são da fonte winget; sem isso, uma falha na
        # fonte "msstore" (comum logo depois de instalar o Windows) derruba a instalação inteira
        & winget.exe install --id $id -e --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
        # 0 = instalado; -1978335189 (0x8A15002B) = já instalado e atualizado
        $sucesso = ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189)
        if (-not $sucesso -and $t -eq 1) { Start-Sleep -Seconds 10 }
    }
    if ($sucesso) { Write-Host ' ok' -ForegroundColor Green; $ok += $nome }
    else { Write-Host " falhou (código $LASTEXITCODE)" -ForegroundColor Yellow; $falhou += $nome }
}

Etapa 'Pronto!'
if ($ok) { Info "Instalados: $($ok -join ', ')" }
if ($falhou) {
    Aviso "Não instalados: $($falhou -join ', ')"
    Aviso 'Tente depois rodando C:\ProgramData\M3Windows\m3-apps.ps1, ou instale pela Microsoft Store.'
}
Info "Registro: $Base\apps.log"
Sair 0 $true
