import {describe, expect, it} from 'vitest';
import {enterInList, parseRich, plainRich, toggleBold, toggleList} from './richText';

describe('메모 서식', () => {
  it('글머리·번호·굵게를 읽는다', () => {
    const l = parseRich('제목\n- 사과 **빨강**\n2. 배');
    expect(l[0]).toEqual({kind: 'text', indent: 0, spans: [{text: '제목', bold: false}]});
    expect(l[1]).toEqual({kind: 'bullet', indent: 0, spans: [{text: '사과 ', bold: false}, {text: '빨강', bold: true}]});
    expect(l[2]).toMatchObject({kind: 'number', n: 2});
    expect(plainRich('- a **b**\n1. c')).toBe('• a b\n1. c');
  });
  it('목록 줄에서 엔터를 치면 기호가 이어진다', () => {
    expect(enterInList('- 사과', 4)).toEqual({text: '- 사과\n- ', start: 7, end: 7});
    expect(enterInList('  1. 배', 6)).toEqual({text: '  1. 배\n  2. ', start: 12, end: 12});
    expect(enterInList('그냥 글', 4)).toBeNull();
  });
  it('기호만 있는 줄에서 엔터를 치면 목록이 끝난다', () => {
    expect(enterInList('- a\n- ', 6)).toEqual({text: '- a\n', start: 4, end: 4});
  });
  it('굵게를 감싸고 푼다', () => {
    const on = toggleBold('ab cd', 3, 5);
    expect(on).toEqual({text: 'ab **cd**', start: 5, end: 7});
    expect(toggleBold(on.text, on.start, on.end)).toEqual({text: 'ab cd', start: 3, end: 5});
    expect(toggleBold('', 0, 0)).toEqual({text: '****', start: 2, end: 2});
  });
  it('줄들을 목록으로 바꾸고 다시 푼다', () => {
    const b = toggleList('a\nb', 0, 3, 'bullet');
    expect(b.text).toBe('- a\n- b');
    expect(toggleList(b.text, 0, b.text.length, 'bullet').text).toBe('a\nb');
    expect(toggleList('- a\n- b', 0, 7, 'number').text).toBe('1. a\n2. b');
  });
});
