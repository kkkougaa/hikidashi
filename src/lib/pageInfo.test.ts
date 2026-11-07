import {describe, expect, it} from 'vitest';
import {clip, logoUrl, parseReader, tidyTitle, youtubeId} from './pageInfo';

describe('링크 정보 정리', () => {
  it('유튜브 주소에서 영상 id 를 찾는다', () => {
    expect(youtubeId('https://www.youtube.com/watch?v=jNQXAC9IVRw')).toBe('jNQXAC9IVRw');
    expect(youtubeId('https://youtu.be/jNQXAC9IVRw?t=3')).toBe('jNQXAC9IVRw');
    expect(youtubeId('https://m.youtube.com/shorts/abcDEF12345')).toBe('abcDEF12345');
    expect(youtubeId('https://example.com/watch?v=1')).toBeNull();
  });

  it('제목 끝의 사이트 이름을 뗀다', () => {
    expect(tidyTitle('Me at the zoo - YouTube')).toBe('Me at the zoo');
    expect(tidyTitle('CSS 그리드 | MDN', 'MDN')).toBe('CSS 그리드');
    expect(tidyTitle('좋은 글 - brunch', undefined, 'brunch.co.kr')).toBe('좋은 글');
    expect(tidyTitle('MDN', 'MDN')).toBe('MDN');
    expect(tidyTitle('CSS 그리드 레이아웃 - CSS: Cascading Style Sheets | MDN', 'MDN Web Docs')).toBe('CSS 그리드 레이아웃 - CSS: Cascading Style Sheets');
    expect(tidyTitle('Grid - MDN Web Docs', 'MDN Web Docs')).toBe('Grid');
  });

  it('긴 소개문은 단어 경계에서 자른다', () => {
    const s = '가나다 '.repeat(60);
    const out = clip(s, 40);
    expect(out.length).toBeLessThanOrEqual(41);
    expect(out.endsWith('…')).toBe(true);
    expect(clip('짧은 글')).toBe('짧은 글');
  });

  it('로고 주소를 만든다', () => {
    expect(logoUrl('https://www.brunch.co.kr/@a/1')).toBe('https://www.google.com/s2/favicons?domain=brunch.co.kr&sz=64');
    expect(logoUrl('')).toBeNull();
  });

  it('대표 이미지가 있으면 그것을, 없으면 본문 이미지를 쓴다', () => {
    const url = 'https://blog.example.com/post/1';
    const withOg = parseReader({title: '글', metadata: {'og:image': 'https://cdn.example.com/cover.jpg'}, images: {a: 'https://cdn.example.com/body.jpg'}}, url);
    expect(withOg.image).toBe('https://cdn.example.com/cover.jpg');
    const noOg = parseReader({title: '글', images: {
      a: 'https://cdn.example.com/favicon.png',
      b: 'https://yt3.ggpht.com/abc=s48-c-k',
      c: url,
      d: 'https://cdn.example.com/photo.jpg',
    }}, url);
    expect(noOg.image).toBe('https://cdn.example.com/photo.jpg');
    expect(parseReader({title: '글', images: {a: 'https://x.com/logo.png'}}, url).image).toBeUndefined();
  });

  it('유튜브는 영상 썸네일과 깔끔한 제목을 쓴다', () => {
    const info = parseReader({title: 'Me at the zoo - YouTube', description: 'Enjoy the videos and music you love, upload original content'}, 'https://www.youtube.com/watch?v=jNQXAC9IVRw');
    expect(info.title).toBe('Me at the zoo');
    expect(info.image).toBe('https://i.ytimg.com/vi/jNQXAC9IVRw/hqdefault.jpg');
    // 공통 소개문뿐이면 조회수 같은 화면 글자를 가져오지 않고 비워 둔다
    const junk = parseReader({title: 'x - YouTube', description: 'Enjoy the videos and music you love', content: 'jawed 447,943,663 views 21y ago and more words here'}, 'https://youtu.be/jNQXAC9IVRw');
    expect(junk.description).toBeUndefined();
  });

  it('소개문이 없거나 사이트 공통 문구면 본문 첫 문단을 쓴다', () => {
    const content = 'Skip to main content\n\n![img](https://x.com/a.png)\n\n> 우리는 좋은 글이 가지는 힘을 믿습니다. 좋은 글은 수많은 사람들에게 영향을 미칩니다.\n\n다음 문단';
    const info = parseReader({title: '브런치', description: '글이 작품이 되는 공간, 브런치', content}, 'https://brunch.co.kr/@brunch/1');
    expect(info.description).toBe('우리는 좋은 글이 가지는 힘을 믿습니다. 좋은 글은 수많은 사람들에게 영향을 미칩니다.');
    const own = parseReader({title: 'a', description: '사이트가 적어 둔 소개문입니다'}, 'https://ex.com/a');
    expect(own.description).toBe('사이트가 적어 둔 소개문입니다');
  });
});
