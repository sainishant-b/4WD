// Types shared by the web view (src/client) and the Devvit server (src/server).
// The Godot game reads the same JSON shapes through the page's fetch.

/** One leaderboard line. `rank` is 1-based; `timeMs` is the ranked time. */
export type Row = {
  rank: number;
  name: string;
  timeMs: number;
  /**
   * The player's Reddit avatar (snoovatar) image URL. Only on leaderboard
   * rows (GET /api/leaderboard), and only when the player has one.
   */
  avatar?: string;
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
  /** The viewer's Reddit avatar (snoovatar) image URL; null when logged out or they have none. */
  avatar: string | null;
  /** The viewer's line on this day's board. */
  me: Row | null;
  streak: Streak;
  /** Players and top times on this day's board. */
  players: number;
  top: Row[];
  /** How many levels the viewer has a time on; all of them = ranked overall. */
  mapsDone: number;
  /** Milliseconds until the next Daily Circuit starts (00:00 UTC), as of the response. */
  nextCircuitInMs: number;
  /** True when the viewer has opted in to showing their streak as user flair. */
  flairOn: boolean;
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
  /** Milliseconds until the next Daily Circuit starts (00:00 UTC), as of the response. */
  nextCircuitInMs: number;
  /** True when the viewer has opted in to showing their streak as user flair. */
  flairOn: boolean;
};

/** POST /api/flair — turn the streak flair on or off (opt-in, off by default). */
export type FlairRequest = {
  on: boolean;
};

export type FlairResponse = {
  /** Whether the streak flair is on now. */
  on: boolean;
  /** The flair text shown, when on. */
  text: string | null;
  /** Set when the change could not be made (logged out, or Reddit refused). */
  error?: string;
};

/** GET /api/leaderboard?board=overall|level|day[&level=<id>][&limit=<n>] */
export type LeaderboardResponse = Board & {
  day: number;
  mapsDone: number;
  mapsTotal: number;
};
