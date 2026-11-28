@echo off
title Hodophylax AI
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher\start-llm.ps1"
if errorlevel 1 pause
