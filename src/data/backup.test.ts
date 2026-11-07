import {describe, expect, it} from 'vitest';
import {BackupError, makeBackup, mergeRecords, parseBackup} from './backup';
import {newFolder, newItem} from './library';

describe('백업', () => {
  const f = newFolder('참고', 'cyan', 0, 1000);
  const i = newItem({kind: 'link', url: 'https://ex.com', title: 'ex', note: '', folderId: f.id, tags: ['a']}, 2000);

  it('내보낸 것을 그대로 다시 읽는다', () => {
    const b = parseBackup(JSON.stringify(makeBackup([f], [i], 3000)));
    expect(b.folders).toEqual([f]);
    expect(b.items).toEqual([i]);
    expect(b.exportedAt).toBe(3000);
  });

  it('서랍 백업이 아니면 알려준다', () => {
    expect(() => parseBackup('{oops')).toThrow(BackupError);
    expect(() => parseBackup(JSON.stringify({app: 'other', version: 1, items: [], folders: []}))).toThrow(BackupError);
  });

  it('깨진 레코드는 빼고 읽는다', () => {
    const raw = makeBackup([f, {...f, id: 'x', color: 'neon'} as never], [i, {...i, id: 'y', kind: 'video'} as never]);
    const b = parseBackup(JSON.stringify(raw));
    expect(b.folders.map(x => x.id)).toEqual([f.id]);
    expect(b.items.map(x => x.id)).toEqual([i.id]);
  });

  it('합칠 때 더 최근에 고친 쪽이 이긴다', () => {
    const older = {...i, title: '옛 제목', updatedAt: 1500};
    const newer = {...i, title: '새 제목', updatedAt: 9000};
    const other = {...i, id: 'other'};
    const r1 = mergeRecords([older], [newer, other]);
    expect(r1.merged.find(x => x.id === i.id)?.title).toBe('새 제목');
    expect(r1.changed.map(x => x.id).sort()).toEqual([i.id, 'other'].sort());
    const r2 = mergeRecords([newer], [older]);
    expect(r2.changed).toEqual([]);
    expect(r2.merged[0].title).toBe('새 제목');
  });
});
