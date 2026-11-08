import {describe, expect, it} from 'vitest';
import {isSyncFile, readAll, SYNC_FILE, writeAll} from './sync';
import {makeBackup, mergeRecords} from './backup';
import type {Item} from './types';

/** 메모리 속 폴더 (브라우저의 폴더 핸들 흉내) */
function memDir(files: Record<string, string>) {
  return {
    name: 'hikidashi',
    files,
    async *values() {
      for (const [name, text] of Object.entries(files)) yield {kind: 'file' as const, name, getFile: async () => ({text: async () => text}) as unknown as File};
    },
    async getFileHandle(name: string) {
      return {createWritable: async () => {
        let buf = '';
        return {write: async (d: string) => { buf += d; }, close: async () => { files[name] = buf; }};
      }};
    },
    async removeEntry(name: string) { delete files[name]; },
    async queryPermission() { return 'granted' as const; },
    async requestPermission() { return 'granted' as const; },
  };
}

const item = (id: string, updatedAt: number, title: string): Item =>
  ({id, kind: 'memo', title, note: '', folderId: null, tags: [], starred: false, createdAt: 1, updatedAt, deletedAt: null});

describe('iCloud 폴더 동기화', () => {
  it('충돌 사본까지 읽어 합치고, 합친 걸 쓴 뒤 사본은 지운다', async () => {
    const dir = memDir({
      [SYNC_FILE]: JSON.stringify(makeBackup([], [item('a', 10, '아이폰에서 고침'), item('b', 5, '둘')])),
      'hikidashi-sync 2.json': JSON.stringify(makeBackup([], [item('a', 20, '더 나중에 고침'), item('c', 7, '셋')])),
      '다른 파일.json': '{}',
    });
    const {backups, extras} = await readAll(dir);
    expect(backups).toHaveLength(2);
    expect(extras).toEqual(['hikidashi-sync 2.json']);
    let local: Item[] = [item('a', 15, '웹에서 고침')];
    for (const b of backups) local = mergeRecords(local, b.items).merged;
    expect(local.find(i => i.id === 'a')?.title).toBe('더 나중에 고침');
    expect(local.map(i => i.id).sort()).toEqual(['a', 'b', 'c']);
    await writeAll(dir, JSON.stringify(makeBackup([], local)), extras);
    expect(Object.keys(dir.files).sort()).toEqual(['hikidashi-sync.json', '다른 파일.json']);
    expect(JSON.parse(dir.files[SYNC_FILE]).items).toHaveLength(3);
  });
  it('파일 이름 규칙', () => {
    expect(isSyncFile('hikidashi-sync.json')).toBe(true);
    expect(isSyncFile('hikidashi-sync (1).json')).toBe(true);
    expect(isSyncFile('hikidashi-backup.json')).toBe(false);
  });
});
