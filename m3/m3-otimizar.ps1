#Requires -Version 5.1
<#
    M3 Windows - otimização do Windows 11 para desempenho
    ------------------------------------------------------
    Roda sozinho no primeiro login (instalação pelo pendrive do M3 Windows) ou à mão
    num Windows já instalado:

        powershell -ExecutionPolicy Bypass -File .\m3-otimizar.ps1

    Pode ser rodado de novo depois de grandes atualizações do Windows (algumas
    configurações e apps voltam). Antes de mudar qualquer coisa, cria um ponto de
    restauração.

    Mantém LIGADOS: Windows Defender, Windows Update, proteções do kernel e o firewall.
#>
param(
    [string]$Config = (Join-Path $PSScriptRoot 'config.json'),
    [switch]$PrimeiraVez   # chamado pela instalação automática: sem perguntas e reinicia no fim
)

$Versao = '0.1.0'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ------------------------------------------------------------------ administrador
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Config `"$Config`""
    Start-Process powershell.exe -ArgumentList $argumentos -Verb RunAs
    exit
}

$Host.UI.RawUI.WindowTitle = "M3 Windows $Versao - otimizando"
$PastaLog = Join-Path $env:ProgramData 'M3Windows'
New-Item -ItemType Directory -Force -Path $PastaLog | Out-Null
Start-Transcript -Path (Join-Path $PastaLog 'otimizar.log') -Append | Out-Null

function Etapa([string]$texto) { Write-Host "`n==> $texto" -ForegroundColor Cyan }
function Info([string]$texto)  { Write-Host "    $texto" }
function Aviso([string]$texto) { Write-Host "    ! $texto" -ForegroundColor Yellow }

function Set-Reg {
    param([string]$Caminho, [string]$Nome, $Valor, [string]$Tipo = 'DWord')
    try {
        if (-not (Test-Path $Caminho)) { New-Item -Path $Caminho -Force | Out-Null }
        New-ItemProperty -Path $Caminho -Name $Nome -Value $Valor -PropertyType $Tipo -Force -ErrorAction Stop | Out-Null
    } catch {
        Aviso "Não deu para gravar $Caminho\$Nome ($($_.Exception.Message))"
    }
}

Write-Host ''
Write-Host '  M3 WINDOWS' -ForegroundColor Cyan
Write-Host "  Otimização para desempenho - versão $Versao"
Write-Host '  Não desligue o computador até terminar.'

# ------------------------------------------------------------------ opções
$Opcoes = [ordered]@{
    RemoverOneDrive            = $false
    DesligarIntegridadeMemoria = $false
}
if (Test-Path $Config) {
    try {
        $lido = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @($Opcoes.Keys)) {
            if ($null -ne $lido.$k) { $Opcoes[$k] = [bool]$lido.$k }
        }
        Info "Opções lidas de $Config"
    } catch { Aviso "config.json inválido; usando o padrão." }
} elseif (-not $PrimeiraVez) {
    $r = Read-Host '    Remover o OneDrive? [s/N]'
    $Opcoes.RemoverOneDrive = $r -match '^[sS]'
    Write-Host '    Integridade de Memória (VBS): desligar dá alguns % de FPS em certos jogos,'
    Write-Host '    mas tira uma camada de proteção contra drivers maliciosos.'
    $r = Read-Host '    Desligar a Integridade de Memória? [s/N]'
    $Opcoes.DesligarIntegridadeMemoria = $r -match '^[sS]'
}

$Notebook = $null -ne (Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)
if ($Notebook) { Info 'Notebook detectado (bateria presente).' }

# ------------------------------------------------------------------ ponto de restauração
if (-not $PrimeiraVez) {
    Etapa 'Criando ponto de restauração'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
        Checkpoint-Computer -Description 'Antes do M3 Windows' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Info 'Ponto de restauração "Antes do M3 Windows" criado.'
    } catch { Aviso "Não deu para criar o ponto de restauração: $($_.Exception.Message)" }
}

