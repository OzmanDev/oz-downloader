import { getAppPaths } from './appPaths';

export interface CommandResult {
  exitCode: number;
  output: string;
}

export class ZotifyCLI {
  static async parseOzJSON(output: string): Promise<Record<string, any> | null> {
    const lines = output.split(/\r?\n/);
    for (const raw of lines) {
      const line = raw.trim();
      if (line.startsWith('OZ_JSON|')) {
        try {
          const payload = line.slice('OZ_JSON|'.length);
          return JSON.parse(payload);
        } catch (_) {}
      }
    }
    return null;
  }

  static async isolatedFlags(rootPath: string): Promise<string[]> {
    const paths = await getAppPaths();
    return [
      '-c', paths.zotifyConfigPath,
      '--creds', paths.zotifyCredentialsPath,
      '-rp', rootPath,
    ];
  }

  static async run({
    id,
    command,
    args,
    onLine,
    stallTimeout = 90,
  }: {
    id: string;
    command: string;
    args: string[];
    onLine?: (line: string) => void;
    stallTimeout?: number;
  }): Promise<CommandResult> {
    const api = (window as any).electronAPI;
    if (!api) {
      console.warn('Electron API unavailable for CLI run');
      return { exitCode: 0, output: '' };
    }

    let carryOut = '';
    let carryErr = '';
    let lastBeat = Date.now();
    let stallTimer: any = null;

    const bumpBeat = () => {
      lastBeat = Date.now();
    };

    const emitChunk = (chunk: string, isErr: boolean) => {
      bumpBeat();
      let carry = isErr ? carryErr + chunk : carryOut + chunk;
      const lines = carry.split(/[\r\n]+/);
      // Keep last incomplete segment in carry
      const hasTrailingDelimiter = /[\r\n]$/.test(carry);
      const readyLines = hasTrailingDelimiter ? lines : lines.slice(0, -1);
      const remaining = hasTrailingDelimiter ? '' : (lines[lines.length - 1] || '');

      if (isErr) carryErr = remaining;
      else carryOut = remaining;

      for (const raw of readyLines) {
        const line = raw.trim();
        if (line && onLine) {
          onLine(line);
        }
      }
    };

    const cleanupStdout = api.onCLIStdout(id, (text: string) => emitChunk(text, false));
    const cleanupStderr = api.onCLIStderr(id, (text: string) => emitChunk(text, true));

    if (stallTimeout > 0) {
      stallTimer = setInterval(() => {
        if (Date.now() - lastBeat > stallTimeout * 1000) {
          console.warn(`[Oz Downloader] CLI process ${id} stalled for ${stallTimeout}s, killing...`);
          api.killCLI(id);
        }
      }, 5000);
    }

    try {
      const result = await api.spawnCLI(id, command, args);
      // Flush carry
      if (carryOut.trim() && onLine) onLine(carryOut.trim());
      if (carryErr.trim() && onLine) onLine(carryErr.trim());
      return result;
    } finally {
      if (stallTimer) clearInterval(stallTimer);
      cleanupStdout();
      cleanupStderr();
    }
  }

  static async kill(id: string): Promise<boolean> {
    const api = (window as any).electronAPI;
    if (api) return await api.killCLI(id);
    return false;
  }
}
