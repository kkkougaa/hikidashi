import {afterEach, beforeEach, describe, expect, it} from 'vitest';
import {act, useState} from 'react';
import {createRoot, type Root} from 'react-dom/client';
import {TagInput} from './TagInput';

(globalThis as {IS_REACT_ACT_ENVIRONMENT?: boolean}).IS_REACT_ACT_ENVIRONMENT = true;

let host: HTMLDivElement;
let root: Root;
let latest: string[] = [];

function Harness({start = [] as string[], url}: {start?: string[]; url?: string}) {
  const [tags, setTags] = useState(start);
  latest = tags;
  return <TagInput value={tags} onChange={setTags} suggestions={['참고', '나중에', 'css']} sourceUrl={url} />;
}

const input = () => host.querySelector('input')!;
// React 가 값 변경을 알아채도록 브라우저 기본 setter 로 넣고 input 이벤트를 보낸다
function type(v: string) {
  const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    set.call(input(), v);
    input().dispatchEvent(new Event('input', {bubbles: true}));
  });
}
const key = (k: string) => act(() => { input().dispatchEvent(new KeyboardEvent('keydown', {key: k, bubbles: true})); });
const chips = () => [...host.querySelectorAll('.tag-chip')].map(c => c.textContent);

beforeEach(() => {
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
});
afterEach(() => {
  act(() => root.unmount());
  host.remove();
});

describe('태그 입력', () => {
  it('스페이스를 치면 칩이 되고, 처음 보는 태그도 새로 만든다', () => {
    act(() => root.render(<Harness />));
    type('여행 ');
    expect(latest).toEqual(['여행']);
    expect(input().value).toBe('');
    type('#오사카,맛집 ');
    expect(latest).toEqual(['여행', '오사카', '맛집']);
    expect(chips()).toEqual(['#여행', '#오사카', '#맛집']);
  });

  it('같은 태그는 두 번 들어가지 않는다', () => {
    act(() => root.render(<Harness start={['참고']} />));
    type('참고 ');
    expect(latest).toEqual(['참고']);
  });

  it('엔터로도 추가하고, 빈 칸에서 지우기를 누르면 마지막 태그를 뺀다', () => {
    act(() => root.render(<Harness start={['a']} />));
    type('b');
    key('Enter');
    expect(latest).toEqual(['a', 'b']);
    key('Backspace');
    expect(latest).toEqual(['a']);
  });

  it('입력에 맞는 기존 태그를 추천하고, 없으면 새 태그 버튼을 보여 준다', () => {
    act(() => root.render(<Harness />));
    type('c');
    const picks = [...host.querySelectorAll('.tag-suggest-chip')].map(b => b.textContent);
    expect(picks).toContain('#css');
    expect(picks.some(p => p?.startsWith('새 태그'))).toBe(true);
    act(() => (host.querySelector('.tag-suggest-chip:not(.new)') as HTMLButtonElement).click());
    expect(latest).toEqual(['css']);
  });

  it('링크면 맨 앞에 출처 사이트 칩을 보여 준다', () => {
    act(() => root.render(<Harness url="https://www.brunch.co.kr/@a/1" />));
    const box = host.querySelector('.tag-box')!;
    expect(box.firstElementChild?.className).toBe('source-chip');
    expect(box.firstElementChild?.textContent).toBe('brunch.co.kr');
  });
});
