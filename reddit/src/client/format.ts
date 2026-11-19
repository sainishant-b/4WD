/** 83456 -> "1:23.46". Same m:ss.cc shape as Game.format_time in scripts/game_data.gd. */
export function formatTime(timeMs: number): string {
  const centis = Math.round(timeMs / 10);
  const minutes = Math.floor(centis / 6000);
  const seconds = Math.floor((centis % 6000) / 100);
  const rest = centis % 100;
  return `${minutes}:${String(seconds).padStart(2, '0')}.${String(rest).padStart(2, '0')}`;
}

/** "2026-11-27" -> "Nov 27". */
export function formatDate(isoDate: string): string {
  return new Date(`${isoDate}T00:00:00Z`).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  });
}
