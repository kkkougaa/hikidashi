import {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {getMeta, loadAll, putFolders, putItems, setMeta} from './db';
import {mergeRecords} from './backup';
import type {Backup, ColorKey, Folder, Item, ItemDraft} from './types';

const uid = () =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

export function newFolder(name: string, color: ColorKey, order: number, now = Date.now()): Folder {
  return {id: uid(), name, color, order, createdAt: now, updatedAt: now, deletedAt: null};
}
export function newItem(d: ItemDraft, now = Date.now()): Item {
  return {...d, id: uid(), starred: false, createdAt: now, updatedAt: now, deletedAt: null};
}

/** 처음 열었을 때 만들어 두는 서랍 */
export function defaultFolders(now = Date.now()): Folder[] {
  return [
    newFolder('나중에 읽기', 'blue', 0, now),
    newFolder('참고', 'cyan', 1, now),
    newFolder('아이디어', 'orange', 2, now),
  ];
}

export interface Library {
  ready: boolean;
  /** 삭제 표시가 없는 것만 */
  items: Item[];
  folders: Folder[];
  addItem: (d: ItemDraft) => Item;
  updateItem: (id: string, patch: Partial<ItemDraft & {starred: boolean}>) => void;
  removeItem: (id: string) => void;
  restoreItem: (id: string) => void;
  addFolder: (name: string, color: ColorKey) => Folder;
  updateFolder: (id: string, patch: Partial<Pick<Folder, 'name' | 'color' | 'order'>>) => void;
  /** 서랍을 지우고 안의 항목은 미분류로 옮긴다. 되돌리기용 함수를 돌려준다 */
  removeFolder: (id: string) => () => void;
  importBackup: (b: Backup) => {items: number; folders: number};
  allRecords: () => {items: Item[]; folders: Folder[]};
}

export function useLibrary(): Library {
  const [ready, setReady] = useState(false);
  const [items, setItems] = useState<Item[]>([]);
  const [folders, setFolders] = useState<Folder[]>([]);
  // 이벤트 핸들러에서 항상 최신 값을 쓰기 위한 참조
  const itemsRef = useRef(items);
  const foldersRef = useRef(folders);
  itemsRef.current = items;
  foldersRef.current = folders;

  useEffect(() => {
    let alive = true;
    (async () => {
      const data = await loadAll();
      let fs = data.folders;
      if (!(await getMeta<boolean>('seeded'))) {
        fs = defaultFolders();
        await putFolders(fs);
        await setMeta('seeded', true);
      }
      if (!alive) return;
      setItems(data.items);
      setFolders(fs);
      setReady(true);
    })();
    return () => {
      alive = false;
    };
  }, []);

  const writeItems = useCallback((changed: Item[]) => {
    const ids = new Set(changed.map(c => c.id));
    const next = [...itemsRef.current.filter(i => !ids.has(i.id)), ...changed];
    itemsRef.current = next;
    setItems(next);
    void putItems(changed);
  }, []);
  const writeFolders = useCallback((changed: Folder[]) => {
    const ids = new Set(changed.map(c => c.id));
    const next = [...foldersRef.current.filter(f => !ids.has(f.id)), ...changed];
    foldersRef.current = next;
    setFolders(next);
    void putFolders(changed);
  }, []);

  const find = (id: string) => itemsRef.current.find(i => i.id === id);

  const api = useMemo<Omit<Library, 'ready' | 'items' | 'folders'>>(() => ({
    addItem: d => {
      const it = newItem(d);
      writeItems([it]);
      return it;
    },
    updateItem: (id, patch) => {
      const cur = find(id);
      if (cur) writeItems([{...cur, ...patch, updatedAt: Date.now()}]);
    },
    removeItem: id => {
      const cur = find(id);
      if (cur) writeItems([{...cur, deletedAt: Date.now(), updatedAt: Date.now()}]);
    },
    restoreItem: id => {
      const cur = find(id);
      if (cur) writeItems([{...cur, deletedAt: null, updatedAt: Date.now()}]);
    },
    addFolder: (name, color) => {
      const live = foldersRef.current.filter(f => !f.deletedAt);
      const f = newFolder(name, color, live.length ? Math.max(...live.map(x => x.order)) + 1 : 0);
      writeFolders([f]);
      return f;
    },
    updateFolder: (id, patch) => {
      const cur = foldersRef.current.find(f => f.id === id);
      if (cur) writeFolders([{...cur, ...patch, updatedAt: Date.now()}]);
    },
    removeFolder: id => {
      const now = Date.now();
      const folder = foldersRef.current.find(f => f.id === id);
      const moved = itemsRef.current.filter(i => i.folderId === id);
      if (!folder) return () => {};
      writeFolders([{...folder, deletedAt: now, updatedAt: now}]);
      if (moved.length) writeItems(moved.map(i => ({...i, folderId: null, updatedAt: now})));
      return () => {
        const t = Date.now();
        writeFolders([{...folder, deletedAt: null, updatedAt: t}]);
        const ids = new Set(moved.map(m => m.id));
        const back = itemsRef.current.filter(i => ids.has(i.id) && i.folderId === null);
        if (back.length) writeItems(back.map(i => ({...i, folderId: id, updatedAt: t})));
      };
    },
    importBackup: b => {
      const fi = mergeRecords(foldersRef.current, b.folders);
      const ii = mergeRecords(itemsRef.current, b.items);
      if (fi.changed.length) writeFolders(fi.changed);
      if (ii.changed.length) writeItems(ii.changed);
      return {items: ii.changed.length, folders: fi.changed.length};
    },
    allRecords: () => ({items: itemsRef.current, folders: foldersRef.current}),
  }), [writeItems, writeFolders]);

  const liveItems = useMemo(() => items.filter(i => !i.deletedAt).sort((a, b) => b.createdAt - a.createdAt), [items]);
  const liveFolders = useMemo(() => folders.filter(f => !f.deletedAt).sort((a, b) => a.order - b.order), [folders]);

  return {ready, items: liveItems, folders: liveFolders, ...api};
}
