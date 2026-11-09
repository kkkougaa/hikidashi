import {describe, expect, it} from 'vitest';
import {mediaUrls} from './offline';
import type {Item} from '../data/types';

const base: Item = {id: 'a', kind: 'link', url: 'https://x.com/a/status/1', title: '', note: '', folderId: null, tags: [], starred: false, createdAt: 0, updatedAt: 0, deletedAt: null};

describe('오프라인 저장', () => {
  it('영상·사진·프로필·본문 그림을 겹치지 않게 모은다', () => {
    const urls = mediaUrls({...base, video: 'https://v/1.mp4', image: 'https://p/1.jpg', images: ['https://p/1.jpg', 'https://p/2.jpg'], avatar: 'https://p/av.jpg'},
      {blocks: [{t: 'img', src: 'https://p/3.jpg'}, {t: 'p', text: '글'}]} as never);
    expect(urls).toEqual(['https://v/1.mp4', 'https://p/1.jpg', 'https://p/2.jpg', 'https://p/av.jpg', 'https://p/3.jpg']);
  });
  it('data: 주소나 빈 값은 받지 않는다', () => {
    expect(mediaUrls({...base, image: 'data:image/png;base64,AA', icon: 'data:x'})).toEqual([]);
  });
});
