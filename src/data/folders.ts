import type {Folder, Item} from './types';

/**
 * 하위 서랍(한 단계). 하위 서랍은 색을 따로 정하지 않고 상위 서랍 색을 따른다.
 * 칩·고르기 목록에는 "상위-하위" 로 적는다. 상위 서랍이 없어졌으면 그냥 위 단계 서랍으로 본다.
 */
export const isChild = (f: Folder, byId: Map<string, Folder>) => !!f.parentId && byId.has(f.parentId) && f.parentId !== f.id;

/** 화면에 보여줄 모습: 하위 서랍은 이름을 "상위-하위", 색은 상위 것으로 */
export function displayFolders(folders: Folder[]): Map<string, Folder> {
  const byId = new Map(folders.map(f => [f.id, f]));
  return new Map(folders.map(f => {
    const p = isChild(f, byId) ? byId.get(f.parentId!)! : null;
    return [f.id, p ? {...f, name: `${p.name}-${f.name}`, color: p.color, hex: p.hex ?? null} : f];
  }));
}

/** 위 단계 서랍 순서대로, 각 서랍 바로 뒤에 하위 서랍 */
export function orderedFolders(folders: Folder[]): {folder: Folder; depth: 0 | 1}[] {
  const byId = new Map(folders.map(f => [f.id, f]));
  const byOrder = (a: Folder, b: Folder) => a.order - b.order;
  const tops = folders.filter(f => !isChild(f, byId)).sort(byOrder);
  return tops.flatMap(t => [
    {folder: t, depth: 0 as const},
    ...folders.filter(f => f.parentId === t.id && isChild(f, byId)).sort(byOrder).map(c => ({folder: c, depth: 1 as const})),
  ]);
}

/** 서랍과 그 하위 서랍 id */
export function familyOf(id: string, folders: Folder[]): Set<string> {
  return new Set([id, ...folders.filter(f => f.parentId === id && f.id !== id).map(f => f.id)]);
}

/** NSFW 는 태그로 단다 (대소문자 상관없이) */
export const NSFW_TAG = 'nsfw';
export const isNsfw = (i: Item) => i.tags.some(t => t.toLowerCase() === NSFW_TAG);
export const withNsfw = (tags: string[], on: boolean) =>
  on ? (tags.some(t => t.toLowerCase() === NSFW_TAG) ? tags : [...tags, NSFW_TAG]) : tags.filter(t => t.toLowerCase() !== NSFW_TAG);
