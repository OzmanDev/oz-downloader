export const catalogSize = 20;

export function slot(pick: number): number {
  const wrapped = pick % catalogSize;
  return wrapped >= 0 ? wrapped : wrapped + catalogSize;
}

export function randomPick(): number {
  return Math.floor(Math.random() * catalogSize);
}

export function allDone(pick: number): string {
  switch (slot(pick)) {
    case 0: return 'Oz got the job done as always 🎧✨';
    case 1: return "That's a wrap — the songs are in 🎵🔥";
    case 2: return 'Playlist conquered. Headphones on 🎧🎉';
    case 3: return "Oz didn't miss. It's all here 💪🎶";
    case 4: return 'Done and dusted. Go press play ▶️✨';
    case 5: return 'The queue bowed out. You won 🏆🎵';
    case 6: return 'Every track landed. Oz approves 👌🔥';
    case 7: return 'Fresh files, zero drama 😎🎶';
    case 8: return "Whole playlist. Chef's kiss 👨‍🍳💋";
    case 9: return "Oz clocked out. The music didn't 🌙🎧";
    case 10: return 'All saved. The speakers are jealous 🔊💚';
    case 11: return 'Mission complete. Dance break authorized 💃🎉';
    case 12: return 'Nothing left but vibes ✨🎶';
    case 13: return 'Oz signed off. You can listen 📝🎧';
    case 14: return 'Full playlist, full send 🚀🎵';
    case 15: return 'The files showed up like they were invited 🎟️🔥';
    case 16: return 'Clean finish. Oz is smiling 😁🎧';
    case 17: return "That's all of them. Legendary 👑🎶";
    case 18: return 'Tagged, saved, and ready to blast 🏷️🔥';
    default: return 'Close this and open the music 🚪🎵';
  }
}

/** null when failed is below 1, so an all-done run never gets a failure line. */
export function withFailures(failed: number, succeeded: number, pick: number): string | null {
  if (failed < 1) return null;
  const f = String(failed);
  const s = String(succeeded);
  const fw = failed === 1 ? 'failure' : 'failures';
  switch (slot(pick)) {
    case 0: return `Oz got ${f} ${fw}, but look at the good side ${s} succeeded 😅👏🏾`;
    case 1: return `${f} ${fw} crashed the party. ${s} succeeded anyway 🎉😅`;
    case 2: return `Almost perfect. ${f} ${fw}, and ${s} succeeded 💪🎶`;
    case 3: return `Oz salvaged the night: ${s} succeeded, ${f} ${fw} 🔁😅`;
    case 4: return `${s} succeeded. The other ${f} ${fw} can try again 🎵🔄`;
    case 5: return `Not a shutout. ${s} succeeded, ${f} ${fw} sat this one out 🪑😅`;
    case 6: return `Oz counted ${s} succeeded and ${f} ${fw} 📊🔥`;
    case 7: return `The good pile is ${s} succeeded. The oops pile is ${f} ${fw} 😅🎧`;
    case 8: return `${f} ${fw} slipped. ${s} succeeded and they're ready 🎶✨`;
    case 9: return `Partial victory dance: ${s} succeeded, ${f} ${fw} 💃😅`;
    case 10: return `Oz got most of it. ${s} succeeded, ${f} ${fw} 🏆😅`;
    case 11: return `${s} succeeded like champs. ${f} ${fw} need a rematch 🥊🎵`;
    case 12: return `Look at ${s} succeeded before you frown at ${f} ${fw} 👀💚`;
    case 13: return `The folder is richer by ${s} succeeded. ${f} ${fw} stayed home 📁😅`;
    case 14: return `${f} ${fw}, ${s} succeeded. Oz calls that a win with footnotes 📝🔥`;
    case 15: return `Headphones are happy about ${s} succeeded. ${f} ${fw} can wait 🎧😅`;
    case 16: return `${s} succeeded. Oz side-eyed the ${f} ${fw} 👀🎶`;
    case 17: return `Good news first: ${s} succeeded. Then ${f} ${fw} 😅✨`;
    case 18: return `${f} ${fw} didn't make the album. ${s} succeeded 💿🔥`;
    default: return `Oz wrapped it: ${s} succeeded, ${f} ${fw} 🎁😅`;
  }
}

