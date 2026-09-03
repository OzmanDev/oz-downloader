import React, { useState, useEffect } from 'react';
import {
  Link as LinkIcon,
  XCircle,
  StopCircle,
  CheckCircle2,
  Sparkles,
  AlertCircle,
} from 'lucide-react';
import { appStore } from '../services/appStore';
import { downloadService } from '../services/downloadService';
import { linkPreviewService } from '../services/linkPreviewService';
import { LinkPreviewCard } from '../components/LinkPreviewCard';

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
    statusMessage.toLowerCase().includes('stop') ||
    statusMessage.toLowerCase().includes('completed');

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
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="text-sm font-semibold text-white">Progress</span>
              {isRunning && (
                <span className="px-2 py-0.5 text-xs font-medium bg-sky-500/20 text-sky-400 rounded-full animate-pulse">
                  Downloading
                </span>
              )}
              {isConverting && (
                <span className="px-2 py-0.5 text-xs font-medium bg-purple-500/20 text-purple-400 rounded-full">
                  Converting
                </span>
              )}
            </div>

            <div className="flex items-center gap-3">
              {downloadRate && (
                <span className="text-xs font-mono text-neutral-400">{downloadRate}</span>
              )}
              {isRunning && (
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

          <p className="text-xs text-neutral-300 font-medium">{statusMessage}</p>

          {/* Song Items List */}
          {songItems.length > 0 && (
            <div className="max-h-60 overflow-y-auto space-y-2 pr-1 border-t border-white/5 pt-3">
              {songItems.map((song) => (
                <div
                  key={song.number}
                  className="flex items-center justify-between text-xs py-1.5 px-2.5 rounded-lg bg-[#1c1c1e]/60 border border-white/5"
                >
                  <div className="flex items-center gap-2 truncate pr-2">
                    <span className="text-neutral-500 font-mono w-5">{song.number}</span>
                    <span className="text-neutral-200 truncate">{song.name}</span>
                  </div>

                  <div className="flex-shrink-0">
                    {song.status === 'done' ? (
                      <span className="text-emerald-400 flex items-center gap-1 font-medium">
                        <CheckCircle2 className="w-3.5 h-3.5" /> Done
                      </span>
                    ) : song.status === 'skipped' ? (
                      <span className="text-neutral-400">
                        Skipped ({song.skipReason === 'duplicate' ? 'duplicate' : 'exists'})
                      </span>
                    ) : song.status === 'downloading' ? (
                      <span className="text-sky-400 font-mono">
                        {Math.round(song.fraction * 100)}%
                      </span>
                    ) : song.status === 'failed' ? (
                      <span className="text-red-400 flex items-center gap-1">
                        <AlertCircle className="w-3.5 h-3.5" /> Error
                      </span>
                    ) : (
                      <span className="text-neutral-500">Pending</span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* Celebration Banner */}
          {showCelebration && (
            <div className="p-3 bg-emerald-500/15 border border-emerald-500/30 rounded-xl flex items-center gap-2.5 text-emerald-400 text-sm font-medium">
              <Sparkles className="w-4 h-4" />
              <span>Download completed successfully!</span>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
