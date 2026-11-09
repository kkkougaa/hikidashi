import {afterEach, beforeEach, describe, expect, it} from 'vitest';
import {act} from 'react';
import {createRoot, type Root} from 'react-dom/client';
import {PassphraseForm} from './SettingsSheet';

(globalThis as {IS_REACT_ACT_ENVIRONMENT?: boolean}).IS_REACT_ACT_ENVIRONMENT = true;

let host: HTMLDivElement;
let root: Root;
let sent: string[] = [];

const inputs = () => [...host.querySelectorAll('input')];
const submit = () => host.querySelector<HTMLButtonElement>('button[type=submit]')!;
const alertText = () => host.querySelector('[role=alert]')?.textContent ?? '';
function type(el: HTMLInputElement, v: string) {
  const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => { set.call(el, v); el.dispatchEvent(new Event('input', {bubbles: true})); });
}
function show(fresh: boolean, answer: string | null = null) {
  act(() => root.render(<PassphraseForm fresh={fresh} onSubmit={async p => { sent.push(p); return answer; }} />));
}

beforeEach(() => {
  host = document.createElement('div');
  document.body.appendChild(host);
  root = createRoot(host);
  sent = [];
});
afterEach(() => { act(() => root.unmount()); host.remove(); });

describe('동기화 암호 입력', () => {
  it('처음 정할 땐 8자 이상, 두 번 같게 넣어야 보낸다', async () => {
    show(true);
    expect(inputs()).toHaveLength(2);
    type(inputs()[0], '짧음');
    expect(alertText()).toBe('8자 이상으로 정해주세요');
    expect(submit().disabled).toBe(true);
    type(inputs()[0], '서랍 암호 123');
    type(inputs()[1], '서랍 암호 12');
    expect(alertText()).toBe('두 암호가 달라요');
    type(inputs()[1], '서랍 암호 123');
    expect(submit().disabled).toBe(false);
    await act(async () => { submit().click(); });
    expect(sent).toEqual(['서랍 암호 123']);
  });

  it('이미 정한 암호를 넣을 땐 한 칸, 틀리면 이유를 보여 준다', async () => {
    show(false, '암호가 맞지 않아요');
    expect(inputs()).toHaveLength(1);
    expect(submit().disabled).toBe(true);
    type(inputs()[0], '아무거나');
    await act(async () => { submit().click(); });
    expect(sent).toEqual(['아무거나']);
    expect(alertText()).toBe('암호가 맞지 않아요');
  });
});
