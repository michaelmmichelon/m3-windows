#Requires -Version 5.1
<#
    M3 Windows - otimização do Windows 11 para desempenho
    ------------------------------------------------------
    Roda sozinho no primeiro login (instalação pelo pendrive do M3 Windows) ou à mão
    num Windows já instalado:

        powershell -ExecutionPolicy Bypass -File .\m3-otimizar.ps1

    Depois de aplicado, o M3 se mantém sozinho:
      - contas novas recebem as configurações do M3 no primeiro login (Active Setup);
      - depois de uma atualização grande do Windows (ex.: 25H2 -> 26H2), a tarefa
        "\M3\M3 Windows - reaplicar" aplica o M3 de novo no boot seguinte.
    Os arquivos ficam em C:\ProgramData\M3Windows.

    Mantém LIGADOS: Windows Defender, Windows Update, proteções do kernel e o firewall.

    Modos internos (não precisa usar à mão):
      -PrimeiraVez  chamado pela instalação automática: sem perguntas e reinicia no fim
      -SoUsuario    só as configurações da conta atual, sem administrador (Active Setup)
      -ContaNova    com -SoUsuario, no 1º login de uma conta nova, depois que a área de
                    trabalho abre (RunOnce do perfil padrão): também refaz a barra de tarefas
      -Verificar    pela tarefa agendada: reaplica se a versão do Windows mudou
#>
param(
    [string]$Config,
    [switch]$PrimeiraVez,
    [switch]$SoUsuario,
    [switch]$ContaNova,
    [switch]$Verificar
)

$Versao = '0.3.0'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Base = Join-Path $env:ProgramData 'M3Windows'          # onde o M3 fica instalado
$Wallpaper = "$env:SystemRoot\Web\Wallpaper\M3\wallpaper-m3.png"
if (-not $Config) {
    $Config = Join-Path $PSScriptRoot 'config.json'
    if (-not (Test-Path $Config)) { $Config = Join-Path $Base 'config.json' }
}
$BuildWindows = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild

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

function Ler-Opcoes {
    $o = [ordered]@{ RemoverOneDrive = $false; DesligarIntegridadeMemoria = $false }
    if (Test-Path $Config) {
        try {
            $lido = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @($o.Keys)) { if ($null -ne $lido.$k) { $o[$k] = [bool]$lido.$k } }
        } catch { Aviso 'config.json inválido; usando o padrão.' }
    }
    return $o
}

