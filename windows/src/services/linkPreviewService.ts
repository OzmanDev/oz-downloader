import { LinkPreview, MatchStatus } from '../types/downloads';
import { DownloadQueueItem } from '../types/downloads';
import { getAppPaths, escapePythonPath } from './appPaths';
import { ZotifyCLI } from './zotifyCLI';

type Listener = () => void;

class LinkPreviewServiceState {
  previews: LinkPreview[] = [];
  isLoading: boolean = false;
  isEnriching: boolean = false;
  urlsText: string = '';
  message: string = '';
  inputError: string | null = null;

  private oembedCache: Map<string, { title: string; thumbnailURL: string }> = new Map();
  private debounceTimer: any = null;
  private currentRequestId: number = 0;
  private listeners = new Set<Listener>();

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private notify() {
    this.listeners.forEach((fn) => fn());
  }

  get hasRenderablePreview(): boolean {
    return this.previews.some(
      (p) => !p.error && p.name !== 'Loading…' && p.name !== ''
    );
  }

  clear() {
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    this.currentRequestId++;
    this.urlsText = '';
    this.previews = [];
    this.message = '';
    this.inputError = null;
    this.isLoading = false;
    this.isEnriching = false;
    this.notify();
  }

  seedForDownload(queue: DownloadQueueItem[], musicRoot: string) {
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    const urls = queue.map((i) => i.url).filter(Boolean);
    if (!urls.length) return;

    this.urlsText = urls.join('\n');
    this.inputError = null;
    this.message = '';

    const seeds: LinkPreview[] = queue.slice(0, 5).map((item) => ({
      id: item.url,
      url: item.url,
      kind: this.kindFromURL(item.url),
      name: item.name || 'Loading…',
      detail: '',
      trackCount: Math.max(item.trackCount, 0),
      trackIds: [],
      trackNames: [],
      alreadyHave: 0,
      status: 'unknown',
      error: null,
    }));

    this.previews = seeds;
    const waitingForTitle = seeds.some((s) => s.name === 'Loading…' || !s.name);
    this.isLoading = waitingForTitle;
    this.isEnriching = !waitingForTitle;
    this.notify();

    const reqId = ++this.currentRequestId;
    this.refresh(urls, musicRoot, reqId);
  }

  schedulePreview(urlsText: string, musicRoot: string) {
    this.urlsText = urlsText;
    if (this.debounceTimer) clearTimeout(this.debounceTimer);

    const trimmed = urlsText.trim();
    if (!trimmed) {
      this.clear();
      return;
    }

    const urls = this.extractSpotifyURLs(trimmed);
    if (!urls.length) {
      this.previews = [];
      this.message = '';
      this.isLoading = false;
      this.isEnriching = false;
      this.inputError = 'That doesn’t look like a Spotify playlist, album, or song link.';
      this.notify();
      return;
    }

    this.inputError = null;
    this.isLoading = true;
    this.isEnriching = false;
    this.previews = [];
    this.message = 'Looking up…';
    this.notify();

    const reqId = ++this.currentRequestId;
    const delay = trimmed.includes('open.spotify.com/') && !trimmed.endsWith('/') ? 0 : 300;

    this.debounceTimer = setTimeout(() => {
      if (this.currentRequestId === reqId) {
        this.refresh(urls, musicRoot, reqId);
      }
    }, delay);
  }

  refreshNow(urlsText: string, musicRoot: string) {
    this.schedulePreview(urlsText, musicRoot);
  }

