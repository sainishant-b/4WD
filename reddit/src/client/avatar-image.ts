// Turns a player's avatar URL (from the server's leaderboard rows) into a small
// square PNG the Godot game can decode: `FWS.avatar(url, done)` in game.ts.
//
// Snoovatars are tall full-body pictures, so the top square (the head and
// shoulders) is kept and scaled to SIZE px. Only Reddit-hosted images and this
// page's own host are loaded: the web view may only show media hosted on
// Reddit. When the image cannot be read (blocked, missing, no CORS) the answer
// is "", and the game draws the player's initial instead.

/** Side of the PNG handed to the game, in px (the board draws it at ~32 px). */
const SIZE = 96;

const REDDIT_IMAGE_HOSTS = ['i.redd.it', 'preview.redd.it', 'styles.redditmedia.com', 'www.redditstatic.com'];

const cache = new Map<string, Promise<string>>();

/** The URL resolved against this page, or null if it is not one we load. */
export function avatarSource(url: string, page: string): URL | null {
  let parsed: URL;
  try {
    parsed = new URL(url, page);
  } catch {
    return null;
  }
  const own = parsed.origin === new URL(page).origin;
  const reddit = parsed.protocol === 'https:' && REDDIT_IMAGE_HOSTS.includes(parsed.hostname);
  return own || reddit ? parsed : null;
}

/** The square to keep from a `width` x `height` picture: the top one when tall, else the middle. */
export function cropOf(width: number, height: number): { x: number; y: number; side: number } {
  const side = Math.min(width, height);
  return { x: (width - side) / 2, y: height > width ? 0 : (height - side) / 2, side };
}

function loadImage(src: string, crossOrigin: boolean): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const image = new Image();
    if (crossOrigin) image.crossOrigin = 'anonymous';
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error(`could not load ${src}`));
    image.src = src;
  });
}

/**
 * Reads the picture: first as bytes (a same-origin blob never taints the
 * canvas), then, if the page may not fetch it (content policy, CORS), as an
 * <img> asking for CORS. A server that answers with an error is not asked twice.
 */
async function readImage(source: URL): Promise<HTMLImageElement> {
  let response: Response;
  try {
    response = await fetch(source, { mode: 'cors', credentials: 'omit' });
  } catch {
    return loadImage(source.href, true);
  }
  if (!response.ok) throw new Error(`avatar ${response.status}`);
  const blobUrl = URL.createObjectURL(await response.blob());
  try {
    return await loadImage(blobUrl, false);
  } finally {
    URL.revokeObjectURL(blobUrl);
  }
}

async function render(source: URL): Promise<string> {
  const image = await readImage(source);
  const crop = cropOf(image.naturalWidth || image.width, image.naturalHeight || image.height);
  if (crop.side <= 0) return '';
  const canvas = document.createElement('canvas');
  canvas.width = SIZE;
  canvas.height = SIZE;
  const context = canvas.getContext('2d');
  if (!context) return '';
  context.imageSmoothingQuality = 'high';
  context.drawImage(image, crop.x, crop.y, crop.side, crop.side, 0, 0, SIZE, SIZE);
  // Throws if the canvas is tainted (an image served without CORS).
  return canvas.toDataURL('image/png').replace(/^data:image\/png;base64,/, '');
}

/** Base64 PNG of the avatar's head, or "" when it cannot be shown. Cached per URL. */
export function avatarPng(url: string): Promise<string> {
  const source = avatarSource(url, location.href);
  if (!source) return Promise.resolve('');
  let pending = cache.get(source.href);
  if (!pending) {
    pending = render(source).catch((error: unknown) => {
      console.warn('avatar not shown', source.href, error);
      return '';
    });
    cache.set(source.href, pending);
  }
  return pending;
}
