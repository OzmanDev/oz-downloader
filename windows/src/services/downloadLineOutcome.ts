export interface ClassifiedSongLine {
  kind: 'skipped' | 'failed';
  label: string;
  quotedName: string | null;
  alreadySaved: boolean;
}

export type SongBoardStatus = 'waiting' | 'inProgress' | 'skipped' | 'failed' | 'downloaded';
export type ProgressColumn = SongBoardStatus;

/** null when there are no failures (the all-done celebration stays). */
export function failureLine(count: number): string | null {
  if (count === 1) return 'done with 1 failure 😅👏🏾';
  if (count >= 2) return `done with ${count} failures 😅👏🏾`;
  return null;
}

export function summary(skipped: number, failed: number, left: number): string {
  if (failed > 0) return `${skipped} skipped · ${failed} failed · ${left} left`;
  return `${skipped} skipped · ${left} left`;
}

export function rowLabel(status: SongBoardStatus, reasonLabel: string, skipReason: string): string {
  if (status === 'waiting' || status === 'inProgress' || status === 'downloaded') return '';
  if (reasonLabel !== '') return reasonLabel;
  if (status === 'skipped' && skipReason === 'alreadySaved') return 'Already here';
  if (skipReason === 'duplicate') return 'Duplicate';
  if (skipReason === 'cancelled') return 'Cancelled';
  if (status === 'skipped') return 'Skipped';
  return 'Failed';
}

export function column(status: SongBoardStatus): ProgressColumn {
  if (status === 'failed') return 'failed';
  if (status === 'waiting') return 'waiting';
  if (status === 'skipped') return 'skipped';
  if (status === 'downloaded') return 'downloaded';
  return 'inProgress';
}

export function classify(line: string): ClassifiedSongLine | null {
  const upper = line.toUpperCase();
  if (upper.includes('FAILED TO GET CONTENT STREAM')) {
    return { kind: 'failed', label: 'No audio stream', quotedName: null, alreadySaved: false };
  }
  if (upper.includes('IS UNAVAILABLE')) {
    return { kind: 'failed', label: 'Unavailable', quotedName: firstQuoted(line), alreadySaved: false };
  }
  if (upper.includes('IS A LOCAL FILE')) {
    return { kind: 'failed', label: 'Local file', quotedName: firstQuoted(line), alreadySaved: false };
  }
  if (upper.includes('FILE ALREADY EXISTS')) {
    return { kind: 'skipped', label: 'Already here', quotedName: firstQuoted(line), alreadySaved: true };
  }
  if (upper.includes('DOWNLOADED PREVIOUSLY')) {
    return {
      kind: 'skipped',
      label: 'Downloaded previously',
      quotedName: firstQuoted(line),
      alreadySaved: true,
    };
  }
  if (upper.includes('ALREADY DOWNLOADED THIS SESSION')) {
    return {
      kind: 'skipped',
      label: 'Already downloaded',
      quotedName: firstQuoted(line),
      alreadySaved: true,
    };
  }
  if (upper.includes('MATCHES REGEX FILTER')) {
    return { kind: 'skipped', label: 'Filtered', quotedName: null, alreadySaved: false };
  }
  return null;
}

function firstQuoted(line: string): string | null {
  const match = line.match(/"([^"]*)"/);
  return match ? match[1] : null;
}