  private async refresh(urls: [string, ...string[]] | string[], musicRoot: string, reqId: number) {
    const targetURLs = urls.slice(0, 5);
    const localIds = await this.loadLocalTrackIds(musicRoot);

    // Phase 1: fast title via oEmbed + public embed (no sign-in required).
    const quickByUrl = new Map<string, LinkPreview>();
    await Promise.all(
      targetURLs.map(async (url) => {
        if (this.currentRequestId !== reqId) return;
        const [oembed, embed] = await Promise.all([
          this.fetchOEmbed(url).catch(() => null),
          this.fetchPublicEmbedMeta(url),
        ]);
        if (this.currentRequestId !== reqId) return;

        const kind = embed?.kind ?? this.kindFromURL(url);
        const parsed = this.parseSpotifyURL(url);
        const name =
          (embed?.name && embed.name.trim()) ||
          oembed?.title?.trim() ||
          (kind === 'track' ? 'Song' : kind === 'album' ? 'Album' : 'Playlist');

        let trackIds = embed?.trackIds ?? [];
        let trackNames = embed?.trackNames ?? [];
        let trackCount = embed?.trackCount ?? 0;

        if (kind === 'track' && parsed) {
          if (!trackIds.includes(parsed.id)) trackIds = [parsed.id];
          if (trackCount < 1) trackCount = 1;
          if (!trackNames.length) trackNames = [name];
        }

        quickByUrl.set(url, {
          id: url,
          url,
          kind,
          name,
          detail: embed?.detail ?? '',
          trackCount: trackCount > 0 ? trackCount : trackIds.length,
          trackIds,
          trackNames,
          alreadyHave: 0,
          status: 'unknown',
          error: null,
        });
      })
    );

    const quickResults = targetURLs.map((url) => quickByUrl.get(url)).filter(Boolean) as LinkPreview[];

    if (this.currentRequestId !== reqId) return;
    if (quickResults.length) {
      const withLocal = quickResults.map((preview) => this.applyLocalMatch(preview, localIds));
      this.previews = withLocal;
      this.isLoading = false;
      this.inputError = null;
      this.message = '';
      this.notify();
    }

    // Phase 2: enrich with signed-in zotify metadata when available.
    const api = (window as any).electronAPI;
    const hasRuntime = api ? await api.hasRuntime() : false;
    const hasCreds = api
      ? await api.exists((await getAppPaths()).zotifyCredentialsPath)
      : false;

    if (!hasRuntime || !hasCreds) {
      this.isEnriching = false;
      this.notify();
      return;
    }

    this.isEnriching = true;
    this.notify();

    const enriched: LinkPreview[] = [];
    for (const url of targetURLs) {
      if (this.currentRequestId !== reqId) return;
      const quick = quickResults.find((q) => q.url === url);
      try {
        const meta = await this.fetchMetadata(url);
        const ids = meta.trackIds.length ? meta.trackIds : quick?.trackIds ?? [];
        const names = meta.trackNames.length ? meta.trackNames : quick?.trackNames ?? [];
        const count = Math.max(meta.trackCount, ids.length, quick?.trackCount ?? 0);
        enriched.push(
          this.applyLocalMatch(
            {
              id: url,
              url,
              kind: meta.kind,
              name: meta.name || quick?.name || 'Unknown',
              detail: meta.detail || quick?.detail || '',
              trackCount: count,
              trackIds: ids,
              trackNames: names,
              alreadyHave: 0,
              status: 'unknown',
              error: null,
            },
            localIds
          )
        );
      } catch {
        if (quick) enriched.push(this.applyLocalMatch(quick, localIds));
      }
    }

    if (this.currentRequestId !== reqId) return;
    if (enriched.length) this.previews = enriched;
    this.isLoading = false;
    this.isEnriching = false;
    this.notify();
  }

  private applyLocalMatch(preview: LinkPreview, localIds: Set<string>): LinkPreview {
    const ids = preview.trackIds;
    if (!ids.length) return preview;
    const have = ids.filter((id) => localIds.has(id)).length;
    let status: MatchStatus = 'unknown';
    if (have === 0) status = 'noneDownloaded';
    else if (have >= ids.length) status = 'fullyDownloaded';
    else status = 'partiallyDownloaded';
    return { ...preview, alreadyHave: have, status };
  }

  async lookup(urlText: string, musicRoot: string): Promise<{ preview: LinkPreview | null; error: string | null }> {
    const trimmed = urlText.trim();
    if (!trimmed) return { preview: null, error: 'Paste a Spotify playlist, album, or song link.' };
    const urls = this.extractSpotifyURLs(trimmed);
    if (!urls.length) return { preview: null, error: 'That doesn’t look like a Spotify playlist, album, or song link.' };

    const url = urls[0];
    const localIds = await this.loadLocalTrackIds(musicRoot);
    const embed = await this.fetchPublicEmbedMeta(url);
    const kind = embed?.kind ?? this.kindFromURL(url);
    const parsed = this.parseSpotifyURL(url);

    let trackIds = embed?.trackIds ?? [];
    let trackCount = embed?.trackCount ?? 0;
    let name = embed?.name ?? '';
    if (kind === 'track' && parsed) {
      if (!trackIds.includes(parsed.id)) trackIds = [parsed.id];
      trackCount = 1;
    }

    if (!name) {
      try {
        const oembed = await this.fetchOEmbed(url);
        name = oembed.title;
      } catch (_) {}
    }

    if (!name && !trackCount) {
      return { preview: null, error: 'Couldn’t find that on Spotify.' };
    }

    const preview = this.applyLocalMatch(
      {
        id: url,
        url,
        kind,
        name: name || 'Playlist',
        detail: embed?.detail ?? '',
        trackCount: Math.max(trackCount, trackIds.length),
        trackIds,
        trackNames: embed?.trackNames ?? [],
        alreadyHave: 0,
        status: 'unknown',
        error: null,
      },
      localIds
    );
    return { preview, error: null };
  }

