#Requires -Version 5.1
<#
    M3 Windows - medição de desempenho em repouso

    Mede o que o M3 promete reduzir: RAM em uso, processos, serviços, CPU parada,
    tarefas agendadas e tempo de boot. Use no Windows "puro" e no M3 Windows (mesma
    máquina ou duas VMs iguais), com o PC parado uns 5 minutos depois de ligar.

        powershell -ExecutionPolicy Bypass -File .\m3-medir.ps1
        powershell -ExecutionPolicy Bypass -File .\m3-medir.ps1 -Comparar puro.json m3.json

    O resultado é salvo em Documentos Públicos (C:\Users\Public\Documents) como .json.
    Rode como administrador para ter o tempo de boot (log de desempenho do Windows).
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Comparar,
    [int]$SegundosCpu = 30,
    [string]$Nome,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arquivos
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$Rotulos = [ordered]@{
    RamEmUsoMB          = 'RAM em uso (MB)'
    RamCommitMB         = 'Memória comprometida (MB)'
    Processos           = 'Processos'
    Threads             = 'Threads'
    ServicosRodando     = 'Serviços rodando'
    CpuOciosaPct        = 'CPU parada, média (%)'
    TarefasAtivas       = 'Tarefas agendadas ativas'
    ProgramasNoInicio   = 'Programas na inicialização'
    AppsInstalados      = 'Apps da Loja instalados'
    DiscoUsadoGB        = 'Disco C: usado (GB)'
    BootSegundos        = 'Último boot (s)'
}

function Mostrar-Tabela($medidas) {
    $cab = '{0,-28}' -f 'Medida'
    foreach ($m in $medidas) { $cab += '{0,16}' -f $m.Nome }
    if ($medidas.Count -eq 2) { $cab += '{0,14}' -f 'Diferença' }
    Write-Host $cab -ForegroundColor Cyan
    Write-Host ('-' * $cab.Length)
    foreach ($k in $Rotulos.Keys) {
        $linha = '{0,-28}' -f $Rotulos[$k]
        foreach ($m in $medidas) {
            $v = $m.$k
            $linha += '{0,16}' -f $(if ($null -eq $v) { '-' } else { $v })
        }
        if ($medidas.Count -eq 2 -and $null -ne $medidas[0].$k -and $null -ne $medidas[1].$k -and [double]$medidas[0].$k -ne 0) {
            $a = [double]$medidas[0].$k; $b = [double]$medidas[1].$k
            $pct = [math]::Round(($b - $a) / $a * 100)
            $txt = if ($pct -gt 0) { "+$pct%" } else { "$pct%" }
            $cor = if ($pct -lt 0) { 'Green' } elseif ($pct -gt 0) { 'Yellow' } else { 'Gray' }
            Write-Host $linha -NoNewline
            Write-Host ('{0,14}' -f $txt) -ForegroundColor $cor
        } else {
            Write-Host $linha
        }
    }
    Write-Host ''
    foreach ($m in $medidas) {
        Write-Host ("{0}: {1} | M3 Windows: {2} | medido em {3}" -f $m.Nome, $m.Sistema, $m.M3Windows, $m.Data) -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------------ comparar
if ($Comparar) {
    $lista = @($Arquivos | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    if ($lista.Count -lt 1) { Write-Host 'Informe os arquivos: .\m3-medir.ps1 -Comparar puro.json m3.json'; return }
    $medidas = foreach ($arq in $lista) { Get-Content $arq -Raw -Encoding UTF8 | ConvertFrom-Json }
    Write-Host ''
    Mostrar-Tabela @($medidas)
    if ($medidas.Count -eq 2) {
        Write-Host "`nDiferença: do primeiro para o segundo. Verde = o segundo usa menos." -ForegroundColor DarkGray
    }
    return
}

# ------------------------------------------------------------------ medir
$so = Get-CimInstance Win32_OperatingSystem
$uptimeMin = [math]::Round(((Get-Date) - $so.LastBootUpTime).TotalMinutes)
Write-Host "`n  M3 WINDOWS - medição em repouso" -ForegroundColor Cyan
Write-Host "  Ligado há $uptimeMin min. Feche os programas e não mexa no PC durante a medição."
if ($uptimeMin -lt 5) {
    Write-Host '  ! Ligado há menos de 5 min: o Windows ainda está terminando tarefas de início; a medição fica maior.' -ForegroundColor Yellow
}

Write-Host "  Medindo a CPU por $SegundosCpu s..."
$amostras = for ($i = 0; $i -lt $SegundosCpu; $i++) {
    (Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
    Start-Sleep -Seconds 1
}
$cpu = [math]::Round(($amostras | Measure-Object -Average).Average, 1)

$procs = Get-Process
$boot = $null
try {
    $ev = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction Stop
    $xml = [xml]$ev.ToXml()
    $ms = ($xml.Event.EventData.Data | Where-Object Name -eq 'BootTime').'#text'
    if ($ms) { $boot = [math]::Round([double]$ms / 1000, 1) }
} catch {}

$disco = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
$m3 = Get-ItemProperty 'HKLM:\SOFTWARE\M3Windows' -ErrorAction SilentlyContinue
if (-not $Nome) { $Nome = if ($m3) { 'M3' } else { 'Windows' } }

$r = [ordered]@{
    Nome              = $Nome
    Data              = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    Sistema           = "$($so.Caption) $($so.Version)"
    M3Windows         = $(if ($m3) { $m3.Versao } else { 'não' })
    RamTotalMB        = [math]::Round($so.TotalVisibleMemorySize / 1KB)
    RamEmUsoMB        = [math]::Round(($so.TotalVisibleMemorySize - $so.FreePhysicalMemory) / 1KB)
    RamCommitMB       = [math]::Round(($so.TotalVirtualMemorySize - $so.FreeVirtualMemory) / 1KB)
    Processos         = $procs.Count
    Threads           = ($procs | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum
    ServicosRodando   = @(Get-Service | Where-Object Status -eq 'Running').Count
    CpuOciosaPct      = $cpu
    TarefasAtivas     = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object State -ne 'Disabled').Count
    ProgramasNoInicio = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue).Count
    AppsInstalados    = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and $_.SignatureKind -eq 'Store' }).Count
    DiscoUsadoGB      = [math]::Round(($disco.Size - $disco.FreeSpace) / 1GB, 1)
    BootSegundos      = $boot
    MaioresProcessos  = @($procs | Sort-Object WorkingSet64 -Descending | Select-Object -First 8 |
                          ForEach-Object { '{0} ({1} MB)' -f $_.ProcessName, [math]::Round($_.WorkingSet64 / 1MB) })
}

$arquivo = Join-Path "$env:PUBLIC\Documents" ("m3-medicao-{0}-{1}.json" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm'))
$r | ConvertTo-Json | Set-Content -Path $arquivo -Encoding UTF8

Write-Host ''
Mostrar-Tabela @([pscustomobject]$r)
Write-Host "`nProcessos que mais usam RAM:" -ForegroundColor Cyan
$r.MaioresProcessos | ForEach-Object { Write-Host "  $_" }
if ($null -eq $boot) { Write-Host "`n(Tempo de boot: rode como administrador para ler.)" -ForegroundColor DarkGray }
Write-Host "`nSalvo em: $arquivo" -ForegroundColor Cyan
Write-Host 'Para comparar duas medições:  .\m3-medir.ps1 -Comparar puro.json m3.json'
