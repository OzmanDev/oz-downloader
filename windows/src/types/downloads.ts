export type SongStatus = 'pending' | 'downloading' | 'done' | 'skipped' | 'failed';
export type SkipReason = 'none' | 'duplicate' | 'alreadySaved' | 'cancelled';

export type DownloadPhase =
  | 'idle'
  | 'starting'
  | 'fetchingTrackInfo'
  | 'checkingExisting'
  | 'downloading'
  | 'converting'
  | 'signingIn'
  | 'retrying'
  | 'stopping';

export interface SongDownloadItem {
  id: number;
  number: number;
  name: string;
  status: SongStatus;
  fraction: number;
  trackId: string;
  skipReason: SkipReason;
}

export type QueueStatus = 'pending' | 'downloading' | 'done' | 'failed' | 'cancelled';

export interface DownloadQueueItem {
  id: string; // url
  name: string;
  url: string;
  trackCount: number;
  imageURL: string;
  status: QueueStatus;
  retryAttempt: number;
  lastError: string;
}

export type MatchStatus = 'noneDownloaded' | 'partiallyDownloaded' | 'fullyDownloaded' | 'unknown';

export interface LinkPreview {
  id: string; // url
  url: string;
  kind: 'playlist' | 'album' | 'track' | 'unknown';
  name: string;
  detail: string;
  trackCount: number;
  trackIds: string[];
  trackNames: string[];
  alreadyHave: number;
  status: MatchStatus;
  error?: string | null;
}
