# M3 Windows - confere os scripts antes de gerar pendrive/ISO
#   powershell -ExecutionPolicy Bypass -File .\ferramentas\validar.ps1
# 1) Regrava os .ps1 em UTF-8 COM BOM: o PowerShell 5.1 lê .ps1 sem BOM como ANSI e
#    estraga os acentos. 2) Confere a sintaxe de todos. 3) Confere XML e JSON.
$ErrorActionPreference = 'Stop'
$Raiz = Split-Path $PSScriptRoot
$erros = 0
foreach ($f in Get-ChildItem $Raiz -Recurse -Filter *.ps1 | Where-Object FullName -notmatch '\\saida\\') {
    $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($f.FullName, $t, (New-Object Text.UTF8Encoding($true)))
    $tok = $null; $err = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$err) | Out-Null
    if ($err) {
        $erros++
        "ERRO em $($f.Name):"; $err | ForEach-Object { "  linha $($_.Extent.StartLineNumber): $($_.Message)" }
    } else { "ok   $($f.FullName.Substring($Raiz.Length + 1))" }
}
foreach ($x in 'modelo\autounattend.xml', 'm3\LayoutModification.xml') {
    try { [xml](Get-Content (Join-Path $Raiz $x) -Raw) | Out-Null; "ok   $x" } catch { $erros++; "ERRO em ${x}: $($_.Exception.Message)" }
}
try { Get-Content (Join-Path $Raiz 'm3\LayoutModification.json') -Raw | ConvertFrom-Json | Out-Null; 'ok   m3\LayoutModification.json' }
catch { $erros++; "ERRO no LayoutModification.json: $($_.Exception.Message)" }
if ($erros) { "`n$erros erro(s)"; exit 1 } else { "`nTudo certo." }
