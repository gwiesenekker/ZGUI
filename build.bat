@echo off
rem SCU-style PowerShell entry point; retain cmd-only support for minimal hosts.
where powershell.exe >nul 2>nul
if errorlevel 1 goto cmdonly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
exit /b %errorlevel%
:cmdonly
call "%~dp0tools\build_zgui.cmd" %*
exit /b %errorlevel%
