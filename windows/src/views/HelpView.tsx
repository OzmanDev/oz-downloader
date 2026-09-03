import React from 'react';
import { Mail, Instagram } from 'lucide-react';
import { downloadService } from '../services/downloadService';

export const HelpView: React.FC = () => {
  const email = 'mailosman.dev@gmail.com';
  const instagramURL = 'https://www.instagram.com/oz.suliman/';

  const copyEmail = () => {
    const api = (window as any).electronAPI;
    if (api) {
      api.writeClipboard(email);
    } else {
      navigator.clipboard.writeText(email);
    }
    downloadService.showToast('Email copied');
  };

  const openInstagram = () => {
    const api = (window as any).electronAPI;
    if (api) {
      api.openExternal(instagramURL);
    } else {
      window.open(instagramURL, '_blank');
    }
  };

  return (
    <div className="flex-1 overflow-y-auto px-8 py-6 space-y-6 max-w-2xl">
      <div>
        <h1 className="text-2xl font-bold text-white tracking-tight">Oz Downloader</h1>
        <div className="text-sm font-medium text-neutral-400 mt-1">v0.2.0</div>
        <p className="text-sm text-neutral-400 mt-1">
          Download your Spotify playlists to this PC — simply.
        </p>
      </div>

      {/* Tip 1 */}
      <div className="p-4 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-md space-y-2">
        <h2 className="text-sm font-semibold text-white">How to get started</h2>
        <p className="text-xs text-neutral-300 whitespace-pre-line leading-relaxed">
          1. Open Preferences and sign in with Spotify.{'\n'}
          2. Go to My Playlists and load your lists.{'\n'}
          3. Keep the ones you want, then download.{'\n\n'}
          Or paste a Spotify link directly on Get Music.
        </p>
      </div>

      {/* Tip 2 */}
      <div className="p-4 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-md space-y-2">
        <h2 className="text-sm font-semibold text-white">Your privacy</h2>
        <p className="text-xs text-neutral-300 leading-relaxed">
          Oz Downloader keeps its own Spotify login, settings, and download folder. It does not
          share them with anyone.
        </p>
      </div>

      {/* Tip 3 */}
      <div className="p-4 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-md space-y-2">
        <h2 className="text-sm font-semibold text-white">Downloads not working?</h2>
        <p className="text-xs text-neutral-300 leading-relaxed whitespace-pre-line">
          If you see “Download tools are missing”, the app was installed without bundled Python/zotify.
          Reinstall using OzDownloader-Installer.exe built on a Windows PC — not a copy built on Mac.
        </p>
      </div>

      {/* Tip 4 */}
      <div className="p-4 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-md space-y-2">
        <h2 className="text-sm font-semibold text-white">Need help?</h2>
        <p className="text-xs text-neutral-300 leading-relaxed">
          Something not working? Contact me and I’ll help you out.
        </p>
      </div>

      {/* Contact card */}
      <div className="p-4 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-md space-y-3">
        <h2 className="text-sm font-semibold text-white">Contact</h2>
        <div className="flex flex-col gap-2">
          <button
            onClick={copyEmail}
            className="flex items-center gap-2 text-xs text-sky-400 hover:text-sky-300 font-medium transition w-fit"
          >
            <Mail className="w-4 h-4" />
            <span>{email}</span>
          </button>

          <button
            onClick={openInstagram}
            className="flex items-center gap-2 text-xs text-sky-400 hover:text-sky-300 font-medium transition w-fit"
          >
            <Instagram className="w-4 h-4" />
            <span>instagram.com/oz.suliman</span>
          </button>
        </div>
      </div>
    </div>
  );
};
