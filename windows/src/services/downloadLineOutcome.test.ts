import { classify, column, rowLabel, summary } from './downloadLineOutcome.ts';

const failures: string[] = [];

const noAudio = classify('ERROR:  SKIPPING TRACK - FAILED TO GET CONTENT STREAM   ###');
if (
  noAudio?.kind !== 'failed' ||
  noAudio.label !== 'No audio stream' ||
  noAudio.alreadySaved !== false ||
  noAudio.quotedName != null
) {
  failures.push(
    `19. FAILED TO GET CONTENT STREAM is failed, label No audio stream, alreadySaved false, quotedName nil, got ${JSON.stringify(noAudio)}`
  );
}

const unavailable = classify('SKIPPING:  "Nova Song" (TRACK IS UNAVAILABLE)   ###');
if (
  unavailable?.kind !== 'failed' ||
  unavailable.label !== 'Unavailable' ||
  unavailable.alreadySaved !== false
) {
  failures.push(
    `20. IS UNAVAILABLE is failed with label Unavailable, got ${JSON.stringify(unavailable)}`
  );
}
if (unavailable?.quotedName !== 'Nova Song') {
  failures.push(
    `46. IS UNAVAILABLE keeps the quoted song name Nova Song, got ${JSON.stringify(unavailable?.quotedName)}`
  );
}

const localFile = classify('SKIPPING:  "Nova Song" (TRACK IS A LOCAL FILE)   ###');
if (localFile?.kind !== 'failed' || localFile.label !== 'Local file' || localFile.alreadySaved !== false) {
  failures.push(`21. IS A LOCAL FILE is failed with label Local file, got ${JSON.stringify(localFile)}`);
}
if (localFile?.quotedName !== 'Nova Song') {
  failures.push(
    `47. IS A LOCAL FILE keeps the quoted song name Nova Song, got ${JSON.stringify(localFile?.quotedName)}`
  );
}

const alreadyHere = classify('SKIPPING:  "Dj House/19_Some Song.ogg" (FILE ALREADY EXISTS)   ###');
if (
  alreadyHere?.kind !== 'skipped' ||
  alreadyHere.label !== 'Already here' ||
  alreadyHere.alreadySaved !== true ||
  alreadyHere.quotedName !== 'Dj House/19_Some Song.ogg'
) {
  failures.push(
    `22. FILE ALREADY EXISTS is skipped Already here with the quoted filename, got ${JSON.stringify(alreadyHere)}`
  );
}

const downloadedPreviously = classify('SKIPPING:  "Some Song" (TRACK DOWNLOADED PREVIOUSLY)   ###');
if (
  downloadedPreviously?.kind !== 'skipped' ||
  downloadedPreviously.label !== 'Downloaded previously' ||
  downloadedPreviously.alreadySaved !== true
) {
  failures.push(
    `23. DOWNLOADED PREVIOUSLY is skipped Downloaded previously, alreadySaved true, got ${JSON.stringify(downloadedPreviously)}`
  );
}

const alreadyThisSession = classify('SKIPPING:  "Some Song" (TRACK ALREADY DOWNLOADED THIS SESSION)   ###');
if (
  alreadyThisSession?.kind !== 'skipped' ||
  alreadyThisSession.label !== 'Already downloaded' ||
  alreadyThisSession.alreadySaved !== true
) {
  failures.push(
    `24. ALREADY DOWNLOADED THIS SESSION is skipped Already downloaded, alreadySaved true, got ${JSON.stringify(alreadyThisSession)}`
  );
}

const filtered = classify('SKIPPING:  TRACK MATCHES REGEX FILTER   ###');
if (filtered?.kind !== 'skipped' || filtered.label !== 'Filtered' || filtered.alreadySaved !== false) {
  failures.push(
    `25. MATCHES REGEX FILTER is skipped Filtered, alreadySaved false, got ${JSON.stringify(filtered)}`
  );
}

const lyricsSkip = classify('SKIPPING:  LYRICS FOR "Some Song" (not found)   ###');
if (lyricsSkip != null) {
  failures.push(`26. a lyrics skip line does not classify a song, got ${JSON.stringify(lyricsSkip)}`);
}

const onlySkipping = classify('SKIPPING:  "Some Song"   ###');
if (onlySkipping != null) {
  failures.push(`27. a line that only skips does not classify a song, got ${JSON.stringify(onlySkipping)}`);
}

const failedColumn = column('failed');
if (failedColumn !== 'failed') {
  failures.push(`28. a failed song is in the failed column, got ${failedColumn}`);
}

const waitingColumn = column('waiting');
if (waitingColumn !== 'waiting') {
  failures.push(`29. a waiting song is in the waiting column, got ${waitingColumn}`);
}

const skippedColumn = column('skipped');
if (skippedColumn !== 'skipped') {
  failures.push(`30. a skipped song is in the skipped column, got ${skippedColumn}`);
}

const downloadedColumn = column('downloaded');
if (downloadedColumn !== 'downloaded') {
  failures.push(`31. a downloaded song is in the downloaded column, got ${downloadedColumn}`);
}

const inProgressColumn = column('inProgress');
if (inProgressColumn !== 'inProgress') {
  failures.push(`32. an in-progress song is in the in-progress column, got ${inProgressColumn}`);
}

const previousLabel = rowLabel('skipped', 'Downloaded previously', '');
if (previousLabel !== 'Downloaded previously') {
  failures.push(`33. a skipped row shows its reason label, got ${previousLabel}`);
}

const noStreamLabel = rowLabel('failed', 'No audio stream', '');
if (noStreamLabel !== 'No audio stream') {
  failures.push(`34. a failed row shows its reason label, got ${noStreamLabel}`);
}