# =================================================================== CONTA DO USUÁRIO
# Tudo o que fica no perfil da pessoa (HKCU). Roda para quem aplicou o M3 e, pelo
# Active Setup, para cada conta nova no primeiro login. Não precisa de administrador.
function Aplicar-Usuario($Opcoes) {
    Etapa 'Configurações da conta'

    # Propagandas (Copilot, Recall e Bing na busca são políticas do computador: ver Aplicar-Computador)
    $CDM = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($v in 'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
                   'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled',
                   'SoftLandingEnabled', 'RotatingLockScreenEnabled', 'RotatingLockScreenOverlayEnabled',
                   'SubscribedContent-310093Enabled', 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled',
                   'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled',
                   'SubscribedContent-353696Enabled', 'SubscribedContent-353698Enabled') {
        Set-Reg $CDM $v 0
    }
    $Adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg $Adv 'Start_IrisRecommendations' 0          # sugestões no menu Iniciar
    Set-Reg $Adv 'Start_Layout' 1                       # Iniciar com mais fixados e menos recomendações
    Set-Reg $Adv 'Start_AccountNotifications' 0
    Set-Reg $Adv 'ShowSyncProviderNotifications' 0      # propaganda no Explorador
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0  # "vamos terminar de configurar"
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0                  # pedidos de feedback

    # Jogos e resposta
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1                      # Modo de Jogo
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1
    Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0                              # gravação em segundo plano
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings' 'SwapEffectUpgradeEnable=1;' 'String'  # jogos em janela
    Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'                          # sem aceleração do mouse
    Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
    Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0  # inicialização sem espera

    # Visual M3: tema escuro e destaque ciano #12C0EC (o registro guarda ABGR / ARGB)
    $Pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-Reg $Pers 'AppsUseLightTheme' 0
    Set-Reg $Pers 'SystemUsesLightTheme' 0
    Set-Reg $Pers 'EnableTransparency' 1
    Set-Reg $Pers 'ColorPrevalence' 0
    Set-Reg 'HKCU:\Control Panel\Desktop' 'AutoColorization' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'AccentColor' 0xFFECC012
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorizationColor' 0xC412C0EC
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorizationAfterglow' 0xC412C0EC
    Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'ColorPrevalence' 0
    $Acc = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
    Set-Reg $Acc 'AccentColorMenu' 0xFFECC012
    Set-Reg $Acc 'StartColorMenu' 0xFFBD9A0E   # tom mais escuro (#0E9ABD)
    [byte[]]$Paleta = 0x9D,0xE7,0xF8,0x00, 0x6A,0xD9,0xF3,0x00, 0x3E,0xCD,0xEF,0x00, 0x12,0xC0,0xEC,0x00,
                      0x0E,0x9A,0xBD,0x00, 0x0B,0x73,0x90,0x00, 0x07,0x4D,0x60,0x00, 0x88,0x17,0x98,0x00
    Set-Reg $Acc 'AccentPalette' $Paleta 'Binary'

    if (-not ('M3.Sistema' -as [type])) {
        Add-Type -Namespace M3 -Name Sistema -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
[DllImport("user32.dll", EntryPoint = "SystemParametersInfoW")]
public static extern int SystemParametersInfoMouse(int uAction, int uParam, int[] lpvParam, int fuWinIni);
'@
    }
    [M3.Sistema]::SystemParametersInfoMouse(4, 0, [int[]](0, 0, 0), 3) | Out-Null   # aplica o mouse já
    if (Test-Path $Wallpaper) {
        Set-Reg 'HKCU:\Control Panel\Desktop' 'WallpaperStyle' '10' 'String'          # preencher
        Set-Reg 'HKCU:\Control Panel\Desktop' 'TileWallpaper' '0' 'String'
        Set-Reg 'HKCU:\Control Panel\Desktop' 'Wallpaper' $Wallpaper 'String'
        [M3.Sistema]::SystemParametersInfo(20, 0, $Wallpaper, 3) | Out-Null
    }

    # Barra de tarefas e Explorador
    Set-Reg $Adv 'ShowTaskViewButton' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1   # busca só como ícone
    Set-Reg "$Adv\TaskbarDeveloperSettings" 'TaskbarEndTask' 1                                  # "Finalizar tarefa" no clique direito
    Set-Reg $Adv 'HideFileExt' 0                                                                # mostrar extensões
    Set-Reg $Adv 'LaunchTo' 1                                                                   # Explorador abre em "Este Computador"
    Set-Reg 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '(default)' '' 'String'  # menu de contexto clássico

    if ($Opcoes.RemoverOneDrive) {
        Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name OneDrive -ErrorAction SilentlyContinue
    }
    Info 'Tema, jogos, mouse, barra de tarefas e privacidade da conta aplicados.'
}

