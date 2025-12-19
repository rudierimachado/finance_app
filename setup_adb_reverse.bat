@echo off
echo ========================================
echo Configurando ADB Reverse para Backend
echo ========================================
echo.
echo Este script mapeia a porta 5000 do PC para o celular via USB
echo Assim o celular pode acessar localhost:5000
echo.

REM Tenta encontrar ADB no Flutter SDK
set ADB_PATH=C:\flutter\flutter\bin\cache\dart-sdk\bin\resources\devtools\adb.exe

REM Se não encontrar, tenta caminho alternativo
if not exist "%ADB_PATH%" (
    set ADB_PATH=C:\Users\%USERNAME%\AppData\Local\Android\Sdk\platform-tools\adb.exe
)

REM Verifica se encontrou o ADB
if not exist "%ADB_PATH%" (
    echo [ERRO] ADB nao encontrado!
    echo.
    echo Por favor, execute manualmente:
    echo 1. Abra o terminal onde o Flutter esta instalado
    echo 2. Execute: flutter\bin\cache\dart-sdk\bin\resources\devtools\adb.exe reverse tcp:5000 tcp:5000
    echo.
    echo OU instale o Android SDK Platform Tools
    pause
    exit /b 1
)

echo Usando ADB em: %ADB_PATH%
echo.

REM Lista dispositivos conectados
echo Dispositivos conectados:
"%ADB_PATH%" devices
echo.

REM Configura o reverse
echo Configurando reverse port forwarding...
"%ADB_PATH%" reverse tcp:5000 tcp:5000

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [SUCESSO] Porta 5000 mapeada com sucesso!
    echo.
    echo Agora o celular pode acessar localhost:5000
    echo Execute: flutter run
) else (
    echo.
    echo [ERRO] Falha ao configurar reverse port
    echo.
    echo Verifique se:
    echo 1. O celular esta conectado via USB
    echo 2. A depuracao USB esta ativada no celular
    echo 3. Voce autorizou a depuracao USB no celular
)

echo.
pause
