import {describe, expect, it} from 'vitest';
import {minutes, parseMarkdown, readerUrl, supportsReader} from './reader';

describe('리더 마크다운', () => {
  it('제목·문단·목록·인용·코드·그림을 나눈다', () => {
    const md = [
      '이 페이지는 번역되었습니다.',
      '',
      'CSS 그리드 완전 정복',
      '==========',
      '',
      '그리드는 **두 방향**으로 배치하는 [레이아웃](https://ex.com/l) 방식이다.',
      '줄과 칸을 한 번에 다룬다.',
      '',
      '![도표](https://ex.com/img/diagram.png)',
      '',
      '## 예제',
      '',
      '```css',
      '.grid {',
      '  display: grid;',
      '}',
      '```',
      '',
      '> 인용문입니다',
      '',
      '*   첫째 항목',
      '*   [관련 글 링크만 있는 줄](https://ex.com/x)',
      '',
      '공유하기',
    ].join('\n');
    expect(parseMarkdown(md)).toEqual([
      {t: 'p', text: '그리드는 두 방향으로 배치하는 레이아웃 방식이다. 줄과 칸을 한 번에 다룬다.'},
      {t: 'img', src: 'https://ex.com/img/diagram.png'},
      {t: 'h', text: '예제', level: 2},
      {t: 'code', text: '.grid {\n  display: grid;\n}'},
      {t: 'q', text: '인용문입니다'},
      {t: 'li', text: '첫째 항목'},
    ]);
  });
  it('주소 규칙', () => {
    expect(readerUrl('https://blog.naver.com/abc/223')).toBe('https://m.blog.naver.com/abc/223');
    expect(supportsReader('https://ex.com/a')).toBe(true);
    expect(supportsReader('https://x.com/elonmusk/status/1585341984679469056')).toBe(false);
    expect(supportsReader('https://youtu.be/jNQXAC9IVRw')).toBe(false);
    expect(minutes({blocks: [{t: 'p', text: 'a'.repeat(1600)}]})).toBe(3);
  });
});
