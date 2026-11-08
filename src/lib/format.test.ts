import {describe, expect, it} from 'vitest';
import {bucketOf, cleanUrl, daysAgo, domainOf, findUrl, findUrls, guessTitle, normalizeUrl, parseTags, stamp} from './format';

describe('주소', () => {
  it('프로토콜 없이 적어도 https 주소로 바꾼다', () => {
    expect(normalizeUrl('example.com/a')).toBe('https://example.com/a');
    expect(normalizeUrl('  https://www.figma.com/community ')).toBe('https://www.figma.com/community');
  });
  it('주소가 아니면 null', () => {
    expect(normalizeUrl('')).toBeNull();
    expect(normalizeUrl('그냥 메모')).toBeNull();
    expect(normalizeUrl('hello')).toBeNull();
    expect(normalizeUrl('javascript:alert(1)')).toBeNull();
    expect(normalizeUrl('ftp://example.com')).toBeNull();
  });
  it('도메인에서 www 를 뺀다', () => {
    expect(domainOf('https://www.youtube.com/watch?v=1')).toBe('youtube.com');
    expect(domainOf('not a url')).toBe('');
  });
  it('공유된 글에서 주소를 찾는다', () => {
    expect(findUrl('이거 봐 https://brunch.co.kr/@a/42 재밌음')).toBe('https://brunch.co.kr/@a/42');
    expect(findUrl('주소 없음')).toBeNull();
  });
  it('주소에서 제목을 짐작한다', () => {
    expect(guessTitle('https://ex.com/blog/css-grid_layout.html')).toBe('css grid layout');
    expect(guessTitle('https://ex.com/posts/12345')).toBe('ex.com');
    expect(guessTitle('https://www.ex.com/')).toBe('ex.com');
  });
});

describe('태그', () => {
  it('쉼표로 나누고 # 과 중복을 없앤다', () => {
    expect(parseTags('참고, #나중에 ,, 참고，ui')).toEqual(['참고', '나중에', 'ui']);
    expect(parseTags('   ')).toEqual([]);
  });
});

describe('날짜', () => {
  const now = new Date(2026, 10, 7, 21, 30).getTime();
  const at = (d: number, h = 10) => new Date(2026, 10, d, h).getTime();
  it('자정 기준으로 며칠 전인지 센다', () => {
    expect(daysAgo(new Date(2026, 10, 7, 0, 1).getTime(), now)).toBe(0);
    expect(daysAgo(new Date(2026, 10, 6, 23, 59).getTime(), now)).toBe(1);
  });
  it('묶음을 나눈다', () => {
    expect(bucketOf(at(7), now)).toBe('오늘');
    expect(bucketOf(at(6), now)).toBe('어제');
    expect(bucketOf(at(2), now)).toBe('이번 주');
    expect(bucketOf(new Date(2026, 9, 20).getTime(), now)).toBe('이번 달');
    expect(bucketOf(new Date(2026, 5, 1).getTime(), now)).toBe('이전');
  });
  it('목록 시각 표시', () => {
    expect(stamp(at(6), now)).toBe('어제');
    expect(stamp(new Date(2026, 9, 28).getTime(), now)).toBe('10월 28일');
    expect(stamp(new Date(2025, 0, 3).getTime(), now)).toBe('2025년 1월 3일');
  });
});


describe('추적 꼬리 떼기', () => {
  it('앱과 같은 규칙', () => {
    expect(normalizeUrl('https://ex.com/a?utm_source=x&id=3&fbclid=abc')).toBe('https://ex.com/a?id=3');
    expect(normalizeUrl('https://ex.com/a?utm_medium=m')).toBe('https://ex.com/a');
    expect(normalizeUrl('https://youtu.be/jNQXAC9IVRw?si=abcd&t=10')).toBe('https://youtu.be/jNQXAC9IVRw?t=10');
    expect(normalizeUrl('https://x.com/a/status/1585341984679469056?s=20&t=xyz')).toBe('https://x.com/a/status/1585341984679469056');
    expect(normalizeUrl('https://ex.com/search?s=css&t=2')).toBe('https://ex.com/search?s=css&t=2');
    expect(cleanUrl('https://ex.com/a#:~:text=hello')).toBe('https://ex.com/a');
    expect(cleanUrl('https://ex.com/a#section')).toBe('https://ex.com/a#section');
  });
  it('글 속 주소 모두', () => {
    expect(findUrls('볼 것: https://a.com/x, 그리고 (https://b.com/y). 또 https://a.com/x')).toEqual(['https://a.com/x', 'https://b.com/y']);
  });
});
