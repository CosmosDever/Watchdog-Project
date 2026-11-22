# Starts a guest system VM from this drive on Windows.
# Each vm\<name>-amd64 folder holding a .qcow2 is an OS option; pick with -Os or at the prompt.
param(
    [ValidateSet('gui', 'ssh')] [string]$Mode = 'gui',
    [string]$Os = '',
    [int]$MemoryMB = 0,
    [int]$Cpus = 0,
    [int]$SshPort = 2222,
    [string]$MonitorPipe = '',
    [switch]$Snapshot,
    [switch]$SkipPreflight
)
$ErrorActionPreference = 'Stop'

if (-not $SkipPreflight) {
    . (Join-Path $PSScriptRoot 'preflight.ps1')
    if (-not (Invoke-Preflight -For kali)) { exit 1 }
}

$root = Split-Path -Parent $PSScriptRoot
$bin  = Join-Path $root 'runtime\windows-x64\ucrt64\bin'
$qemu = Join-Path $bin 'qemu-system-x86_64.exe'
if (-not (Test-Path -LiteralPath $qemu)) { throw "QEMU not found: $qemu" }

# Discover bootable systems: a vm\<name> folder with a .qcow2. Windows runs amd64/x86 images.
$systems = @(Get-ChildItem -LiteralPath (Join-Path $root 'vm') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $q = Get-ChildItem -LiteralPath $_.FullName -Filter '*.qcow2' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($q -and $_.Name -match 'amd64|x86|x64') { [pscustomobject]@{ Name = $_.Name; Disk = $q.FullName } }
})
if ($systems.Count -eq 0) { throw 'No bootable system found. Expected a .qcow2 under vm\<name>-amd64\.' }

if ($Os) {
    $selected = $systems | Where-Object Name -eq $Os | Select-Object -First 1
    if (-not $selected) { throw "System not found: $Os" }
} elseif ($systems.Count -eq 1) {
    $selected = $systems[0]
} else {
    Write-Host 'Choose a system to boot:'
    for ($i = 0; $i -lt $systems.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $systems[$i].Name) }
    $pick = [int](Read-Host 'Number')
    if ($pick -lt 1 -or $pick -gt $systems.Count) { throw 'Invalid choice.' }
    $selected = $systems[$pick - 1]
}
$disk = Get-Item -LiteralPath $selected.Disk

$totalMB = [int]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
$logical = [int](Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
if ($MemoryMB -le 0) { $MemoryMB = [math]::Max(2048, [math]::Min(6144, [int]($totalMB * 0.4))) }
if ($Cpus -le 0)     { $Cpus = [math]::Max(2, [math]::Min(6, [int]($logical / 2))) }

if (Get-NetTCPConnection -State Listen -LocalPort $SshPort -ErrorAction SilentlyContinue) {
    throw "Port $SshPort is already in use. Is a VM already running?"
}

$qemuArgs = @(
    '-name', "Watchdog - $($selected.Name)",
    '-machine', 'q35',
    '-accel', 'whpx,kernel-irqchip=off',
    '-accel', 'tcg,thread=multi',
    '-cpu', 'qemu64,-svm,+ssse3,+sse4.1,+sse4.2,+popcnt',
    '-smp', "$Cpus",
    '-m', "$MemoryMB",
    '-drive', "file=$($disk.FullName),if=virtio,format=qcow2,cache=writeback,discard=unmap",
    '-netdev', "user,id=net0,tftp=$(Join-Path $root 'launcher\guest'),hostfwd=tcp:127.0.0.1:$SshPort-:22",
    '-device', 'virtio-net-pci,netdev=net0',
    '-device', 'qemu-xhci',
    '-device', 'usb-tablet',
    '-device', 'virtio-rng-pci'
)
$qemuArgs += @('-device', 'virtio-vga', '-display', 'none')

# Shared data disk: the same /data in every OS and on every host. One VM at a time.
# A problem here must never stop the VM from starting.
$dataDisk = Join-Path $root 'shared\data.qcow2'
if (-not (Test-Path -LiteralPath $dataDisk)) {
    $qemuImg = Join-Path $bin 'qemu-img.exe'
    if (Test-Path -LiteralPath $qemuImg) {
        try {
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dataDisk)
            & $qemuImg create -f qcow2 $dataDisk 100G | Out-Null
        } catch { Write-Host "Could not create the shared data disk: $_" -ForegroundColor Yellow }
    }
}
if (Test-Path -LiteralPath $dataDisk) {
    $qemuArgs += @(
        '-drive', "file=$dataDisk,if=none,id=data0,format=qcow2,cache=writeback,discard=unmap",
        '-device', 'virtio-blk-pci,drive=data0,serial=watchdog-data'
    )
}
if ($Snapshot) { $qemuArgs += '-snapshot'; Write-Host 'Snapshot mode: changes are discarded on exit.' }

Write-Host "System: $($selected.Name)  ($Mode mode, $Cpus CPUs, $MemoryMB MB RAM)" -ForegroundColor Cyan
Write-Host "SSH:    ssh <user>@127.0.0.1 -p $SshPort"
Write-Host 'Shut down the VM before unplugging the drive.' -ForegroundColor Yellow

