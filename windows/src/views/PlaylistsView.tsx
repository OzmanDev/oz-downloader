import React, { useState, useEffect } from 'react';
import {
  ArrowDownCircle,
  Search,
  CheckSquare,
  Square,
  Trash2,
  RefreshCw,
  FolderPlus,
  AlertCircle,
} from 'lucide-react';
import { appStore } from '../services/appStore';
import { downloadService } from '../services/downloadService';
import { linkPreviewService } from '../services/linkPreviewService';
import { PlaylistFilter } from '../types/models';
import { PlaylistArtwork } from '../components/PlaylistArtwork';
import { DownloadQueueItem } from '../types/downloads';

export const PlaylistsView: React.FC = () => {
  const [spotifyPlaylists, setSpotifyPlaylists] = useState(appStore.spotifyPlaylists);
  const [savedPlaylists, setSavedPlaylists] = useState(appStore.playlists);
  const [isLoggedIn, setIsLoggedIn] = useState(appStore.isLoggedIn);
  const [filter, setFilter] = useState<PlaylistFilter>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedSpotify, setSelectedSpotify] = useState<Set<string>>(new Set());
  const [selectedSaved, setSelectedSaved] = useState<Set<string>>(new Set());
  const [showAddModal, setShowAddModal] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);

  // Add Playlist modal states
  const [addUrl, setAddUrl] = useState('');
  const [addName, setAddName] = useState('');
  const [addIsLookingUp, setAddIsLookingUp] = useState(false);
  const [addError, setAddError] = useState<string | null>(null);

  useEffect(() => {
    const unsub = appStore.subscribe(() => {
      setSpotifyPlaylists([...appStore.spotifyPlaylists]);
      setSavedPlaylists([...appStore.playlists]);
      setIsLoggedIn(appStore.isLoggedIn);
    });
    return unsub;
  }, []);

  const handleRefresh = async () => {
    setIsRefreshing(true);
    const items = await downloadService.fetchPlaylists(appStore);
    if (items.length) {
      await appStore.replaceSpotifyPlaylists(items);
    }
    setIsRefreshing(false);
  };

  const filteredSpotify = spotifyPlaylists.filter((pl) => {
    let matchCat = true;
    if (filter === 'byMe') matchCat = pl.isOwned;
    else if (filter === 'followed') matchCat = !pl.isOwned && !pl.isSpotify;
    else if (filter === 'spotify') matchCat = pl.isSpotify;

    if (!matchCat) return false;
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return (
      pl.name.toLowerCase().includes(q) ||
      (pl.owner && pl.owner.toLowerCase().includes(q))
    );
  });

  const filteredSaved = savedPlaylists.filter((pl) => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    return pl.name.toLowerCase().includes(q) || pl.alias.toLowerCase().includes(q);
  });

  const toggleSelectSpotify = (id: string) => {
    const next = new Set(selectedSpotify);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelectedSpotify(next);
  };

  const toggleSelectSaved = (alias: string) => {
    const next = new Set(selectedSaved);
    if (next.has(alias)) next.delete(alias);
    else next.add(alias);
    setSelectedSaved(next);
  };

  const handleDownloadSelected = () => {
    const queue: DownloadQueueItem[] = [];

    spotifyPlaylists
      .filter((p) => selectedSpotify.has(p.id))
      .forEach((p) => {
        queue.push({
          id: p.url,
          name: p.name,
          url: p.url,
          trackCount: p.trackCount,
          imageURL: p.imageURL,
          status: 'pending',
          retryAttempt: 0,
          lastError: '',
        });
      });

    savedPlaylists
      .filter((p) => selectedSaved.has(p.alias))
      .forEach((p) => {
        queue.push({
          id: p.url,
          name: p.name,
          url: p.url,
          trackCount: p.trackCount,
          imageURL: p.imageURL,
          status: 'pending',
          retryAttempt: 0,
          lastError: '',
        });
      });

    if (queue.length > 0) {
      downloadService.startQueue(queue);
    }
  };

  const handleAddPlaylist = async () => {
    if (!addUrl.trim()) return;
    setAddIsLookingUp(true);
    setAddError(null);

    const res = await linkPreviewService.lookup(addUrl, appStore.settings.rootPath);
    setAddIsLookingUp(false);

    if (res.error) {
      setAddError(res.error);
      return;
    }

    if (res.preview) {
      appStore.rememberPlaylist(
        addName.trim() || res.preview.name,
        res.preview.url,
        res.preview.trackCount,
        ''
      );
      setShowAddModal(false);
      setAddUrl('');
      setAddName('');
      downloadService.showToast('Playlist added to My Playlists');
    }
  };

  const hasSelection = selectedSpotify.size > 0 || selectedSaved.size > 0;

  return (
    <div className="flex-1 overflow-y-auto px-8 py-6 space-y-6 flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white tracking-tight">My playlists</h1>
          <p className="text-sm text-neutral-400">
            Select playlists to download or save your favorite links.
          </p>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={() => setShowAddModal(true)}
            className="flex items-center gap-1.5 px-3.5 py-1.5 bg-[#2c2c2e] hover:bg-[#3a3a3c] text-white rounded-lg text-sm font-medium border border-white/10 transition"
          >
            <FolderPlus className="w-4 h-4 text-sky-400" />
            <span>Add playlist</span>
          </button>

          <button
            onClick={handleDownloadSelected}
            disabled={!hasSelection}
            className={`flex items-center gap-1.5 px-4 py-1.5 rounded-lg text-sm font-medium transition ${
              hasSelection
                ? 'bg-sky-500 hover:bg-sky-600 text-white shadow-md'
                : 'bg-neutral-800 text-neutral-500 cursor-not-allowed border border-white/5'
            }`}
          >
            <ArrowDownCircle className="w-4 h-4" />
            <span>Download selected ({selectedSpotify.size + selectedSaved.size})</span>
          </button>
        </div>
      </div>

      {/* Toolbar & Filter */}
      <div className="flex items-center justify-between gap-4">
        {/* Categories */}
        <div className="flex items-center gap-1 p-1 bg-[#2c2c2e]/60 rounded-lg border border-white/5">
          {(['all', 'byMe', 'followed', 'spotify'] as PlaylistFilter[]).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-3 py-1 rounded-md text-xs font-medium transition ${
                filter === f
                  ? 'bg-sky-500 text-white font-semibold'
                  : 'text-neutral-400 hover:text-white'
              }`}
            >
              {f === 'all'
                ? 'All'
                : f === 'byMe'
                ? 'By me'
                : f === 'followed'
                ? 'Followed'
                : 'Spotify'}
            </button>
          ))}
        </div>

        {/* Search */}
        <div className="relative w-64">
          <Search className="absolute left-2.5 top-2.5 w-3.5 h-3.5 text-neutral-400" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search playlists…"
            className="w-full bg-[#1c1c1e] text-white pl-8 pr-3 py-1.5 rounded-lg border border-white/10 text-xs focus:outline-none focus:border-sky-500"
          />
        </div>
      </div>

      {/* 2-Column Main View */}
      <div className="grid grid-cols-2 gap-6 flex-1 min-h-[400px]">
        {/* Spotify Playlists Column */}
        <div className="flex flex-col bg-[#2c2c2e]/40 rounded-xl border border-white/10 p-4 space-y-3">
          <div className="flex items-center justify-between pb-2 border-b border-white/5">
            <h2 className="text-sm font-semibold text-white">Spotify Playlists</h2>
            {isLoggedIn && (
              <button
                onClick={handleRefresh}
                disabled={isRefreshing}
                className="text-neutral-400 hover:text-white transition"
                title="Refresh Spotify playlists"
              >
                <RefreshCw className={`w-3.5 h-3.5 ${isRefreshing ? 'animate-spin' : ''}`} />
              </button>
            )}
          </div>

          {!isLoggedIn ? (
            <div className="flex-1 flex flex-col items-center justify-center text-center p-6 text-neutral-400 space-y-2">
              <AlertCircle className="w-8 h-8 text-neutral-500" />
              <p className="text-sm">Sign in to Spotify in Preferences to see your playlists.</p>
            </div>
          ) : filteredSpotify.length === 0 ? (
            <div className="flex-1 flex items-center justify-center text-neutral-500 text-xs">
              No playlists found
            </div>
          ) : (
            <div className="flex-1 overflow-y-auto space-y-2 pr-1">
              {filteredSpotify.map((pl) => {
                const isSelected = selectedSpotify.has(pl.id);
                return (
                  <div
                    key={pl.id}
                    onClick={() => toggleSelectSpotify(pl.id)}
                    className={`flex items-center gap-3 p-2 rounded-lg cursor-pointer transition border ${
                      isSelected
                        ? 'bg-sky-500/15 border-sky-500/40 text-white'
                        : 'bg-[#1c1c1e]/60 border-white/5 text-neutral-200 hover:bg-white/5'
                    }`}
                  >
                    {isSelected ? (
                      <CheckSquare className="w-4 h-4 text-sky-400 flex-shrink-0" />
                    ) : (
                      <Square className="w-4 h-4 text-neutral-500 flex-shrink-0" />
                    )}

                    <PlaylistArtwork imageURL={pl.imageURL} spotifyURL={pl.url} size={36} />

                    <div className="flex-1 min-w-0">
                      <div className="text-xs font-medium truncate">{pl.name}</div>
                      <div className="text-[11px] text-neutral-400 truncate">
                        {pl.trackCount} songs {pl.owner && `· ${pl.owner}`}
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Saved Playlists Column */}
        <div className="flex flex-col bg-[#2c2c2e]/40 rounded-xl border border-white/10 p-4 space-y-3">
          <div className="flex items-center justify-between pb-2 border-b border-white/5">
            <h2 className="text-sm font-semibold text-white">Saved Playlists</h2>
            <span className="text-xs text-neutral-400">{savedPlaylists.length}</span>
          </div>

          {filteredSaved.length === 0 ? (
            <div className="flex-1 flex flex-col items-center justify-center text-center p-6 text-neutral-400 space-y-2">
              <p className="text-sm">No saved playlists yet.</p>
              <p className="text-xs text-neutral-500">
                Playlists you download from Get Music will be saved here automatically.
              </p>
            </div>
          ) : (
            <div className="flex-1 overflow-y-auto space-y-2 pr-1">
              {filteredSaved.map((pl) => {
                const isSelected = selectedSaved.has(pl.alias);
                return (
                  <div
                    key={pl.alias}
                    className={`flex items-center justify-between p-2 rounded-lg transition border ${
                      isSelected
                        ? 'bg-sky-500/15 border-sky-500/40 text-white'
                        : 'bg-[#1c1c1e]/60 border-white/5 text-neutral-200 hover:bg-white/5'
                    }`}
                  >
                    <div
                      className="flex items-center gap-3 flex-1 min-w-0 cursor-pointer"
                      onClick={() => toggleSelectSaved(pl.alias)}
                    >
                      {isSelected ? (
                        <CheckSquare className="w-4 h-4 text-sky-400 flex-shrink-0" />
                      ) : (
                        <Square className="w-4 h-4 text-neutral-500 flex-shrink-0" />
                      )}

                      <PlaylistArtwork imageURL={pl.imageURL} spotifyURL={pl.url} size={36} />

                      <div className="flex-1 min-w-0">
                        <div className="text-xs font-medium truncate">{pl.name}</div>
                        <div className="text-[11px] text-neutral-400 truncate">
                          {pl.trackCount > 0 && `${pl.trackCount} songs · `}
                          alias: {pl.alias}
                        </div>
                      </div>
                    </div>

                    <button
                      onClick={() => appStore.removePlaylist(pl.alias)}
                      className="text-neutral-500 hover:text-red-400 p-1.5 transition"
                      title="Remove playlist"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>

      {/* Add Modal */}
      {showAddModal && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-[#2c2c2e] border border-white/10 rounded-2xl w-full max-w-md p-6 space-y-4 shadow-2xl">
            <h2 className="text-base font-bold text-white">Add playlist</h2>
            <p className="text-xs text-neutral-400">
              Paste a link to add a playlist directly to your saved list.
            </p>

            <div className="space-y-3">
              <div>
                <label className="text-xs text-neutral-300 font-medium">Spotify Link</label>
                <input
                  type="text"
                  value={addUrl}
                  onChange={(e) => setAddUrl(e.target.value)}
                  placeholder="https://open.spotify.com/playlist/..."
                  className="w-full mt-1 bg-[#1c1c1e] text-white px-3 py-2 rounded-lg border border-white/10 text-xs focus:outline-none focus:border-sky-500"
                />
              </div>

              <div>
                <label className="text-xs text-neutral-300 font-medium">Name (Optional)</label>
                <input
                  type="text"
                  value={addName}
                  onChange={(e) => setAddName(e.target.value)}
                  placeholder="Custom name"
                  className="w-full mt-1 bg-[#1c1c1e] text-white px-3 py-2 rounded-lg border border-white/10 text-xs focus:outline-none focus:border-sky-500"
                />
              </div>

              {addError && <p className="text-xs text-red-400">{addError}</p>}
            </div>

            <div className="flex justify-end gap-3 pt-2">
              <button
                onClick={() => setShowAddModal(false)}
                className="px-4 py-2 rounded-lg text-xs font-medium text-neutral-300 hover:bg-white/5 transition"
              >
                Cancel
              </button>
              <button
                onClick={handleAddPlaylist}
                disabled={addIsLookingUp || !addUrl.trim()}
                className="px-4 py-2 bg-sky-500 hover:bg-sky-600 text-white rounded-lg text-xs font-medium transition shadow"
              >
                {addIsLookingUp ? 'Looking up…' : 'Add'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
