import {describe, expect, it} from 'vitest';
import {syncFile, type RemoteFile} from './fileSync';
import {mergeRecords} from './backup';
import {deriveKey, newKdf, openEnvelope, readEnvelope, seal, WrongPassphrase, type Envelope, type Vault} from './vault';
import type {Backup, Folder, Item} from './types';

const item = (id: string, updatedAt: number, title: string): Item =>
  ({id, kind: 'memo', title, note: '', folderId: null, tags: [], starred: false, createdAt: 1, updatedAt, deletedAt: null});

/** 시험에선 빨리 돌게 반복 횟수를 줄인다 */
async function vault(pass: string, kdf = newKdf(1000)): Promise<Vault> {
  return {key: await deriveKey(pass, kdf), kdf};
}

/** 메모리 속 드롭박스 파일 (판이 다르면 거절) */
function memFile() {
  let file: {text: string; rev: string} | null = null;
  let n = 0;
  const f: RemoteFile & {file: () => typeof file; raceOnce?: () => Promise<void>; reads: number} = {
    reads: 0,
    file: () => file,
    async rev() { return file?.rev ?? null; },
    async read() { f.reads++; return file; },
    async write(text, rev) {
      if (f.raceOnce) { const r = f.raceOnce; f.raceOnce = undefined; await r(); }
      if ((file?.rev ?? null) !== rev) return 'conflict';
      file = {text, rev: `r${++n}`};
      return file.rev;
    },
  };
  return f;
}

function device(items: Item[] = [], folders: Folder[] = []) {
  const d = {
    items, folders, rev: undefined as string | undefined,
    apply: (b: Backup) => {
      const f = mergeRecords(d.folders, b.folders);
      const i = mergeRecords(d.items, b.items);
      d.folders = f.merged; d.items = i.merged;
      return f.changed.length + i.changed.length;
    },
    async sync(remote: RemoteFile, v: Vault, dirty = true) {
      const r = await syncFile(remote, v, d.apply, () => ({items: d.items, folders: d.folders}), {lastRev: d.rev, dirty});
      d.rev = r.rev ?? undefined;
      return r;
    },
  };
  return d;
}

describe('암호화', () => {
  it('아이폰 앱과 같은 시험 값을 연다 (PBKDF2-SHA256 + AES-GCM, 한글 암호)', async () => {
    const kdf = {name: 'PBKDF2' as const, hash: 'SHA-256' as const, iter: 1000, salt: 'AAECAwQFBgcICQoLDA0ODw=='};
    const env: Envelope = {app: 'hikidashi-sync', v: 1, kdf, iv: 'oKGio6Slpqeoqaqr', data: 'A6Qmg9Yt9FLY7oj19FEHXW1LC3+ZquzRk7lFDnrBtQyXtQ=='};
    // 조합형(NFD)으로 들어와도 같은 키
    const v = {key: await deriveKey('서랍 암호 123'.normalize('NFD'), kdf), kdf};
    expect(await openEnvelope(v, env)).toBe('{"hello":"서랍"}');
  });

  it('잠근 파일엔 내용이 보이지 않고, 틀린 암호로는 못 연다', async () => {
    const v = await vault('맞는 암호');
    const text = await seal(v, '{"비밀":"메모"}');
    expect(text).not.toContain('비밀');
    expect(await openEnvelope(v, readEnvelope(text))).toBe('{"비밀":"메모"}');
    const wrong = {key: await deriveKey('틀린 암호', v.kdf), kdf: v.kdf};
    await expect(openEnvelope(wrong, readEnvelope(text))).rejects.toBeInstanceOf(WrongPassphrase);
    // 다른 기기에서 암호를 바꿔 salt 가 달라진 경우
    await expect(openEnvelope(await vault('맞는 암호'), readEnvelope(text))).rejects.toBeInstanceOf(WrongPassphrase);
  });
});

describe('드롭박스 파일 동기화', () => {
  it('두 기기가 같은 항목을 고치면 나중에 고친 쪽이 남는다', async () => {
    const remote = memFile();
    const v = await vault('암호');
    const phone = device([item('a', 10, '아이폰'), item('b', 5, '둘')]);
    const web = device([item('a', 15, '웹'), item('c', 7, '셋')]);
    expect((await phone.sync(remote, v)).uploaded).toBe(true);
    const w = await web.sync(remote, v);
    expect(w.changed).toBe(1); // b
    expect(w.uploaded).toBe(true); // a(웹이 더 나중), c
    await phone.sync(remote, v);
    expect(phone.items.find(i => i.id === 'a')?.title).toBe('웹');
    expect(phone.items.map(i => i.id).sort()).toEqual(['a', 'b', 'c']);
    // 다 맞춘 뒤엔 올릴 게 없다
    expect((await web.sync(remote, v)).uploaded).toBe(false);
  });

  it('지난번과 판이 같고 고친 게 없으면 내려받지 않는다', async () => {
    const remote = memFile();
    const v = await vault('암호');
    const d = device([item('a', 1, '')]);
    await d.sync(remote, v);
    const before = remote.reads;
    await d.sync(remote, v, false);
    expect(remote.reads).toBe(before);
  });

  it('올리는 사이 다른 기기가 먼저 올리면 다시 받아 합친다', async () => {
    const remote = memFile();
    const v = await vault('암호');
    const web = device([item('a', 10, '처음')]);
    await web.sync(remote, v);
    const phone = device([item('p', 30, '아이폰 새 항목')]);
    web.items = [item('a', 20, '웹에서 고침')];
    remote.raceOnce = async () => { await phone.sync(remote, v); };
    await web.sync(remote, v);
    expect(web.items.map(i => i.id).sort()).toEqual(['a', 'p']);
    const final = JSON.parse(await openEnvelope(v, readEnvelope(remote.file()!.text)));
    expect(final.items.map((i: Item) => i.id).sort()).toEqual(['a', 'p']);
    expect(final.items.find((i: Item) => i.id === 'a').title).toBe('웹에서 고침');
  });

  it('암호가 다르면 합치지 않고 멈춘다', async () => {
    const remote = memFile();
    await device([item('a', 1, '')]).sync(remote, await vault('하나'));
    const other = device([item('b', 2, '')]);
    await expect(other.sync(remote, await vault('둘'))).rejects.toBeInstanceOf(WrongPassphrase);
    expect(other.items.map(i => i.id)).toEqual(['b']);
  });
});
