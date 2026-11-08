import {tidyTitle, xStatusId, youtubeId} from './pageInfo';

/** 리더 모드 한 덩어리 (앱과 같은 종류) */
export type ReaderBlock =
  | {t: 'h'; text: string; level: number}
  | {t: 'p'; text: string}
  | {t: 'q'; text: string}
  | {t: 'li'; text: string}
  | {t: 'code'; text: string}
  | {t: 'img'; src: string};

export interface Article {
  title?: string;
  siteName?: string;
  image?: string;
  blocks: ReaderBlock[];
  /** 받아 둔 때 */
  savedAt?: number;
}

export const textOf = (b: ReaderBlock): string | null => (b.t === 'img' ? null : b.text);

export const textLength = (a: Article) => a.blocks.reduce((n, b) => n + (b.t === 'p' || b.t === 'q' || b.t === 'li' || b.t === 'code' ? b.text.length : 0), 0);

/** 읽는 데 걸리는 시간(분). 한국어는 분당 약 500자 */
export const minutes = (a: Article) => Math.max(1, Math.round(textLength(a) / 500));

/** 리더로 열 만한 링크인지 (X, 유튜브는 원래 화면이 낫다) */
export const supportsReader = (url?: string) => !!url && /^https?:/i.test(url) && !xStatusId(url) && !youtubeId(url);

