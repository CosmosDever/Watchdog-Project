# Hodophylax in-place provisioner (Windows). Lives on the drive at setup\.
# Downloads and hash-verifies QEMU, llama.cpp, Python, the agent engine, the OS image,
# and the models INTO this drive, reading config\hodophylax.json. Needs Python for the
# QEMU step. hodo-run offers to run this when the drive is not set up yet.
param([switch]$Yes)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot   # the drive root (parent of setup\)
$config = Join-Path $root 'config\hodophylax.json'
if (-not (Test-Path -LiteralPath $config)) { $config = Join-Path $root 'config\hodophylax.example.json' }
if (-not (Test-Path -LiteralPath $config)) { throw "No manifest found in $root\config\." }
$manifest = Get-Content -Raw -LiteralPath $config | ConvertFrom-Json

$LLAMA_BUILD = 'b12625'
$LLAMA_WIN   = @{ url = "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD/llama-$LLAMA_BUILD-bin-win-vulkan-x64.zip";
                  sha = 'c7cdd8cd414fa2613dfeacadd067287c921e626b849afc8e69da33d3a6516f2d' }
$PY_URL = 'https://www.python.org/ftp/python/3.13.3/python-3.13.3-embed-amd64.zip'
$OPENCODE_VER = 'v1.19.6'
$OPENCODE = @(
    @{ name = 'opencode-linux-x64.tar.gz';   sha = '47734e08968b30cc22a0bffb6d9feeed76ad4aa743213a12122040392d09a057' },
    @{ name = 'opencode-linux-arm64.tar.gz'; sha = '5b68c1f4c5e75b4134e664cc8f36d634d64208d4fcfe5bcf3b48bab699c2dbac' }
)

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw 'Python is required to provision on Windows (for the QEMU step). Install it from python.org, then run this again.'
}

Write-Host "This downloads about 6 GB (QEMU, llama.cpp, Kali, models) onto $root." -ForegroundColor Cyan
if (-not $Yes) { if ((Read-Host 'Continue? [Y/n]') -match '^[nN]') { Write-Host 'Cancelled.'; exit 0 } }

function Get-Verified($url, $path, $sha) {
    if ((Test-Path -LiteralPath $path) -and $sha -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() -eq $sha) {
        Write-Host "  cached $(Split-Path $path -Leaf)"; return
    }
    Write-Host "  downloading $(Split-Path $path -Leaf)..."
    curl.exe -fL --retry 5 --retry-delay 5 -C - -o $path $url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $url" }
    if ($sha) {
        $got = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
        if ($got -ne $sha) { Remove-Item -LiteralPath $path -Force; throw "HASH MISMATCH for $(Split-Path $path -Leaf)" }
    }
}

$dl = Join-Path $root '_downloads'
$osDir = Join-Path $root "vm\$($manifest.os.name)-$($manifest.os.arch)"
foreach ($d in @("$root\llm\models", "$root\llm\runtime\windows-x64", "$root\llm\runtime\python-win",
                 "$root\llm\runtime\macos", "$root\runtime\windows-x64", $osDir, "$root\shared", $dl)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

Write-Host 'QEMU + SPICE viewer (MSYS2)...' -ForegroundColor Cyan
python -I (Join-Path $PSScriptRoot 'fetch_qemu.py') (Join-Path $dl 'qemu-msys2') "$root\runtime\windows-x64"
if ($LASTEXITCODE -ne 0) { throw 'QEMU fetch failed.' }

Write-Host 'llama.cpp...' -ForegroundColor Cyan
Get-Verified $LLAMA_WIN.url "$dl\llama-win.zip" $LLAMA_WIN.sha
tar -xf "$dl\llama-win.zip" -C "$root\llm\runtime\windows-x64"

Write-Host 'Portable Python...' -ForegroundColor Cyan
Get-Verified $PY_URL "$dl\python-embed.zip" $null
Expand-Archive -LiteralPath "$dl\python-embed.zip" -DestinationPath "$root\llm\runtime\python-win" -Force

Write-Host 'Agent engine (OpenCode) for the guest...' -ForegroundColor Cyan
foreach ($oc in $OPENCODE) {
    Get-Verified "https://github.com/anomalyco/opencode/releases/download/$OPENCODE_VER/$($oc.name)" "$root\launcher\guest\$($oc.name)" $oc.sha
}

Write-Host "Guest OS image ($($manifest.os.name) $($manifest.os.arch))..." -ForegroundColor Cyan
$imgArchive = "$dl\os-image" + [IO.Path]::GetExtension($manifest.os.url)
Get-Verified $manifest.os.url $imgArchive $manifest.os.sha256
if ($manifest.os.type -eq 'qemu-image') { tar -xf $imgArchive -C $osDir }
else { Copy-Item $imgArchive "$osDir\" -Force; Write-Host '  iso-installer: run the system once in gui mode to install.' }

Write-Host 'Models...' -ForegroundColor Cyan
foreach ($m in $manifest.models) { Get-Verified $m.url "$root\llm\models\$($m.name)" $m.sha256 }

Write-Host "`nDone. This drive is ready. Run hodo-run from its root." -ForegroundColor Green
