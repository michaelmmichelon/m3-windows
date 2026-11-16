# M3 Windows - cria a conta local durante a instalação (fase "specialize", como SYSTEM).
# Gerado pelo gerar-pendrive.ps1. É apagado pelo m3-otimizar.ps1 no primeiro login.
$ErrorActionPreference = 'Stop'
$log = "$env:WINDIR\Setup\M3\criar-usuario.log"
try {
    $usuario = '{{USUARIO}}'
    $senha = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('{{SENHA_B64}}'))
    $segura = ConvertTo-SecureString $senha -AsPlainText -Force
    if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
        New-LocalUser -Name $usuario -Password $segura -PasswordNeverExpires -AccountNeverExpires | Out-Null
    }
    # S-1-5-32-544 = Administradores (o nome do grupo muda com o idioma, o SID não)
    Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $usuario -ErrorAction SilentlyContinue
    "OK: conta $usuario criada" | Out-File $log -Encoding utf8
} catch {
    "ERRO: $($_.Exception.Message)" | Out-File $log -Encoding utf8
    exit 1
}
