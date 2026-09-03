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
& $PyExe -m pip install --upgrade pip wheel setuptools
# music-tag (hyphen) provides the music_tag module; installing it first avoids a
# broken "music_tag" sdist wheel name during zotify's dependency install.
& $PyExe -m pip install "music-tag" mutagen requests imageio-ffmpeg
& $PyExe -m pip install "git+https://github.com/Googolplexed0/zotify.git"

Write-Host "==> Extracting ffmpeg.exe"
$FFmpegScript = "import imageio_ffmpeg, shutil, os; shutil.copy(imageio_ffmpeg.get_ffmpeg_exe(), os.path.join(r'$RuntimeDir', 'ffmpeg.exe'))"
& $PyExe -c $FFmpegScript

Write-Host "==> Copying postprocess script"
$PostProcessSource = $null
$Candidates = @(
    (Join-Path $Root "scripts\zotify-postprocess.py"),
    (Join-Path $Root "scripts\zotify-postprocess")
)
if ($env:ZOTIFY_TOOLS) {
    $Candidates += (Join-Path $env:ZOTIFY_TOOLS "bin\zotify-postprocess")
}
$Candidates += (Join-Path (Split-Path -Parent $Root) "zotify-tools\bin\zotify-postprocess")
$Candidates += (Join-Path $env:USERPROFILE "Desktop\zotify-tools\bin\zotify-postprocess")

foreach ($c in $Candidates) {
    if (Test-Path $c) { $PostProcessSource = $c; break }
}
if (-not $PostProcessSource) {
    Write-Host "ERROR: missing zotify-postprocess.py"
    Write-Host "Expected one of:"
    $Candidates | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Copy-Item $PostProcessSource (Join-Path $RuntimeDir "zotify-postprocess.py") -Force
Write-Host "    from $PostProcessSource"

$PatchOAuth = Join-Path $Root "scripts\patch_oauth.py"
if (-not (Test-Path $PatchOAuth) -and $env:ZOTIFY_TOOLS) {
    $PatchOAuth = Join-Path $env:ZOTIFY_TOOLS "scripts\patch_oauth.py"
}
if (Test-Path $PatchOAuth) {
    Write-Host "==> Applying OAuth patch"
    & $PyExe $PatchOAuth
}

$PatchSkip = Join-Path $Root "scripts\patch_skip_existing.py"
if (-not (Test-Path $PatchSkip) -and $env:ZOTIFY_TOOLS) {
    $PatchSkip = Join-Path $env:ZOTIFY_TOOLS "scripts\patch_skip_existing.py"
}
if (Test-Path $PatchSkip) {
    Write-Host "==> Applying skip-existing patch"
    & $PyExe $PatchSkip
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
