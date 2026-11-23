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

/** How long the splash's car dot takes to lap the thumbnail. */
const LAP_MS = 7000;
/** The animation frame of the car dot now running, so a redraw can stop it. */
let lapFrame = 0;

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
  lapCar(svg, track, road);
}

/**
 * A gold dot with a short trail lapping the circuit from the start line, the
 * way the race goes (the points run in driving order). Attributes only, set
 * each frame; a still dot on the start line when the viewer asks for less
 * motion.
 */
function lapCar(svg: Element, track: TrackShape, road: number): void {
  cancelAnimationFrame(lapFrame);
  const xs: number[] = [];
  const ys: number[] = [];
  for (let i = 0; i + 1 < track.points.length; i += 2) {
    xs.push(track.points[i] as number);
    ys.push(track.points[i + 1] as number);
  }
  if (xs.length < 2) return;
  xs.push(xs[0] as number); // close the loop
  ys.push(ys[0] as number);
  const along = [0];
  for (let i = 1; i < xs.length; i++) {
    const step = Math.hypot((xs[i] as number) - (xs[i - 1] as number), (ys[i] as number) - (ys[i - 1] as number));
    along.push((along[i - 1] as number) + step);
  }
  const lap = along[along.length - 1] as number;
  const at = (distance: number): string => {
    const d = ((distance % lap) + lap) % lap;
    let lo = 0;
    let hi = along.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if ((along[mid] as number) <= d) lo = mid;
      else hi = mid;
    }
    const span = (along[hi] as number) - (along[lo] as number) || 1;
    const t = (d - (along[lo] as number)) / span;
    const x = (xs[lo] as number) + ((xs[hi] as number) - (xs[lo] as number)) * t;
    const y = (ys[lo] as number) + ((ys[hi] as number) - (ys[lo] as number)) * t;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  };

  const trail = document.createElementNS(SVG_NS, 'polyline');
  trail.setAttribute('class', 'trail');
  trail.setAttribute('stroke-width', String(road * 0.42));
  const dot = document.createElementNS(SVG_NS, 'circle');
  dot.setAttribute('class', 'runner');
  dot.setAttribute('r', String(road * 0.62));
  dot.setAttribute('stroke-width', String(road * 0.24));
  svg.append(trail, dot);

  const trailLength = lap * 0.07;
  const place = (distance: number): void => {
    const points: string[] = [];
    for (let k = 0; k <= 8; k++) points.push(at(distance - trailLength * (1 - k / 8)));
    trail.setAttribute('points', points.join(' '));
    const [x, y] = (points[8] as string).split(',');
    dot.setAttribute('cx', x as string);
    dot.setAttribute('cy', y as string);
  };
  place(0);
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
    trail.setAttribute('points', '');
    return;
  }
  const started = performance.now();
  const frame = (now: number): void => {
    place(((now - started) / LAP_MS) * lap);
    lapFrame = requestAnimationFrame(frame);
  };
  lapFrame = requestAnimationFrame(frame);
}

function renderToday(levelId: number): void {
  const track = TRACKS[levelId];
  if (!track) return;
  drawTrack(el('track'), track);
  el('today-name').textContent = track.name;
  const weekday = track.weekday.charAt(0) + track.weekday.slice(1).toLowerCase();
  const laps = `${track.laps} lap${track.laps === 1 ? '' : 's'}`;
  el('today-detail').textContent = `${weekday} · ${laps} · top speed ${track.topSpeed}`;
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
