import React, { useState, useEffect } from 'react';
import { Music } from 'lucide-react';

interface PlaylistArtworkProps {
  imageURL: string;
  spotifyURL?: string;
  size?: number;
}

const memoryCache = new Map<string, string>();

export const PlaylistArtwork: React.FC<PlaylistArtworkProps> = ({
  imageURL,
  spotifyURL = '',
  size = 48,
}) => {
  const [src, setSrc] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let isMounted = true;
    const load = async () => {
      setLoading(true);
      const key = (imageURL || spotifyURL).trim();
      if (!key) {
        setLoading(false);
        return;
      }

      if (memoryCache.has(key)) {
        setSrc(memoryCache.get(key)!);
        setLoading(false);
        return;
      }

      let resolvedURL = imageURL.trim();
      if (!resolvedURL && spotifyURL) {
        try {
          const res = await fetch(`https://open.spotify.com/oembed?url=${encodeURIComponent(spotifyURL)}`);
          if (res.ok) {
            const data = await res.json();
            if (data.thumbnail_url) {
              resolvedURL = data.thumbnail_url;
            }
          }
        } catch (_) {}
      }

      if (resolvedURL && isMounted) {
        memoryCache.set(key, resolvedURL);
        setSrc(resolvedURL);
      }
      if (isMounted) setLoading(false);
    };

    load();
    return () => { isMounted = false; };
  }, [imageURL, spotifyURL]);

  return (
    <div
      style={{ width: size, height: size }}
      className="relative flex-shrink-0 bg-neutral-800 rounded overflow-hidden flex items-center justify-center border border-white/5"
    >
      {src ? (
        <img src={src} alt="Cover" className="w-full h-full object-cover" />
      ) : loading ? (
        <div className="w-4 h-4 border-2 border-white/20 border-t-white/80 rounded-full animate-spin" />
      ) : (
        <Music className="text-neutral-500" style={{ width: size * 0.4, height: size * 0.4 }} />
      )}
    </div>
  );
};
