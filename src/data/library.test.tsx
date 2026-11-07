import {afterEach, beforeEach, describe, expect, it} from 'vitest';
import {act} from 'react';
import {createRoot, type Root} from 'react-dom/client';
import {IDBFactory} from 'fake-indexeddb';
import {loadAll, resetDbForTests} from './db';
import {useLibrary, type Library} from './library';

// React 의 act 경고를 끄기 위한 표시
(globalThis as {IS_REACT_ACT_ENVIRONMENT?: boolean}).IS_REACT_ACT_ENVIRONMENT = true;

let lib: Library;
let root: Root;
let host: HTMLElement;
function Probe() {
  lib = useLibrary();
  return null;
}
const flush = () => act(async () => { await new Promise(r => setTimeout(r, 20)); });

async function mount() {
  host = document.createElement('div');
  root = createRoot(host);
  await act(async () => root.render(<Probe />));
  await flush();
}

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory();
  resetDbForTests();
});
afterEach(() => act(() => root.unmount()));

describe('서랍 데이터', () => {
  it('처음 열면 기본 서랍 3개를 만들고, 다시 열어도 또 만들지 않는다', async () => {
    await mount();
    expect(lib.ready).toBe(true);
    expect(lib.folders.map(f => f.name)).toEqual(['나중에 읽기', '참고', '아이디어']);
    act(() => root.unmount());
    resetDbForTests();
    await mount();
    expect(lib.folders).toHaveLength(3);
  });

  it('추가·수정·삭제가 IndexedDB 에 남고, 삭제는 표시만 한다', async () => {
    await mount();
    const folderId = lib.folders[0].id;
    let id = '';
    await act(async () => { id = lib.addItem({kind: 'memo', title: '장보기', note: '계란', folderId, tags: []}).id; });
    await act(async () => lib.updateItem(id, {starred: true, title: '장보기 목록'}));
    await flush();
    expect(lib.items[0]).toMatchObject({title: '장보기 목록', starred: true});

    await act(async () => lib.removeItem(id));
    await flush();
    expect(lib.items).toHaveLength(0);
    const stored = (await loadAll()).items.find(i => i.id === id);
    expect(stored?.deletedAt).toBeTypeOf('number');

    await act(async () => lib.restoreItem(id));
    await flush();
    expect(lib.items.map(i => i.id)).toEqual([id]);
  });

  it('서랍을 지우면 항목은 미분류로 가고, 되돌리면 제자리로 온다', async () => {
    await mount();
    const f = lib.folders[1];
    await act(async () => {
      lib.addItem({kind: 'link', url: 'https://a.com', title: 'a', note: '', folderId: f.id, tags: []});
      lib.addItem({kind: 'link', url: 'https://b.com', title: 'b', note: '', folderId: f.id, tags: []});
    });
    let undo = () => {};
    await act(async () => { undo = lib.removeFolder(f.id); });
    expect(lib.folders.map(x => x.id)).not.toContain(f.id);
    expect(lib.items.every(i => i.folderId === null)).toBe(true);

    await act(async () => undo());
    await flush();
    expect(lib.folders.map(x => x.id)).toContain(f.id);
    expect(lib.items.every(i => i.folderId === f.id)).toBe(true);
  });

  it('백업을 가져오면 더 새로운 것만 바뀐다', async () => {
    await mount();
    let id = '';
    await act(async () => { id = lib.addItem({kind: 'memo', title: '원본', note: 'x', folderId: null, tags: []}).id; });
    const mine = lib.items[0];
    let r = {items: 0, folders: 0};
    await act(async () => {
      r = lib.importBackup({app: 'seorap', version: 1, exportedAt: 0, folders: [], items: [{...mine, title: '옛것', updatedAt: mine.updatedAt - 10}]});
    });
    expect(r.items).toBe(0);
    await act(async () => {
      r = lib.importBackup({app: 'seorap', version: 1, exportedAt: 0, folders: [], items: [{...mine, title: '새것', updatedAt: mine.updatedAt + 10}]});
    });
    expect(r.items).toBe(1);
    expect(lib.items.find(i => i.id === id)?.title).toBe('새것');
  });
});
