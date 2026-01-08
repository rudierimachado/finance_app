$ErrorActionPreference = "Stop"

# Uso: .\scripts\set_version.ps1 -Version 2.0.9
param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$pubspecPath = "finance_app/pubspec.yaml"

if (-not (Test-Path $pubspecPath)) {
    Write-Error "Arquivo pubspec.yaml não encontrado em $pubspecPath"
}

Write-Host "Atualizando versão no pubspec.yaml para $Version..."

# Ler o conteúdo do pubspec
$content = Get-Content -Path $pubspecPath -Raw

# Regex para encontrar a versão atual (ex: version: 2.0.8+2)
if ($content -match 'version:\s*([^\s+]+)\+(\d+)') {
    $currentName = $Matches[1]
    $currentBuild = [int]$Matches[2]
    $newBuild = $currentBuild + 1
    
    $oldLine = $Matches[0]
    $newLine = "version: $Version+$newBuild"
    
    $content = $content.Replace($oldLine, $newLine)
    Set-Content -Path $pubspecPath -Value $content -Encoding UTF8
    
    Write-Host "Sucesso! Versão alterada de $currentName+$currentBuild para $Version+$newBuild"
} else {
    Write-Error "Não foi possível localizar o padrão de versão no pubspec.yaml"
}
