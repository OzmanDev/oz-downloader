import {
  AppSettings,
  DEFAULT_APP_SETTINGS,
  SavedPlaylist,
  FetchedPlaylist,
  SpotifyAccountInfo,
  EMPTY_ACCOUNT_INFO,
} from '../types/models';
import { getAppPaths, escapePythonPath } from './appPaths';
import { ZotifyCLI } from './zotifyCLI';

type Listener = () => void;

class AppStoreState {
  settings: AppSettings = { ...DEFAULT_APP_SETTINGS };
  playlists: SavedPlaylist[] = [];
  account: SpotifyAccountInfo = { ...EMPTY_ACCOUNT_INFO };
  avatarBase64: string | null = null;
  spotifyPlaylists: FetchedPlaylist[] = [];
  isLoggedIn: boolean = false;
  isRefreshingProfile: boolean = false;
  isInitialized: boolean = false;

  private listeners = new Set<Listener>();

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notify() {
    this.listeners.forEach((fn) => fn());
  }

  get accountTitle(): string {
    if (!this.isLoggedIn) return 'Not signed in';
    const name = this.account.displayName.trim();
    return name ? name : 'Signed in';
  }

  get accountSubtitle(): string {
    if (!this.isLoggedIn) return 'Connect Spotify to load your playlists.';
    if (this.account.displayName) return 'Signed in with Spotify';
    return 'Your Spotify account is connected.';
  }

  async init() {
    if (this.isInitialized) return;
    const paths = await getAppPaths();
    const api = (window as any).electronAPI;

    // Load settings
    if (api) {
      const settingsRaw = await api.readFile(paths.settingsPath);
      if (settingsRaw) {
        try {
          this.settings = { ...DEFAULT_APP_SETTINGS, ...JSON.parse(settingsRaw) };
        } catch (_) {}
      }

      if (!this.settings.rootPath || this.settings.rootPath.trim() === '') {
        this.settings.rootPath = paths.defaultMusicRoot;
      }

      // Load saved playlists
      const playlistsRaw = await api.readFile(paths.playlistsPath);
      if (playlistsRaw) {
        try {
          this.playlists = JSON.parse(playlistsRaw);
        } catch (_) {}
      }

      // Load account
      const accountRaw = await api.readFile(paths.accountPath);
      if (accountRaw) {
        try {
          this.account = JSON.parse(accountRaw);
        } catch (_) {}
      }

      // Load spotify playlists cache
      const spotifyPlaylistsRaw = await api.readFile(paths.spotifyPlaylistsPath);
      if (spotifyPlaylistsRaw) {
        try {
          this.spotifyPlaylists = JSON.parse(spotifyPlaylistsRaw);
        } catch (_) {}
      }

      // Check credentials
      this.isLoggedIn = await api.exists(paths.zotifyCredentialsPath);
      await this.syncAccountFromCredentials();

      // Save defaults if files didn't exist
      await this.saveSettings();
      await this.savePlaylists();
      await this.syncToZotifyConfig();
    } else {
      this.settings.rootPath = paths.defaultMusicRoot;
    }

    this.isInitialized = true;
    this.notify();

    if (this.isLoggedIn) {
      this.refreshAccountProfile();
    }
  }

  async updateSettings(updater: (prev: AppSettings) => AppSettings) {
    this.settings = updater(this.settings);
    await this.saveSettings();
    await this.syncToZotifyConfig();
    this.notify();
  }

  private async saveSettings() {
    const paths = await getAppPaths();
    const api = (window as any).electronAPI;
    if (api) {
      await api.writeFile(paths.settingsPath, JSON.stringify(this.settings, null, 2));
    }
  }

  private async savePlaylists() {
    const paths = await getAppPaths();
    const api = (window as any).electronAPI;
    if (api) {
      await api.writeFile(paths.playlistsPath, JSON.stringify(this.playlists, null, 2));
    }
  }

  private async saveAccount() {
    const paths = await getAppPaths();
    const api = (window as any).electronAPI;
    if (api) {
      await api.writeFile(paths.accountPath, JSON.stringify(this.account, null, 2));
    }
  }

  async replaceSpotifyPlaylists(items: FetchedPlaylist[]) {
    this.spotifyPlaylists = items;
    const paths = await getAppPaths();
    const api = (window as any).electronAPI;
    if (api) {
      await api.writeFile(paths.spotifyPlaylistsPath, JSON.stringify(items, null, 2));
    }
    this.notify();
  }

