// Types shared by the web view (src/client) and the Devvit server (src/server).
// The Godot game reads the same JSON shapes through the page's fetch.

/** One leaderboard line. `rank` is 1-based; `timeMs` is the ranked time. */
export type Row = {
  rank: number;
  name: string;
  timeMs: number;
};

export type Streak = {
  /** Consecutive days finished, counting today or yesterday as the latest. */
  current: number;
  best: number;
};

/**
 * Which ranking a board holds:
 *  - `day`     best time on that day's circuit (one level a day),
 *  - `level`   best time ever on one level,
 *  - `overall` each player's best times on ALL levels added up; only players
 *              with a time on every level are ranked. Lowest total first.
 */
export type BoardKind = 'day' | 'level' | 'overall';

export type Board = {
  kind: BoardKind;
  /** The level's permanent id (the game's `LEVELS[i].id`); null for `overall`. */
  levelId: number | null;
  players: number;
  top: Row[];
  /** The viewer's own line, or null when logged out or not ranked on it. */
  me: Row | null;
};

/** GET /api/init — everything the splash and the game need to start. */
export type InitResponse = {
  /** Daily Circuit number this post belongs to (1 = launch day). */
  day: number;
  /** Deterministic seed for `day`; same for every player. */
  seed: number;
  /** UTC date of `day`, as YYYY-MM-DD. */
  date: string;
  /** False when the post is an older circuit: still playable, no streak. */
  isToday: boolean;
  /** The level (permanent id) that is this day's circuit. */
  levelId: number;
  /** Every level's permanent id, in the game's order. */
  levelIds: number[];
  /** Null when the viewer is logged out (can play, cannot rank). */
  username: string | null;
  /** The viewer's line on this day's board. */
  me: Row | null;
  streak: Streak;
  /** Players and top times on this day's board. */
  players: number;
  top: Row[];
  /** How many levels the viewer has a time on; all of them = ranked overall. */
  mapsDone: number;
};

/** POST /api/run — report a finished race. */
export type RunRequest = {
  /** Permanent id of the level that was raced. */
  levelId: number;
  timeMs: number;
};

export type RunResponse = {
  /** False when logged out or the run failed validation; nothing was stored. */
  accepted: boolean;
  /** True when this run beat the player's previous best on that level. */
  improved: boolean;
  /** True when the level was this day's circuit, so the day board and streak moved. */
  countsForDay: boolean;
  /** The viewer's line on this day's board. */
  me: Row | null;
  streak: Streak;
  players: number;
  top: Row[];
  level: Board;
  overall: Board;
  mapsDone: number;
};

/** GET /api/leaderboard?board=overall|level|day[&level=<id>][&limit=<n>] */
export type LeaderboardResponse = Board & {
  day: number;
  mapsDone: number;
  mapsTotal: number;
};