# ------------------------------------------------------------------ apps pré-instalados
Etapa 'Removendo apps pré-instalados'
# A lista fica em apps-remover.txt (a mesma usada na instalação, antes do primeiro login)
$ListaApps = Join-Path $PSScriptRoot 'apps-remover.txt'
if (-not (Test-Path $ListaApps)) { Aviso 'apps-remover.txt não encontrado ao lado do script; pulando.' }
$Apps = @(Get-Content $ListaApps -Encoding UTF8 -ErrorAction SilentlyContinue |
    ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ })
$Instalados = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) +
              @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName)
foreach ($app in $Apps) {
    # Primeiro tira da imagem (contas novas não recebem), depois desinstala de quem já tem.
    # Erros aqui são esperados (pacote já removido) e não interessam ao log.
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object DisplayName -eq $app |
        ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
    Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
    if (Get-AppxPackage -AllUsers -Name $app -ErrorAction SilentlyContinue) {
        Aviso "não removido: $app"
    } elseif ($Instalados -contains $app) {
        Info "removido: $app"
    }
}

# Impede o Windows de baixar de novo Outlook, Dev Home e Vincular ao Celular
foreach ($t in 'OutlookUpdate', 'DevHomeUpdate', 'CrossDeviceUpdate') {
    Remove-Item "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\$t" -Recurse -Force -ErrorAction SilentlyContinue
}

if ($Opcoes.RemoverOneDrive) {
    Etapa 'Removendo o OneDrive'
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
    $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($setup) { Start-Process $setup -ArgumentList '/uninstall' -Wait }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget uninstall --id Microsoft.OneDrive -e --silent --accept-source-agreements 2>$null | Out-Null
    }
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name OneDrive -ErrorAction SilentlyContinue
    Info 'OneDrive removido (seus arquivos na nuvem continuam no site do OneDrive).'
}

# ------------------------------------------------------------------ IA, propagandas e sugestões
Etapa 'Desligando Copilot, Recall, Widgets e propagandas'
Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1   # Recall
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
if (Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction SilentlyContinue) {
    Disable-WindowsOptionalFeature -Online -FeatureName Recall -NoRestart -ErrorAction SilentlyContinue | Out-Null
}
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 0                    # Copilot no Edge
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0                 # Widgets

$CDM = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
foreach ($v in 'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
               'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled',
               'SoftLandingEnabled', 'RotatingLockScreenEnabled', 'RotatingLockScreenOverlayEnabled',
               'SubscribedContent-310093Enabled', 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled',
               'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled',
               'SubscribedContent-353696Enabled', 'SubscribedContent-353698Enabled') {
    Set-Reg $CDM $v 0
}
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
$Adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-Reg $Adv 'Start_IrisRecommendations' 0          # sugestões no menu Iniciar
Set-Reg $Adv 'Start_Layout' 1                       # Iniciar com mais fixados e menos recomendações
Set-Reg $Adv 'Start_AccountNotifications' 0
Set-Reg $Adv 'ShowSyncProviderNotifications' 0      # propaganda no Explorador
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0  # "vamos terminar de configurar"
Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1                   # Bing na busca
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0

