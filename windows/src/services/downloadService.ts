import {
  SongDownloadItem,
  DownloadQueueItem,
} from '../types/downloads';
import { DownloadTabBadge, FetchedPlaylist } from '../types/models';
import { appStore } from './appStore';
import { getAppPaths, escapePythonPath } from './appPaths';
import { ZotifyCLI } from './zotifyCLI';

type Listener = () => void;

class DownloadServiceState {
  logText: string = '';
  isRunning: boolean = false;
  isConverting: boolean = false;
  statusMessage: string = '';
  playlistStatusMessage: string = '';
  songItems: SongDownloadItem[] = [];
  queueItems: DownloadQueueItem[] = [];
  currentQueueIndex: number = 0;
  totalExpected: number = 0;
  totalCompleted: number = 0;
  downloadRate: string = '';
  tabBadge: DownloadTabBadge = 'none';
  toastMessage: string = '';
  toastVisible: boolean = false;
  showCelebration: boolean = false;
  requestShowGetMusic: boolean = false;
  downloadErrorMessage: string = '';

  private currentJobId: string | null = null;
  private isCancelled: boolean = false;
  private listeners = new Set<Listener>();
  private toastTimer: any = null;

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notify() {
    this.listeners.forEach((fn) => fn());
  }

  showToast(message: string, durationMs = 3200) {
    if (this.toastTimer) clearTimeout(this.toastTimer);
    this.toastMessage = message;
    this.toastVisible = true;
    this.notify();
    this.toastTimer = setTimeout(() => {
      this.toastVisible = false;
      this.toastMessage = '';
      this.notify();
    }, durationMs);
  }

  clearTabBadge() {
    if (this.tabBadge === 'success' || this.tabBadge === 'failure') {
      this.tabBadge = 'none';
      this.notify();
    }
  }

  async cancel() {
    this.isCancelled = true;
    this.statusMessage = 'Stopping…';
    this.tabBadge = 'none';
    this.notify();

    if (this.currentJobId) {
      await ZotifyCLI.kill(this.currentJobId);
    }

    this.isRunning = false;
    this.isConverting = false;
    this.statusMessage = 'Download cancelled.';
    this.showToast('Download cancelled');
    this.notify();
  }

  async startDownload(url: string, name: string = '', trackCount = 0, imageURL = '') {
    const item: DownloadQueueItem = {
      id: url,
      name: name || 'Download',
      url,
      trackCount,
      imageURL,
      status: 'pending',
      retryAttempt: 0,
      lastError: '',
    };
    await this.startQueue([item]);
  }

  async startQueue(items: DownloadQueueItem[]) {
    const api = (window as any).electronAPI;
    if (api && !(await api.hasRuntime())) {
      const status = api.getRuntimeStatus ? await api.getRuntimeStatus() : null;
      const where = status?.bundledRuntimeDir ? `\n\nExpected: ${status.bundledRuntimeDir}` : '';
      this.showToast('Download tools are missing. Reinstall from OzDownloader-Installer.exe.');
      this.downloadErrorMessage =
        'Bundled Python/zotify tools were not found inside this install.' +
        where +
        '\n\nReinstall using OzDownloader-Installer.exe built on a Windows PC (not the Mac-built copy).';
      this.notify();
      return;
    }

    if (this.isRunning) {
      // Append to queue
      this.queueItems.push(...items);
      this.showToast(`Added ${items.length} ${items.length === 1 ? 'item' : 'items'} to queue`);
      this.notify();
      return;
    }

    this.queueItems = [...items];
    this.currentQueueIndex = 0;
    this.isRunning = true;
    this.isCancelled = false;
    this.downloadErrorMessage = '';
    this.showCelebration = false;
    this.tabBadge = 'inProgress';
    this.requestShowGetMusic = true;
    this.notify();

    try {
      for (let i = 0; i < this.queueItems.length; i++) {
        if (this.isCancelled) break;
        this.currentQueueIndex = i;
        const current = this.queueItems[i];
        current.status = 'downloading';
        this.notify();

        const success = await this.processQueueItem(current);
        if (this.isCancelled) {
          current.status = 'cancelled';
          break;
        }

        if (success) {
          current.status = 'done';
          appStore.rememberPlaylist(current.name, current.url, current.trackCount, current.imageURL);
        } else {
          current.status = 'failed';
          this.downloadErrorMessage = current.lastError || 'Download failed';
        }
        this.notify();
      }

      if (!this.isCancelled) {
        const anyFailed = this.queueItems.some((q) => q.status === 'failed');
        if (anyFailed) {
          this.tabBadge = 'failure';
          this.statusMessage = 'Some downloads had errors.';
        } else {
          this.tabBadge = 'success';
          this.statusMessage = 'All downloads completed!';
          this.showCelebration = true;
          this.showToast('All downloads completed!');
        }
      }
    } finally {
      this.isRunning = false;
      this.isConverting = false;
      this.currentJobId = null;
      this.notify();
    }
  }

