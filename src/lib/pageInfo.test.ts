import {describe, expect, it} from 'vitest';
import {clip, directMedia, logoUrl, parseFxTweet, parseReader, tidyTitle, xStatusId, youtubeId} from './pageInfo';

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

  it('X 게시물 주소에서 id 를 찾는다', () => {
    expect(xStatusId('https://x.com/elonmusk/status/1585341984679469056')).toBe('1585341984679469056');
    expect(xStatusId('https://twitter.com/NASA/status/1857000000000000000?s=20')).toBe('1857000000000000000');
    expect(xStatusId('https://mobile.twitter.com/i/web/status/123456789')).toBe('123456789');
    expect(xStatusId('https://x.com/elonmusk')).toBeNull();
    expect(xStatusId('https://example.com/a/status/123456')).toBeNull();
  });

  it('X 게시물은 글·사진·작성자를 쓴다', () => {
    const withPhoto = parseFxTweet({
      text: '오늘 찍은 사진\n두 번째 줄 https://t.co/abc123',
      author: {name: '홍길동', screen_name: 'hong', avatar_url: 'https://pbs.twimg.com/profile_images/1/a_normal.jpg'},
      media: {photos: [{url: 'https://pbs.twimg.com/media/photo.jpg'}]},
    });
    expect(withPhoto).toEqual({title: undefined, description: '오늘 찍은 사진\n두 번째 줄', image: 'https://pbs.twimg.com/media/photo.jpg', avatar: 'https://pbs.twimg.com/profile_images/1/a_200x200.jpg', siteName: 'X · @hong'});
    const video = parseFxTweet({text: '영상', author: {screen_name: 'a'}, media: {videos: [{url: 'https://video.twimg.com/v.mp4', thumbnail_url: 'https://pbs.twimg.com/thumb.jpg', type: 'video'}]}});
    expect(video.image).toBe('https://pbs.twimg.com/thumb.jpg');
    expect(video.video).toBe('https://video.twimg.com/v.mp4');
    // 움짤도 mp4 로 온다
    const gif = parseFxTweet({text: '움짤', media: {all: [{type: 'gif', url: 'https://video.twimg.com/tweet_video/g.mp4', thumbnail_url: 'https://pbs.twimg.com/g.jpg'}]}});
    expect(gif.video).toBe('https://video.twimg.com/tweet_video/g.mp4');
    expect(parseFxTweet({text: '사진', media: {photos: [{url: 'https://pbs.twimg.com/p.jpg'}]}}).video).toBeUndefined();
    // 타임라인 보기용: 프로필 사진과 사진 여러 장
    const many = parseFxTweet({text: '여러 장', author: {screen_name: 'a', avatar_url: 'https://pbs.twimg.com/profile_images/1/a_normal.jpg'},
      media: {photos: [1, 2, 3, 4, 5].map(n => ({url: `https://pbs.twimg.com/${n}.jpg`}))}});
    expect(many.avatar).toBe('https://pbs.twimg.com/profile_images/1/a_200x200.jpg');
    expect(many.images).toEqual([1, 2, 3, 4].map(n => `https://pbs.twimg.com/${n}.jpg`));
    expect(many.image).toBe('https://pbs.twimg.com/1.jpg');
    expect(parseFxTweet({text: '한 장', media: {photos: [{url: 'https://pbs.twimg.com/1.jpg'}]}}).images).toBeUndefined();
    // 사진이 없으면 작성자 프로필 사진
    const noMedia = parseFxTweet({text: '글만', author: {name: 'A', screen_name: 'a', avatar_url: 'https://pbs.twimg.com/profile_images/1/a_normal.jpg'}});
    expect(noMedia.image).toBe('https://pbs.twimg.com/profile_images/1/a_200x200.jpg');
    expect(noMedia.title).toBeUndefined();
    expect(noMedia.description).toBe('글만');
    expect(parseFxTweet({text: '', author: {name: 'A'}}).title).toBe('A의 게시물');
  });

  it('영상·그림 파일 주소는 페이지를 읽지 않고 바로 쓴다', () => {
    expect(directMedia('https://cdn.example.com/clips/%EA%B3%A0%EC%96%91%EC%9D%B4.mp4?x=1')).toEqual({title: '고양이.mp4', video: 'https://cdn.example.com/clips/%EA%B3%A0%EC%96%91%EC%9D%B4.mp4?x=1', siteName: 'cdn.example.com'});
    expect(directMedia('https://www.example.com/a/b.GIF')).toEqual({title: 'b.GIF', image: 'https://www.example.com/a/b.GIF', siteName: 'example.com'});
    expect(directMedia('https://example.com/post/1')).toBeNull();
  });
});
