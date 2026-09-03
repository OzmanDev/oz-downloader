# Windows Installer Build Script (PowerShell)
# Builds the Vite React frontend, compiles Electron main/preload, and packages into NSIS installer.
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$WinDir = Join-Path $Root "windows"

Set-Location $WinDir

function Require-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: '$Name' was not found on PATH."
        Write-Host $Hint
        exit 1
    }
}

Require-Command "npm" @"
Install Node.js LTS from https://nodejs.org (includes npm), then open a NEW PowerShell
window and re-run:
  powershell -ExecutionPolicy Bypass -File .\scripts\make_windows_installer.ps1
"@

Write-Host "==> Bundling Windows embedded runtime if missing"
$RuntimeDir = Join-Path $WinDir "resources\runtime"
$RuntimeExe = Join-Path $RuntimeDir "python.exe"
$RuntimePost = Join-Path $RuntimeDir "zotify-postprocess.py"
$RuntimeFFmpeg = Join-Path $RuntimeDir "ffmpeg.exe"
if (-not (Test-Path $RuntimeExe) -or -not (Test-Path $RuntimePost) -or -not (Test-Path $RuntimeFFmpeg)) {
    & (Join-Path $Root "scripts\bundle_windows_runtime.ps1")
}

Write-Host "==> Installing Node dependencies"
npm install

Write-Host "==> Compiling React UI and Electron processes"
npm run build:all

Write-Host "==> Generating Windows NSIS Installer (OzDownloader-Installer.exe)"
if (-not (Test-Path $RuntimeExe) -or -not (Test-Path $RuntimePost) -or -not (Test-Path $RuntimeFFmpeg)) {
    Write-Host "ERROR: Windows runtime is incomplete under $RuntimeDir"
    Write-Host "Run scripts\bundle_windows_runtime.ps1 on Windows first."
    exit 1
}
npm run dist:win

Write-Host "==> Ready!"
Write-Host "Installer created at: windows\dist-installer\OzDownloader-Installer.exe"
