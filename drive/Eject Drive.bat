@echo off
rem Safely eject the Watchdog drive this file lives on. Double-click to run.
set "DRV=%~d0"
echo.
echo Ejecting drive %DRV% ...
echo (If this fails, close the Kali VM window and the AI "start-llm" window first.)
echo.
rem Move off the drive so this window does not hold it open.
cd /d "%SystemDrive%\"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d='%DRV%'; $L=$d.TrimEnd(':'); try{ Write-VolumeCache -DriveLetter $L -ErrorAction SilentlyContinue }catch{}; $sh=New-Object -ComObject Shell.Application; $v=$sh.Namespace(17).ParseName($d); if(-not $v){ $v=$sh.Namespace(17).ParseName($d+'\') }; if($v){ $v.InvokeVerb('Eject') }; Start-Sleep -Seconds 2; if(Test-Path ($d+'\')){ Write-Host 'Could NOT eject - something is still using the drive. Close the Kali VM window and the AI (start-llm) window, then run this again.' -ForegroundColor Yellow }else{ Write-Host 'Done. The drive is safe to unplug.' -ForegroundColor Green }"
echo.
pause
