# Checks that this Windows machine can run the portable Kali / AI setup.
# Returns $true if it is safe to continue, $false on a hard blocker.
# Soft issues (slow without GPU or virtualization) print a warning but still return $true.
function Invoke-Preflight {
    param([Parameter(Mandatory)][ValidateSet('kali', 'llm')] [string]$For)

    $root = Split-Path -Parent $PSScriptRoot
    $ok = $true
    Write-Host "Checking this computer..." -ForegroundColor Cyan

    function Good($m) { Write-Host "  [ok]   $m" -ForegroundColor Green }
    function Warn($m) { Write-Host "  [warn] $m" -ForegroundColor Yellow }
    function Bad($m)  { Write-Host "  [stop] $m" -ForegroundColor Red }

    # Architecture: the bundled binaries are x64.
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'AMD64') { Good "64-bit x64 Windows" }
    elseif ($arch -eq 'ARM64') { Warn "ARM Windows: runs through emulation and will be slow." }
    else { Bad "Unsupported CPU architecture ($arch)."; $ok = $false }

    # Memory
    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    if ($ramGB -ge 8) { Good "RAM ${ramGB} GB" }
    elseif ($ramGB -ge 5) { Warn "RAM ${ramGB} GB: close other apps; run Kali and the AI one at a time." }
    else { Bad "RAM ${ramGB} GB is too low to run this comfortably."; $ok = $false }

    # Free space on the SSD
    $drive = (Split-Path -Qualifier $root).TrimEnd(':')
    $freeGB = [math]::Round((Get-Volume -DriveLetter $drive).SizeRemaining / 1GB, 1)
    if ($freeGB -ge 10) { Good "Free space ${freeGB} GB on $drive`:" }
    else { Warn "Only ${freeGB} GB free on $drive`: - the VM needs room to grow." }

    if ($For -eq 'kali') {
        foreach ($need in @('runtime\windows-x64\ucrt64\bin\qemu-system-x86_64.exe',
                            'runtime\windows-x64\ucrt64\bin\remote-viewer.exe')) {
            if (Test-Path -LiteralPath (Join-Path $root $need)) { Good ("$(Split-Path $need -Leaf) is on the SSD") }
            else { Bad "Missing bundled file: $need"; $ok = $false }
        }
        $virt = (Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled
        $hyp  = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
        if ($virt -or $hyp) { Good "Hardware virtualization available (fast mode)" }
        else { Warn "Virtualization is off in BIOS/UEFI. Kali will run but slowly. Enable Intel VT-x / AMD-V in firmware for full speed." }
    }

    if ($For -eq 'llm') {
        $server = Join-Path $root 'llm\runtime\windows-x64\llama-server.exe'
        if (Test-Path -LiteralPath $server) { Good "llama-server is on the SSD" } else { Bad "Missing llama-server."; $ok = $false }
        if (Test-Path -LiteralPath (Join-Path $root 'llm\runtime\python-win\python.exe')) { Good "Portable Python is on the SSD" }
        else { Warn "Portable Python missing; WhiteRabbitNeo needs it. Qwen will still work." }
        if (@(Get-ChildItem -LiteralPath (Join-Path $root 'llm\models') -Filter '*.gguf' -ErrorAction SilentlyContinue).Count -gt 0) { Good "At least one model is present" }
        else { Bad "No .gguf model found in llm\models."; $ok = $false }
        try {
            $dev = (& $server --list-devices 2>&1) -join ' '
            if ($dev -match 'Vulkan|CUDA|GPU') { Good "A GPU was detected (fast inference)" }
            else { Warn "No GPU detected; the model will run on CPU and be slow." }
        } catch { Warn "Could not check the GPU." }
    }

    if ($ok) { Write-Host "Ready to start.`n" -ForegroundColor Green }
    else { Write-Host "`nCannot start: fix the [stop] items above.`n" -ForegroundColor Red }
    return $ok
}
