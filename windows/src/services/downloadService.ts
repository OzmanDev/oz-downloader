import {
  SongDownloadItem,
  DownloadQueueItem,
  DownloadPhase,
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
  downloadPhase: DownloadPhase = 'idle';
  convertFraction: number = 0;
  convertLabel: string = '';
  convertSkipped: boolean = false;
  showProgressDetails: boolean = true;
  tabBadge: DownloadTabBadge = 'none';
  toastMessage: string = '';
  toastVisible: boolean = false;
  showCelebration: boolean = false;
  requestShowGetMusic: boolean = false;
  downloadErrorMessage: string = '';

  private currentJobId: string | null = null;
  private isCancelled: boolean = false;
  private activeSongIndex: number | null = null;
  private listeners = new Set<Listener>();
  private toastTimer: any = null;

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notify() {
    this.listeners.forEach((fn) => fn());
  }

  get phaseStatusLabel(): string {
    const playlist = this.queueItems[this.currentQueueIndex]?.name ?? '';
    switch (this.downloadPhase) {
      case 'idle':
        return this.statusMessage || '';
      case 'starting':
        return playlist ? `Starting ${playlist}…` : 'Starting…';
      case 'fetchingTrackInfo':
        return 'Fetching track list…';
      case 'checkingExisting':
        return 'Checking library…';
      case 'downloading': {
        const newCount = this.songItems.filter(
          (s) =>
            s.status === 'pending' ||
            s.status === 'downloading' ||
            s.status === 'done' ||
            s.status === 'failed'
        ).length;
        if (newCount > 0) {
          return newCount === 1
            ? 'Downloading 1 new song…'
            : `Downloading ${newCount} new songs…`;
        }
        return playlist ? `Downloading ${playlist}…` : 'Downloading…';
      }
      case 'converting':
        return this.convertLabel || 'Converting…';
      case 'signingIn':
        return 'Sign in with Spotify…';
      case 'retrying':
        return playlist ? `Retrying ${playlist}…` : 'Retrying…';
      case 'stopping':
        return 'Cancelling…';
      default:
        return this.statusMessage || '';
    }
  }

  get phaseProgressSummary(): string {
    const skipped = this.songItems.filter((s) => s.status === 'skipped').length;
    const left = this.songItems.filter(
      (s) => s.status === 'pending' || s.status === 'downloading' || s.status === 'failed'
    ).length;
    switch (this.downloadPhase) {
      case 'idle':
        return '';
      case 'starting':
        return 'Getting ready…';
      case 'fetchingTrackInfo':
        return 'Loading song titles from Spotify…';
      case 'checkingExisting':
        if (skipped > 0 || left > 0) return `${skipped} skipped · ${left} left`;
        return 'Checking which songs you already have.';
      case 'downloading':
        return `${skipped} skipped · ${left} left`;
      case 'converting':
        return this.convertLabel || 'Converting downloaded files to FLAC, embedding lyrics, and renaming…';
      case 'signingIn':
        return 'Complete Spotify sign-in in your browser, then this will continue.';
      case 'retrying':
        return 'Connection issue — retrying…';
      case 'stopping':
        return 'Stopping…';
      default:
        return '';
    }
  }

  get totalFraction(): number {
    if (this.isConverting || this.downloadPhase === 'converting') {
      return Math.min(1, Math.max(0.05, this.convertFraction));
    }
    const expected = Math.max(this.totalExpected, this.songItems.length, 1);
    const finished = this.songItems.filter((s) =>
      s.status === 'done' || s.status === 'skipped'
    ).length;
    return Math.min(1, finished / expected);
  }

  private setPhase(phase: DownloadPhase) {
    this.downloadPhase = phase;
    if (phase !== 'idle') {
      this.statusMessage = this.phaseStatusLabel;
    }
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

  toggleProgressDetails() {
    this.showProgressDetails = !this.showProgressDetails;
    this.notify();
  }

  async cancel() {
    this.isCancelled = true;
    this.setPhase('stopping');
    this.statusMessage = 'Stopping…';
    this.tabBadge = 'none';
    this.notify();

    if (this.currentJobId) {
      await ZotifyCLI.kill(this.currentJobId);
    }

    this.isRunning = false;
    this.isConverting = false;
    this.convertSkipped = true;
    this.convertFraction = Math.max(this.convertFraction, 1);
    this.convertLabel = this.convertLabel || 'Convert skipped';
    this.downloadPhase = 'idle';
    this.statusMessage = 'Download cancelled.';
    this.showToast('Cancelled');
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
    this.convertFraction = 0;
    this.convertLabel = '';
    this.convertSkipped = false;
    this.showProgressDetails = true;
    this.tabBadge = 'inProgress';
    this.requestShowGetMusic = true;
    this.setPhase('starting');
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
        const anyFailed =
          this.queueItems.some((q) => q.status === 'failed') ||
          this.songItems.some((s) => s.status === 'failed');
        if (anyFailed) {
          this.tabBadge = 'failure';
          this.statusMessage = 'Finished with errors';
          this.downloadPhase = 'idle';
        } else {
          this.tabBadge = 'success';
          this.statusMessage = 'Done';
          this.downloadPhase = 'idle';
          this.showCelebration = true;
          this.showFinishToast();
        }
      }
    } finally {
      this.isRunning = false;
      this.isConverting = false;
      this.currentJobId = null;
      if (this.downloadPhase !== 'idle') this.downloadPhase = 'idle';
      this.notify();
    }
  }

  private showFinishToast() {
    const newCount = this.songItems.filter((s) => s.status === 'done').length;
    const alreadyHere = this.songItems.filter(
      (s) => s.status === 'skipped' && s.skipReason === 'alreadySaved'
    ).length;
    if (this.songItems.length === 0) {
      this.showToast('All downloads completed!');
      return;
    }
    if (newCount === 0) {
      this.showToast('All already here');
    } else if (alreadyHere > 0) {
      this.showToast(`${newCount} new · ${alreadyHere} already here`);
    } else {
      this.showToast(`${newCount} new`);
    }
  }

  private seedPendingSongs(count: number) {
    if (count <= 0 || this.songItems.length > 0) return;
    this.songItems = Array.from({ length: count }, (_, i) => ({
      id: i + 1,
      number: i + 1,
      name: `Song ${i + 1}`,
      status: 'pending' as const,
      fraction: 0,
      trackId: '',
      skipReason: 'none' as const,
    }));
    this.totalExpected = Math.max(this.totalExpected, count);
  }

  private async processQueueItem(item: DownloadQueueItem): Promise<boolean> {
    this.songItems = [];
    this.totalExpected = item.trackCount || 0;
    this.totalCompleted = 0;
    this.activeSongIndex = null;
    this.downloadRate = '';
    this.seedPendingSongs(item.trackCount);
    this.setPhase(item.trackCount > 0 ? 'checkingExisting' : 'starting');
    this.downloadRate = 'Looking for existing songs…';
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
      if (
        appStore.settings.autoPostprocess &&
        appStore.settings.convertFormat !== 'none' &&
        appStore.settings.convertFormat.toLowerCase() !== 'ogg'
      ) {
        await this.runPostprocess(item.name);
      }
      return true;
    } else {
      item.lastError = res.output.slice(-200) || 'CLI error';
      return false;
    }
  }

  private ensureSong(number: number, name?: string): SongDownloadItem {
    let existing = this.songItems.find((s) => s.number === number);
    if (!existing) {
      existing = {
        id: number,
        number,
        name: name || `Song ${number}`,
        status: 'pending',
        fraction: 0,
        trackId: '',
        skipReason: 'none',
      };
      this.songItems.push(existing);
      this.songItems.sort((a, b) => a.number - b.number);
    } else if (name && (existing.name.startsWith('Song ') || existing.name.startsWith('Track '))) {
      existing.name = name;
    } else if (name && name.length >= existing.name.length) {
      existing.name = name;
    }
    return existing;
  }

  private promoteToDownloading(song: SongDownloadItem) {
    if (song.status === 'pending') {
      song.status = 'downloading';
    }
    this.activeSongIndex = this.songItems.findIndex((s) => s.id === song.id);
    this.setPhase('downloading');
  }

  private completeActive(
    status: 'done' | 'skipped' | 'failed',
    skipReason: SongDownloadItem['skipReason'] = 'none',
    name?: string
  ) {
    let active =
      (this.activeSongIndex != null ? this.songItems[this.activeSongIndex] : undefined) ||
      this.songItems.find((s) => s.status === 'downloading') ||
      this.songItems.find((s) => s.status === 'pending');
    if (!active) return;
    if (name) active.name = name;
    active.status = status;
    active.fraction = 1;
    if (status === 'skipped') {
      active.skipReason = skipReason === 'none' ? 'alreadySaved' : skipReason;
    }
    this.totalCompleted = this.songItems.filter(
      (s) => s.status === 'done' || s.status === 'skipped'
    ).length;
    this.activeSongIndex = null;
    const next = this.songItems.find((s) => s.status === 'pending');
    this.activeSongIndex = next ? this.songItems.indexOf(next) : null;
  }

  private handleCLIProgressLine(line: string) {
    this.logText += line + '\n';
    const upper = line.toUpperCase();

    const rateMatch = line.match(/([0-9.]+\s*[kKmMgG]?i?[Bb]\/s)/);
    if (rateMatch) {
      this.downloadRate = rateMatch[1];
      this.setPhase('downloading');
      const active =
        (this.activeSongIndex != null ? this.songItems[this.activeSongIndex] : undefined) ||
        this.songItems.find((s) => s.status === 'pending');
      if (active && active.status === 'pending') {
        this.promoteToDownloading(active);
      }
    }

    const trackNumMatch = line.match(/\[(\d+)\/(\d+)\]\s+(.+)/);
    if (trackNumMatch) {
      const currentNum = parseInt(trackNumMatch[1], 10);
      const totalNum = parseInt(trackNumMatch[2], 10);
      const songName = trackNumMatch[3].trim();
      this.totalExpected = Math.max(this.totalExpected, totalNum);
      const song = this.ensureSong(currentNum, songName);
      // Stay Waiting until real transfer (speed / ≥8% / DOWNLOADED).
      if (song.status !== 'done' && song.status !== 'skipped' && song.status !== 'failed') {
        if (song.status === 'downloading') {
          // keep
        } else {
          song.status = 'pending';
        }
        this.activeSongIndex = this.songItems.indexOf(song);
      }
      if (this.downloadPhase === 'starting' || this.downloadPhase === 'idle') {
        this.setPhase('checkingExisting');
      }
      this.notify();
    }

    const percentMatch = line.match(/(\d+(?:\.\d+)?)%/);
    if (percentMatch) {
      const pct = parseFloat(percentMatch[1]) / 100;
      const idx =
        this.activeSongIndex != null && this.songItems[this.activeSongIndex]
          ? this.activeSongIndex
          : this.songItems.findIndex((s) => s.status === 'downloading' || s.status === 'pending');
      if (idx >= 0) {
        const song = this.songItems[idx];
        if (pct >= 0.08) {
          this.promoteToDownloading(song);
        }
        if (song.status === 'downloading') {
          song.fraction = Math.min(0.99, Math.max(song.fraction, pct));
        }
        this.notify();
      }
    }

    if (
      upper.includes('SKIPPING') ||
      line.includes('already exists') ||
      line.includes('already on disk')
    ) {
      if (this.downloadPhase !== 'downloading') {
        this.setPhase('checkingExisting');
      }
      const skipReason = upper.includes('DUPLICATE') ? 'duplicate' : 'alreadySaved';
      this.completeActive('skipped', skipReason);
      this.notify();
      return;
    }

    if (upper.includes('DOWNLOADED') || line.includes('Downloaded:') || line.includes('Finished:')) {
      this.setPhase('downloading');
      let name: string | undefined;
      const quoted = line.match(/["']([^"']+)["']/);
      if (quoted) {
        const base = quoted[1].replace(/^.*[/\\]/, '').replace(/\.[^.]+$/, '');
        if (base) name = base;
      }
      this.completeActive('done', 'none', name);
      this.notify();
      return;
    }

    if (upper.includes('FAILED TO GET CONTENT STREAM')) {
      this.completeActive('failed');
      this.notify();
    }
  }

  private async runPostprocess(playlistName: string) {
    const paths = await getAppPaths();
    const format = appStore.settings.convertFormat;
    const rootPath = appStore.settings.rootPath;
    const folderPath = `${rootPath.replace(/[/\\]+$/, '')}/${playlistName.replace(/[/\\?%*:|"<>]/g, '_')}`;

    const api = (window as any).electronAPI;
    const hasOgg = api?.folderHasOgg ? await api.folderHasOgg(folderPath) : true;
    if (!hasOgg) {
      this.convertSkipped = true;
      this.convertFraction = 1;
      this.convertLabel = 'No .ogg files to convert';
      this.isConverting = false;
      this.setPhase('idle');
      this.statusMessage = 'Done';
      this.notify();
      return;
    }

    this.isConverting = true;
    this.convertSkipped = false;
    this.convertFraction = 0.05;
    const fmt = format.toUpperCase();
    this.convertLabel =
      fmt === 'FLAC' || format.toLowerCase() === 'flac'
        ? 'Converting to FLAC + lyrics…'
        : `Converting to ${fmt}…`;
    this.setPhase('converting');
    this.notify();

    const genre = appStore.settings.defaultGenre || '';
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
        onLine: (line) => {
          const pct = line.match(/(\d+(?:\.\d+)?)%/);
          if (pct) {
            this.convertFraction = Math.min(0.99, Math.max(this.convertFraction, parseFloat(pct[1]) / 100));
          } else if (/lyric/i.test(line)) {
            this.convertFraction = Math.min(0.95, Math.max(this.convertFraction, 0.7));
            this.convertLabel = 'Embedding lyrics…';
          } else if (/renam/i.test(line)) {
            this.convertFraction = Math.min(0.98, Math.max(this.convertFraction, 0.85));
            this.convertLabel = 'Renaming songs…';
          } else if (/convert|flac|ogg|mp3/i.test(line)) {
            this.convertFraction = Math.min(0.85, Math.max(this.convertFraction, this.convertFraction + 0.05));
            this.convertLabel = fmt === 'FLAC' ? 'Converting to FLAC…' : `Converting to ${fmt}…`;
          }
          this.notify();
        },
      });
      this.convertFraction = 1;
      this.convertLabel = 'Converted · lyrics embedded · renamed';
    } catch (e) {
      console.warn('Postprocess failed:', e);
      this.convertFraction = 1;
      this.convertLabel = 'Convert failed';
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
