@echo off
chcp 65001 >nul
title Instalador Multi-Modos Winget PRO - GUI
set "SCRIPT_PATH=%~dp0Instalador_Winget_GUI_v1.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=[IO.File]::ReadAllText('%SCRIPT_PATH%',[Text.Encoding]::UTF8); $sb=[ScriptBlock]::Create($c); & $sb -LocalPath '%SCRIPT_PATH%'"
