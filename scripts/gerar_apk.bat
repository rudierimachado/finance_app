@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"

:: Uso: scripts\gerar_apk.bat
:: Incrementa versão (último dígito) em navitools/modulos/App_financeiro/version.txt,
:: exporta APP_VERSION e gera o APK release.

set "VERSION_FILE=%PROJECT_DIR%\..\navitools\modulos\App_financeiro\version.txt"
set "DEFAULT_VERSION=0.0.0.11"

if not exist "%VERSION_FILE%" (
  echo %DEFAULT_VERSION%>"%VERSION_FILE%"
)

set "VERSION=%DEFAULT_VERSION%"
for /f "usebackq delims=" %%v in ("%VERSION_FILE%") do set "VERSION=%%v"
if "%VERSION%"=="" set "VERSION=%DEFAULT_VERSION%"

for /f "tokens=1-4 delims=." %%a in ("%VERSION%") do (
  set "MAJ=%%a"
  set "MIN=%%b"
  set "PATCH=%%c"
  set "BUILD=%%d"
)
if "!MIN!"=="" set "MIN=0"
if "!PATCH!"=="" set "PATCH=0"
if "!BUILD!"=="" set "BUILD=0"
set /a BUILD=!BUILD!+1

set "VERSION=!MAJ!.!MIN!.!PATCH!.!BUILD!"
echo !VERSION!>"%VERSION_FILE%"

echo Versao gerada automaticamente: !VERSION!

set "APP_VERSION=!VERSION!"
echo Versao gravada em %VERSION_FILE%

:: Usar um PUB_CACHE local (evita quebrar por cache global corrompido)
set "PUB_CACHE=%PROJECT_DIR%\.pub-cache"
if not exist "%PUB_CACHE%" (
  mkdir "%PUB_CACHE%" >nul 2>nul
)

:: Remover metadados gerados para garantir que o pub gere package_config apontando para o PUB_CACHE local
if exist "%PROJECT_DIR%\.dart_tool" (
  call cmd /c rmdir /s /q "%PROJECT_DIR%\.dart_tool"
)
if exist "%PROJECT_DIR%\.flutter-plugins" (
  del /f /q "%PROJECT_DIR%\.flutter-plugins" >nul 2>nul
)
if exist "%PROJECT_DIR%\.flutter-plugins-dependencies" (
  del /f /q "%PROJECT_DIR%\.flutter-plugins-dependencies" >nul 2>nul
)

:: Limpa artefatos locais para garantir que o package_config aponte pro PUB_CACHE local
echo Rodando flutter clean...
call flutter clean
if errorlevel 1 (
  echo flutter clean falhou. Verifique o log acima.
  exit /b 1
)

:: Forçar recache do flutter_secure_storage se estiver corrompido (funciona mesmo chamando via PowerShell)
set "FSS_DIR=%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\flutter_secure_storage-9.2.4"
if exist "%FSS_DIR%" (
  echo Limpando cache corrompido de flutter_secure_storage... "%FSS_DIR%"
  call cmd /c rmdir /s /q "%FSS_DIR%"
)
set "FSS_DIR2=%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\flutter_secure_storage_*"
call cmd /c rmdir /s /q "%FSS_DIR2%" 2>nul
set "FSS_DIR3=C:\flutter\flutter\.pub-cache\hosted\pub.dev\flutter_secure_storage*"
call cmd /c rmdir /s /q "%FSS_DIR3%" 2>nul

echo Rodando flutter pub get...
call flutter pub get
if errorlevel 1 (
  echo flutter pub get falhou. Verifique o log acima.
  exit /b 1
)

echo Iniciando build do APK...
call flutter build apk --release
if errorlevel 1 (
  echo Build falhou. Verifique o log acima.
  exit /b 1
)

:: Validar se o APK realmente foi gerado
set "APK_PATH=%PROJECT_DIR%\build\app\outputs\flutter-apk\app-release.apk"
if not exist "%APK_PATH%" (
  echo Build finalizou, mas o APK nao foi encontrado em: %APK_PATH%
  exit /b 1
)

echo Concluido. APK gerado em build\app\outputs\flutter-apk\

endlocal
