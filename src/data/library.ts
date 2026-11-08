import {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {getMeta, loadAll, putFolders, putItems, setMeta} from './db';
import {mergeRecords} from './backup';
import type {Backup, ColorKey, Folder, Item, ItemDraft} from './types';

export const uid = () =>
  typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;

export function newFolder(name: string, color: ColorKey, order: number, now = Date.now()): Folder {
  return {id: uid(), name, color, order, createdAt: now, updatedAt: now, deletedAt: null};
}
export function newItem(d: ItemDraft, now = Date.now(), id = uid()): Item {
  return {...d, id, starred: false, createdAt: now, updatedAt: now, deletedAt: null};
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
  /** id 를 넘기면 그 id 로 만든다 (애니메이션 안에서 추가해도 id 를 미리 알 수 있게) */
  addItem: (d: ItemDraft, id?: string) => Item;
  updateItem: (id: string, patch: Partial<ItemDraft & {starred: boolean}>) => void;
  removeItem: (id: string) => void;
  restoreItem: (id: string) => void;
  addFolder: (name: string, color: ColorKey) => Folder;
  updateFolder: (id: string, patch: Partial<Pick<Folder, 'name' | 'color' | 'order'>>) => void;
  /** 서랍을 지우고 안의 항목은 미분류로 옮긴다. 되돌리기용 함수를 돌려준다 */
  removeFolder: (id: string) => () => void;
  importBackup: (b: Backup) => {items: number; folders: number};
  allRecords: () => {items: Item[]; folders: Folder[]};
  /** 여러 항목을 한 번에 고친다. 되돌리기용으로 고치기 전 모습을 돌려준다 */
  updateMany: (ids: string[], fn: (i: Item) => Partial<Item>) => Item[];
  /** updateMany 가 돌려준 모습으로 되돌린다 (다른 기기에도 퍼지게 수정 시각은 새로) */
  restoreVersions: (prev: Item[]) => void;
  /** 태그 이름 바꾸기 (같은 이름이 있으면 합쳐진다) */
  renameTag: (from: string, to: string) => Item[];
  removeTag: (tag: string) => Item[];
  toggleHighlight: (id: string, text: string) => void;
  reorderFolders: (ids: string[]) => void;
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
    addItem: (d, id) => {
      const it = newItem(d, Date.now(), id);
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
    updateMany: (ids, fn) => {
      const set = new Set(ids);
      const prev = itemsRef.current.filter(i => set.has(i.id));
      const now = Date.now();
      if (prev.length) writeItems(prev.map(i => ({...i, ...fn(i), updatedAt: now})));
      return prev;
    },
    restoreVersions: prev => {
      const now = Date.now();
      if (prev.length) writeItems(prev.map(i => ({...i, updatedAt: now})));
    },
    renameTag: (from, to) => {
      const t = to.trim().replace(/^#+/, '').trim();
      if (!t || t === from) return [];
      const live = itemsRef.current.filter(i => !i.deletedAt && i.tags.includes(from));
      const now = Date.now();
      if (live.length) writeItems(live.map(i => ({...i, tags: [...new Set(i.tags.map(x => (x === from ? t : x)))], updatedAt: now})));
      return live;
    },
    removeTag: tag => {
      const live = itemsRef.current.filter(i => !i.deletedAt && i.tags.includes(tag));
      const now = Date.now();
      if (live.length) writeItems(live.map(i => ({...i, tags: i.tags.filter(x => x !== tag), updatedAt: now})));
      return live;
    },
    toggleHighlight: (id, text) => {
      const cur = find(id);
      if (!cur) return;
      const h = cur.highlights ?? [];
      writeItems([{...cur, highlights: h.includes(text) ? h.filter(x => x !== text) : [...h, text], updatedAt: Date.now()}]);
    },
    reorderFolders: ids => {
      const now = Date.now();
      const changed = ids.flatMap((id, n) => {
        const f = foldersRef.current.find(x => x.id === id);
        return f && f.order !== n ? [{...f, order: n, updatedAt: now}] : [];
      });
      if (changed.length) writeFolders(changed);
    },
  }), [writeItems, writeFolders]);

  const liveItems = useMemo(() => items.filter(i => !i.deletedAt).sort((a, b) => b.createdAt - a.createdAt), [items]);
  const liveFolders = useMemo(() => folders.filter(f => !f.deletedAt).sort((a, b) => a.order - b.order), [folders]);

  return {ready, items: liveItems, folders: liveFolders, ...api};
}
