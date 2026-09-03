export interface AppPathConfig {
  supportDir: string;
  defaultMusicRoot: string;
  settingsPath: string;
  playlistsPath: string;
  accountPath: string;
  avatarPath: string;
  spotifyPlaylistsPath: string;
  coversDir: string;
  coverIndexPath: string;
  zotifySupportDir: string;
  zotifyConfigPath: string;
  zotifyCredentialsPath: string;
  tokenCachePath: string;
  bundledRuntimeDir: string;
}

let cachedPaths: AppPathConfig | null = null;

export async function getAppPaths(): Promise<AppPathConfig> {
  if (cachedPaths) return cachedPaths;
  if ((window as any).electronAPI) {
    cachedPaths = await (window as any).electronAPI.getPaths();
    return cachedPaths!;
  }
  // Web / Dev fallback
  cachedPaths = {
    supportDir: '/AppData/Roaming/OzDownloader',
    defaultMusicRoot: '/Music/Oz Downloader',
    settingsPath: '/AppData/Roaming/OzDownloader/settings.json',
    playlistsPath: '/AppData/Roaming/OzDownloader/playlists.json',
    accountPath: '/AppData/Roaming/OzDownloader/account.json',
    avatarPath: '/AppData/Roaming/OzDownloader/avatar.jpg',
    spotifyPlaylistsPath: '/AppData/Roaming/OzDownloader/spotify_playlists.json',
    coversDir: '/AppData/Roaming/OzDownloader/playlist-covers',
    coverIndexPath: '/AppData/Roaming/OzDownloader/playlist-covers/index.json',
    zotifySupportDir: '/AppData/Roaming/OzDownloader/zotify',
    zotifyConfigPath: '/AppData/Roaming/OzDownloader/zotify/config.json',
    zotifyCredentialsPath: '/AppData/Roaming/OzDownloader/zotify/credentials.json',
    tokenCachePath: '/AppData/Roaming/OzDownloader/zotify/.token_cache.json',
    bundledRuntimeDir: '',
  };
  return cachedPaths;
}

export function escapePythonPath(pathStr: string): string {
  const escaped = pathStr.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
  return `'${escaped}'`;
}