# =================================================================== COMPUTADOR
# Tudo o que vale para o PC inteiro (HKLM, serviços, apps, energia). Precisa de admin.
function Aplicar-Computador($Opcoes) {
    $Notebook = $null -ne (Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue)
    if ($Notebook) { Info 'Notebook detectado (bateria presente).' }

    # ---------------------------------------------------------- apps pré-instalados
    Etapa 'Removendo apps pré-instalados'
    # A lista fica em apps-remover.txt (a mesma usada na instalação, antes do primeiro login)
    $ListaApps = Join-Path $PSScriptRoot 'apps-remover.txt'
    if (-not (Test-Path $ListaApps)) { $ListaApps = Join-Path $Base 'apps-remover.txt' }
    if (-not (Test-Path $ListaApps)) { Aviso 'apps-remover.txt não encontrado; pulando.' }
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
        Info 'OneDrive removido (seus arquivos na nuvem continuam no site do OneDrive).'
    }

    # ---------------------------------------------------------- IA e propagandas
    Etapa 'Desligando Copilot, Recall, Widgets e propagandas'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1   # Recall
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
    if (Get-WindowsOptionalFeature -Online -FeatureName Recall -ErrorAction SilentlyContinue) {
        Disable-WindowsOptionalFeature -Online -FeatureName Recall -NoRestart -ErrorAction SilentlyContinue | Out-Null
    }
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1  # Bing na busca (todas as contas)
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0                 # Widgets
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1

    # ---------------------------------------------------------- Edge leve
    Etapa 'Edge sem rodar em segundo plano'
    $Edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    Set-Reg $Edge 'StartupBoostEnabled' 0              # não abre escondido junto com o Windows
    Set-Reg $Edge 'BackgroundModeEnabled' 0            # não fica rodando depois de fechado
    Set-Reg $Edge 'HubsSidebarEnabled' 0               # barra lateral (Copilot)
    Set-Reg $Edge 'EdgeShoppingAssistantEnabled' 0     # ofertas de compras
    Set-Reg $Edge 'ShowRecommendationsEnabled' 0       # recomendações e dicas
    Set-Reg $Edge 'ShowMicrosoftRewards' 0
    Set-Reg $Edge 'HideFirstRunExperience' 1           # sem o assistente de boas-vindas
    Info 'O Edge continua instalado e funcionando; só não gasta RAM quando fechado.'

    # ---------------------------------------------------------- telemetria
    Etapa 'Reduzindo telemetria'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1   # mínimo aceito no Home/Pro
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0    # histórico de atividades
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
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

    # ---------------------------------------------------------- energia
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

    # ---------------------------------------------------------- jogos e segurança opcional
    Etapa 'Ajustes para jogos'
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2          # agendamento de GPU por hardware
    if ($Opcoes.DesligarIntegridadeMemoria) {
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0
        Info 'Integridade de Memória desligada (vale depois de reiniciar). Para religar: Segurança do Windows > Segurança do dispositivo > Isolamento de núcleo.'
    }

    # ---------------------------------------------------------- Windows Update
    Etapa 'Windows Update sem reinício surpresa'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1
    Info 'Atualizações continuam automáticas; o reinício fica com você.'

    # ---------------------------------------------------------- visual do PC
    Etapa 'Papel de parede e tela de bloqueio M3'
    $Origem = Join-Path $PSScriptRoot 'wallpaper-m3.png'
    if ((Test-Path $Origem) -and ($Origem -ne $Wallpaper)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $Wallpaper) | Out-Null
        Copy-Item $Origem $Wallpaper -Force
    }
    if (Test-Path $Wallpaper) {
        $CSP = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
        Set-Reg $CSP 'LockScreenImagePath' $Wallpaper 'String'
        Set-Reg $CSP 'LockScreenImageUrl' $Wallpaper 'String'
        Set-Reg $CSP 'LockScreenImageStatus' 1
    }

    # ---------------------------------------------------------- identificação
    $OEM = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation'
    Set-Reg $OEM 'Manufacturer' 'M3 TECH' 'String'
    Set-Reg $OEM 'Model' 'M3 Windows' 'String'
    Set-Reg $OEM 'SupportURL' 'https://github.com/michaelmmichelon/m3-windows' 'String'
    Set-Reg 'HKLM:\SOFTWARE\M3Windows' 'Versao' $Versao 'String'
    Set-Reg 'HKLM:\SOFTWARE\M3Windows' 'Aplicado' (Get-Date -Format 's') 'String'
    Set-Reg 'HKLM:\SOFTWARE\M3Windows' 'BuildWindows' $BuildWindows 'String'
}