  private async processQueueItem(item: DownloadQueueItem): Promise<boolean> {
    this.songItems = [];
    this.totalExpected = item.trackCount || 0;
    this.totalCompleted = 0;
    this.statusMessage = `Downloading ${item.name}…`;
    this.notify();

    const jobId = `job_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    this.currentJobId = jobId;

    const rootPath = appStore.settings.rootPath;
    const flags = await ZotifyCLI.isolatedFlags(rootPath);
    const args = [...flags, item.url];

    const res = await ZotifyCLI.run({
      id: jobId,
      command: 'python',
      args: ['-m', 'zotify', ...args],
      onLine: (line) => this.handleCLIProgressLine(line),
    });

    if (this.isCancelled) return false;

    if (res.exitCode === 0) {
      if (appStore.settings.autoPostprocess && appStore.settings.convertFormat !== 'none') {
        await this.runPostprocess(item.name);
      }
      return true;
    } else {
      item.lastError = res.output.slice(-200) || 'CLI error';
      return false;
    }
  }

  private handleCLIProgressLine(line: string) {
    this.logText += line + '\n';

    // Parse download speed (e.g. 1.25MB/s, 850kB/s)
    const rateMatch = line.match(/([0-9.]+\s*[kKmMgG]?i?[Bb]\/s)/);
    if (rateMatch) {
      this.downloadRate = rateMatch[1];
    }

    // Parse song downloading e.g. "Downloading: 45%" or "[1/20] Artist - Song"
    const trackNumMatch = line.match(/\[(\d+)\/(\d+)\]\s+(.+)/);
    if (trackNumMatch) {
      const currentNum = parseInt(trackNumMatch[1], 10);
      const totalNum = parseInt(trackNumMatch[2], 10);
      const songName = trackNumMatch[3].trim();

      this.totalExpected = Math.max(this.totalExpected, totalNum);
      let existing = this.songItems.find((s) => s.number === currentNum);
      if (!existing) {
        existing = {
          id: currentNum,
          number: currentNum,
          name: songName,
          status: 'downloading',
          fraction: 0,
          trackId: '',
          skipReason: 'none',
        };
        this.songItems.push(existing);
      } else {
        existing.status = 'downloading';
        existing.name = songName;
      }
      this.statusMessage = `Song ${currentNum} of ${this.totalExpected}`;
      this.notify();
    }

    // Parse percentage
    const percentMatch = line.match(/(\d+)%/);
    if (percentMatch) {
      const pct = parseInt(percentMatch[1], 10) / 100;
      const downloadingItem = this.songItems.find((s) => s.status === 'downloading');
      if (downloadingItem) {
        downloadingItem.fraction = pct;
        this.notify();
      }
    }

    // Parse skipped / completed
    if (line.includes('Skipping') || line.includes('already exists') || line.includes('already on disk')) {
      const active = this.songItems.find((s) => s.status === 'downloading');
      if (active) {
        active.status = 'skipped';
        active.fraction = 1;
        active.skipReason = line.includes('duplicate') ? 'duplicate' : 'alreadySaved';
        this.totalCompleted++;
        this.notify();
      }
    } else if (line.includes('Downloaded:') || line.includes('Finished:')) {
      const active = this.songItems.find((s) => s.status === 'downloading');
      if (active) {
        active.status = 'done';
        active.fraction = 1;
        this.totalCompleted++;
        this.notify();
      }
    }
  }

  private async runPostprocess(playlistName: string) {
    this.isConverting = true;
    this.statusMessage = `Converting to ${appStore.settings.convertFormat.toUpperCase()}…`;
    this.notify();

    const paths = await getAppPaths();
    const format = appStore.settings.convertFormat;
    const genre = appStore.settings.defaultGenre || '';
    const rootPath = appStore.settings.rootPath;
    const folderPath = `${rootPath.replace(/\/$/, '')}/${playlistName.replace(/[/\\?%*:|"<>]/g, '_')}`;

    const postprocessPy = `${paths.bundledRuntimeDir}/zotify-postprocess.py`;
    const args = [postprocessPy, folderPath, '--format', format];
    if (genre) {
      args.push('--genre', genre);
    }

    try {
      await ZotifyCLI.run({
        id: `postprocess_${Date.now()}`,
        command: 'python',
        args,
      });
    } catch (e) {
      console.warn('Postprocess failed:', e);
    }

    this.isConverting = false;
    this.notify();
  }

  async fetchPlaylists(store: typeof appStore): Promise<FetchedPlaylist[]> {
    if (!store.isLoggedIn) return [];
    this.playlistStatusMessage = 'Loading playlists…';
    this.notify();

    const paths = await getAppPaths();
    const configEscaped = escapePythonPath(paths.zotifyConfigPath);

    const script = `
import json, time, sys
from argparse import Namespace
from pathlib import Path
fields = dict(persist=False, update_config=False, update_archive=False, debug=False,
              no_splash=True, config_location=${configEscaped}, username=None, token=None, urls='',
              file_of_urls=None, liked_songs=False, user_playlists=True,
              followed_artists=False, followed_albums=False, search=None, verify_library=False)
args = Namespace(**fields)
from zotify.config import Zotify, Config
from zotify.termoutput import Printer
Printer.splash = staticmethod(lambda: None)
Zotify.CONFIG = Config()
Zotify.start()
Zotify.CONFIG.load(args)
for i in range(4):
    try:
        Zotify.login(args); break
    except Exception:
        time.sleep(2)
else:
    print("OZ_JSON|" + json.dumps({"ok": False, "items": []}))
    raise SystemExit(0)

try:
    playlists = Zotify.SESSION.api().get_user_playlists()
    items = []
    for pl in (playlists or []):
        if not isinstance(pl, dict): continue
        pid = pl.get('id') or pl.get('uri', '').split(':')[-1]
        name = pl.get('name') or 'Playlist'
        url = f"https://open.spotify.com/playlist/{pid}"
        owner_obj = pl.get('owner') or {}
        owner = owner_obj.get('display_name') or owner_obj.get('id') or ''
        tracks_obj = pl.get('tracks') or {}
        count = tracks_obj.get('total') or 0
        images = pl.get('images') or []
        img_url = images[0].get('url') if images and isinstance(images[0], dict) else ''
        items.append({
            "id": pid, "name": name, "url": url, "owner": owner,
            "trackCount": count, "imageURL": img_url,
            "isSpotify": pid.startswith("37i9"),
            "isOwned": False
        })
    print("OZ_JSON|" + json.dumps({"ok": True, "items": items}))
except Exception as e:
    print("OZ_JSON|" + json.dumps({"ok": False, "error": str(e), "items": []}))
`;

    try {
      const res = await ZotifyCLI.run({
        id: 'fetch_playlists',
        command: 'python',
        args: ['-c', script],
      });
      const data = await ZotifyCLI.parseOzJSON(res.output);
      if (data && data.ok && Array.isArray(data.items)) {
        const playlists: FetchedPlaylist[] = data.items.map((it: any) => ({
          id: it.id,
          name: it.name,
          url: it.url,
          owner: it.owner,
          isOwned: it.owner === store.account.userId || it.owner === store.account.displayName,
          isSpotify: it.isSpotify || it.id.startsWith('37i9'),
          trackCount: it.trackCount || 0,
          imageURL: it.imageURL || '',
        }));
        this.playlistStatusMessage = '';
        this.notify();
        return playlists;
      }
    } catch (err) {
      console.warn('fetchPlaylists error:', err);
    }

    this.playlistStatusMessage = '';
    this.notify();
    return [];
  }
}

export const downloadService = new DownloadServiceState();
