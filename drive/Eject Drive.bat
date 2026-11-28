@echo off
rem Safely eject the Hodophylax drive this file lives on. Double-click to run.
rem Flush + force-dismount works even though this .bat lives on the drive being ejected.
set "DRV=%~d0"
set "EJPS=%~dp0launcher\eject-drive.ps1"
rem Move off the drive so this window holds it a little less.
cd /d "%SystemDrive%\"
powershell -NoProfile -ExecutionPolicy Bypass -File "%EJPS%" -Drive "%DRV%"