  async syncAccountFromCredentials() {
    const paths = await getAppPaths();
    const api = (window as any).electronAPI;
    if (!api) return;

    this.isLoggedIn = await api.exists(paths.zotifyCredentialsPath);
    if (!this.isLoggedIn) {
      if (this.account.userId !== '') {
        this.account = { ...EMPTY_ACCOUNT_INFO };
        this.avatarBase64 = null;
        await api.deleteFile(paths.accountPath);
        await api.deleteFile(paths.avatarPath);
        this.notify();
      }
      return;
    }

    const credsRaw = await api.readFile(paths.zotifyCredentialsPath);
    if (credsRaw) {
      try {
        const obj = JSON.parse(credsRaw);
        const userId = obj.username || '';
        if (userId) {
          if (this.account.userId !== userId && this.account.userId !== '') {
            this.account = { userId, displayName: '', imageURL: '' };
            this.avatarBase64 = null;
          } else {
            this.account.userId = userId;
          }
          await this.saveAccount();
          this.notify();
        }
      } catch (_) {}
    }
  }

  async syncToZotifyConfig() {
    const paths = await getAppPaths();
    const api = (window as any).electronAPI;
    if (!api) return;

    let dict: Record<string, string> = {};
    const existingRaw = await api.readFile(paths.zotifyConfigPath);
    if (existingRaw) {
      try {
        const obj = JSON.parse(existingRaw);
        for (const k in obj) {
          dict[k] = String(obj[k]);
        }
      } catch (_) {}
    }

    dict['ROOT_PATH'] = this.settings.rootPath;
    dict['CREDENTIALS_LOCATION'] = paths.zotifyCredentialsPath;
    dict['SAVE_CREDENTIALS'] = 'True';
    dict['DOWNLOAD_FORMAT'] = this.settings.downloadFormat;
    dict['DOWNLOAD_QUALITY'] = this.settings.downloadQuality;
    dict['BULK_WAIT_TIME'] = this.settings.bulkWaitTime || '1';
    dict['DOWNLOAD_RATE_LIMITER'] = this.settings.downloadRateLimiter || '0';
    dict['RETRY_ATTEMPTS'] = this.settings.retryAttempts || '3';
    dict['SKIP_EXISTING'] = this.settings.skipExisting ? 'True' : 'False';
    dict['SKIP_PREVIOUSLY_DOWNLOADED'] = this.settings.skipPreviouslyDownloaded ? 'True' : 'False';
    dict['API_CLIENT_ID'] = this.settings.apiClientId;
    dict['MD_SAVE_GENRES'] = 'False';
    dict['MD_DISC_TRACK_TOTALS'] = 'False';
    delete dict['DOWNLOAD_LYRICS'];
    dict['LYRICS_TO_METADATA'] = 'False';
    dict['LYRICS_TO_FILE'] = 'False';
    dict['ALWAYS_CHECK_LYRICS'] = 'False';
    delete dict['OUTPUT_PLAYLIST'];
    dict['OUTPUT_PLAYLIST_EXT'] = '{playlist}/{playlist_num}_{song_name}';
    dict['OUTPUT'] = '{song_name}';
    dict['OUTPUT_SINGLE'] = '{song_name}';
    dict['OUTPUT_ALBUM'] = '{album_num}_{song_name}';

    await api.writeFile(paths.zotifyConfigPath, JSON.stringify(dict, null, 2));
  }

  async refreshAccountProfile() {
    await this.syncAccountFromCredentials();
    if (!this.isLoggedIn) return;

    this.isRefreshingProfile = true;
    this.notify();

    const paths = await getAppPaths();
    const configEscaped = escapePythonPath(paths.zotifyConfigPath);

    const script = `
import json, time, sys
from argparse import Namespace
from pathlib import Path
fields = dict(persist=False, update_config=False, update_archive=False, debug=False,
              no_splash=True, config_location=${configEscaped}, username=None, token=None, urls='',
              file_of_urls=None, liked_songs=False, user_playlists=False,
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
    print("OZ_JSON|" + json.dumps({"ok": False}))
    raise SystemExit(0)
cred = json.loads(Path(Zotify.CONFIG.get_credentials_location()).read_text())
username = cred.get('username') or ''
profile = Zotify.SESSION.api().get_user_profile(username, playlist_limit=1)
name = ''
image = ''
if isinstance(profile, dict):
    name = (profile.get('name') or profile.get('display_name') or '').strip()
    image = (profile.get('image_url') or profile.get('imageUrl') or '').strip()
    if not image:
        imgs = profile.get('images') or []
        if isinstance(imgs, list) and imgs:
            best, best_w = None, -1
            for im in imgs:
                if not isinstance(im, dict): continue
                u = (im.get('url') or '').strip()
                if not u: continue
                w = im.get('width') or 0
                try: w = int(w)
                except Exception: w = 0
                if u and w >= best_w:
                    best, best_w = u, w
            image = best or ((imgs[0].get('url') if isinstance(imgs[0], dict) else '') or '')
print("OZ_JSON|" + json.dumps({"ok": True, "userId": username, "displayName": name, "imageURL": image}))
`;

    try {
      const res = await ZotifyCLI.run({
        id: 'account_profile',
        command: 'python',
        args: ['-c', script],
      });
      const data = await ZotifyCLI.parseOzJSON(res.output);
      if (data && data.ok) {
        this.account = {
          userId: data.userId || this.account.userId,
          displayName: data.displayName || this.account.displayName,
          imageURL: data.imageURL || this.account.imageURL,
        };
        await this.saveAccount();
      }
    } catch (err) {
      console.warn('refreshAccountProfile error:', err);
    } finally {
      this.isRefreshingProfile = false;
      this.notify();
    }
  }