# ------------------------------------------------------------------ telemetria
Etapa 'Reduzindo telemetria'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1   # mínimo aceito no Home/Pro
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0    # histórico de atividades
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0                  # pedidos de feedback
foreach ($s in 'DiagTrack', 'dmwappushservice', 'RetailDemo') {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
        Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
        Info "serviço desligado: $s"
    }
}
foreach ($t in @(
        @('\Microsoft\Windows\Application Experience\', 'Microsoft Compatibility Appraiser'),
        @('\Microsoft\Windows\Application Experience\', 'ProgramDataUpdater'),
        @('\Microsoft\Windows\Customer Experience Improvement Program\', 'Consolidator'),
        @('\Microsoft\Windows\Customer Experience Improvement Program\', 'UsbCeip'),
        @('\Microsoft\Windows\DiskDiagnostic\', 'Microsoft-Windows-DiskDiagnosticDataCollector'))) {
    Disable-ScheduledTask -TaskPath $t[0] -TaskName $t[1] -ErrorAction SilentlyContinue | Out-Null
}

# ------------------------------------------------------------------ energia
Etapa 'Configurando energia'
if ($Notebook) {
    # Plano Equilibrado + modo de energia: "Melhor desempenho" na tomada, "Equilibrado" na bateria
    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e | Out-Null
    $PS = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
    Set-Reg $PS 'ActiveOverlayAcPowerScheme' 'ded574b5-45a0-4f42-8737-46345c09c238' 'String'
    Set-Reg $PS 'ActiveOverlayDcPowerScheme' '00000000-0000-0000-0000-000000000000' 'String'
    Info 'Notebook: Melhor desempenho na tomada, Equilibrado na bateria.'
} else {
    # Desktop: plano "Desempenho Máximo" (Ultimate Performance); sem ele, "Alto desempenho"
    $existente = powercfg /list | Select-String -Pattern 'Desempenho M[aá]ximo|Ultimate Performance'
    if ($existente -and ($existente[0].Line -match '([0-9a-f]{8}-[0-9a-f-]{27})')) {
        $guid = $Matches[1]
    } else {
        $saida = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
        $guid = $null
        if ("$saida" -match '([0-9a-f]{8}-[0-9a-f-]{27})') { $guid = $Matches[1] }
    }
    if ($guid) {
        powercfg /setactive $guid | Out-Null
        Info 'Desktop: plano Desempenho Máximo ativo.'
    } else {
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
        Info 'Desktop: plano Alto desempenho ativo.'
    }
}

# ------------------------------------------------------------------ jogos
Etapa 'Ajustes para jogos'
Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1                      # Modo de Jogo
Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0                              # gravação em segundo plano
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2          # agendamento de GPU por hardware
Set-Reg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings' 'SwapEffectUpgradeEnable=1;' 'String'  # otimização de jogos em janela
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'                          # sem aceleração do mouse
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0  # programas de inicialização sem espera

if ($Opcoes.DesligarIntegridadeMemoria) {
    Etapa 'Desligando a Integridade de Memória (VBS/HVCI)'
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
    Info 'Vale depois de reiniciar. Para religar: Segurança do Windows > Segurança do dispositivo > Isolamento de núcleo.'
}

# ------------------------------------------------------------------ Windows Update
Etapa 'Windows Update sem reinício surpresa'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1
Info 'Atualizações continuam automáticas; o reinício fica com você.'

# ------------------------------------------------------------------ visual M3
Etapa 'Aplicando o visual M3'
$Pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
Set-Reg $Pers 'AppsUseLightTheme' 0
Set-Reg $Pers 'SystemUsesLightTheme' 0
Set-Reg $Pers 'EnableTransparency' 1
Set-Reg $Pers 'ColorPrevalence' 0
# Destaque ciano M3 #12C0EC (o registro guarda ABGR / ARGB)
Set-Reg 'HKCU:\Control Panel\Desktop' 'AutoColorization' 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'AccentColor' 0xFFECC012   # ABGR de #12C0EC
Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorizationColor' 0xC412C0EC
Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorizationAfterglow' 0xC412C0EC
Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence' 0
$Acc = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
Set-Reg $Acc 'AccentColorMenu' 0xFFECC012
Set-Reg $Acc 'StartColorMenu' 0xFFBD9A0E   # tom mais escuro (#0E9ABD)
[byte[]]$Paleta = 0x9D,0xE7,0xF8,0x00, 0x6A,0xD9,0xF3,0x00, 0x3E,0xCD,0xEF,0x00, 0x12,0xC0,0xEC,0x00,
                  0x0E,0x9A,0xBD,0x00, 0x0B,0x73,0x90,0x00, 0x07,0x4D,0x60,0x00, 0x88,0x17,0x98,0x00
Set-Reg $Acc 'AccentPalette' $Paleta 'Binary'

# Papel de parede e tela de bloqueio
$Origem = Join-Path $PSScriptRoot 'wallpaper-m3.png'
$Destino = "$env:SystemRoot\Web\Wallpaper\M3\wallpaper-m3.png"
if (Test-Path $Origem) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Destino) | Out-Null
    Copy-Item $Origem $Destino -Force
    Set-Reg 'HKCU:\Control Panel\Desktop' 'WallpaperStyle' '10' 'String'                # preencher
    Set-Reg 'HKCU:\Control Panel\Desktop' 'TileWallpaper' '0' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'Wallpaper' $Destino 'String'
    if (-not ('M3.Papel' -as [type])) {
        Add-Type -Namespace M3 -Name Papel -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@
    }
    [M3.Papel]::SystemParametersInfo(20, 0, $Destino, 3) | Out-Null
    $CSP = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
    Set-Reg $CSP 'LockScreenImagePath' $Destino 'String'
    Set-Reg $CSP 'LockScreenImageUrl' $Destino 'String'
    Set-Reg $CSP 'LockScreenImageStatus' 1
}

# Barra de tarefas e Explorador
Set-Reg $Adv 'ShowTaskViewButton' 0
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1   # busca só como ícone
Set-Reg "$Adv\TaskbarDeveloperSettings" 'TaskbarEndTask' 1                                  # "Finalizar tarefa" no clique direito
Set-Reg $Adv 'HideFileExt' 0                                                                # mostrar extensões
Set-Reg $Adv 'LaunchTo' 1                                                                   # Explorador abre em "Este Computador"
Set-Reg 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '(default)' '' 'String'  # menu de contexto clássico (mais rápido)

# Identificação
$OEM = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation'
Set-Reg $OEM 'Manufacturer' 'M3 TECH' 'String'
Set-Reg $OEM 'Model' 'M3 Windows' 'String'
Set-Reg $OEM 'SupportURL' 'https://github.com/michaelmmichelon/m3-windows' 'String'
Set-Reg 'HKLM:\SOFTWARE\M3Windows' 'Versao' $Versao 'String'
Set-Reg 'HKLM:\SOFTWARE\M3Windows' 'Aplicado' (Get-Date -Format 's') 'String'

# ------------------------------------------------------------------ fim
if ($PrimeiraVez) {
    # A senha usada para criar a conta não precisa mais ficar no disco
    Remove-Item (Join-Path $PSScriptRoot 'criar-usuario.ps1') -Force -ErrorAction SilentlyContinue
    # O login automático da instalação não continua depois do primeiro reinício
    $WL = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    Set-Reg $WL 'AutoAdminLogon' '0' 'String'
    Remove-ItemProperty -Path $WL -Name 'DefaultPassword', 'AutoLogonCount' -ErrorAction SilentlyContinue
    # Reconstrói a barra de tarefas só com os fixados do M3 (o Windows acrescenta um atalho
    # do Outlook depois da instalação, que não sai pelo layout)
    Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -Recurse -Force -ErrorAction SilentlyContinue
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    # Os fixados do Iniciar já foram aplicados à conta; a política sai para você poder mudá-los
    Remove-Item 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item 'HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\B5292708-1619-419B-9923-E5D9F3925E71\default\Device\Start' -Recurse -Force -ErrorAction SilentlyContinue
}

Etapa 'Pronto!'
Info "Registro do que foi feito: $PastaLog\otimizar.log"
Stop-Transcript | Out-Null

if ($PrimeiraVez) {
    Write-Host "`n    O computador vai reiniciar em 15 segundos para aplicar tudo." -ForegroundColor Cyan
    Start-Sleep -Seconds 15
    Restart-Computer -Force
} else {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue   # recarrega barra de tarefas e tema
    Write-Host "`n    Reinicie o computador para aplicar tudo (energia, GPU e Integridade de Memória)." -ForegroundColor Cyan
    Read-Host '    Enter para fechar'
}
