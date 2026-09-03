import { contextBridge, ipcRenderer } from 'electron';

export interface ElectronAPI {
  getPaths: () => Promise<any>;
  hasRuntime: () => Promise<boolean>;
  getRuntimeStatus: () => Promise<{ ok: boolean; bundledRuntimeDir: string; missing: string[] }>;
  readFile: (path: string) => Promise<string | null>;
  writeFile: (path: string, content: string) => Promise<boolean>;
  deleteFile: (path: string) => Promise<boolean>;
  exists: (path: string) => Promise<boolean>;
  saveBase64Image: (path: string, base64: string) => Promise<boolean>;
  loadLocalTrackIds: (rootPath: string) => Promise<string[]>;
  chooseDirectory: () => Promise<string | null>;
  openPath: (path: string) => Promise<void>;
  openExternal: (url: string) => Promise<void>;
  writeClipboard: (text: string) => Promise<void>;
  startOAuthServer: () => Promise<boolean>;
  onOAuthCallback: (callback: (data: { code?: string; error?: string; fullUrl?: string }) => void) => () => void;
  spawnCLI: (id: string, command: string, args: string[], cwd?: string) => Promise<{ exitCode: number; output: string }>;
  onCLIStdout: (id: string, callback: (text: string) => void) => () => void;
  onCLIStderr: (id: string, callback: (text: string) => void) => () => void;
  killCLI: (id: string) => Promise<boolean>;
}

const api: ElectronAPI = {
  getPaths: () => ipcRenderer.invoke('app:getPaths'),
  hasRuntime: () => ipcRenderer.invoke('app:hasRuntime'),
  getRuntimeStatus: () => ipcRenderer.invoke('app:getRuntimeStatus'),
  readFile: (p) => ipcRenderer.invoke('fs:readFile', p),
  writeFile: (p, c) => ipcRenderer.invoke('fs:writeFile', p, c),
  deleteFile: (p) => ipcRenderer.invoke('fs:deleteFile', p),
  exists: (p) => ipcRenderer.invoke('fs:exists', p),
  saveBase64Image: (p, b) => ipcRenderer.invoke('fs:saveBase64Image', p, b),
  loadLocalTrackIds: (r) => ipcRenderer.invoke('fs:loadLocalTrackIds', r),
  chooseDirectory: () => ipcRenderer.invoke('dialog:chooseDirectory'),
  openPath: (p) => ipcRenderer.invoke('shell:openPath', p),
  openExternal: (u) => ipcRenderer.invoke('shell:openExternal', u),
  writeClipboard: (t) => ipcRenderer.invoke('clipboard:write', t),
  startOAuthServer: () => ipcRenderer.invoke('auth:startOAuthServer'),
  onOAuthCallback: (callback) => {
    const handler = (_: any, data: any) => callback(data);
    ipcRenderer.on('auth:callback', handler);
    return () => ipcRenderer.removeListener('auth:callback', handler);
  },
  spawnCLI: (id, command, args, cwd) => ipcRenderer.invoke('cli:spawn', { id, command, args, cwd }),
  onCLIStdout: (id, callback) => {
    const channel = `cli:stdout:${id}`;
    const handler = (_: any, text: string) => callback(text);
    ipcRenderer.on(channel, handler);
    return () => ipcRenderer.removeListener(channel, handler);
  },
  onCLIStderr: (id, callback) => {
    const channel = `cli:stderr:${id}`;
    const handler = (_: any, text: string) => callback(text);
    ipcRenderer.on(channel, handler);
    return () => ipcRenderer.removeListener(channel, handler);
  },
  killCLI: (id) => ipcRenderer.invoke('cli:kill', id),
};

contextBridge.exposeInMainWorld('electronAPI', api);
