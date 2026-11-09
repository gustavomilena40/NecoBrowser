@echo off
rem Compila e roda os testes do nucleo (src\core) em Win64.
rem Saida em tests\Win64 (fora do Git). Codigo de saida = numero de falhas.
setlocal
set BDSBIN=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin
cd /d "%~dp0"
if not exist Win64\dcu mkdir Win64\dcu
"%BDSBIN%\dcc64.exe" -B -Q -W+ -EWin64 -NUWin64\dcu -NSSystem;Winapi CoreTests.dpr
if errorlevel 1 exit /b 1
Win64\CoreTests.exe
exit /b %ERRORLEVEL%
