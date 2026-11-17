@echo off
rem Ventania - inicia o servidor completo: meta-servidor (contas, lobby, passe, loja)
rem + servidor de partida (salas com bots). Precisa do Python 3.11+ (python.org, marque "Add to PATH").
cd /d "%~dp0"
if "%SALAS%"=="" set SALAS=2
if "%BOTS%"=="" set BOTS=16
if "%PORTA%"=="" set PORTA=24800
if "%PORTA_META%"=="" set PORTA_META=8080
where python >nul 2>nul || (echo ERRO: instale o Python 3.11 ou mais novo e marque "Add python.exe to PATH". & pause & exit /b 1)
if not exist dados mkdir dados
if not exist logs mkdir logs
if not exist dados\segredo.txt python -c "import secrets; print(secrets.token_urlsafe(24))" > dados\segredo.txt
set /p SEGREDO=<dados\segredo.txt
set VENTANIA_SEGREDO=%SEGREDO%
set VENTANIA_DB=%CD%\dados\meta.sqlite3
set VENTANIA_PORT=%PORTA_META%
start "Ventania - meta-servidor" /min cmd /c "cd meta && python -m meta_server > ..\logs\meta.log 2>&1"
timeout /t 3 /nobreak >nul
start "Ventania - partida" /min cmd /c "VentaniaServidor.console.exe --headless -- --servidor --salas=%SALAS% --bots=%BOTS% --porta=%PORTA% --meta=http://127.0.0.1:%PORTA_META% --segredo=%SEGREDO% --relatorio=60 %EXTRA% > logs\partida.log 2>&1"
echo Ventania no ar!
echo   Nos aparelhos: Configuracoes - Servidor - http://IP-DESTE-PC:%PORTA_META%
echo   Libere no firewall: TCP %PORTA_META% e UDP %PORTA% (e as salas seguintes)
echo   IP deste PC (procure "IPv4"):
ipconfig | findstr /i "IPv4"
echo   Para desligar: feche as janelas "Ventania - ..." ou rode parar.bat
pause