  private async fetchPublicEmbedMeta(url: string): Promise<{
    kind: 'playlist' | 'album' | 'track' | 'unknown';
    name: string;
    detail: string;
    trackCount: number;
    trackIds: string[];
    trackNames: string[];
  } | null> {
    const parsed = this.parseSpotifyURL(url);
    if (!parsed) return null;

    const embedURL = `https://open.spotify.com/embed/${parsed.kind}/${parsed.id}`;
    try {
      const res = await fetch(embedURL, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      });
      if (!res.ok) return null;
      const html = await res.text();

      let name = '';
      const nameMatch = html.match(/"name"\s*:\s*"((?:[^"\\]|\\.)*)"/);
      if (nameMatch) {
        name = nameMatch[1].replace(/\\"/g, '"').replace(/\\\//g, '/');
      }
      if (!name) {
        const titleMatch = html.match(/"title"\s*:\s*"((?:[^"\\]|\\.)*)"/);
        if (titleMatch) name = titleMatch[1];
      }

      const trackIds: string[] = [];
      const seen = new Set<string>();
      const idRe = /spotify:track:([A-Za-z0-9]+)/g;
      let m: RegExpExecArray | null;
      while ((m = idRe.exec(html)) !== null) {
        if (!seen.has(m[1])) {
          seen.add(m[1]);
          trackIds.push(m[1]);
        }
      }

      let rowMax = -1;
      const rowRe = /tracklist-row-(\d+)/g;
      while ((m = rowRe.exec(html)) !== null) {
        rowMax = Math.max(rowMax, parseInt(m[1], 10));
      }
      const rowCount = rowMax >= 0 ? rowMax + 1 : 0;
      let trackCount = Math.max(trackIds.length, rowCount);
      if (parsed.kind === 'track') trackCount = Math.max(trackCount, 1);

      const trackNames: string[] = [];
      const titleRe = /TracklistRow_title__[^"]*"[^>]*>([^<]+)</g;
      while ((m = titleRe.exec(html)) !== null) {
        const t = m[1].trim();
        if (t) trackNames.push(t);
      }
      while (trackNames.length < trackIds.length) {
        trackNames.push(`Song ${trackNames.length + 1}`);
      }

      if (trackCount <= 0 && !name) return null;
      return {
        kind: parsed.kind as 'playlist' | 'album' | 'track',
        name: name || (parsed.kind === 'track' ? 'Song' : parsed.kind),
        detail: '',
        trackCount,
        trackIds: parsed.kind === 'track' && trackIds.length === 0 ? [parsed.id] : trackIds,
        trackNames,
      };
    } catch {
      return null;
    }
  }

  private parseSpotifyURL(raw: string): { kind: 'playlist' | 'album' | 'track'; id: string } | null {
    const m = raw.match(/(playlist|album|track)[/:]([A-Za-z0-9]+)/i);
    if (!m) return null;
    return { kind: m[1].toLowerCase() as 'playlist' | 'album' | 'track', id: m[2] };
  }

  private async fetchOEmbed(url: string): Promise<{ title: string; thumbnailURL: string }> {
    if (this.oembedCache.has(url)) return this.oembedCache.get(url)!;
    const res = await fetch(`https://open.spotify.com/oembed?url=${encodeURIComponent(url)}`);
    if (!res.ok) throw new Error('oEmbed request failed');
    const data = await res.json();
    const result = { title: data.title || '', thumbnailURL: data.thumbnail_url || '' };
    this.oembedCache.set(url, result);
    return result;
  }

  private async fetchMetadata(url: string): Promise<{
    kind: 'playlist' | 'album' | 'track' | 'unknown';
    name: string;
    detail: string;
    trackCount: number;
    trackIds: string[];
    trackNames: string[];
  }> {
    const paths = await getAppPaths();
    const configEscaped = escapePythonPath(paths.zotifyConfigPath);

    const script = `
import json, os, re, sys, time, requests
raw = sys.argv[1].strip()
m = re.search(r'(playlist|album|track)[/:]([A-Za-z0-9]+)', raw)
if not m:
    print("OZ_JSON|" + json.dumps({"ok": False, "error": "Not a Spotify link"}))
    raise SystemExit(0)
kind, sid = m.group(1), m.group(2)
OZ_CONFIG = ${configEscaped}

from argparse import Namespace
from zotify.config import Zotify, Config
from zotify.termoutput import Printer
Printer.splash = staticmethod(lambda: None)
Zotify.CONFIG = Config()
Zotify.start()
fields = dict(persist=False, update_config=False, update_archive=False, debug=False,
              no_splash=True, config_location=OZ_CONFIG, username=None, token=None, urls='',
              file_of_urls=None, liked_songs=False, user_playlists=False,
              followed_artists=False, followed_albums=False, search=None, verify_library=False)
args = Namespace(**fields)
Zotify.CONFIG.load(args)
for i in range(4):
    try:
        Zotify.login(args); break
    except Exception:
        time.sleep(2)
else:
    print("OZ_JSON|" + json.dumps({"ok": False, "error": "Sign in with Spotify in Preferences first"}))
    raise SystemExit(0)

try:
    from zotify.api import Playlist as _Pl, Album as _Al, Track as _Tr
    uri = f"spotify:{kind}:{sid}"
    if kind == "playlist":
        resp = Zotify.invoke_libre_md(_Pl, uri) or {}
        a = resp.get('attributes') or {}
        name = resp.get('name') or a.get('name') or "Playlist"
        ow = resp.get('owner') or {}
        detail = ow.get('display_name') or ow.get('name') or ''
        contents = (resp.get('contents') or {}).get('items') or []
        ids = [it.get('uri','').split(':')[-1] for it in contents if it.get('uri')]
        names = [(it.get('attributes') or {}).get('name') or f"Track {i+1}" for i, it in enumerate(contents)]
        count = len(ids)
    elif kind == "album":
        resp = Zotify.invoke_libre_md(_Al, uri) or {}
        name = resp.get('name') or "Album"
        arts = resp.get('artist') or resp.get('artists') or []
        detail = ", ".join(a.get('name','') for a in arts if isinstance(a, dict))
        tracks = resp.get('tracks') or []
        ids = [t.get('uri','').split(':')[-1] for t in tracks if t.get('uri')]
        names = [t.get('name') or f"Track {i+1}" for i, t in enumerate(tracks)]
        count = len(ids)
    else:
        resp = Zotify.invoke_libre_md(_Tr, uri) or {}
        name = resp.get('name') or "Track"
        arts = resp.get('artist') or resp.get('artists') or []
        detail = ", ".join(a.get('name','') for a in arts if isinstance(a, dict))
        ids = [sid]
        names = [name]
        count = 1

    print("OZ_JSON|" + json.dumps({
        "ok": True, "kind": kind, "name": name, "detail": detail,
        "trackCount": count, "trackIds": ids, "trackNames": names
    }))
except Exception as e:
    print("OZ_JSON|" + json.dumps({"ok": False, "error": str(e)}))
`;

    const res = await ZotifyCLI.run({
      id: 'link_metadata',
      command: 'python',
      args: ['-c', script, url],
      stallTimeout: 25,
    });

    const data = await ZotifyCLI.parseOzJSON(res.output);
    if (!data || !data.ok) {
      throw new Error(data?.error || 'Could not fetch metadata from Spotify');
    }

    return {
      kind: data.kind,
      name: data.name,
      detail: data.detail,
      trackCount: data.trackCount,
      trackIds: data.trackIds || [],
      trackNames: data.trackNames || [],
    };
  }

  private async loadLocalTrackIds(musicRoot: string): Promise<Set<string>> {
    const api = (window as any).electronAPI;
    if (!api || !musicRoot) return new Set();
    const ids = await api.loadLocalTrackIds(musicRoot);
    return new Set(ids);
  }

  private kindFromURL(url: string): 'playlist' | 'album' | 'track' | 'unknown' {
    if (url.includes('/playlist/') || url.includes('spotify:playlist:')) return 'playlist';
    if (url.includes('/album/') || url.includes('spotify:album:')) return 'album';
    if (url.includes('/track/') || url.includes('spotify:track:')) return 'track';
    return 'unknown';
  }

  private extractSpotifyURLs(text: string): string[] {
    const pattern = /https?:\/\/open\.spotify\.com\/(playlist|album|track)\/[A-Za-z0-9]+[^\s]*|spotify:(playlist|album|track):[A-Za-z0-9]+/gi;
    const matches = text.match(pattern);
    if (!matches) return [];
    return Array.from(new Set(matches.map((u) => u.split('?')[0])));
  }
}

export const linkPreviewService = new LinkPreviewServiceState();
