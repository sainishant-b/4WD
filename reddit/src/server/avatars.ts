// Players' Reddit avatars (snoovatars) on the leaderboard rows.
//
//  - Each row gets `avatar`: the URL of the player's snoovatar, or nothing
//    when they have none (the game then draws their initial instead).
//  - URLs are cached for a day per player, so a busy board does not ask
//    Reddit for every name on every view, a changed avatar shows by tomorrow,
//    and a deleted account's avatar drops out on its own.
//  - Only Reddit-hosted https images are passed on: the web view may only
//    show media hosted on Reddit.
//
// No Devvit imports: the lookup is passed in (index.ts uses
// reddit.getSnoovatarUrl; the tests and tools/serve-local.ts fake it).

import type { Board, Row } from '../shared/api.ts';
import type { Store } from './daily.ts';

/** Finds a player's avatar URL; undefined when they have none. */
export type AvatarLookup = (username: string) => Promise<string | undefined>;

const avatarKey = (name: string) => `avatar:${name}`;
/** Stored for a player who has no avatar, so they are not looked up again today. */
const NONE = '-';
export const AVATAR_TTL_SECONDS = 24 * 60 * 60;

/** Hosts Reddit serves user avatars from. */
const REDDIT_IMAGE_HOSTS = ['i.redd.it', 'preview.redd.it', 'styles.redditmedia.com', 'www.redditstatic.com'];

export function isRedditImage(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'https:' && REDDIT_IMAGE_HOSTS.includes(parsed.hostname);
  } catch {
    return false;
  }
}

/**
 * One player's avatar URL, from the cache or the lookup. A failed lookup is
 * not cached (it is tried again next time) and gives no avatar.
 */
async function avatarOf(
  store: Store,
  lookup: AvatarLookup,
  name: string,
  accept: (url: string) => boolean,
): Promise<string | undefined> {
  const cached = await store.get(avatarKey(name));
  if (cached !== undefined) return cached === NONE ? undefined : cached;
  let url: string | undefined;
  try {
    url = await lookup(name);
  } catch (error) {
    console.error(`avatar lookup failed for ${name}`, error);
    return undefined;
  }
  const kept = url && accept(url) ? url : undefined;
  await store.set(avatarKey(name), kept ?? NONE);
  await store.expire(avatarKey(name), AVATAR_TTL_SECONDS);
  return kept;
}

/** Avatar URLs for `names` (each looked up once), keyed by name; players without one are left out. */
export async function avatarsFor(
  store: Store,
  lookup: AvatarLookup,
  names: string[],
  accept: (url: string) => boolean = isRedditImage,
): Promise<Record<string, string>> {
  const unique = [...new Set(names)];
  const urls = await Promise.all(unique.map((name) => avatarOf(store, lookup, name, accept)));
  const found: Record<string, string> = {};
  unique.forEach((name, i) => {
    const url = urls[i];
    if (url) found[name] = url;
  });
  return found;
}

/** The board with `avatar` filled in on its rows (`top` and `me`). */
export async function withAvatars<T extends Pick<Board, 'top' | 'me'>>(
  store: Store,
  lookup: AvatarLookup,
  board: T,
  accept: (url: string) => boolean = isRedditImage,
): Promise<T> {
  const rows = board.me ? [...board.top, board.me] : board.top;
  const found = await avatarsFor(store, lookup, rows.map((row) => row.name), accept);
  const dress = (row: Row): Row => (found[row.name] ? { ...row, avatar: found[row.name] } : row);
  return { ...board, top: board.top.map(dress), me: board.me ? dress(board.me) : null };
}
