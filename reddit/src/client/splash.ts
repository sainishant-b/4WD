// Inline post view: shows today's circuit and the viewer's standing, then
// opens the game full-screen. Kept tiny so the post paints instantly in the
// feed; the 36 MB engine only downloads after the player taps Drive.

import { requestExpandedMode } from '@devvit/web/client';
import type { InitResponse } from '../shared/api.ts';
import { formatDate, formatTime } from './format.ts';

function el(id: string): HTMLElement {
  const node = document.getElementById(id);
  if (!node) throw new Error(`missing #${id}`);
  return node;
}

function render(init: InitResponse): void {
  el('eyebrow').textContent = `Daily Circuit #${init.day} · ${formatDate(init.date)}`;
  el('stat-best').textContent = init.me ? formatTime(init.me.timeMs) : '--';
  el('stat-rank').textContent = init.me ? `#${init.me.rank}` : '--';
  el('stat-streak').textContent = String(init.streak.current);
  el('play').textContent = init.me ? 'Beat your time' : 'Drive';

  const drivers = `${init.players} driver${init.players === 1 ? '' : 's'}`;
  let note: string;
  if (init.players === 0) note = 'Nobody has set a time yet. Be first.';
  else if (!init.isToday) note = `${drivers} on this circuit. It no longer counts for streaks.`;
  else if (!init.username) note = `${drivers} today. Log in to appear on the board.`;
  else note = `${drivers} today.`;
  el('footnote').textContent = note;
}

async function refresh(): Promise<void> {
  try {
    const response = await fetch('/api/init');
    if (!response.ok) throw new Error(`init ${response.status}`);
    render((await response.json()) as InitResponse);
  } catch (error) {
    // The post is still playable without stats; leave the placeholders.
    console.error('could not load daily stats', error);
  }
}

/** Opens the game full-screen, optionally straight onto one of its screens. */
function openGame(event: MouseEvent, screen: string): void {
  try {
    // The game page reads and clears this on boot (see game.ts).
    if (screen) localStorage.setItem('fws-screen', screen);
    else localStorage.removeItem('fws-screen');
  } catch {
    // No storage: the game just opens on its normal first screen.
  }
  try {
    requestExpandedMode(event, 'game');
  } catch (error) {
    // No Devvit bridge (tools/serve-local.ts): open the game page directly.
    console.warn('expanded mode unavailable, navigating instead', error);
    location.href = 'game.html';
  }
}

el('play').addEventListener('click', (event) => openGame(event, ''));
el('board').addEventListener('click', (event) => openGame(event, 'leaderboard'));

// Fires when the player closes the expanded game and returns to the post.
addEventListener('focus', () => void refresh());
void refresh();
