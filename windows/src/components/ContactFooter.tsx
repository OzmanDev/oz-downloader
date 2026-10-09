import React from 'react';
import { Mail, Instagram, Globe, Music } from 'lucide-react';
import { downloadService } from '../services/downloadService';

export const ContactFooter: React.FC = () => {
  const email = 'mailosman.dev@gmail.com';
  const instagramURL = 'https://www.instagram.com/oz.suliman/';
  const portfolioURL = 'https://osmandev.me/';
  const djPortfolioURL = 'https://osmandev.me/dj';

  const copyEmail = () => {
    const api = (window as any).electronAPI;
    if (api) {
      api.writeClipboard(email);
    } else {
      navigator.clipboard.writeText(email);
    }
    downloadService.showToast('Email copied');
  };

  const openLink = (url: string) => {
    const api = (window as any).electronAPI;
    if (api) {
      api.openExternal(url);
    } else {
      window.open(url, '_blank');
    }
  };

  return (
    <footer className="h-9 px-4 flex items-center justify-between bg-[#2c2c2e]/40 border-t border-white/5 text-xs text-neutral-400 select-none">
      <div>Oz Downloader v2.1.0 · made with ❤️ by Oz</div>

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
          onClick={() => openLink(instagramURL)}
          className="flex items-center gap-1.5 hover:text-neutral-200 transition"
          title="instagram.com/oz.suliman"
        >
          <Instagram className="w-3.5 h-3.5" />
          <span>@oz.suliman</span>
        </button>

        <button
          onClick={() => openLink(portfolioURL)}
          className="flex items-center gap-1.5 hover:text-neutral-200 transition"
          title="osmandev.me"
        >
          <Globe className="w-3.5 h-3.5" />
          <span>Portfolio</span>
        </button>

        <button
          onClick={() => openLink(djPortfolioURL)}
          className="flex items-center gap-1.5 hover:text-neutral-200 transition"
          title="osmandev.me/dj"
        >
          <Music className="w-3.5 h-3.5" />
          <span>DJ</span>
        </button>
      </div>
    </footer>
  );
};
