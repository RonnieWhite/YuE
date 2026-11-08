@echo off
rem YuE2 launcher: bypass PowerShell execution policy for run.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
exit /b %ERRORLEVEL%
