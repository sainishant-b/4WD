// Inline post view: shows today's circuit (its name and a picture of the
// track, from tracks.ts) and the viewer's standing, then opens the game
// full-screen. Kept tiny so the post paints instantly in the
// feed; the 36 MB engine only downloads after the player taps Drive.

import { requestExpandedMode } from '@devvit/web/client';
import type { InitResponse } from '../shared/api.ts';
import { formatDate, formatTime } from './format.ts';
import { TRACKS, type TrackShape } from './tracks.ts';

const SVG_NS = 'http://www.w3.org/2000/svg';

function el(id: string): HTMLElement {
  const node = document.getElementById(id);
  if (!node) throw new Error(`missing #${id}`);
  return node;
}

function line(svg: Element, cls: string, points: string, width: number): void {
  const shape = document.createElementNS(SVG_NS, 'polyline');
  shape.setAttribute('class', cls);
  shape.setAttribute('points', points);
  shape.setAttribute('stroke-width', String(width));
  svg.appendChild(shape);
}

/**
 * Draws a circuit the way the game does: green road, white edges, a dark
 * casing, and a gold bar across the start/finish line. Attributes only (no
 * inline styles), which Reddit's CSP allows.
 */
function drawTrack(svg: Element, track: TrackShape): void {
  svg.replaceChildren();
  svg.setAttribute('viewBox', `0 0 ${track.width} ${track.height}`);
  const pairs: string[] = [];
  for (let i = 0; i + 1 < track.points.length; i += 2) pairs.push(`${track.points[i]},${track.points[i + 1]}`);
  pairs.push(pairs[0] as string); // close the loop
  const points = pairs.join(' ');
  // Thumbnail-sized, so the edges are drawn wider than true scale to stay visible.
  const road = track.roadWidth * 1.6;
  const edge = Math.max(track.width, track.height) * 0.012;
  line(svg, 'casing', points, road + edge * 4);
  line(svg, 'edge', points, road + edge * 2);
  line(svg, 'road', points, road);
  const [sx, sy] = track.start;
  const [dx, dy] = track.startDir;
  const half = road / 2 + edge;
  line(svg, 'start', `${sx - dy * half},${sy + dx * half} ${sx + dy * half},${sy - dx * half}`, edge * 2.5);
}

function renderToday(levelId: number): void {
  const track = TRACKS[levelId];
  if (!track) return;
  drawTrack(el('track'), track);
  el('today-name').textContent = track.name;
  el('today-detail').textContent = `${track.laps} laps · top speed ${track.topSpeed}`;
  el('today').hidden = false;
  document.body.classList.add('has-today');
}

function render(init: InitResponse): void {
  el('eyebrow').textContent = `Daily Circuit #${init.day} · ${formatDate(init.date)}`;
  renderToday(init.levelId);
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