# A warm reboot can hang under WHPX, so each guest reboot becomes a full stop and start.
$traceLog = Join-Path $env:TEMP 'watchdog-qemu.trace'
$qemuArgs += @('-no-reboot', '-D', $traceLog, '-trace', 'enable=qemu_system_shutdown_request')

# With -no-reboot, a reset exits cleanly without a shutdown request. Power-off and quit log one.
function Test-GuestReboot([int]$ExitCode) {
    if ($ExitCode -ne 0) { return $false }
    $line = Get-Content -LiteralPath $traceLog -ErrorAction SilentlyContinue |
        Where-Object { $_ -match 'qemu_system_shutdown_request' } | Select-Object -First 1
    return (-not $line)
}

if ($Mode -eq 'ssh') {
    if ($MonitorPipe) { $qemuArgs += @('-monitor', "tcp:127.0.0.1:$MonitorPipe,server,nowait") }
    do {
        Remove-Item -LiteralPath $traceLog -ErrorAction SilentlyContinue
        & $qemu @qemuArgs
        $code = $LASTEXITCODE
        $again = Test-GuestReboot $code
        if ($again) { Write-Host 'Restarting...' }
    } while ($again)
    exit $code
}

function Test-PortListening([int]$Port) {
    [bool](Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Send-VmCommand([int]$Port, [string]$Command) {
    $client = New-Object Net.Sockets.TcpClient('127.0.0.1', $Port)
    try {
        $writer = New-Object IO.StreamWriter($client.GetStream())
        $writer.AutoFlush = $true
        Start-Sleep -Milliseconds 300
        $writer.WriteLine($Command)
        Start-Sleep -Milliseconds 500
    } finally { $client.Close() }
}

$viewer = Join-Path $bin 'remote-viewer.exe'
if (-not (Test-Path -LiteralPath $viewer)) { throw "SPICE viewer not found: $viewer" }
$spicePort = 5930..5939 | Where-Object { -not (Test-PortListening $_) } | Select-Object -First 1
if (-not $spicePort) { throw 'No free display port between 5930 and 5939.' }
$monitorPort = if ($MonitorPipe) { [int]$MonitorPipe } else { 45450 }
if (Test-PortListening $monitorPort) { throw "Port $monitorPort is already in use. Is a VM already running?" }

$qemuArgs += @(
    '-spice', "port=$spicePort,addr=127.0.0.1,disable-ticketing=on",
    '-device', 'virtio-serial-pci',
    '-chardev', 'spicevmc,id=vdagent,name=vdagent',
    '-device', 'virtserialport,chardev=vdagent,name=com.redhat.spice.0',
    '-monitor', "tcp:127.0.0.1:$monitorPort,server,nowait"
)
$quoted = ($qemuArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
$stdout = Join-Path $env:TEMP 'watchdog-qemu.out'
$stderr = Join-Path $env:TEMP 'watchdog-qemu.err'
do {
    Remove-Item -LiteralPath $traceLog -ErrorAction SilentlyContinue
    $vm = Start-Process -FilePath $qemu -ArgumentList $quoted -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $null = $vm.Handle  # Keeps ExitCode readable after the process ends.

    for ($i = 0; $i -lt 60 -and -not $vm.HasExited -and -not (Test-PortListening $spicePort); $i++) {
        Start-Sleep -Milliseconds 500
    }
    if ($vm.HasExited -or -not (Test-PortListening $spicePort)) {
        Get-Content -LiteralPath $stderr -ErrorAction SilentlyContinue | Write-Host
        if (-not $vm.HasExited) { Stop-Process -Id $vm.Id -Force }
        throw 'The system could not start.'
    }

    while (-not $vm.HasExited) {
        $window = Start-Process -FilePath $viewer -PassThru -ArgumentList @(
            '--title', "`"Watchdog - $($selected.Name)`"", '--auto-resize=always', "spice://127.0.0.1:$spicePort")
        while (-not $window.HasExited -and -not $vm.HasExited) { Start-Sleep -Milliseconds 500 }
        if ($vm.HasExited) {
            if (-not $window.HasExited) { Stop-Process -Id $window.Id -Force }
            break
        }

        Write-Host "`nThe window was closed, but the VM is still running." -ForegroundColor Yellow
        $answer = Read-Host 'Press Enter to reopen it, or type S to shut the VM down'
        if ($answer -match '^[sS]') {
            Send-VmCommand $monitorPort 'system_powerdown'
            Write-Host 'Shutting down. Wait for this window to close...'
            if (-not $vm.WaitForExit(120000)) {
                Write-Host 'Not down yet. Reopening so you can shut it down inside the VM.' -ForegroundColor Yellow
            }
        }
    }

    $vm.WaitForExit()
    $again = Test-GuestReboot $vm.ExitCode
    if ($again) {
        Write-Host 'Restarting...'
        for ($i = 0; $i -lt 20 -and (Test-PortListening $spicePort); $i++) { Start-Sleep -Milliseconds 500 }
    }
} while ($again)
Write-Host 'The VM has shut down.'
exit 0
