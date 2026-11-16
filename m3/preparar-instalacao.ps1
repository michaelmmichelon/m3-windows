# M3 Windows - preparação durante a instalação (fase "specialize", como SYSTEM),
# ANTES do primeiro login. O que é feito aqui o Windows já usa ao montar a conta nova:
#   - tira os apps da lista da imagem (não chegam a ser instalados nem fixados)
#   - define os fixados do Iniciar e da barra de tarefas (sem atalhos patrocinados)
$ErrorActionPreference = 'Continue'
$log = "$env:WINDIR\Setup\M3\preparar-instalacao.log"
Start-Transcript -Path $log | Out-Null

# Apps
$lista = Get-Content (Join-Path $PSScriptRoot 'apps-remover.txt') -Encoding UTF8 |
    ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ }
$prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
foreach ($p in $prov | Where-Object { $lista -contains $_.DisplayName }) {
    Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction SilentlyContinue | Out-Null
    "removido da imagem: $($p.DisplayName)"
}

# Tarefas que baixam e fixam Outlook, Dev Home e Vincular ao Celular depois da instalação
foreach ($t in 'OutlookUpdate', 'DevHomeUpdate', 'CrossDeviceUpdate') {
    Remove-Item "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\$t" -Recurse -Force -ErrorAction SilentlyContinue
    "tarefa removida: $t"
}

# Barra de tarefas (arquivo no perfil padrão) e Iniciar (política lida no primeiro login)
$shell = "$env:SystemDrive\Users\Default\AppData\Local\Microsoft\Windows\Shell"
New-Item -ItemType Directory -Force -Path $shell | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'LayoutModification.xml') $shell -Force

$fixados = (Get-Content (Join-Path $PSScriptRoot 'LayoutModification.json') -Raw -Encoding UTF8 | ConvertFrom-Json) |
    ConvertTo-Json -Depth 5 -Compress
$provedor = 'B5292708-1619-419B-9923-E5D9F3925E71'
$k1 = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start'
$k2 = "HKLM:\SOFTWARE\Microsoft\PolicyManager\providers\$provedor\default\Device\Start"
foreach ($k in $k1, $k2) { New-Item -Path $k -Force | Out-Null }
New-ItemProperty -Path $k1 -Name 'ConfigureStartPins' -Value $fixados -PropertyType String -Force | Out-Null
New-ItemProperty -Path $k1 -Name 'ConfigureStartPins_ProviderSet' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $k1 -Name 'ConfigureStartPins_WinningProvider' -Value $provedor -PropertyType String -Force | Out-Null
New-ItemProperty -Path $k2 -Name 'ConfigureStartPins' -Value $fixados -PropertyType String -Force | Out-Null
New-ItemProperty -Path $k2 -Name 'ConfigureStartPins_LastWrite' -Value 1 -PropertyType DWord -Force | Out-Null
'fixados do Iniciar e da barra definidos'
Stop-Transcript | Out-Null
