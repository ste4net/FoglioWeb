@echo off
rem Installa la CLI di Foglio con un doppio clic (Windows). Nessuna cartella da scegliere, nessuna shell da aprire.
rem Facoltativi: installa-foglio.cmd <nome-ia>   (es. claude-code, codex)
rem Le variabili FOGLIO_AGENT, FOGLIO_URL, FOGLIO_ANON_KEY, FOGLIO_CLI_BASE si possono impostare qui sotto con `set`.
setlocal
if not "%~1"=="" set "FOGLIO_AGENT=%~1"
if "%FOGLIO_CLI_BASE%"=="" set "FOGLIO_CLI_BASE=https://foglio.online/cli"
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm '%FOGLIO_CLI_BASE%/install.ps1' | iex"
echo.
pause