const alreadyHereLabel = rowLabel('skipped', '', 'alreadySaved');
if (alreadyHereLabel !== 'Already here') {
  failures.push(
    `35. a skipped already-saved row with no reason label shows Already here, got ${alreadyHereLabel}`
  );
}

const duplicateLabel = rowLabel('skipped', '', 'duplicate');
if (duplicateLabel !== 'Duplicate') {
  failures.push(`36. a duplicate skip shows Duplicate, got ${duplicateLabel}`);
}

const cancelledLabel = rowLabel('skipped', '', 'cancelled');
if (cancelledLabel !== 'Cancelled') {
  failures.push(`37. a cancelled skip shows Cancelled, got ${cancelledLabel}`);
}

const plainSkipped = rowLabel('skipped', '', '');
if (plainSkipped !== 'Skipped') {
  failures.push(`38. a skipped row with no reason shows Skipped, got ${plainSkipped}`);
}

const plainFailed = rowLabel('failed', '', '');
if (plainFailed !== 'Failed') {
  failures.push(`39. a failed row with no reason shows Failed, got ${plainFailed}`);
}

const inProgressLabel = rowLabel('inProgress', '50%', '');
if (inProgressLabel !== '') {
  failures.push(`41. an in-progress row has no status label from this function, got ${inProgressLabel}`);
}

const waitingLabel = rowLabel('waiting', '', '');
if (waitingLabel !== '') {
  failures.push(`40. a waiting row has no status label from this function, got ${waitingLabel}`);
}

const downloadedLabel = rowLabel('downloaded', 'Downloaded', '');
if (downloadedLabel !== '') {
  failures.push(`42. a downloaded row has no status label from this function, got ${downloadedLabel}`);
}

const waitingWithReason = rowLabel('waiting', 'No audio stream', '');
if (waitingWithReason !== '') {
  failures.push(`43. a waiting row ignores a reason label, got ${waitingWithReason}`);
}

const withFailed = summary(2, 1, 3);
if (withFailed !== '2 skipped · 1 failed · 3 left') {
  failures.push(`44. a summary with failures counts failed songs, got ${withFailed}`);
}

const noFailed = summary(4, 0, 5);
if (noFailed !== '4 skipped · 5 left') {
  failures.push(`45. a summary with no failures does not mention failed, got ${noFailed}`);
}

const lowercaseNoAudio = classify('error: skipping track - failed to get content stream');
if (
  lowercaseNoAudio?.kind !== 'failed' ||
  lowercaseNoAudio.label !== 'No audio stream' ||
  lowercaseNoAudio.quotedName != null
) {
  failures.push(
    `48. case 1 lowercase failed to get content stream expected failed, label "No audio stream", quotedName nil, got ${JSON.stringify(lowercaseNoAudio)}`
  );
}

const sessionSkip = classify('SKIPPING:  "Some Song" (TRACK ALREADY DOWNLOADED THIS SESSION)   ###');
if (sessionSkip?.kind !== 'skipped' || sessionSkip.label !== 'Already downloaded') {
  failures.push(
    `49. case 2 ALREADY DOWNLOADED THIS SESSION expected skipped, label "Already downloaded", got ${JSON.stringify(sessionSkip)}`
  );
}
if (sessionSkip?.label === 'Downloaded previously') {
  failures.push('49. case 2 ALREADY DOWNLOADED THIS SESSION label is "Downloaded previously"');
}

const trackUnavailable = classify('SKIPPING:  "Track Name" (TRACK IS UNAVAILABLE)   ###');
if (
  trackUnavailable?.kind !== 'failed' ||
  trackUnavailable.label !== 'Unavailable' ||
  trackUnavailable.quotedName !== 'Track Name'
) {
  failures.push(
    `50. case 3 TRACK IS UNAVAILABLE expected failed, label "Unavailable", quotedName "Track Name", got ${JSON.stringify(trackUnavailable)}`
  );
}

const lyricsMissing = classify('SKIPPING:  LYRICS FOR "Track Name" (missing)   ###');
if (lyricsMissing != null) {
  failures.push(`51. case 4 lyrics skip (missing) expected nil, got ${JSON.stringify(lyricsMissing)}`);
}

const emptyLine = classify('');
if (emptyLine != null) {
  failures.push(`52. case 5 empty string expected nil, got ${JSON.stringify(emptyLine)}`);
}

const zeroSkippedOneFailed = summary(0, 1, 16);
if (zeroSkippedOneFailed !== '0 skipped · 1 failed · 16 left') {
  failures.push(
    `53. case 6 summary(0, 1, 16) expected "0 skipped · 1 failed · 16 left", got ${zeroSkippedOneFailed}`
  );
}

const oneSkippedNoneFailed = summary(1, 0, 16);
if (oneSkippedNoneFailed !== '1 skipped · 16 left') {
  failures.push(`54. case 7 summary(1, 0, 16) expected "1 skipped · 16 left", got ${oneSkippedNoneFailed}`);
}

const failedColumnCheck = column('failed');
if (failedColumnCheck !== 'failed') {
  failures.push(`55. column('failed') expected "failed", got ${failedColumnCheck}`);
}

const reasonLabelWins = rowLabel('skipped', 'Local file', 'alreadySaved');
if (reasonLabelWins !== 'Local file') {
  failures.push(
    `56. case 9 skipped row with reason label "Local file" and skipReason alreadySaved expected "Local file", got ${reasonLabelWins}`
  );
}

if (failures.length > 0) {
  for (const failure of failures) console.log(failure);
  process.exit(1);
}