/** 마크다운 한 줄을 글자만 남기고, 줄 안의 그림 주소는 따로 모은다 */
function inline(s: string, images: string[]): string {
  return s
    .replace(/!\[[^\]]*]\(([^)\s]+)[^)]*\)/g, (_, src: string) => { images.push(src); return ''; })
    .replace(/\[([^\]]*)]\([^)]*\)/g, '$1')
    .replace(/<[^>]+>/g, '')
    .replace(/(\*\*|__)(.+?)\1/g, '$2')
    .replace(/(^|[^\w*])[*_](\S.*?\S|\S)[*_](?!\w)/g, '$1$2')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\\([\\`*_{}[\]()#+\-.!])/g, '$1')
    .replace(/\s+/g, ' ')
    .trim();
}

/** 링크 글자가 대부분인 줄(메뉴, 관련 글 목록) */
function linkHeavy(raw: string, text: string): boolean {
  const linked = [...raw.matchAll(/\[([^\]]*)]\([^)]*\)/g)].reduce((n, m) => n + m[1].length, 0);
  return text.length > 0 && linked / text.length > 0.6;
}

const isContentImage = (src: string) =>
  /^https?:/i.test(src) && !/\.(svg|ico|gif)(\?|$)/i.test(src) && !/(favicon|logo|icon|avatar|emoji|sprite|badge|pixel|spacer|tracking)/i.test(src);

/** Jina Reader 가 준 마크다운을 리더 덩어리로 */
export function parseMarkdown(md: string, title?: string): ReaderBlock[] {
  const lines = md.replace(/\r/g, '').split('\n');
  const out: ReaderBlock[] = [];
  const seenImg = new Set<string>();
  const seenText = new Set<string>();
  let para: string[] = [];

  const push = (b: ReaderBlock) => {
    if (b.t === 'img') {
      if (!isContentImage(b.src) || seenImg.has(b.src)) return;
      seenImg.add(b.src);
    } else {
      if (!b.text || seenText.has(b.text)) return;
      seenText.add(b.text);
    }
    out.push(b);
  };
  const flush = () => {
    if (!para.length) return;
    const raw = para.join(' ');
    para = [];
    const imgs: string[] = [];
    const text = inline(raw, imgs);
    if (text && !linkHeavy(raw, text)) push({t: 'p', text});
    imgs.forEach(src => push({t: 'img', src}));
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();
    if (/^```/.test(trimmed)) {
      flush();
      const code: string[] = [];
      for (i++; i < lines.length && !/^```/.test(lines[i].trim()); i++) code.push(lines[i]);
      const text = code.join('\n').replace(/\s+$/, '');
      if (text) push({t: 'code', text});
      continue;
    }
    if (!trimmed) { flush(); continue; }
    // 밑줄 제목 (제목\n=== 또는 ---)
    const next = lines[i + 1]?.trim() ?? '';
    if (para.length === 0 && /^(=+|-+)$/.test(next) && next.length >= 3 && !/^[-*+] /.test(trimmed)) {
      const imgs: string[] = [];
      push({t: 'h', text: inline(trimmed, imgs), level: next.startsWith('=') ? 1 : 2});
      i++;
      continue;
    }
    if (/^(-{3,}|\*{3,}|_{3,})$/.test(trimmed) || /^\|?\s*:?-{3,}/.test(trimmed)) { flush(); continue; }
    let m: RegExpMatchArray | null;
    const imgs: string[] = [];
    if ((m = trimmed.match(/^(#{1,6})\s+(.*)$/))) {
      flush();
      push({t: 'h', text: inline(m[2].replace(/\s+#+$/, ''), imgs), level: m[1].length});
    } else if ((m = trimmed.match(/^>\s?(.*)$/))) {
      flush();
      const text = inline(m[1], imgs);
      const last = out[out.length - 1];
      if (last?.t === 'q' && /^>/.test(lines[i - 1]?.trim() ?? '')) last.text = `${last.text}\n${text}`.trim(); else if (text) push({t: 'q', text});
    } else if ((m = trimmed.match(/^(?:[-*+]|\d+[.)])\s+(.*)$/))) {
      flush();
      const text = inline(m[1], imgs);
      if (text && !linkHeavy(m[1], text) && text.length < 600) push({t: 'li', text});
    } else if (/^!\[[^\]]*]\([^)]+\)\s*$/.test(trimmed)) {
      flush();
      inline(trimmed, imgs);
    } else {
      para.push(trimmed);
      continue;
    }
    imgs.forEach(src => push({t: 'img', src}));
  }
  flush();

  // 앞쪽 제목(h1)은 위에 따로 보여주니 빼고, 그 앞 안내 문구도 덜어낸다
  const h1 = out.slice(0, 6).findIndex(b => b.t === 'h' && b.level === 1);
  if (h1 >= 0) out.splice(0, h1 + 1);
  else if (out[0]?.t === 'h' && title && out[0].text === title) out.shift();
  while (out.length) {
    const last = out[out.length - 1];
    if (last.t === 'h' || (last.t === 'p' && last.text.length < 20)) out.pop(); else break;
  }
  return out.slice(0, 600);
}

const READER = 'https://r.jina.ai/';

/** 네이버 블로그는 본문이 프레임 안에 있어 모바일 주소로 읽는다 */
export function readerUrl(url: string): string {
  try {
    const u = new URL(url);
    if (u.hostname === 'blog.naver.com') return `https://m.blog.naver.com${u.pathname}${u.search}`;
  } catch { /* 그대로 */ }
  return url;
}

const REMOVE = 'nav, header, footer, aside, form, script, style, noscript, [role=navigation], [role=banner], [role=contentinfo], .sidebar, .comments';

async function read(url: string, target: boolean) {
  const headers: Record<string, string> = {Accept: 'application/json', 'X-Timeout': '15', 'X-Remove-Selector': REMOVE};
  // 본문 영역만 (없으면 422 → 영역 없이 다시)
  if (target) headers['X-Target-Selector'] = 'article, main, [role=main]';
  const res = await fetch(READER + url, {headers, signal: typeof AbortSignal.timeout === 'function' ? AbortSignal.timeout(25000) : undefined});
  if (!res.ok) return null;
  const body = (await res.json()) as {data?: {title?: string; content?: string; metadata?: Record<string, string>}};
  return body.data?.content ? body.data : null;
}

/** 본문 받기 (Jina Reader). 읽을 글이 너무 짧으면 null */
export async function fetchArticle(url: string): Promise<Article | null> {
  try {
    const target = readerUrl(url);
    const d = (await read(target, true)) ?? (await read(target, false));
    if (!d?.content) return null;
    const meta = d.metadata ?? {};
    const siteName = meta['og:site_name'] || undefined;
    let host = '';
    try { host = new URL(url).hostname.replace(/^www\./, ''); } catch { /* 없음 */ }
    const a: Article = {
      title: d.title ? tidyTitle(d.title, siteName, host) : undefined,
      siteName,
      image: meta['og:image'] && /^https?:/i.test(meta['og:image']) ? meta['og:image'] : undefined,
      blocks: parseMarkdown(d.content, d.title),
      savedAt: Date.now(),
    };
    return textLength(a) >= 200 ? a : null;
  } catch {
    return null;
  }
}
