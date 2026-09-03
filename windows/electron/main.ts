import { app, BrowserWindow, ipcMain, shell, dialog, clipboard } from 'electron';
import * as path from 'path';
import * as fs from 'fs';
import * as http from 'http';
import { spawn, ChildProcess } from 'child_process';

let mainWindow: BrowserWindow | null = null;
const activeProcesses = new Map<string, ChildProcess>();

function runtimeStatus(bundledRuntimeDir: string) {
  const winPy = path.join(bundledRuntimeDir, 'python.exe');
  const unixPy = path.join(bundledRuntimeDir, 'bin', 'python3');
  const pythonPath = fs.existsSync(winPy) ? winPy : (fs.existsSync(unixPy) ? unixPy : null);
  const postprocessPath = path.join(bundledRuntimeDir, 'zotify-postprocess.py');
  const ffmpegPath = process.platform === 'win32'
    ? path.join(bundledRuntimeDir, 'ffmpeg.exe')
    : path.join(bundledRuntimeDir, 'bin', 'ffmpeg');
  const missing: string[] = [];
  if (!pythonPath) missing.push('python');
  if (!fs.existsSync(postprocessPath)) missing.push('zotify-postprocess');
  if (!fs.existsSync(ffmpegPath)) missing.push('ffmpeg');
  return {
    ok: missing.length === 0,
    bundledRuntimeDir,
    pythonPath,
    missing,
  };
}

function warnIfRuntimeMissing() {
  if (!app.isPackaged) return;
  const status = runtimeStatus(getAppPaths().bundledRuntimeDir);
  if (status.ok) return;
  const detail = [
    'This copy of Oz Downloader was installed without bundled download tools.',
    '',
    'Reinstall using OzDownloader-Installer.exe built on a Windows PC.',
    '',
    `Expected folder: ${status.bundledRuntimeDir}`,
    `Missing: ${status.missing.join(', ')}`,
  ].join('\n');
  dialog.showMessageBoxSync({
    type: 'error',
    title: 'Download tools missing',
    message: 'Oz Downloader cannot download music until tools are installed.',
    detail,
  });
}

function getAppPaths() {
  const appData = process.env.APPDATA || (process.platform === 'darwin' ? path.join(process.env.HOME || '', 'Library', 'Application Support') : path.join(process.env.HOME || '', '.config'));
  const supportDir = path.join(appData, 'OzDownloader');
  const homeDir = process.env.USERPROFILE || process.env.HOME || '';
  const defaultMusicRoot = path.join(homeDir, 'Music', 'Oz Downloader');
  const zotifySupportDir = path.join(supportDir, 'zotify');
  const coversDir = path.join(supportDir, 'playlist-covers');

  // Ensure directories exist
  [supportDir, defaultMusicRoot, zotifySupportDir, coversDir].forEach(dir => {
    if (!fs.existsSync(dir)) {
      try { fs.mkdirSync(dir, { recursive: true }); } catch (_) {}
    }
  });

  const bundledRuntimeDir = app.isPackaged
    ? path.join(process.resourcesPath, 'runtime')
    : (fs.existsSync(path.join(process.cwd(), 'runtime'))
        ? path.join(process.cwd(), 'runtime')
        : path.join(__dirname, '..', 'resources', 'runtime'));

  return {
    supportDir,
    defaultMusicRoot,
    settingsPath: path.join(supportDir, 'settings.json'),
    playlistsPath: path.join(supportDir, 'playlists.json'),
    accountPath: path.join(supportDir, 'account.json'),
    avatarPath: path.join(supportDir, 'avatar.jpg'),
    spotifyPlaylistsPath: path.join(supportDir, 'spotify_playlists.json'),
    coversDir,
    coverIndexPath: path.join(coversDir, 'index.json'),
    zotifySupportDir,
    zotifyConfigPath: path.join(zotifySupportDir, 'config.json'),
    zotifyCredentialsPath: path.join(zotifySupportDir, 'credentials.json'),
    tokenCachePath: path.join(zotifySupportDir, '.token_cache.json'),
    bundledRuntimeDir,
  };
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1040,
    height: 720,
    minWidth: 980,
    minHeight: 680,
    title: 'Oz Downloader',
    backgroundColor: '#1c1c1e',
    titleBarStyle: 'hidden',
    titleBarOverlay: {
      color: '#1c1c1e',
      symbolColor: '#f2f2f7',
      height: 38,
    },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  if (process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
  } else {
    mainWindow.loadFile(path.join(__dirname, '..', 'dist', 'index.html'));
  }

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });
}

