import {openDB, type DBSchema, type IDBPDatabase} from 'idb';
import type {Folder, Item} from './types';

interface SeorapDB extends DBSchema {
  items: {key: string; value: Item};
  folders: {key: string; value: Folder};
  meta: {key: string; value: unknown};
}

const DB_NAME = 'seorap';
let dbPromise: Promise<IDBPDatabase<SeorapDB>> | null = null;

export function db() {
  dbPromise ??= openDB<SeorapDB>(DB_NAME, 1, {
    upgrade(d) {
      d.createObjectStore('items', {keyPath: 'id'});
      d.createObjectStore('folders', {keyPath: 'id'});
      d.createObjectStore('meta');
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