# =================================================================== MANTER O M3
# Copia os arquivos para C:\ProgramData\M3Windows, liga o Active Setup (contas novas)
# e a tarefa que reaplica depois de atualizações grandes.
function Instalar-Manutencao($Opcoes) {
    Etapa 'Mantendo o M3 em contas novas e depois de atualizações'
    New-Item -ItemType Directory -Force -Path $Base | Out-Null
    foreach ($f in 'm3-otimizar.ps1', 'apps-remover.txt', 'wallpaper-m3.png', 'm3-medir.ps1', 'm3-apps.ps1', 'apps-catalogo.txt') {
        $o = Join-Path $PSScriptRoot $f
        $d = Join-Path $Base $f
        if ((Test-Path $o) -and ([IO.Path]::GetFullPath($o) -ne [IO.Path]::GetFullPath($d))) { Copy-Item $o $d -Force }
    }
    # config.json do M3: as opções + o que veio do pendrive (apps escolhidos etc.)
    $cfgSaida = [ordered]@{}
    if (Test-Path $Config) {
        try { (Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cfgSaida[$_.Name] = $_.Value } } catch {}
    }
    foreach ($k in $Opcoes.Keys) { $cfgSaida[$k] = $Opcoes[$k] }
    if ([IO.Path]::GetFullPath($Config) -ne [IO.Path]::GetFullPath((Join-Path $Base 'config.json'))) {
        ($cfgSaida | ConvertTo-Json) | Set-Content (Join-Path $Base 'config.json') -Encoding UTF8
    }
    # Só administradores e o sistema alteram a pasta (a tarefa roda como SYSTEM); usuários leem
    & icacls.exe $Base /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null

    # Active Setup: o Windows roda o StubPath uma vez por conta (e de novo quando a versão sobe)
    $VersaoAS = ($Versao -replace '\.', ',') + ",$BuildWindows"
    $AS = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\M3Windows'
    Set-Reg $AS '(default)' 'M3 Windows' 'String'
    Set-Reg $AS 'StubPath' "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Base\m3-otimizar.ps1`" -SoUsuario" 'String'
    Set-Reg $AS 'Version' $VersaoAS 'String'
    Set-Reg $AS 'IsInstalled' 1
    # A conta atual já recebeu tudo agora: marca como feita para não repetir no próximo login
    Set-Reg 'HKCU:\Software\Microsoft\Active Setup\Installed Components\M3Windows' 'Version' $VersaoAS 'String'

    # Contas novas: o Active Setup roda antes da área de trabalho e o Windows sobrescreve o tema
    # logo depois. Por isso, no perfil padrão (molde das contas novas) vai um RunOnce, que roda
    # DEPOIS que a área de trabalho abre; e o Active Setup fica marcado como feito ali.
    $hive = "$env:SystemDrive\Users\Default\NTUSER.DAT"
    & reg.exe load 'HKU\M3Default' $hive | Out-Null
    if ($LASTEXITCODE -eq 0) {
        & reg.exe add 'HKU\M3Default\Software\Microsoft\Windows\CurrentVersion\RunOnce' /v M3Windows /t REG_SZ /f `
            /d "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $Base\m3-otimizar.ps1 -SoUsuario -ContaNova" | Out-Null
        & reg.exe add 'HKU\M3Default\Software\Microsoft\Active Setup\Installed Components\M3Windows' /v Version /t REG_SZ /d $VersaoAS /f | Out-Null
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        & reg.exe unload 'HKU\M3Default' | Out-Null
        if ($LASTEXITCODE -ne 0) { Start-Sleep 2; & reg.exe unload 'HKU\M3Default' | Out-Null }
    } else { Aviso 'Não deu para abrir o perfil padrão; contas novas recebem o M3 pelo Active Setup.' }

    # Tarefa: 2 min depois do boot, confere se o Windows mudou de versão (sai na hora se não mudou)
    try {
        $acao = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Base\m3-otimizar.ps1`" -Verificar"
        $gatilho = New-ScheduledTaskTrigger -AtStartup
        $gatilho.Delay = 'PT2M'
        $quem = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
        $ajustes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -Priority 7
        Register-ScheduledTask -TaskPath '\M3\' -TaskName 'M3 Windows - reaplicar' -Action $acao -Trigger $gatilho `
            -Principal $quem -Settings $ajustes -Description 'Reaplica o M3 Windows depois de atualizações grandes do Windows.' -Force | Out-Null
        Info 'Contas novas: recebem o M3 no primeiro login.'
        Info 'Atualização grande do Windows: o M3 é reaplicado sozinho no boot seguinte.'
    } catch { Aviso "Não deu para criar a tarefa de reaplicação: $($_.Exception.Message)" }
}

# Contas novas copiam o Iniciar (fixados) da conta de quem instalou o M3. O Windows guarda os
# fixados em start2.bin, que só existe depois que o Iniciar abre; por isso a cópia é feita no
# boot seguinte (pela tarefa) e só uma vez.
function Copiar-FixadosIniciar {
    $principal = (Get-ItemProperty 'HKLM:\SOFTWARE\M3Windows' -ErrorAction SilentlyContinue).UsuarioPrincipal
    if (-not $principal) { return }
    $rel = 'AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\LocalState\start2.bin'
    $origem = Join-Path "$env:SystemDrive\Users\$principal" $rel
    $destino = Join-Path "$env:SystemDrive\Users\Default" $rel
    if ((Test-Path $origem) -and -not (Test-Path $destino)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $destino) | Out-Null
        Copy-Item $origem $destino -Force
    }
}

# =================================================================== MODOS

# ---- só a conta (Active Setup / login de conta nova): sem admin, sem janela
if ($SoUsuario) {
    $logUsuario = Join-Path $env:LOCALAPPDATA 'M3Windows'
    New-Item -ItemType Directory -Force -Path $logUsuario | Out-Null
    Start-Transcript -Path (Join-Path $logUsuario 'usuario.log') -Append | Out-Null
    Aplicar-Usuario (Ler-Opcoes)
    if ($ContaNova) {
        # Conta nova: a barra vem com os fixados do Windows (Outlook etc.); refaz pelo layout do M3.
        # Reiniciar o Explorer também aplica o tema, a busca e os botões da barra na hora.
        Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband' -Recurse -Force -ErrorAction SilentlyContinue
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    }
    Stop-Transcript | Out-Null
    exit 0
}

