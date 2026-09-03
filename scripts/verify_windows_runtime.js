#!/usr/bin/env node
/**
 * Fail fast when building the Windows installer without the bundled Python runtime.
 * The runtime must be created on Windows (see bundle_windows_runtime.ps1).
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const runtimeDir = path.join(root, 'windows', 'resources', 'runtime');
const pythonExe = path.join(runtimeDir, 'python.exe');
const postprocess = path.join(runtimeDir, 'zotify-postprocess.py');
const ffmpegExe = path.join(runtimeDir, 'ffmpeg.exe');

const missing = [];
if (!fs.existsSync(pythonExe)) missing.push('python.exe');
if (!fs.existsSync(postprocess)) missing.push('zotify-postprocess.py');
if (!fs.existsSync(ffmpegExe)) missing.push('ffmpeg.exe');

if (missing.length) {
  console.error('');
  console.error('ERROR: Windows download runtime is incomplete.');
  console.error(`       Directory: ${runtimeDir}`);
  console.error(`       Missing: ${missing.join(', ')}`);
  console.error('');
  console.error('The installer cannot be built without bundled Python/zotify/ffmpeg.');
  console.error('On a Windows PC, run:');
  console.error('  powershell -ExecutionPolicy Bypass -File .\\scripts\\make_windows_installer.ps1');
  console.error('');
  console.error('Or bundle the runtime first:');
  console.error('  powershell -ExecutionPolicy Bypass -File .\\scripts\\bundle_windows_runtime.ps1');
  console.error('');
  process.exit(1);
}

console.log(`Windows runtime OK (${runtimeDir})`);
