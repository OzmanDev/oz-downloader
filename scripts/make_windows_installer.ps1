# Windows Installer Build Script (PowerShell)
# Builds the Vite React frontend, compiles Electron main/preload, and packages into NSIS installer.
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$WinDir = Join-Path $Root "windows"

Set-Location $WinDir

# Node installers often update Machine/User PATH without refreshing this shell.
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

function Find-Npm {
    # Prefer npm.cmd — PowerShell's npm.ps1 shim is blocked under Restricted execution policy.
    $candidates = @(
        (Join-Path ${env:ProgramFiles} "nodejs\npm.cmd"),
        (Join-Path ${env:ProgramFiles(x86)} "nodejs\npm.cmd"),
        (Join-Path $env:LOCALAPPDATA "Programs\nodejs\npm.cmd"),
        (Join-Path $env:APPDATA "nvm\nodejs\npm.cmd")
    )
    foreach ($path in $candidates) {
        if ($path -and (Test-Path $path)) { return $path }
    }

    $cmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notlike "*.ps1") { return $cmd.Source }
    return $null
}

$Npm = Find-Npm
if (-not $Npm) {
    Write-Host "ERROR: npm.cmd was not found."
    Write-Host ""
    Write-Host "Install Node.js LTS from https://nodejs.org (check 'Add to PATH')."
    Write-Host "If 'npm -v' fails with Execution Policy, either use npm.cmd or run:"
    Write-Host "  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
    Write-Host ""
    Write-Host "Verify with:  node -v   and   npm.cmd -v"
    Write-Host "Then re-run:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File .\scripts\make_windows_installer.ps1"
    exit 1
}

Write-Host "==> Using npm: $Npm"

Write-Host "==> Bundling Windows embedded runtime if missing"
$RuntimeDir = Join-Path $WinDir "resources\runtime"
$RuntimeExe = Join-Path $RuntimeDir "python.exe"
$RuntimePost = Join-Path $RuntimeDir "zotify-postprocess.py"
$RuntimeFFmpeg = Join-Path $RuntimeDir "ffmpeg.exe"
if (-not (Test-Path $RuntimeExe) -or -not (Test-Path $RuntimePost) -or -not (Test-Path $RuntimeFFmpeg)) {
    & (Join-Path $Root "scripts\bundle_windows_runtime.ps1")
}

Write-Host "==> Installing Node dependencies"
& $Npm install

Write-Host "==> Compiling React UI and Electron processes"
& $Npm run build:all

Write-Host "==> Generating Windows NSIS Installer (OzDownloader-Installer.exe)"
if (-not (Test-Path $RuntimeExe) -or -not (Test-Path $RuntimePost) -or -not (Test-Path $RuntimeFFmpeg)) {
    Write-Host "ERROR: Windows runtime is incomplete under $RuntimeDir"
    Write-Host "Run scripts\bundle_windows_runtime.ps1 on Windows first."
    exit 1
}
& $Npm run dist:win

Write-Host "==> Ready!"
Write-Host "Installer created at: windows\dist-installer\OzDownloader-Installer.exe"
