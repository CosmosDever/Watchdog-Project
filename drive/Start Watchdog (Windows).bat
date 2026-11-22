@echo off
title Watchdog
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher\start-kali.ps1" -Mode gui
if errorlevel 1 pause
