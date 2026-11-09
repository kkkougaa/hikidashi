import {describe, expect, it} from 'vitest';
import {COLORS, COLOR_NAMES} from './types';

// WCAG 상대 휘도와 대비
const lum = (hex: string) => {
  const [r, g, b] = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16) / 255).map(c => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a: string, b: string) => {
  const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m);
  return (x + 0.05) / (y + 0.05);
};

describe('서랍 색', () => {
  it('모든 색에서 흰 굵은 글자가 3:1 이상 읽힌다', () => {
    for (const [k, v] of Object.entries(COLORS)) expect(contrast('#FFFFFF', v), k).toBeGreaterThanOrEqual(3);
  });
  it('모든 색에 한국어 이름이 있고 겹치지 않는다', () => {
    const keys = Object.keys(COLORS);
    expect(keys.length).toBeGreaterThanOrEqual(17);
    expect(new Set(Object.values(COLORS)).size).toBe(keys.length);
    expect(new Set(keys.map(k => COLOR_NAMES[k as keyof typeof COLORS])).size).toBe(keys.length);
  });
});
