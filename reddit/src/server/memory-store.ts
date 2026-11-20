// In-memory `Store` for the unit tests and tools/serve-local.ts. Never bundled
// into the Devvit server, which uses Reddit's redis.

import type { Store } from './daily.ts';

export class MemoryStore implements Store {
  strings = new Map<string, string>();
  hashes = new Map<string, Record<string, string>>();
  boards = new Map<string, Map<string, number>>();

  async get(key: string) {
    return this.strings.get(key);
  }

  async set(key: string, value: string) {
    this.strings.set(key, value);
  }

  async expire() {}

  async hGetAll(key: string) {
    return { ...this.hashes.get(key) };
  }

  async hSet(key: string, fieldValues: Record<string, string>) {
    this.hashes.set(key, { ...this.hashes.get(key), ...fieldValues });
  }

  async hDel(key: string, fields: string[]) {
    const hash = { ...this.hashes.get(key) };
    for (const field of fields) delete hash[field];
    this.hashes.set(key, hash);
  }

  async zAdd(key: string, ...members: { member: string; score: number }[]) {
    const board = this.boards.get(key) ?? new Map<string, number>();
    for (const { member, score } of members) board.set(member, score);
    this.boards.set(key, board);
  }

  async zRem(key: string, members: string[]) {
    for (const member of members) this.boards.get(key)?.delete(member);
  }

  async zScore(key: string, member: string) {
    return this.boards.get(key)?.get(member);
  }

  async zCard(key: string) {
    return this.boards.get(key)?.size ?? 0;
  }

  /** Lowest score first, like redis ZRANGE by rank. */
  private sorted(key: string) {
    return [...(this.boards.get(key) ?? [])]
      .map(([member, score]) => ({ member, score }))
      .sort((a, b) => a.score - b.score || a.member.localeCompare(b.member));
  }

  async zRank(key: string, member: string) {
    const index = this.sorted(key).findIndex((entry) => entry.member === member);
    return index < 0 ? undefined : index;
  }

  /** Like redis: a negative `stop` counts from the end (-1 = the last). */
  async zRange(key: string, start: number, stop: number) {
    const all = this.sorted(key);
    return all.slice(start, stop < 0 ? all.length + stop + 1 : stop + 1);
  }
}
