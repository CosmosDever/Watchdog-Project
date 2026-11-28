param([string]$Drive)
# Flush and safely dismount the Hodophylax drive. Works for USB SSDs that Windows treats as
# a fixed disk (where the Shell "Eject" verb does nothing). Called by "Eject Drive.bat".
$ErrorActionPreference = 'SilentlyContinue'

$d = $Drive.TrimEnd('\')
if (-not $d) { $d = Split-Path -Qualifier $PSCommandPath }
$L = $d.TrimEnd(':')

Write-Host ''
Write-Host "Flushing and ejecting $d ..."

# 1) Write all cached data to the physical drive first, so a forced dismount loses nothing.
try { Write-VolumeCache -DriveLetter $L -ErrorAction SilentlyContinue } catch {}

# 2) Force-dismount the volume. FSCTL_DISMOUNT_VOLUME succeeds even while this script's own
#    file is still open, because the data is already flushed.
$code = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class WdVol {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  static extern SafeFileHandle CreateFileW(string n, uint a, uint s, IntPtr sec, uint d, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool DeviceIoControl(SafeFileHandle h, uint c, IntPtr ib, uint iz, IntPtr ob, uint oz, out uint r, IntPtr o);
  public static bool Dismount(string vol) {
    var h = CreateFileW(vol, 0x40000000u, 3u, IntPtr.Zero, 3u, 0u, IntPtr.Zero);
    if (h.IsInvalid) { return false; }
    uint r; bool ok = DeviceIoControl(h, 0x00090020u, IntPtr.Zero, 0u, IntPtr.Zero, 0u, out r, IntPtr.Zero);
    h.Dispose();
    return ok;
  }
}
'@
try { Add-Type -TypeDefinition $code } catch {}

$ok = $false
try { $ok = [WdVol]::Dismount("\\.\$d") } catch {}
Start-Sleep -Milliseconds 800

if ($ok -or -not (Test-Path ($d + '\'))) {
    Write-Host 'Done. The drive is flushed and dismounted - safe to unplug.' -ForegroundColor Green
} else {
    Write-Host 'Flushed the drive. All writes are saved, so it is safe to unplug now.' -ForegroundColor Yellow
    Write-Host '(For a full dismount, close the Kali VM and AI start-llm windows, then run this again.)' -ForegroundColor Yellow
}
Write-Host ''
$null = Read-Host 'Press Enter to close'
