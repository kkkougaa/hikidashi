import {useEffect, useState} from 'react';

/** 이 기기에만 두는 설정 (동기화하지 않는다) */
export interface Prefs {
  theme: 'system' | 'light' | 'dark';
  view: 'list' | 'card';
  /** '' 첫 번째 서랍, 'none' 미분류, 그 밖 서랍 id */
  defaultFolder: string;
  /** 링크를 누르면 리더 / 새 탭 */
  linkOpen: 'reader' | 'tab';
  saveArticles: boolean;
  readerFont: 'sans' | 'serif' | 'rounded';
  readerSize: number;
  readerSpacing: number;
  /** 최근 연 항목 id (최신이 앞) */
  recent: string[];
}

const DEFAULTS: Prefs = {
  theme: 'system', view: 'list', defaultFolder: '', linkOpen: 'reader', saveArticles: true,
  readerFont: 'sans', readerSize: 18, readerSpacing: 1.75, recent: [],
};

const KEY = 'hikidashi-prefs';
const EVENT = 'hikidashi-prefs';

export function readPrefs(): Prefs {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) ?? '{}') as Partial<Prefs>;
    // 예전 보기 설정도 이어받는다
    const oldView = localStorage.getItem('hikidashi-view');
    return {...DEFAULTS, ...(oldView === 'card' ? {view: 'card' as const} : {}), ...saved};
  } catch {
    return DEFAULTS;
  }
}

export function setPref<K extends keyof Prefs>(key: K, value: Prefs[K]) {
  const next = {...readPrefs(), [key]: value};
  try { localStorage.setItem(KEY, JSON.stringify(next)); } catch { /* 저장 못 해도 이번엔 쓴다 */ }
  window.dispatchEvent(new CustomEvent(EVENT, {detail: next}));
}

/** 설정 하나를 읽고, 다른 곳에서 바꾸면 따라 바뀐다 */
export function usePref<K extends keyof Prefs>(key: K): [Prefs[K], (v: Prefs[K]) => void] {
  const [value, setValue] = useState<Prefs[K]>(() => readPrefs()[key]);
  useEffect(() => {
    const on = (e: Event) => setValue((e as CustomEvent<Prefs>).detail[key]);
    window.addEventListener(EVENT, on);
    return () => window.removeEventListener(EVENT, on);
  }, [key]);
  return [value, (v: Prefs[K]) => setPref(key, v)];
}

/** 최근 연 항목에 넣는다 */
export function markRecent(id: string) {
  const r = readPrefs().recent.filter(x => x !== id);
  setPref('recent', [id, ...r].slice(0, 12));
}
