$ErrorActionPreference = "Stop"

# Uso: .\scripts\set_version.ps1 -Version 0.0.0.12
param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

# Caminho do arquivo de versão no backend
$versionFile = "navitools/modulos/App_financeiro/version.txt"

Write-Host "Definindo versão do app para $Version"
Set-Content -Path $versionFile -Value $Version -Encoding UTF8

# Exportar APP_VERSION para o processo atual (útil em pipelines)
$env:APP_VERSION = $Version
Write-Host "APP_VERSION=$Version definido no ambiente atual."

Write-Host "Versão gravada em $versionFile"
