@echo off
title Hodophylax
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher\run.ps1" -Mode gui
if errorlevel 1 pause
