$ErrorActionPreference = "Stop"

# Detectar a raiz do projeto (NEXUS) a partir da localização do script
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Parent $scriptPath
$nexusRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

Set-Location $nexusRoot
Write-Host "Executando na raiz do projeto: $nexusRoot" -ForegroundColor Gray

# Caminhos relativos à raiz NEXUS
$pubspecPath = "finance_app/pubspec.yaml"
$apkBuildPath = "finance_app/build/app/outputs/flutter-apk/app-release.apk"
$backendApkDir = "navitools/modulos/App_financeiro"
$backendApkPath = "$backendApkDir/finance_app.apk"

# 1. Obter versão atual
if (-not (Test-Path $pubspecPath)) {
    Write-Error "Não foi possível encontrar o pubspec.yaml em $pubspecPath"
}

$content = Get-Content -Path $pubspecPath -Raw
if ($content -match 'version:\s*([^\s+]+)\+(\d+)') {
    $currentName = $Matches[1]
    $currentBuild = [int]$Matches[2]
    $nextBuild = $currentBuild + 1
    
    Write-Host "`n--- Gerenciador de Release ---" -ForegroundColor Cyan
    Write-Host "Versão atual no pubspec: $currentName+$currentBuild"
    
    # 2. Perguntar sobre a nova versão
    Write-Host "Dica: Digite apenas os números (ex: 2.1.0). O script cuidará do +$nextBuild automaticamente." -ForegroundColor Gray
    $inputVersion = Read-Host "Digite a nova versão (Enter para manter $currentName)"
    
    if ([string]::IsNullOrWhiteSpace($inputVersion)) {
        $newVersion = $currentName
    } else {
        # Limpar caso o usuário digite com + por engano
        $newVersion = $inputVersion.Split('+')[0]
    }
    
    $newFullVersion = "$newVersion+$nextBuild"
    Write-Host "Nova versão definida: $newFullVersion" -ForegroundColor Green
    
    # 3. Atualizar pubspec.yaml
    $oldLine = $Matches[0]
    $newLine = "version: $newFullVersion"
    $content = $content.Replace($oldLine, $newLine)
    Set-Content -Path $pubspecPath -Value $content -Encoding UTF8
} else {
    Write-Error "Padrão de versão não encontrado no pubspec.yaml"
}

# 4. Rodar o build
Write-Host "`n--- Iniciando Build do APK ---" -ForegroundColor Cyan
Set-Location "finance_app"

# Tentar flutter clean, mas ignorar erro se a pasta estiver travada (o build costuma funcionar mesmo assim)
try {
    Write-Host "Limpando build antigo..."
    flutter clean
} catch {
    Write-Host "Aviso: Não foi possível limpar a pasta build (pode estar em uso), prosseguindo..." -ForegroundColor Yellow
}

Write-Host "Obtendo dependências..."
flutter pub get

Write-Host "Compilando APK (isso pode levar alguns minutos)..."
flutter build apk --release

if ($LASTEXITCODE -ne 0) {
    Write-Error "O build do Flutter falhou!"
}
Set-Location $nexusRoot

# 5. Mover para o backend
Write-Host "`n--- Movendo APK para o Backend ---" -ForegroundColor Cyan
if (Test-Path $apkBuildPath) {
    if (-not (Test-Path $backendApkDir)) {
        New-Item -ItemType Directory -Path $backendApkDir -Force | Out-Null
    }
    
    # Tenta copiar, se falhar por estar em uso, avisa o usuário
    try {
        Copy-Item -Path $apkBuildPath -Destination $backendApkPath -Force
        Write-Host "Sucesso! APK movido para: $backendApkPath" -ForegroundColor Green
    } catch {
        Write-Error "Não foi possível substituir o APK no backend. Verifique se o servidor Flask não está travando o arquivo."
    }
} else {
    Write-Error "APK não encontrado em $apkBuildPath após o build!"
}

Write-Host "`nRelease $newFullVersion concluída com sucesso!" -ForegroundColor Cyan
