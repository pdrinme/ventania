@echo off
rem Desliga o servidor de partida e o meta-servidor do Ventania
taskkill /fi "WINDOWTITLE eq Ventania - partida*" /t /f >nul 2>nul
taskkill /fi "WINDOWTITLE eq Ventania - meta-servidor*" /t /f >nul 2>nul
echo Ventania desligado.
pause
