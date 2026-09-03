import React from 'react';
import { Mail, Instagram } from 'lucide-react';
import { downloadService } from '../services/downloadService';

export const ContactFooter: React.FC = () => {
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
    <footer className="h-9 px-4 flex items-center justify-between bg-[#2c2c2e]/40 border-t border-white/5 text-xs text-neutral-400 select-none">
      <div>Oz Downloader v0.2.0 · made with ❤️ by Oz</div>

      <div className="flex items-center gap-4">
        <button
          onClick={copyEmail}
          className="flex items-center gap-1.5 hover:text-neutral-200 transition"
          title="Copy email to clipboard"
        >
          <Mail className="w-3.5 h-3.5" />
          <span>{email}</span>
        </button>

        <button
          onClick={openInstagram}
          className="flex items-center gap-1.5 hover:text-neutral-200 transition"
          title="instagram.com/oz.suliman"
        >
          <Instagram className="w-3.5 h-3.5" />
          <span>@oz.suliman</span>
        </button>
      </div>
    </footer>
  );
};
