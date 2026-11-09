import type {Backup, Folder, Item} from './types';
import {COLORS, isHex} from './types';

export function makeBackup(folders: Folder[], items: Item[], now = Date.now()): Backup {
  return {app: 'hikidashi', version: 1, exportedAt: now, folders, items};
}

export class BackupError extends Error {}

const isStr = (v: unknown): v is string => typeof v === 'string';
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const isBase = (v: Record<string, unknown>) =>
  isStr(v.id) && isNum(v.createdAt) && isNum(v.updatedAt) && (v.deletedAt === null || isNum(v.deletedAt));

/** 가져온 파일을 검사한다. 형식이 틀리면 BackupError */
export function parseBackup(text: string): Backup {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new BackupError('백업 파일을 읽을 수 없어요. hikidashi에서 내보낸 .json 파일인지 확인해주세요.');
  }
  const b = raw as Partial<Backup>;
  if (!b || b.app !== 'hikidashi' || b.version !== 1 || !Array.isArray(b.items) || !Array.isArray(b.folders)) {
    throw new BackupError('hikidashi 백업 파일이 아니에요.');
  }
  const folders = b.folders.filter((f): f is Folder => {
    const r = f as unknown as Record<string, unknown>;
    return !!r && isBase(r) && isStr(r.name) && isStr(r.color) && r.color in COLORS && (r.hex == null || isHex(r.hex)) && isNum(r.order);
  });
  const items = b.items.filter((i): i is Item => {
    const r = i as unknown as Record<string, unknown>;
    return !!r && isBase(r) && (r.kind === 'link' || r.kind === 'memo') && isStr(r.title) && isStr(r.note)
      && (r.folderId === null || isStr(r.folderId)) && Array.isArray(r.tags) && typeof r.starred === 'boolean';
  });
  return {app: 'hikidashi', version: 1, exportedAt: isNum(b.exportedAt) ? b.exportedAt : 0, folders, items};
}

/**
 * id 기준으로 합친다. 같은 id면 더 최근에 수정된 쪽이 이긴다.
 * 서버 동기화를 붙일 때도 같은 규칙을 쓴다.
 */
export function mergeRecords<T extends {id: string; updatedAt: number}>(local: T[], incoming: T[]): {merged: T[]; changed: T[]} {
  const map = new Map(local.map(r => [r.id, r]));
  const changed: T[] = [];
  for (const r of incoming) {
    const cur = map.get(r.id);
    if (!cur || r.updatedAt > cur.updatedAt) {
      map.set(r.id, r);
      changed.push(r);
    }
  }
  return {merged: [...map.values()], changed};
}
