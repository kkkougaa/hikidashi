import {describe, expect, it} from 'vitest';
import {displayFolders, familyOf, isNsfw, orderedFolders, withNsfw} from './folders';
import type {Folder, Item} from './types';

const f = (id: string, order: number, parentId?: string | null, color: Folder['color'] = 'blue'): Folder =>
  ({id, name: id.toUpperCase(), color, order, parentId, createdAt: 1, updatedAt: 1, deletedAt: null});

describe('하위 서랍', () => {
  const folders = [f('b', 1, null, 'red'), f('a', 0, null, 'green'), f('a2', 1, 'a', 'gray'), f('a1', 0, 'a', 'gray'), f('lost', 2, 'gone')];

  it('상위 다음에 하위, 각자 순서대로. 상위가 없어진 건 위 단계로', () => {
    expect(orderedFolders(folders).map(r => `${r.depth}:${r.folder.id}`)).toEqual(['0:a', '1:a1', '1:a2', '0:b', '0:lost']);
  });

  it('하위 서랍은 "상위-하위" 이름에 상위 색', () => {
    const d = displayFolders(folders);
    expect(d.get('a1')).toMatchObject({name: 'A-A1', color: 'green'});
    expect(d.get('a')).toMatchObject({name: 'A', color: 'green'});
    expect(d.get('lost')?.name).toBe('LOST');
  });

  it('상위 서랍을 보면 하위 서랍 것도 같이', () => {
    expect([...familyOf('a', folders)].sort()).toEqual(['a', 'a1', 'a2']);
    expect([...familyOf('a1', folders)]).toEqual(['a1']);
  });
});

describe('NSFW', () => {
  const item = (tags: string[]): Item => ({id: 'x', kind: 'memo', title: '', note: '', folderId: null, tags, starred: false, createdAt: 1, updatedAt: 1, deletedAt: null});
  it('태그로 달고 뺀다 (대소문자 상관없이)', () => {
    expect(isNsfw(item(['NSFW']))).toBe(true);
    expect(withNsfw(['a'], true)).toEqual(['a', 'nsfw']);
    expect(withNsfw(['a', 'Nsfw'], true)).toEqual(['a', 'Nsfw']);
    expect(withNsfw(['a', 'Nsfw'], false)).toEqual(['a']);
  });
});
