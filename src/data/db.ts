import {openDB, type DBSchema, type IDBPDatabase} from 'idb';
import type {Folder, Item} from './types';
import type {Article} from '../lib/reader';
import type {OfflinePack} from '../lib/offline';

interface HikidashiDB extends DBSchema {
  items: {key: string; value: Item};
  folders: {key: string; value: Folder};
  meta: {key: string; value: unknown};
  /** 리더 본문 (항목 id → 본문). 동기화하지 않는다 */
  articles: {key: string; value: Article};
  /** 오프라인 저장 (항목 id → 받은 모습·본문·사진·영상). 동기화하지 않는다 */
  offline: {key: string; value: OfflinePack};
}

const DB_NAME = 'hikidashi';
let dbPromise: Promise<IDBPDatabase<HikidashiDB>> | null = null;

export function db() {
  dbPromise ??= openDB<HikidashiDB>(DB_NAME, 3, {
    upgrade(d, old) {
      if (old < 1) {
        d.createObjectStore('items', {keyPath: 'id'});
        d.createObjectStore('folders', {keyPath: 'id'});
        d.createObjectStore('meta');
      }
      if (old < 2) d.createObjectStore('articles');
      if (old < 3) d.createObjectStore('offline', {keyPath: 'id'});
    },
  });
  return dbPromise;
}

/** 테스트에서 DB를 새로 열 때 쓴다 */
export function resetDbForTests() {
  dbPromise = null;
}

export async function loadAll() {
  const d = await db();
  const [items, folders] = await Promise.all([d.getAll('items'), d.getAll('folders')]);
  return {items, folders};
}

export async function putItems(items: Item[]) {
  const tx = (await db()).transaction('items', 'readwrite');
  await Promise.all([...items.map(i => tx.store.put(i)), tx.done]);
}

export async function putFolders(folders: Folder[]) {
  const tx = (await db()).transaction('folders', 'readwrite');
  await Promise.all([...folders.map(f => tx.store.put(f)), tx.done]);
}

export async function getMeta<T>(key: string): Promise<T | undefined> {
  return (await db()).get('meta', key) as Promise<T | undefined>;
}

export async function setMeta(key: string, value: unknown) {
  await (await db()).put('meta', value, key);
}

/** 브라우저가 저장 공간을 임의로 비우지 않도록 요청한다 */
export async function requestPersistence(): Promise<boolean> {
  try {
    if (!navigator.storage?.persist) return false;
    if (await navigator.storage.persisted()) return true;
    return await navigator.storage.persist();
  } catch {
    return false;
  }
}

/** 본문 검색용: 저장한 본문 전체 (id → 글) */
export async function allArticleTexts(): Promise<Map<string, string>> {
  const d = await db();
  const [keys, values] = await Promise.all([d.getAllKeys('articles'), d.getAll('articles')]);
  return new Map(keys.map((k, n) => [String(k), [values[n]?.title ?? '', ...(values[n]?.blocks ?? []).map(b => ('text' in b ? b.text : ''))].join(' ').toLowerCase()]));
}

export async function getArticle(id: string): Promise<Article | undefined> {
  return (await db()).get('articles', id);
}

export async function putArticle(id: string, a: Article) {
  await (await db()).put('articles', a, id);
}

export async function hasArticle(id: string): Promise<boolean> {
  return (await (await db()).getKey('articles', id)) !== undefined;
}

export async function countArticles(): Promise<number> {
  return (await db()).count('articles');
}

export async function clearArticles() {
  await (await db()).clear('articles');
}
