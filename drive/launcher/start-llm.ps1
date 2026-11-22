# Starts the local LLM on this computer. It listens on 127.0.0.1 only.
# Models whose tool calls need translation (e.g. WhiteRabbitNeo) are served through
# a small proxy so agents like OpenCode get proper tool_calls. Qwen runs directly.
param(
    [string]$Model = '',
    [int]$Port = 8080,
    [int]$ContextSize = 16384,
    [int]$GpuLayers = -1,
    [ValidateSet('auto', 'on', 'off')] [string]$Shim = 'auto',
    [switch]$SkipPreflight
)
$ErrorActionPreference = 'Stop'

if (-not $SkipPreflight) {
    . (Join-Path $PSScriptRoot 'preflight.ps1')
    if (-not (Invoke-Preflight -For llm)) { exit 1 }
}

$root   = Split-Path -Parent $PSScriptRoot
$server = Join-Path $root 'llm\runtime\windows-x64\llama-server.exe'
$proxy  = Join-Path $root 'llm\proxy\toolshim.py'
$models = @(Get-ChildItem -LiteralPath (Join-Path $root 'llm\models') -Filter '*.gguf' | Sort-Object Name)

# Models that print tool calls as plain JSON and need the shim to work as an agent.
$shimModels = @('WhiteRabbitNeo', 'DeepHat')

if (-not (Test-Path -LiteralPath $server)) { throw "llama-server not found: $server" }
if ($models.Count -eq 0) { throw 'No .gguf model found in llm\models.' }

if ($Model) {
    $selected = $models | Where-Object Name -eq $Model | Select-Object -First 1
    if (-not $selected) { throw "Model not found: $Model" }
} elseif ($models.Count -eq 1) {
    $selected = $models[0]
} else {
    for ($i = 0; $i -lt $models.Count; $i++) {
        Write-Host ("[{0}] {1} ({2:N1} GB)" -f ($i + 1), $models[$i].Name, ($models[$i].Length / 1GB))
    }
    $choice = [int](Read-Host 'Choose a model')
    if ($choice -lt 1 -or $choice -gt $models.Count) { throw 'Invalid choice.' }
    $selected = $models[$choice - 1]
}

$useShim = switch ($Shim) {
    'on'  { $true }
    'off' { $false }
    default { [bool]($shimModels | Where-Object { $selected.Name -like "*$_*" }) }
}

# Performance: offload all layers to GPU, flash attention on, threads = physical cores.
$cores = [int](Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum
if ($cores -lt 1) { $cores = 4 }
$perf = @('-fa', 'on', '-t', "$cores")
$common = @('-m', $selected.FullName, '--alias', 'local', '-c', "$ContextSize", '--jinja') + $perf
if ($GpuLayers -ge 0) { $common += @('-ngl', "$GpuLayers") }

function Test-Port([int]$p) { [bool](Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue) }
if (Test-Port $Port) { throw "Port $Port is already in use. Is the LLM already running?" }

Write-Host "Model: $($selected.Name)"
Write-Host "API:   http://127.0.0.1:$Port/v1 (from Kali: http://10.0.2.2:$Port/v1)"
Write-Host "Perf:  GPU offload, flash-attn on, $cores threads, context $ContextSize"

if (-not $useShim) {
    Write-Host 'Mode:  direct'
    & $server @common --host 127.0.0.1 --port $Port
    exit $LASTEXITCODE
}

# Shim mode: backend on Port+1, translation proxy on Port.
$backendPort = $Port + 1
if (Test-Port $backendPort) { throw "Port $backendPort is already in use." }
$python = Join-Path $root 'llm\runtime\python-win\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    $python = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $python) { throw 'Python not found. Needed for the tool-call proxy.' }
}
Write-Host "Mode:  tool-call proxy (backend on $backendPort)"

$log = Join-Path $env:TEMP 'kali-portable-llm.err'
$backend = Start-Process -FilePath $server -ArgumentList ($common + @('--host', '127.0.0.1', '--port', "$backendPort")) `
    -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $env:TEMP 'kali-portable-llm.out') -RedirectStandardError $log
try {
    for ($i = 0; $i -lt 120 -and -not $backend.HasExited; $i++) {
        Start-Sleep -Milliseconds 500
        try { if ((Invoke-RestMethod "http://127.0.0.1:$backendPort/health" -TimeoutSec 2).status -eq 'ok') { break } } catch {}
    }
    if ($backend.HasExited) { Get-Content $log -Tail 10 -ErrorAction SilentlyContinue | Write-Host; throw 'The model backend failed to start.' }
    Write-Host 'Ready. Press Ctrl+C to stop.'
    & $python -I $proxy --listen "127.0.0.1:$Port" --backend "127.0.0.1:$backendPort"
}
finally {
    if ($backend -and -not $backend.HasExited) { Stop-Process -Id $backend.Id -Force -ErrorAction SilentlyContinue }
}
exit 0
