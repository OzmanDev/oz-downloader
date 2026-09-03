import React from 'react';
import {
  Music,
  Disc3,
  Layers,
  AlertTriangle,
  ArrowDownCircle,
  CheckCircle2,
  PieChart,
  HelpCircle,
  PlusCircle,
} from 'lucide-react';
import { LinkPreview } from '../types/downloads';

interface LinkPreviewCardProps {
  preview: LinkPreview;
  downloadTitle?: string;
  isDownloading?: boolean;
  canDownload?: boolean;
  onDownload?: () => void;
}

export const LinkPreviewCard: React.FC<LinkPreviewCardProps> = ({
  preview,
  downloadTitle = 'Download',
  isDownloading = false,
  canDownload = true,
  onDownload,
}) => {
  const getKindIcon = () => {
    if (preview.error) return AlertTriangle;
    switch (preview.kind) {
      case 'album': return Layers;
      case 'track': return Music;
      default: return Disc3;
    }
  };

  const getKindLabel = () => {
    switch (preview.kind) {
      case 'album': return 'Album';
      case 'track': return 'Song';
      case 'playlist': return 'Playlist';
      default: return 'Link';
    }
  };

  const getStatusColor = () => {
    switch (preview.status) {
      case 'fullyDownloaded': return 'text-emerald-400 border-emerald-500/30';
      case 'partiallyDownloaded': return 'text-amber-400 border-amber-500/30';
      case 'noneDownloaded': return 'text-sky-400 border-sky-500/30';
      default: return 'text-neutral-400 border-neutral-600/30';
    }
  };

  const getStatusIcon = () => {
    switch (preview.status) {
      case 'fullyDownloaded': return CheckCircle2;
      case 'partiallyDownloaded': return PieChart;
      case 'noneDownloaded': return ArrowDownCircle;
      default: return HelpCircle;
    }
  };

  const getMatchLabel = () => {
    if (preview.kind === 'track') {
      if (preview.trackCount <= 0) return 'Ready to download';
    } else if (preview.trackCount <= 0) {
      return 'Looking up…';
    }
    switch (preview.status) {
      case 'fullyDownloaded':
        return `All ${preview.trackCount} already on this PC`;
      case 'partiallyDownloaded':
        return `${preview.alreadyHave} of ${preview.trackCount} already on this PC`;
      case 'noneDownloaded':
        return 'None downloaded yet';
      default:
        return 'Not on this PC yet';
    }
  };

  const Icon = getKindIcon();
  const StatusIcon = getStatusIcon();

  return (
    <div className={`flex items-start gap-4 p-4 rounded-xl bg-[#2c2c2e]/70 border ${
      preview.error ? 'border-red-500/40' : getStatusColor()
    } shadow-lg backdrop-blur-sm`}>
      <div className="w-10 flex justify-center pt-1 text-neutral-400">
        <Icon className={`w-7 h-7 ${preview.error ? 'text-red-400' : 'text-neutral-300'}`} />
      </div>

      <div className="flex-1 min-w-0 space-y-2">
        <h3 className="text-base font-semibold text-white truncate">
          {preview.error ? 'Not found' : preview.name}
        </h3>

        {preview.error ? (
          <p className="text-sm text-red-400">{preview.error}</p>
        ) : (
          <div className="flex flex-wrap items-center gap-2 text-sm text-neutral-400">
            <span className="px-2 py-0.5 text-xs font-medium bg-white/10 rounded-full text-neutral-300">
              {getKindLabel()}
            </span>
            <span>
              {preview.kind === 'track'
                ? '1 song'
                : preview.trackCount === 1
                ? '1 song'
                : `${preview.trackCount} songs`}
            </span>
            {preview.detail && (
              <>
                <span>·</span>
                <span className="truncate max-w-[200px]">{preview.detail}</span>
              </>
            )}
          </div>
        )}

        {!preview.error && onDownload && (
          <div className="flex items-center gap-3 pt-1">
            <button
              onClick={onDownload}
              disabled={!canDownload}
              className={`flex items-center gap-1.5 px-4 py-1.5 rounded-lg text-sm font-medium transition ${
                canDownload
                  ? 'bg-sky-500 hover:bg-sky-600 text-white shadow-md active:scale-98'
                  : 'bg-neutral-700 text-neutral-500 cursor-not-allowed'
              }`}
            >
              {isDownloading ? (
                <>
                  <PlusCircle className="w-4 h-4" />
                  <span>Add to queue</span>
                </>
              ) : (
                <>
                  <ArrowDownCircle className="w-4 h-4" />
                  <span>{downloadTitle}</span>
                </>
              )}
            </button>

            <span className="text-xs text-neutral-400 flex items-center gap-1">
              <StatusIcon className="w-3.5 h-3.5" />
              {getMatchLabel()}
            </span>
          </div>
        )}
      </div>
    </div>
  );
};
