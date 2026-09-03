export interface AppSettings {
  rootPath: string;
  downloadFormat: string;
  downloadQuality: string;
  bulkWaitTime: string;
  downloadRateLimiter: string;
  retryAttempts: string;
  skipExisting: boolean;
  skipPreviouslyDownloaded: boolean;
  apiClientId: string;
  convertFormat: string;
  autoPostprocess: boolean;
  defaultGenre: string;
}

export const DEFAULT_APP_SETTINGS: AppSettings = {
  rootPath: '', // Will be resolved dynamically to Music/Oz Downloader
  downloadFormat: 'ogg',
  downloadQuality: 'very_high',
  bulkWaitTime: '1',
  downloadRateLimiter: '0',
  retryAttempts: '3',
  skipExisting: true,
  skipPreviouslyDownloaded: false,
  apiClientId: '',
  convertFormat: 'flac',
  autoPostprocess: true,
  defaultGenre: '',
};

export interface SavedPlaylist {
  alias: string;
  name: string;
  url: string;
  trackCount: number;
  imageURL: string;
}

export interface FetchedPlaylist {
  id: string;
  name: string;
  url: string;
  owner?: string;
  isOwned: boolean;
  isSpotify: boolean;
  trackCount: number;
  imageURL: string;
}

export type PlaylistFilter = 'all' | 'byMe' | 'followed' | 'spotify';

export interface SpotifyAccountInfo {
  userId: string;
  displayName: string;
  imageURL: string;
}

export const EMPTY_ACCOUNT_INFO: SpotifyAccountInfo = {
  userId: '',
  displayName: '',
  imageURL: '',
};

export type AudioFormatId = 'flac' | 'mp3' | 'm4a' | 'wav' | 'ogg' | 'none';

export interface AudioFormatChoice {
  id: AudioFormatId;
  label: string;
}

export const AUDIO_FORMAT_CHOICES: AudioFormatChoice[] = [
  { id: 'flac', label: 'Best quality (FLAC)' },
  { id: 'mp3', label: 'Compatible (MP3)' },
  { id: 'm4a', label: 'Apple Music friendly (M4A)' },
  { id: 'wav', label: 'Uncompressed (WAV)' },
  { id: 'ogg', label: 'Keep as OGG' },
  { id: 'none', label: 'Don’t convert' },
];

export type QualityId = 'auto' | 'normal' | 'high' | 'very_high';

export interface QualityChoice {
  id: QualityId;
  label: string;
}

export const QUALITY_CHOICES: QualityChoice[] = [
  { id: 'auto', label: 'Automatic' },
  { id: 'normal', label: 'Standard' },
  { id: 'high', label: 'High' },
  { id: 'very_high', label: 'Highest' },
];

export type DownloadTabBadge = 'none' | 'inProgress' | 'success' | 'failure';
