# One-command startup for Windows: checks the machine, offers the local AI, then opens Kali.
param([ValidateSet('gui', 'ssh')] [string]$Mode = 'gui')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'preflight.ps1')

Write-Host '==================== Hodophylax ====================' -ForegroundColor Cyan

# If the drive has no runtime / VM / model yet, offer to download and install them.
$driveRoot = Split-Path -Parent $PSScriptRoot
$hasQemu  = Test-Path (Join-Path $driveRoot 'runtime\windows-x64\ucrt64\bin\qemu-system-x86_64.exe')
$hasVm    = @(Get-ChildItem -LiteralPath (Join-Path $driveRoot 'vm') -Recurse -Filter '*.qcow2' -ErrorAction SilentlyContinue).Count -gt 0
$hasModel = @(Get-ChildItem -LiteralPath (Join-Path $driveRoot 'llm\models') -Filter '*.gguf' -ErrorAction SilentlyContinue).Count -gt 0
if (-not ($hasQemu -and $hasVm -and $hasModel)) {
    Write-Host 'This drive is not set up yet (no VM, model, or runtime found).' -ForegroundColor Yellow
    $prov = Join-Path $driveRoot 'setup\provision.ps1'
    if (Test-Path -LiteralPath $prov) {
        if ((Read-Host 'Download and install Kali + the default model now? (~6 GB) [Y/n]') -notmatch '^[nN]') {
            & $prov
            if ($LASTEXITCODE -ne 0) { Read-Host 'Setup failed. Press Enter to close'; exit 1 }
        } else {
            Write-Host 'Set it up later with:  setup\provision.ps1'; exit 0
        }
    } else {
        Write-Host 'Run the provisioner to set it up:  setup\provision.ps1' -ForegroundColor Yellow
        Read-Host 'Press Enter to close'; exit 1
    }
}

if (-not (Invoke-Preflight -For kali)) { Read-Host 'Press Enter to close'; exit 1 }

Write-Host ''
Write-Host 'AI backend for this session:'
Write-Host '  [1] Local model  - runs on this PC GPU, private and offline'
Write-Host '  [2] Cloud API    - Claude / OpenAI / OpenRouter, set your key inside Kali'
Write-Host '  [3] None'
$choice = Read-Host 'Choose [1/2/3]'
switch ($choice) {
    '2' {
        Write-Host 'Cloud API: after Kali opens, set your key and run the agent, e.g.' -ForegroundColor Green
        Write-Host '  export ANTHROPIC_API_KEY=...   then   hodo   (use /models to pick)' -ForegroundColor Green
        Write-Host 'The local model server will not be started.'
    }
    '3' { Write-Host 'No AI backend started.' }
    default {
        if (Invoke-Preflight -For llm) {
            Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', (Join-Path $PSScriptRoot 'start-llm.ps1'), '-SkipPreflight')
            Write-Host 'The local AI is starting in its own window. Pick a model there.' -ForegroundColor Green
            Start-Sleep -Seconds 2
        } else {
            Write-Host 'Skipping the local AI: this machine is not ready for it.' -ForegroundColor Yellow
        }
    }
}

Write-Host 'Opening Kali...' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'start-kali.ps1') -Mode $Mode -SkipPreflight
exit $LASTEXITCODE