  upsertPlaylist(item: SavedPlaylist) {
    const sameURL = (a: string, b: string) => this.normalizeSpotifyURL(a) === this.normalizeSpotifyURL(b);
    const existingIdx = this.playlists.findIndex((p) => sameURL(p.url, item.url));

    if (existingIdx >= 0) {
      const merged = { ...this.playlists[existingIdx] };
      if (item.name) merged.name = item.name;
      if (item.trackCount > 0) merged.trackCount = item.trackCount;
      if (item.imageURL) merged.imageURL = item.imageURL;
      this.playlists[existingIdx] = merged;
    } else {
      const aliasIdx = this.playlists.findIndex((p) => p.alias === item.alias);
      if (aliasIdx >= 0) {
        this.playlists[aliasIdx] = item;
      } else {
        this.playlists.push(item);
      }
    }

    this.playlists.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
    this.savePlaylists();
    this.notify();
  }

  rememberPlaylist(name: string, url: string, trackCount = 0, imageURL = '') {
    const u = url.trim();
    if (!u) return;
    const displayName = name.trim() || 'Playlist';
    const sameURL = (a: string, b: string) => this.normalizeSpotifyURL(a) === this.normalizeSpotifyURL(b);
    const existingIdx = this.playlists.findIndex((p) => sameURL(p.url, u));

    if (existingIdx >= 0) {
      const existing = { ...this.playlists[existingIdx] };
      existing.name = displayName;
      if (trackCount > 0) existing.trackCount = trackCount;
      if (imageURL) existing.imageURL = imageURL;
      this.playlists[existingIdx] = existing;
      this.savePlaylists();
      this.notify();
      return;
    }

    const used = new Set(this.playlists.map((p) => p.alias));
    const alias = this.makeAlias(displayName, used);
    this.upsertPlaylist({ alias, name: displayName, url: u, trackCount, imageURL });
  }

  removePlaylist(alias: string) {
    this.playlists = this.playlists.filter((p) => p.alias !== alias);
    this.savePlaylists();
    this.notify();
  }

  async clearCredentials() {
    const paths = await getAppPaths();
    const api = (window as any).electronAPI;
    if (api) {
      await api.deleteFile(paths.zotifyCredentialsPath);
      await api.deleteFile(paths.accountPath);
      await api.deleteFile(paths.avatarPath);
      await api.deleteFile(paths.spotifyPlaylistsPath);
    }
    this.isLoggedIn = false;
    this.account = { ...EMPTY_ACCOUNT_INFO };
    this.avatarBase64 = null;
    this.spotifyPlaylists = [];
    this.notify();
  }

  normalizeSpotifyURL(raw: string): string {
    let s = raw.trim();
    const q = s.indexOf('?');
    if (q >= 0) s = s.substring(0, q);
    if (s.endsWith('/')) s = s.slice(0, -1);
    return s.toLowerCase();
  }

  private makeAlias(playlistName: string, used: Set<String>): string {
    let bare = playlistName.replace(/^dj[\s_-]*/i, '');
    const words = bare.split(/[^a-zA-Z0-9]+/).filter(Boolean);
    let base = (words[0] || 'pl').slice(0, 2).toLowerCase();
    if (words.length >= 2 && words[0].toLowerCase().startsWith('amapiano') && bare.toLowerCase().includes('appetizer')) {
      base = 'ap';
    }
    let alias = base;
    let n = 2;
    while (used.has(alias)) {
      alias = `${base}${n}`;
      n++;
    }
    used.add(alias);
    return alias;
  }
}

export const appStore = new AppStoreState();
