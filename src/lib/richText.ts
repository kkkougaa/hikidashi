/**
 * 메모 서식. 본문은 평범한 글자로 저장하고, 몇 가지 표시만 읽어서 꾸민다.
 * - "- " (또는 "• ", "* ") 로 시작하는 줄 → 글머리 기호 목록
 * - "1. " 처럼 숫자와 점으로 시작하는 줄 → 번호 목록
 * - **굵게** → 굵은 글자
 * iOS `HikidashiCore/RichText.swift` 와 같은 규칙이어야 한다.
 */

export interface Span { text: string; bold: boolean }
export type RichLine =
  | {kind: 'text'; indent: number; spans: Span[]}
  | {kind: 'bullet'; indent: number; spans: Span[]}
  | {kind: 'number'; indent: number; n: number; spans: Span[]};

const BULLET = /^([ \t]*)[-•*] (.*)$/;
const NUMBER = /^([ \t]*)(\d{1,4})[.)] (.*)$/;
const BOLD = /\*\*(.+?)\*\*/g;

export function spans(text: string): Span[] {
  const out: Span[] = [];
  let at = 0;
  for (const m of text.matchAll(BOLD)) {
    if (m.index! > at) out.push({text: text.slice(at, m.index), bold: false});
    out.push({text: m[1], bold: true});
    at = m.index! + m[0].length;
  }
  if (at < text.length || !out.length) out.push({text: text.slice(at), bold: false});
  return out;
}

const indentOf = (s: string) => s.replace(/\t/g, '  ').length;

export function parseRich(text: string): RichLine[] {
  return text.split('\n').map(line => {
    let m = BULLET.exec(line);
    if (m) return {kind: 'bullet', indent: indentOf(m[1]), spans: spans(m[2])};
    m = NUMBER.exec(line);
    if (m) return {kind: 'number', indent: indentOf(m[1]), n: Number(m[2]), spans: spans(m[3])};
    return {kind: 'text', indent: 0, spans: spans(line)};
  });
}

/** 목록·카드 한 줄 미리보기용: 표시를 지우고 글머리는 • 로 */
export function plainRich(text: string): string {
  return parseRich(text).map(l => {
    const t = l.spans.map(s => s.text).join('');
    return l.kind === 'bullet' ? `• ${t}` : l.kind === 'number' ? `${l.n}. ${t}` : t;
  }).join('\n');
}

export interface Edit { text: string; start: number; end: number }

const lineStart = (text: string, pos: number) => text.lastIndexOf('\n', pos - 1) + 1;
const lineEnd = (text: string, pos: number) => { const i = text.indexOf('\n', pos); return i < 0 ? text.length : i; };

/**
 * 목록 줄에서 엔터를 쳤을 때. 다음 줄에 같은 기호(번호는 +1)를 넣는다.
 * 기호만 있는 빈 줄에서 치면 기호를 지우고 목록을 끝낸다. 목록 줄이 아니면 null.
 */
export function enterInList(text: string, pos: number): Edit | null {
  const s = lineStart(text, pos);
  const before = text.slice(s, pos);
  const rest = text.slice(pos, lineEnd(text, pos));
  const bullet = /^([ \t]*)([-•*]) (.*)$/.exec(before);
  const number = /^([ \t]*)(\d{1,4})([.)]) (.*)$/.exec(before);
  if (bullet) {
    if (!bullet[3].trim() && !rest.trim()) return {text: text.slice(0, s) + text.slice(pos), start: s, end: s};
    const ins = `\n${bullet[1]}${bullet[2]} `;
    return {text: text.slice(0, pos) + ins + text.slice(pos), start: pos + ins.length, end: pos + ins.length};
  }
  if (number) {
    if (!number[4].trim() && !rest.trim()) return {text: text.slice(0, s) + text.slice(pos), start: s, end: s};
    const ins = `\n${number[1]}${Number(number[2]) + 1}${number[3]} `;
    return {text: text.slice(0, pos) + ins + text.slice(pos), start: pos + ins.length, end: pos + ins.length};
  }
  return null;
}

/** 고른 글자를 ** 로 감싸거나 푼다. 고른 게 없으면 **** 를 넣고 가운데에 커서 */
export function toggleBold(text: string, start: number, end: number): Edit {
  const sel = text.slice(start, end);
  if (sel.length >= 4 && sel.startsWith('**') && sel.endsWith('**')) {
    const inner = sel.slice(2, -2);
    return {text: text.slice(0, start) + inner + text.slice(end), start, end: start + inner.length};
  }
  if (text.slice(start - 2, start) === '**' && text.slice(end, end + 2) === '**') {
    return {text: text.slice(0, start - 2) + sel + text.slice(end + 2), start: start - 2, end: end - 2};
  }
  return {text: `${text.slice(0, start)}**${sel}**${text.slice(end)}`, start: start + 2, end: end + 2};
}

/** 고른 줄들을 목록으로 바꾸거나, 이미 그 목록이면 기호를 뗀다 */
export function toggleList(text: string, start: number, end: number, kind: 'bullet' | 'number'): Edit {
  const s = lineStart(text, start);
  const e = lineEnd(text, Math.max(start, end));
  const lines = text.slice(s, e).split('\n');
  const strip = (l: string) => l.replace(BULLET, '$1$2').replace(NUMBER, '$1$3');
  const all = lines.every(l => (kind === 'bullet' ? BULLET : NUMBER).test(l));
  const next = all
    ? lines.map(strip)
    : lines.map((l, i) => {
        const m = /^([ \t]*)(.*)$/.exec(strip(l))!;
        return `${m[1]}${kind === 'bullet' ? '-' : `${i + 1}.`} ${m[2]}`;
      });
  const block = next.join('\n');
  const out = text.slice(0, s) + block + text.slice(e);
  const delta = block.length - (e - s);
  // 한 줄이고 고른 게 없으면 커서는 줄 끝으로
  if (lines.length === 1 && start === end) return {text: out, start: s + block.length, end: s + block.length};
  return {text: out, start: s, end: e + delta};
}
