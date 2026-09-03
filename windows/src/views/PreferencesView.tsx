import React, { useState, useEffect } from 'react';
import {
  User,
  Folder,
  ChevronDown,
  ChevronRight,
  LogOut,
  LogIn,
} from 'lucide-react';
import { appStore } from '../services/appStore';
import { downloadService } from '../services/downloadService';
import { AUDIO_FORMAT_CHOICES, QUALITY_CHOICES } from '../types/models';

export const PreferencesView: React.FC = () => {
  const [settings, setSettings] = useState(appStore.settings);
  const [isLoggedIn, setIsLoggedIn] = useState(appStore.isLoggedIn);
  const [account, setAccount] = useState(appStore.account);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [confirmSignOut, setConfirmSignOut] = useState(false);
  const [runtimeOk, setRuntimeOk] = useState<boolean | null>(null);
  const [runtimeDir, setRuntimeDir] = useState('');

  useEffect(() => {
    const api = (window as any).electronAPI;
    if (!api?.getRuntimeStatus) return;
    api.getRuntimeStatus().then((status: { ok: boolean; bundledRuntimeDir: string }) => {
      setRuntimeOk(status.ok);
      setRuntimeDir(status.bundledRuntimeDir || '');
    });
  }, []);

  useEffect(() => {
    const unsub = appStore.subscribe(() => {
      setSettings({ ...appStore.settings });
      setIsLoggedIn(appStore.isLoggedIn);
      setAccount({ ...appStore.account });
    });
    return unsub;
  }, []);

  const handleChooseFolder = async () => {
    const api = (window as any).electronAPI;
    if (api) {
      const selected = await api.chooseDirectory();
      if (selected) {
        appStore.updateSettings((s) => ({ ...s, rootPath: selected }));
      }
    }
  };

  const handleOpenFolder = () => {
    const api = (window as any).electronAPI;
    if (api) {
      api.openPath(settings.rootPath);
    }
  };

  const handleSignIn = async () => {
    const api = (window as any).electronAPI;
    if (!api) return;

    await api.startOAuthServer();
    // Open OAuth URL
    const authUrl = `https://accounts.spotify.com/authorize?client_id=65b708073fc0480ea92a077233ca87bd&response_type=code&redirect_uri=http%3A%2F%2F127.0.0.1%3A4381%2F&scope=user-read-private%20user-read-email%20playlist-read-private%20user-library-read`;
    api.openExternal(authUrl);

    api.onOAuthCallback(async (data: any) => {
      if (data.code) {
        downloadService.showToast('Connecting Spotify account…');
        // Let Zotify sync credentials
        await appStore.syncAccountFromCredentials();
        await appStore.refreshAccountProfile();
        downloadService.showToast('Signed in with Spotify!');
      }
    });
  };

  const handleSignOut = async () => {
    await appStore.clearCredentials();
    setConfirmSignOut(false);
    downloadService.showToast('Signed out of Spotify');
  };

  return (
    <div className="flex-1 overflow-y-auto px-8 py-6 space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-white tracking-tight">Preferences</h1>
        <p className="text-sm text-neutral-400">Configure downloads, formats, and Spotify login.</p>
      </div>

      {runtimeOk === false && (
        <div className="p-4 rounded-xl bg-red-500/10 border border-red-500/30 space-y-2">
          <h2 className="text-sm font-semibold text-red-300">Download tools missing</h2>
          <p className="text-xs text-red-200/90 leading-relaxed">
            This install does not include bundled Python/zotify/ffmpeg, so downloads cannot run.
            Reinstall using <span className="font-medium">OzDownloader-Installer.exe</span> built on a Windows PC.
          </p>
          {runtimeDir && (
            <p className="text-[11px] text-red-200/70 font-mono break-all">{runtimeDir}</p>
          )}
        </div>
      )}

      {/* Spotify Account Section */}
      <div className="p-5 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-md space-y-4">
        <h2 className="text-sm font-semibold text-white">Spotify Account</h2>

        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3.5">
            <div className="w-12 h-12 rounded-full bg-neutral-700/60 border border-white/10 flex items-center justify-center overflow-hidden">
              {account.imageURL ? (
                <img src={account.imageURL} alt="Avatar" className="w-full h-full object-cover" />
              ) : (
                <User className="w-6 h-6 text-neutral-400" />
              )}
            </div>

            <div>
              <div className="text-sm font-semibold text-white">
                {isLoggedIn ? account.displayName || 'Signed in' : 'Not signed in'}
              </div>
              <div className="text-xs text-neutral-400">
                {isLoggedIn
                  ? 'Your Spotify account is connected.'
                  : 'Connect Spotify to load your playlists.'}
              </div>
            </div>
          </div>

          <div>
            {isLoggedIn ? (
              <button
                onClick={() => setConfirmSignOut(true)}
                className="flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg bg-red-500/15 hover:bg-red-500/25 text-red-400 text-xs font-medium border border-red-500/20 transition"
              >
                <LogOut className="w-3.5 h-3.5" />
                <span>Sign out</span>
              </button>
            ) : (
              <button
                onClick={handleSignIn}
                className="flex items-center gap-1.5 px-4 py-2 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-semibold shadow transition"
              >
                <LogIn className="w-3.5 h-3.5" />
                <span>Sign in with Spotify</span>
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Where files go */}
      <div className="p-5 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-md space-y-4">
        <h2 className="text-sm font-semibold text-white">Where files go</h2>

        <div className="space-y-3">
          <div className="flex gap-2">
            <input
              type="text"
              readOnly
              value={settings.rootPath}
              className="flex-1 bg-[#1c1c1e] text-white px-3 py-2 rounded-lg border border-white/10 text-xs font-mono select-all focus:outline-none"
            />
            <button
              onClick={handleChooseFolder}
              className="px-3 py-2 bg-[#3a3a3c] hover:bg-[#48484a] text-white rounded-lg text-xs font-medium transition"
            >
              Choose…
            </button>
          </div>

          <button
            onClick={handleOpenFolder}
            className="flex items-center gap-1.5 text-xs text-sky-400 hover:text-sky-300 font-medium transition"
          >
            <Folder className="w-3.5 h-3.5" />
            <span>Open default download folder</span>
          </button>
        </div>
      </div>

      {/* Music quality */}
      <div className="p-5 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-md space-y-4">
        <h2 className="text-sm font-semibold text-white">Music quality</h2>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="text-xs text-neutral-400 font-medium">Preferred quality</label>
            <select
              value={settings.downloadQuality}
              onChange={(e) =>
                appStore.updateSettings((s) => ({ ...s, downloadQuality: e.target.value }))
              }
              className="w-full mt-1.5 bg-[#1c1c1e] text-white px-3 py-2 rounded-lg border border-white/10 text-xs focus:outline-none focus:border-sky-500"
            >
              {QUALITY_CHOICES.map((q) => (
                <option key={q.id} value={q.id}>
                  {q.label}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="text-xs text-neutral-400 font-medium">Save downloads as</label>
            <select
              value={settings.convertFormat}
              onChange={(e) =>
                appStore.updateSettings((s) => ({ ...s, convertFormat: e.target.value }))
              }
              className="w-full mt-1.5 bg-[#1c1c1e] text-white px-3 py-2 rounded-lg border border-white/10 text-xs focus:outline-none focus:border-sky-500"
            >
              {AUDIO_FORMAT_CHOICES.map((opt) => (
                <option key={opt.id} value={opt.id}>
                  {opt.label}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div className="pt-2 flex items-center gap-3">
          <input
            type="checkbox"
            id="autoPostprocess"
            checked={settings.autoPostprocess}
            onChange={(e) =>
              appStore.updateSettings((s) => ({ ...s, autoPostprocess: e.target.checked }))
            }
            className="w-4 h-4 rounded text-sky-500 focus:ring-0 bg-[#1c1c1e] border-white/10"
          />
          <label htmlFor="autoPostprocess" className="text-xs text-neutral-200 cursor-pointer">
            Convert automatically after each download
          </label>
        </div>
      </div>

      {/* When re-downloading */}
      <div className="p-5 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-md space-y-3">
        <h2 className="text-sm font-semibold text-white">When re-downloading</h2>

        <div className="space-y-2.5">
          <label className="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={settings.skipExisting}
              onChange={(e) =>
                appStore.updateSettings((s) => ({ ...s, skipExisting: e.target.checked }))
              }
              className="w-4 h-4 rounded text-sky-500 focus:ring-0 bg-[#1c1c1e] border-white/10"
            />
            <span className="text-xs text-neutral-200">Skip songs I already have</span>
          </label>

          <label className="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={settings.skipPreviouslyDownloaded}
              onChange={(e) =>
                appStore.updateSettings((s) => ({
                  ...s,
                  skipPreviouslyDownloaded: e.target.checked,
                }))
              }
              className="w-4 h-4 rounded text-sky-500 focus:ring-0 bg-[#1c1c1e] border-white/10"
            />
            <span className="text-xs text-neutral-200">
              Skip songs downloaded before (even if moved)
            </span>
          </label>
        </div>
      </div>

      {/* Advanced Options */}
      <div className="p-5 rounded-xl bg-[#2c2c2e]/70 border border-white/10 shadow-md">
        <button
          onClick={() => setShowAdvanced(!showAdvanced)}
          className="flex items-center justify-between w-full text-left text-sm font-semibold text-white"
        >
          <span>Advanced options</span>
          {showAdvanced ? (
            <ChevronDown className="w-4 h-4 text-neutral-400" />
          ) : (
            <ChevronRight className="w-4 h-4 text-neutral-400" />
          )}
        </button>

        {showAdvanced && (
          <div className="pt-4 space-y-4 border-t border-white/5 mt-3">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-xs text-neutral-400 font-medium">
                  Pause between songs (seconds)
                </label>
                <input
                  type="text"
                  value={settings.bulkWaitTime}
                  onChange={(e) =>
                    appStore.updateSettings((s) => ({ ...s, bulkWaitTime: e.target.value }))
                  }
                  className="w-full mt-1.5 bg-[#1c1c1e] text-white px-3 py-2 rounded-lg border border-white/10 text-xs focus:outline-none"
                />
              </div>

              <div>
                <label className="text-xs text-neutral-400 font-medium">
                  Download speed limit (0 = fastest)
                </label>
                <input
                  type="text"
                  value={settings.downloadRateLimiter}
                  onChange={(e) =>
                    appStore.updateSettings((s) => ({
                      ...s,
                      downloadRateLimiter: e.target.value,
                    }))
                  }
                  className="w-full mt-1.5 bg-[#1c1c1e] text-white px-3 py-2 rounded-lg border border-white/10 text-xs focus:outline-none"
                />
              </div>
            </div>

            <div>
              <label className="text-xs text-neutral-400 font-medium">Retry failed songs</label>
              <input
                type="text"
                value={settings.retryAttempts}
                onChange={(e) =>
                  appStore.updateSettings((s) => ({ ...s, retryAttempts: e.target.value }))
                }
                className="w-full mt-1.5 bg-[#1c1c1e] text-white px-3 py-2 rounded-lg border border-white/10 text-xs focus:outline-none"
              />
            </div>
          </div>
        )}
      </div>

      {/* Confirmation Sign Out Modal */}
      {confirmSignOut && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-[#2c2c2e] border border-white/10 rounded-2xl w-full max-w-sm p-6 space-y-4 shadow-2xl">
            <h3 className="text-base font-bold text-white">Sign out of Spotify?</h3>
            <p className="text-xs text-neutral-400 leading-relaxed">
              You’ll need to sign in again the next time you load playlists or download.
            </p>

            <div className="flex justify-end gap-3 pt-2">
              <button
                onClick={() => setConfirmSignOut(false)}
                className="px-4 py-2 rounded-lg text-xs font-medium text-neutral-300 hover:bg-white/5 transition"
              >
                Cancel
              </button>
              <button
                onClick={handleSignOut}
                className="px-4 py-2 bg-red-600 hover:bg-red-500 text-white rounded-lg text-xs font-medium transition shadow"
              >
                Sign out
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