app.whenReady().then(() => {
  createWindow();
  warnIfRuntimeMissing();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// Setup IPC handlers
ipcMain.handle('app:getPaths', () => getAppPaths());

ipcMain.handle('app:hasRuntime', () => runtimeStatus(getAppPaths().bundledRuntimeDir).ok);

ipcMain.handle('app:getRuntimeStatus', () => runtimeStatus(getAppPaths().bundledRuntimeDir));

function resolvePythonExecutable(bundledRuntimeDir: string): string | null {
  const winPy = path.join(bundledRuntimeDir, 'python.exe');
  const unixPy = path.join(bundledRuntimeDir, 'bin', 'python3');
  if (fs.existsSync(winPy)) return winPy;
  if (fs.existsSync(unixPy)) return unixPy;
  return null;
}

ipcMain.handle('fs:readFile', async (_, filePath: string) => {
  try {
    if (fs.existsSync(filePath)) {
      return await fs.promises.readFile(filePath, 'utf-8');
    }
    return null;
  } catch {
    return null;
  }
});

ipcMain.handle('fs:writeFile', async (_, filePath: string, content: string) => {
  try {
    await fs.promises.writeFile(filePath, content, 'utf-8');
    return true;
  } catch (err) {
    console.error('writeFile error:', err);
    return false;
  }
});

ipcMain.handle('fs:deleteFile', async (_, filePath: string) => {
  try {
    if (fs.existsSync(filePath)) {
      await fs.promises.unlink(filePath);
    }
    return true;
  } catch {
    return false;
  }
});

ipcMain.handle('fs:exists', (_, filePath: string) => fs.existsSync(filePath));

ipcMain.handle('fs:saveBase64Image', async (_, filePath: string, base64Data: string) => {
  try {
    const buffer = Buffer.from(base64Data.replace(/^data:image\/\w+;base64,/, ''), 'base64');
    await fs.promises.writeFile(filePath, buffer);
    return true;
  } catch {
    return false;
  }
});

ipcMain.handle('dialog:chooseDirectory', async () => {
  if (!mainWindow) return null;
  const res = await dialog.showOpenDialog(mainWindow, {
    properties: ['openDirectory', 'createDirectory'],
  });
  if (res.canceled || !res.filePaths.length) return null;
  return res.filePaths[0];
});

ipcMain.handle('shell:openPath', async (_, targetPath: string) => {
  if (!fs.existsSync(targetPath)) {
    try { fs.mkdirSync(targetPath, { recursive: true }); } catch (_) {}
  }
  await shell.openPath(targetPath);
});

ipcMain.handle('shell:openExternal', async (_, url: string) => {
  await shell.openExternal(url);
});

ipcMain.handle('clipboard:write', (_, text: string) => {
  clipboard.writeText(text);
});

// Scan directory recursively for .song_ids archives
ipcMain.handle('fs:loadLocalTrackIds', async (_, rootPath: string) => {
  const ids: string[] = [];
  if (!fs.existsSync(rootPath)) return ids;

  function scan(dir: string) {
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          scan(fullPath);
        } else if (entry.name === '.song_ids') {
          try {
            const content = fs.readFileSync(fullPath, 'utf-8');
            for (const line of content.split('\n')) {
              const parts = line.trim().split('\t');
              if (parts[0]) ids.push(parts[0]);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  scan(rootPath);
  return Array.from(new Set(ids));
});

// Spotify OAuth Listener Server
let oauthServer: http.Server | null = null;
ipcMain.handle('auth:startOAuthServer', async () => {
  return new Promise((resolve) => {
    if (oauthServer) {
      oauthServer.close();
      oauthServer = null;
    }

    oauthServer = http.createServer((req, res) => {
      const reqUrl = new URL(req.url || '/', `http://${req.headers.host}`);
      const code = reqUrl.searchParams.get('code');
      const error = reqUrl.searchParams.get('error');

      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(`
        <!DOCTYPE html>
        <html>
        <head>
          <title>Oz Downloader - Sign In</title>
          <style>
            body { background: #1c1c1e; color: #f2f2f7; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
            .card { background: #2c2c2e; padding: 32px 48px; border-radius: 16px; text-align: center; box-shadow: 0 8px 32px rgba(0,0,0,0.4); max-width: 400px; }
            h2 { color: #30d158; margin-top: 0; font-size: 24px; }
            p { color: #8e8e93; font-size: 14px; margin-bottom: 0; }
          </style>
        </head>
        <body>
          <div class="card">
            <h2>Sign-in Successful!</h2>
            <p>You can close this tab and return to Oz Downloader.</p>
          </div>
        </body>
        </html>
      `);

      if (mainWindow) {
        mainWindow.webContents.send('auth:callback', { code, error, fullUrl: req.url });
      }

      setTimeout(() => {
        if (oauthServer) {
          oauthServer.close();
          oauthServer = null;
        }
      }, 3000);
    });

    oauthServer.listen(4381, '127.0.0.1', () => {
      resolve(true);
    });

    oauthServer.on('error', (err) => {
      console.error('OAuth server error:', err);
      resolve(false);
    });
  });
});

// Process runner (CLI / Python execution with stdout/stderr line streaming)
ipcMain.handle('cli:spawn', async (_, { id, command, args, cwd }: { id: string; command: string; args: string[]; cwd?: string }) => {
  return new Promise((resolve) => {
    const paths = getAppPaths();
    const env: NodeJS.ProcessEnv = { ...process.env, PYTHONUNBUFFERED: '1', TQDM_MININTERVAL: '0.1' };

    // Add bundled runtime bin/Scripts to PATH
    const runtimeBin = process.platform === 'win32'
      ? path.join(paths.bundledRuntimeDir, 'Scripts')
      : path.join(paths.bundledRuntimeDir, 'bin');
    env.PATH = `${runtimeBin}${path.delimiter}${paths.bundledRuntimeDir}${path.delimiter}${env.PATH || ''}`;

    let executable = command;
    // Resolve python/zotify/ffmpeg from bundled runtime if not specified as full path
    if (command === 'python' || command === 'python3') {
      const py = resolvePythonExecutable(paths.bundledRuntimeDir);
      if (!py) {
        resolve({
          exitCode: 127,
          output: 'Bundled Python runtime not found. Reinstall Oz Downloader from the full installer.',
        });
        return;
      }
      executable = py;
    } else if (command === 'ffmpeg') {
      const winFF = path.join(paths.bundledRuntimeDir, 'ffmpeg.exe');
      const unixFF = path.join(paths.bundledRuntimeDir, 'bin', 'ffmpeg');
      if (fs.existsSync(winFF)) executable = winFF;
      else if (fs.existsSync(unixFF)) executable = unixFF;
    }

    const proc = spawn(executable, args, {
      cwd: cwd || paths.supportDir,
      env,
      shell: false,
    });

    activeProcesses.set(id, proc);

    let output = '';

    proc.stdout.on('data', (data: Buffer) => {
      const text = data.toString('utf-8');
      output += text;
      if (mainWindow) {
        mainWindow.webContents.send(`cli:stdout:${id}`, text);
      }
    });

    proc.stderr.on('data', (data: Buffer) => {
      const text = data.toString('utf-8');
      output += text;
      if (mainWindow) {
        mainWindow.webContents.send(`cli:stderr:${id}`, text);
      }
    });

    proc.on('close', (code) => {
      activeProcesses.delete(id);
      resolve({ exitCode: code ?? 0, output });
    });

    proc.on('error', (err) => {
      activeProcesses.delete(id);
      resolve({ exitCode: 1, output: output + '\n' + err.message });
    });
  });
});

ipcMain.handle('cli:kill', (_, id: string) => {
  const proc = activeProcesses.get(id);
  if (proc && proc.pid) {
    if (process.platform === 'win32') {
      spawn('taskkill', ['/pid', proc.pid.toString(), '/T', '/F']);
    } else {
      proc.kill('SIGKILL');
    }
    activeProcesses.delete(id);
    return true;
  }
  return false;
});
