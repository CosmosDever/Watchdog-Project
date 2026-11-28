@echo off
title Hodophylax SSH
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher\start-kali.ps1" -Mode ssh
if errorlevel 1 pause
