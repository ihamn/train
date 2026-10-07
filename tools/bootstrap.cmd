@echo off
rem bootstrap.cmd - double-clickable wrapper for tools\bootstrap.ps1
rem Restores the dev toolchain after switching cloud instances:
rem tools live on D: (persistent), get projected onto C: + added to user PATH.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" %*
echo.
pause
