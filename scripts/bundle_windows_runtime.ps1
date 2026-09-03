# Windows Runtime Bundling Script (PowerShell)
# Downloads standalone CPython for Windows x86_64 and installs zotify, ffmpeg, mutagen
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$RuntimeDir = Join-Path $Root "windows\resources\runtime"
$CacheDir = Join-Path $Root "windows\resources\cache"

$PyTag = "20251217"
$PyVer = "3.12.12"
$PyArchive = "cpython-${PyVer}+${PyTag}-x86_64-pc-windows-msvc-install_only_stripped.tar.gz"
$PyUrl = "https://github.com/astral-sh/python-build-standalone/releases/download/${PyTag}/${PyArchive}"

Write-Host "==> Creating directories"
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

$ArchivePath = Join-Path $CacheDir $PyArchive
if (-not (Test-Path $ArchivePath)) {
    Write-Host "==> Downloading Python standalone for Windows: $PyUrl"
    Invoke-WebRequest -Uri $PyUrl -OutFile $ArchivePath
}

Write-Host "==> Extracting Python standalone"
tar -xzf $ArchivePath -C $RuntimeDir

$PyExe = Join-Path $RuntimeDir "python.exe"
if (-not (Test-Path $PyExe)) {
    # If nested in python/ folder
    $NestedPy = Join-Path $RuntimeDir "python\python.exe"
    if (Test-Path $NestedPy) {
        Copy-Item -Path "$RuntimeDir\python\*" -Destination $RuntimeDir -Recurse -Force
        Remove-Item -Path "$RuntimeDir\python" -Recurse -Force
    }
}

Write-Host "==> Installing Python dependencies (zotify, mutagen, requests, imageio-ffmpeg)"
& $PyExe -m pip install --upgrade pip wheel
& $PyExe -m pip install mutagen requests imageio-ffmpeg
& $PyExe -m pip install "git+https://github.com/Googolplexed0/zotify.git"

Write-Host "==> Extracting ffmpeg.exe"
$FFmpegScript = "import imageio_ffmpeg, shutil, os; shutil.copy(imageio_ffmpeg.get_ffmpeg_exe(), os.path.join(r'$RuntimeDir', 'ffmpeg.exe'))"
& $PyExe -c $FFmpegScript

Write-Host "==> Copying postprocess script"
$ZotifyTools = if ($env:ZOTIFY_TOOLS) { $env:ZOTIFY_TOOLS } else { Join-Path (Split-Path -Parent $Root) "zotify-tools" }
if (-not (Test-Path $ZotifyTools)) {
    $ZotifyTools = Join-Path $env:USERPROFILE "Desktop\zotify-tools"
}
$PostProcessSource = Join-Path $ZotifyTools "bin\zotify-postprocess"
if (Test-Path $PostProcessSource) {
    Copy-Item $PostProcessSource (Join-Path $RuntimeDir "zotify-postprocess.py")
} else {
    Write-Host "ERROR: missing $PostProcessSource"
    exit 1
}

if (Test-Path (Join-Path $ZotifyTools "scripts\patch_oauth.py")) {
    Write-Host "==> Applying OAuth patch"
    & $PyExe (Join-Path $ZotifyTools "scripts\patch_oauth.py")
}

if (Test-Path (Join-Path $ZotifyTools "scripts\patch_skip_existing.py")) {
    Write-Host "==> Applying skip-existing patch"
    & $PyExe (Join-Path $ZotifyTools "scripts\patch_skip_existing.py")
}

@'
@echo off
"%~dp0python.exe" -m zotify %*
'@ | Set-Content -Path (Join-Path $RuntimeDir "zotify.bat") -Encoding ASCII

@'
@echo off
"%~dp0python.exe" "%~dp0zotify-postprocess.py" %*
'@ | Set-Content -Path (Join-Path $RuntimeDir "zotify-postprocess.bat") -Encoding ASCII

& $PyExe -c "import zotify, mutagen, requests, imageio_ffmpeg; print('runtime ok')"
Write-Host "==> Windows runtime bundling complete!"