export function alreadyHere(pick: number): string {
  switch (slot(pick)) {
    case 0: return 'Oz checked. These were already here 😎🎵';
    case 1: return 'Nothing new to fetch. Already here 📚✨';
    case 2: return 'Already here, every last one. Oz is impressed 🏆🎶';
    case 3: return 'The folder called first. Already here 📁🔥';
    case 4: return "Zero downloads. Already here, and that's a flex 💪🎧";
    case 5: return "Oz didn't re-download. Already here ✋🎵";
    case 6: return 'You beat the queue. Already here 🏁✨';
    case 7: return 'Already here. The hard drive salutes you 🫡🎶';
    case 8: return 'No fresh files. Already here, party as planned 🎉🎧';
    case 9: return 'Oz peeked and nodded. Already here 👀✅';
    case 10: return 'Saved you the wait. Already here ⏱️🔥';
    case 11: return 'Already here. Go listen to what you own 🎧💚';
    case 12: return 'The playlist was a rerun. Already here 🔁😂';
    case 13: return 'Oz found duplicates of joy. Already here 😄🎵';
    case 14: return 'Nothing to fetch. Already here 🚫📥';
    case 15: return 'Your past self did the work. Already here 🕰️✨';
    case 16: return 'Already here. Oz refuses to download twice 🙅🎶';
    case 17: return 'Library check complete. Already here 📋🔥';
    case 18: return "Already here. That's efficiency, baby ⚡🎧";
    default: return 'Oz looked, shrugged, smiled. Already here 🤷😁';
  }
}

export function mixed(newCount: number, already: number, pick: number): string {
  const n = String(newCount);
  const a = String(already);
  switch (slot(pick)) {
    case 0: return `Oz brought ${n} new. ${a} already here 🎵✨`;
    case 1: return `${n} new just landed. ${a} already here 🛬🔥`;
    case 2: return `Fresh batch: ${n} new, and ${a} already here 😎🎶`;
    case 3: return `Oz added ${n} new. ${a} already here ➕🎧`;
    case 4: return `${n} new for the collection. ${a} already here 📚✨`;
    case 5: return `A little sparkle (${n} new) and ${a} already here 🎉🎵`;
    case 6: return `${n} new files clocked in. ${a} already here ⏰🔥`;
    case 7: return `Oz mixed it: ${n} new, ${a} already here 🎛️🎶`;
    case 8: return `${n} new to press play on. ${a} already here ▶️💚`;
    case 9: return `The folder grew by ${n} new. ${a} already here 📁✨`;
    case 10: return `${n} new, ${a} already here. Balanced, like a playlist ⚖️🔥`;
    case 11: return `Oz delivered ${n} new and recognized ${a} already here 👀🎵`;
    case 12: return `${n} new arrivals. ${a} already here, unbothered 😎🎧`;
    case 13: return `${n} new songs joined. ${a} already here 🎤✨`;
    case 14: return `Count it: ${n} new, ${a} already here 🔢🔥`;
    case 15: return `${n} new to brag about. ${a} already here 🗣️🎶`;
    case 16: return `Oz saved ${n} new. ${a} already here didn't need saving 💾😅`;
    case 17: return `${n} new in the bag. ${a} already here 👜✨`;
    case 18: return `The fun part is ${n} new. ${a} already here 🎉🎧`;
    default: return `${n} new, ${a} already here. Oz calls that a solid haul 🧺🔥`;
  }
}

export function fresh(newCount: number, pick: number): string {
  const n = String(newCount);
  switch (slot(pick)) {
    case 0: return `Oz brought ${n} new 🎵🔥`;
    case 1: return `${n} new, hot out of the queue 🔥🎧`;
    case 2: return `Fresh drop: ${n} new ✨🎶`;
    case 3: return `${n} new just moved in 🏠🎉`;
    case 4: return `Oz counted ${n} new and grinned 😁🎵`;
    case 5: return `${n} new for the speakers 🔊💚`;
    case 6: return `That's ${n} new. Press play ▶️✨`;
    case 7: return `${n} new files, zero leftovers 😎🎶`;
    case 8: return `The folder got ${n} new 📁🔥`;
    case 9: return `Oz delivered ${n} new, as promised 📦🎧`;
    case 10: return `${n} new and ready to blast 🚀🎵`;
    case 11: return `Brand-new energy: ${n} new ⚡✨`;
    case 12: return `${n} new joined the library 📚🔥`;
    case 13: return `All ${n} new. No reruns 🙅🎶`;
    case 14: return `Oz stacked ${n} new 📚🎧`;
    case 15: return `${n} new waiting in Downloads ⏳✨`;
    case 16: return `Clean haul: ${n} new 🧹🔥`;
    case 17: return `${n} new, tagged and tidy 🏷️🎵`;
    case 18: return `The queue turned into ${n} new 🎉🎧`;
    default: return `${n} new. Oz is done showing off 👑✨`;
  }
}

export function failureLine(count: number, succeeded = 0, pick = 0): string | null {
  return withFailures(count, succeeded, pick);
}