# ---- daqui para baixo precisa de administrador
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ---- tarefa do boot: reaplica só se o Windows mudou de versão
if ($Verificar) {
    Copiar-FixadosIniciar
    $anterior = (Get-ItemProperty 'HKLM:\SOFTWARE\M3Windows' -ErrorAction SilentlyContinue).BuildWindows
    if ($anterior -eq $BuildWindows) { exit 0 }
    Start-Transcript -Path (Join-Path $Base 'reaplicar.log') -Append | Out-Null
    Info "Windows mudou de versão (build $anterior -> $BuildWindows): reaplicando o M3."
    $opc = Ler-Opcoes
    Aplicar-Computador $opc
    # Sobe a versão do Active Setup: cada conta recebe as configurações de novo no próximo login
    $VersaoAS = ($Versao -replace '\.', ',') + ",$BuildWindows"
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\M3Windows' 'Version' $VersaoAS 'String'
    Etapa 'Reaplicado.'
    Stop-Transcript | Out-Null
    exit 0
}

# ---- aplicação normal (instalação ou à mão)
$Host.UI.RawUI.WindowTitle = "M3 Windows $Versao - otimizando"
New-Item -ItemType Directory -Force -Path $Base | Out-Null
Start-Transcript -Path (Join-Path $Base 'otimizar.log') -Append | Out-Null

Write-Host ''
Write-Host '  M3 WINDOWS' -ForegroundColor Cyan
Write-Host "  Otimização para desempenho - versão $Versao"
Write-Host '  Não desligue o computador até terminar.'

$Opcoes = Ler-Opcoes
if (-not (Test-Path $Config) -and -not $PrimeiraVez) {
    $r = Read-Host '    Remover o OneDrive? [s/N]'
    $Opcoes.RemoverOneDrive = $r -match '^[sS]'
    Write-Host '    Integridade de Memória (VBS): desligar dá alguns % de FPS em certos jogos,'
    Write-Host '    mas tira uma camada de proteção contra drivers maliciosos.'
    $r = Read-Host '    Desligar a Integridade de Memória? [s/N]'
    $Opcoes.DesligarIntegridadeMemoria = $r -match '^[sS]'
}

if (-not $PrimeiraVez) {
    Etapa 'Criando ponto de restauração'
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
        Checkpoint-Computer -Description 'Antes do M3 Windows' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Info 'Ponto de restauração "Antes do M3 Windows" criado.'
    } catch { Aviso "Não deu para criar o ponto de restauração: $($_.Exception.Message)" }
}

Aplicar-Computador $Opcoes
Aplicar-Usuario $Opcoes
Instalar-Manutencao $Opcoes
# Conta de referência para o Iniciar das contas novas (quem instalou/aplicou o M3)
if (-not (Get-ItemProperty 'HKLM:\SOFTWARE\M3Windows' -ErrorAction SilentlyContinue).UsuarioPrincipal) {
    Set-Reg 'HKLM:\SOFTWARE\M3Windows' 'UsuarioPrincipal' $env:USERNAME 'String'
}

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
    # Apps escolhidos no pendrive: instalados no login depois deste reinício (com internet e o
    # winget prontos). A tarefa roda como esta conta, com privilégio de admin, e se apaga no fim.
    $cfgApps = $null
    try { $cfgApps = Get-Content (Join-Path $Base 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    if ($cfgApps -and ((@($cfgApps.Apps).Count -gt 0) -or $cfgApps.DriverVideo)) {
        try {
            $conta = "$env:USERDOMAIN\$env:USERNAME"
            $acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Base\m3-apps.ps1`" -Tarefa"
            $gatilho = New-ScheduledTaskTrigger -AtLogOn -User $conta
            $quem = New-ScheduledTaskPrincipal -UserId $conta -LogonType Interactive -RunLevel Highest
            $ajustes = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
            Register-ScheduledTask -TaskPath '\M3\' -TaskName 'M3 Windows - instalar apps' -Action $acao -Trigger $gatilho `
                -Principal $quem -Settings $ajustes -Description 'Instala os apps escolhidos no M3 Windows (uma vez).' -Force | Out-Null
            Info 'Apps escolhidos: serão instalados no próximo login.'
        } catch { Aviso "Não deu para agendar a instalação dos apps: $($_.Exception.Message)" }
    }
    # Os fixados do Iniciar já foram aplicados à conta; a política sai para você poder mudá-los
    Remove-Item 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start' -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item 'HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\B5292708-1619-419B-9923-E5D9F3925E71\default\Device\Start' -Recurse -Force -ErrorAction SilentlyContinue
}

Etapa 'Pronto!'
Info "Registro do que foi feito: $Base\otimizar.log"
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
