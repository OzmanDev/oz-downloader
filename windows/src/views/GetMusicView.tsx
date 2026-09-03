import React, { useState, useEffect, useMemo } from 'react';
import {
  Link as LinkIcon,
  XCircle,
  StopCircle,
  Sparkles,
  AlertCircle,
  ChevronRight,
  RefreshCw,
} from 'lucide-react';
import { appStore } from '../services/appStore';
import { downloadService } from '../services/downloadService';
import { linkPreviewService } from '../services/linkPreviewService';
import { LinkPreviewCard } from '../components/LinkPreviewCard';
import { SongDownloadItem } from '../types/downloads';

export const GetMusicView: React.FC = () => {
  const [urlsText, setUrlsText] = useState(linkPreviewService.urlsText);
  const [previews, setPreviews] = useState(linkPreviewService.previews);
  const [isLoading, setIsLoading] = useState(linkPreviewService.isLoading);
  const [inputError, setInputError] = useState(linkPreviewService.inputError);
  const [isRunning, setIsRunning] = useState(downloadService.isRunning);
  const [isConverting, setIsConverting] = useState(downloadService.isConverting);
  const [songItems, setSongItems] = useState(downloadService.songItems);
  const [queueItems, setQueueItems] = useState(downloadService.queueItems);
  const [statusMessage, setStatusMessage] = useState(downloadService.statusMessage);
  const [downloadRate, setDownloadRate] = useState(downloadService.downloadRate);
  const [showCelebration, setShowCelebration] = useState(downloadService.showCelebration);
  const [phaseLabel, setPhaseLabel] = useState(downloadService.phaseStatusLabel);
  const [phaseSummary, setPhaseSummary] = useState(downloadService.phaseProgressSummary);
  const [convertFraction, setConvertFraction] = useState(downloadService.convertFraction);
  const [convertLabel, setConvertLabel] = useState(downloadService.convertLabel);
  const [convertSkipped, setConvertSkipped] = useState(downloadService.convertSkipped);
  const [showProgressDetails, setShowProgressDetails] = useState(
    downloadService.showProgressDetails
  );
  const [downloadErrorMessage, setDownloadErrorMessage] = useState(
    downloadService.downloadErrorMessage
  );

  useEffect(() => {
    const unsubPreview = linkPreviewService.subscribe(() => {
      setUrlsText(linkPreviewService.urlsText);
      setPreviews([...linkPreviewService.previews]);
      setIsLoading(linkPreviewService.isLoading);
      setInputError(linkPreviewService.inputError);
    });

    const unsubDownload = downloadService.subscribe(() => {
      setIsRunning(downloadService.isRunning);
      setIsConverting(downloadService.isConverting);
      setSongItems([...downloadService.songItems]);
      setQueueItems([...downloadService.queueItems]);
      setStatusMessage(downloadService.statusMessage);
      setDownloadRate(downloadService.downloadRate);
      setShowCelebration(downloadService.showCelebration);
      setPhaseLabel(downloadService.phaseStatusLabel);
      setPhaseSummary(downloadService.phaseProgressSummary);
      setConvertFraction(downloadService.convertFraction);
      setConvertLabel(downloadService.convertLabel);
      setConvertSkipped(downloadService.convertSkipped);
      setShowProgressDetails(downloadService.showProgressDetails);
      setDownloadErrorMessage(downloadService.downloadErrorMessage);
    });

    return () => {
      unsubPreview();
      unsubDownload();
    };
  }, []);

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = e.target.value;
    setUrlsText(val);
    linkPreviewService.schedulePreview(val, appStore.settings.rootPath);
  };

  const handleStartDownload = () => {
    if (previews.length > 0 && !previews[0].error) {
      const p = previews[0];
      downloadService.startDownload(p.url, p.name, p.trackCount);
    } else if (urlsText.trim()) {
      downloadService.startDownload(urlsText.trim(), 'Download');
    }
  };

  const hasProgress =
    isRunning ||
    isConverting ||
    queueItems.length > 0 ||
    songItems.length > 0 ||
    !!downloadErrorMessage ||
    statusMessage.toLowerCase().includes('stop') ||
    statusMessage.toLowerCase().includes('done') ||
    statusMessage.toLowerCase().includes('completed');

  const autoConvert =
    appStore.settings.autoPostprocess && appStore.settings.convertFormat !== 'none';

  const allSongsFinished =
    songItems.length > 0 && songItems.every((s) => s.status !== 'pending' && s.status !== 'downloading');

  const isPreparingConvert =
    autoConvert &&
    isRunning &&
    !isConverting &&
    convertFraction <= 0 &&
    !convertSkipped &&
    allSongsFinished;

  const showsConvertProgress =
    autoConvert &&
    (isConverting ||
      convertFraction > 0 ||
      convertSkipped ||
      isPreparingConvert ||
      /fail|converted|no new/i.test(convertLabel));

  const waiting = useMemo(
    () => songItems.filter((s) => s.status === 'pending'),
    [songItems]
  );
  const inProgress = useMemo(
    () => songItems.filter((s) => s.status === 'downloading' || s.status === 'failed'),
    [songItems]
  );
  const skipped = useMemo(
    () => songItems.filter((s) => s.status === 'skipped'),
    [songItems]
  );
  const downloaded = useMemo(
    () => songItems.filter((s) => s.status === 'done'),
    [songItems]
  );

  const convertBarValue = (() => {
    if (isConverting || convertFraction > 0) return Math.max(0.02, convertFraction);
    if (isPreparingConvert) return 0.02;
    return 0;
  })();

  const convertStatusLabel = (() => {
    if (convertSkipped) return 'Skipped';
    if (/fail/i.test(convertLabel)) return 'Failed';
    if (convertFraction >= 1 && !isConverting) return 'Done';
    if (isConverting) return `${Math.round(convertFraction * 100)}%`;
    if (isPreparingConvert) return 'Starting…';
    return '—';
  })();

  const convertDetail = (() => {
    if (convertSkipped) return convertLabel || 'Convert skipped';
    if (/fail/i.test(convertLabel)) return convertLabel;
    if (convertFraction >= 1 && !isConverting) {
      return convertLabel || 'Converted · lyrics embedded · renamed';
    }
    if (isConverting) return convertLabel || 'Converting to FLAC + lyrics…';
    if (isPreparingConvert) return 'Download done — starting convert…';
    return convertLabel || 'Converting to FLAC + lyrics…';
  })();

  const convertBarTint = convertSkipped || /fail/i.test(convertLabel)
    ? 'bg-orange-400'
    : convertFraction >= 1 && !isConverting
      ? 'bg-emerald-400'
      : 'bg-sky-400';

  const headerStatus = (() => {
    if (isConverting) return convertLabel || 'Converting…';
    if (isPreparingConvert) return 'Preparing convert…';
    if (downloadRate && !/looking for|on disk|of /i.test(downloadRate)) return downloadRate;
    if (phaseLabel) return phaseLabel;
    return statusMessage;
  })();

  const summaryText = (() => {
    if (showCelebration) return '';
    if (isConverting) return convertLabel || phaseSummary;
    if (isPreparingConvert) return 'Download done — starting convert…';
    if (phaseSummary) return phaseSummary;
    return statusMessage;
  })();

  const finishedCount = songItems.filter(
    (s) => s.status === 'done' || s.status === 'skipped'
  ).length;
  const expectedCount = Math.max(
    downloadService.totalExpected,
    songItems.length,
    0
  );

  return (
    <div className="flex-1 overflow-y-auto px-8 py-6 space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-white tracking-tight">Get music</h1>
        <p className="text-sm text-neutral-400">Paste a Spotify link to download.</p>
      </div>

      {/* Input Card */}
      <div className="p-4 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-md space-y-3">
        <label className="text-sm font-semibold text-white">Spotify link</label>
        <div className="relative flex items-center">
          <LinkIcon className="absolute left-3.5 w-4 h-4 text-sky-400" />
          <input
            type="text"
            value={urlsText}
            onChange={handleInputChange}
            placeholder="Paste a Spotify playlist, album, or song link"
            className="w-full bg-[#1c1c1e] text-white pl-10 pr-10 py-2.5 rounded-lg border border-white/10 focus:outline-none focus:border-sky-500 text-sm transition"
          />
          {isLoading ? (
            <div className="absolute right-3.5 w-4 h-4 border-2 border-sky-400 border-t-transparent rounded-full animate-spin" />
          ) : urlsText ? (
            <button
              onClick={() => linkPreviewService.clear()}
              className="absolute right-3.5 text-neutral-400 hover:text-white transition"
            >
              <XCircle className="w-4 h-4" />
            </button>
          ) : null}
        </div>
        {inputError && <p className="text-xs text-red-400">{inputError}</p>}
      </div>

      {/* Previews */}
      {previews.map((preview) => (
        <LinkPreviewCard
          key={preview.url}
          preview={preview}
          isDownloading={isRunning}
          canDownload={!isRunning}
          onDownload={handleStartDownload}
        />
      ))}

      {/* Progress Section */}
      {hasProgress && (
        <div className="p-5 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-lg space-y-4">
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-2 min-w-0">
              <span className="text-sm font-semibold text-white">Progress</span>
              {(isRunning || isConverting) && (
                <span className="text-xs text-neutral-400 truncate">{headerStatus}</span>
              )}
              {(isRunning || isConverting) && (
                <div className="w-3.5 h-3.5 border-2 border-sky-400 border-t-transparent rounded-full animate-spin flex-shrink-0" />
              )}
            </div>

            <div className="flex items-center gap-3 flex-shrink-0">
              {(isRunning || isConverting) && (
                <button
                  onClick={() => downloadService.cancel()}
                  className="flex items-center gap-1 px-3 py-1 bg-red-500/20 hover:bg-red-500/30 text-red-400 rounded-lg text-xs font-medium transition"
                >
                  <StopCircle className="w-3.5 h-3.5" />
                  <span>Cancel</span>
                </button>
              )}
            </div>
          </div>

          {showCelebration ? (
            <div className="p-3 bg-emerald-500/15 border border-emerald-500/30 rounded-xl flex items-center gap-2.5 text-emerald-400 text-sm font-medium">
              <Sparkles className="w-4 h-4" />
              <span>Hell yeah, all done! Open Downloads to listen.</span>
            </div>
          ) : (
            summaryText && <p className="text-xs text-neutral-300">{summaryText}</p>
          )}

          {downloadErrorMessage && (
            <div className="flex items-start gap-2 text-xs text-red-400">
              <AlertCircle className="w-3.5 h-3.5 mt-0.5 flex-shrink-0" />
              <span className="whitespace-pre-wrap">{downloadErrorMessage}</span>
            </div>
          )}

          {/* Queue */}
          {queueItems.length > 0 && (
            <div className="space-y-2 rounded-lg bg-[#1c1c1e]/60 border border-white/5 p-3">
              {queueItems.map((item, index) => {
                const role =
                  item.status === 'done'
                    ? 'Done'
                    : item.status === 'failed'
                      ? 'Failed'
                      : item.status === 'cancelled'
                        ? 'Skipped'
                        : index === downloadService.currentQueueIndex && (isRunning || isConverting)
                          ? 'Now'
                          : index > downloadService.currentQueueIndex
                            ? 'Next'
                            : 'Done';
                return (
                  <div key={item.id} className="flex items-center gap-2.5 text-xs">
                    <span
                      className={`w-10 font-semibold ${
                        role === 'Now'
                          ? 'text-sky-400'
                          : role === 'Failed'
                            ? 'text-orange-400'
                            : 'text-neutral-500'
                      }`}
                    >
                      {role}
                    </span>
                    <span
                      className={`truncate ${
                        role === 'Done' || role === 'Skipped'
                          ? 'text-neutral-500'
                          : 'text-neutral-200'
                      }`}
                    >
                      {item.name}
                    </span>
                    {item.trackCount > 0 && (
                      <span className="text-neutral-500 flex-shrink-0">
                        {item.trackCount} songs
                      </span>
                    )}
                  </div>
                );
              })}
            </div>
          )}

          {/* Convert or Total progress */}
          {showsConvertProgress ? (
            <div className="space-y-1.5">
              <div className="flex items-baseline justify-between gap-2">
                <div className="flex items-center gap-2 text-sm font-medium text-white">
                  <RefreshCw className="w-3.5 h-3.5 text-neutral-400" />
                  <span>Convert</span>
                </div>
                <span className="text-xs font-mono text-neutral-400">{convertStatusLabel}</span>
              </div>
              <p className="text-xs text-neutral-400 line-clamp-2">{convertDetail}</p>
              <div className="h-1.5 rounded-full bg-white/10 overflow-hidden">
                <div
                  className={`h-full rounded-full transition-all ${convertBarTint}`}
                  style={{ width: `${Math.round(convertBarValue * 100)}%` }}
                />
              </div>
            </div>
          ) : (
            <div className="space-y-1.5">
              <div className="flex items-baseline justify-between gap-2">
                <span className="text-sm font-medium text-white">
                  {queueItems.length > 1 ? 'This playlist' : 'Total'}
                </span>
                <span className="text-xs font-mono text-neutral-400">
                  {expectedCount > 0
                    ? `${finishedCount} of ${expectedCount}`
                    : isRunning
                      ? 'Starting…'
                      : '—'}
                </span>
              </div>
              <div className="h-1.5 rounded-full bg-white/10 overflow-hidden">
                <div
                  className="h-full rounded-full bg-sky-400 transition-all"
                  style={{
                    width: `${Math.round(downloadService.totalFraction * 100)}%`,
                  }}
                />
              </div>
            </div>
          )}

          {/* Show / Hide details */}
          {songItems.length > 0 && (
            <button
              type="button"
              onClick={() => downloadService.toggleProgressDetails()}
              className="flex items-center gap-1.5 text-sm text-neutral-200 hover:text-white transition"
            >
              <ChevronRight
                className={`w-3.5 h-3.5 text-neutral-400 transition-transform ${
                  showProgressDetails ? 'rotate-90' : ''
                }`}
              />
              {showProgressDetails ? 'Hide details' : 'Show details'}
            </button>
          )}

          {showProgressDetails && songItems.length > 0 && (
            <div className="grid grid-cols-4 gap-2">
              <ProgressColumn title="Waiting" songs={waiting} accent="border-white/10" />
              <ProgressColumn
                title="In progress"
                songs={inProgress}
                accent="border-sky-500/40"
              />
              <ProgressColumn title="Skipped" songs={skipped} accent="border-orange-500/40" />
              <ProgressColumn
                title="Downloaded"
                songs={downloaded}
                accent="border-emerald-500/40"
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
};

function songStatusLabel(song: SongDownloadItem): string {
  switch (song.status) {
    case 'pending':
      return 'Waiting';
    case 'downloading':
      return `${Math.round(Math.max(song.fraction, 0) * 100)}%`;
    case 'done':
      return 'Downloaded';
    case 'skipped':
      if (song.skipReason === 'duplicate') return 'Duplicate';
      if (song.skipReason === 'alreadySaved') return 'Already here';
      if (song.skipReason === 'cancelled') return 'Cancelled';
      return 'Skipped';
    case 'failed':
      return 'Failed';
    default:
      return '';
  }
}

function songBarColor(song: SongDownloadItem): string {
  switch (song.status) {
    case 'done':
      return 'bg-emerald-400';
    case 'skipped':
      return 'bg-orange-400';
    case 'failed':
      return 'bg-red-400';
    case 'downloading':
      return 'bg-sky-400';
    default:
      return 'bg-neutral-500';
  }
}

const ProgressColumn: React.FC<{
  title: string;
  songs: SongDownloadItem[];
  accent: string;
}> = ({ title, songs, accent }) => (
  <div className={`rounded-lg bg-[#1c1c1e]/60 border ${accent} p-2 space-y-1.5 min-w-0`}>
    <div className="flex items-baseline gap-1">
      <span className="text-[11px] font-semibold text-neutral-400 truncate">{title}</span>
      <span className="text-[10px] font-mono text-neutral-500">({songs.length})</span>
    </div>
    {songs.length === 0 ? (
      <p className="text-[10px] text-neutral-600 pt-0.5">None yet</p>
    ) : (
      songs.map((song) => (
        <div key={song.id} className="space-y-1">
          <div className="flex items-start gap-1 min-w-0">
            <span className="text-[10px] font-mono text-neutral-500 flex-shrink-0">
              {song.number}.
            </span>
            <span className="text-[11px] text-neutral-200 leading-snug line-clamp-2">
              {song.name}
            </span>
          </div>
          <p className="text-[10px] text-neutral-500">{songStatusLabel(song)}</p>
          {(song.status === 'downloading' ||
            song.status === 'failed' ||
            song.status === 'done' ||
            song.status === 'skipped') && (
            <div className="h-1 rounded-full bg-white/10 overflow-hidden">
              <div
                className={`h-full rounded-full ${songBarColor(song)}`}
                style={{
                  width: `${Math.round(
                    (song.status === 'downloading'
                      ? Math.max(song.fraction, 0.05)
                      : 1) * 100
                  )}%`,
                }}
              />
            </div>
          )}
        </div>
      ))
    )}
  </div>
);
