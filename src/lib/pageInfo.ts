import {domainOf} from './format';

/** 링크에서 가져온 정보. 없는 값은 비워 둔다 */
export interface PageInfo {
  title?: string;
  description?: string;
  /** 글을 대표하는 이미지 */
  image?: string;
  siteName?: string;
}

/**
 * 폰 브라우저는 다른 사이트 글을 직접 읽을 수 없어서(CORS) Jina Reader 를 거친다.
 * 키 없이 쓰는 무료 서비스라 요청 수 제한이 있다. 실패하면 null.
 */
const READER = 'https://r.jina.ai/';

/** 사이트 로고 (Google 파비콘 서비스). 이미지 태그로만 쓰므로 CORS 와 무관하다 */
export function logoUrl(url?: string, size = 64): string | null {
  const host = domainOf(url);
  return host ? `https://www.google.com/s2/favicons?domain=${encodeURIComponent(host)}&sz=${size}` : null;
}

export function youtubeId(url: string): string | null {
  try {
    const u = new URL(url);
    const h = u.hostname.replace(/^(www|m)\./, '');
    if (h === 'youtu.be') return u.pathname.slice(1).split('/')[0] || null;
    if (h === 'youtube.com' || h === 'music.youtube.com') {
      if (u.pathname === '/watch') return u.searchParams.get('v');
      const m = u.pathname.match(/^\/(shorts|embed|live)\/([\w-]{6,})/);
      if (m) return m[2];
    }
  } catch { /* 주소가 아니면 없음 */ }
  return null;
}

const clean = (s?: string | null) => (s ?? '').replace(/\s+/g, ' ').trim();

/** 160자 안쪽으로, 가능하면 단어 경계에서 자른다 */
export function clip(s: string, max = 160): string {
  if (s.length <= max) return s;
  const cut = s.slice(0, max);
  const at = cut.lastIndexOf(' ');
  return `${(at > max * 0.6 ? cut.slice(0, at) : cut).replace(/[\s,.·|:;-]+$/, '')}…`;
}

/** "글 제목 - 사이트" 처럼 붙은 사이트 이름을 뗀다 */
export function tidyTitle(title: string, siteName?: string, host?: string): string {
  let t = clean(title);
  // "글 제목 | 사이트" 는 대부분 | 뒤가 사이트 이름이다
  const bar = t.split(/\s+\|\s+/);
  if (bar.length > 1 && bar[0].length >= 4) t = bar[0];
  const tails = [siteName, siteName?.split(' ')[0], host, host?.split('.')[0], 'YouTube'].filter(Boolean) as string[];
  for (const tail of tails) {
    const re = new RegExp(`\\s*[-|–—:·]\\s*${tail.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`, 'i');
    if (re.test(t) && t.replace(re, '').length >= 2) t = t.replace(re, '');
  }
  return t;
}

/** 아이콘·로고·광고처럼 글 내용이 아닌 이미지를 거른다 */
function isContentImage(src: string, pageUrl: string): boolean {
  if (!/^https?:\/\//i.test(src) || src === pageUrl) return false;
  if (/\.(svg|ico|gif)(\?|$)/i.test(src)) return false;
  if (/(favicon|logo|icon|avatar|emoji|sprite|badge|profile|pixel|spacer|tracking|ads?[/_.-])/i.test(src)) return false;
  if (/[=_-]s(16|24|32|48|64|88)\b|[?&](w|width|size)=(16|24|32|48|64)\b/i.test(src)) return false;
  return true;
}

/** 본문 마크다운에서 첫 번째 쓸 만한 문단을 뽑는다 */
function firstParagraph(md: string): string {
  for (const block of md.split(/\n\s*\n/)) {
    const text = clean(
      block
        .replace(/!\[[^\]]*]\([^)]*\)/g, '')
        .replace(/\[([^\]]*)]\([^)]*\)/g, '$1')
        .replace(/^[#>*\-\s]+/gm, '')
        .replace(/[`*_]/g, ''),
    );
    if (text.length >= 30 && !/^(skip|back|menu|search|로그인|메뉴)/i.test(text)) return text;
  }
  return '';
}

interface ReaderData {
  title?: string;
  description?: string;
  url?: string;
  content?: string;
  images?: Record<string, string>;
  metadata?: Record<string, string>;
}

/** Jina Reader JSON 응답을 PageInfo 로 바꾼다 */
export function parseReader(data: ReaderData, url: string): PageInfo {
  const meta = data.metadata ?? {};
  const host = domainOf(url);
  const siteName = clean(meta['og:site_name']) || undefined;
  const yt = youtubeId(url);

  const ogImage = meta['og:image'] || meta['twitter:image'] || meta['twitter:image:src'];
  const contentImage = Object.values(data.images ?? {}).find(src => isContentImage(src, url));
  const image = yt ? `https://i.ytimg.com/vi/${yt}/hqdefault.jpg` : (ogImage && /^https?:/i.test(ogImage) ? ogImage : contentImage);

  const desc = clean(meta['og:description'] || data.description || meta.description);
  const generic = /^(enjoy the videos and music you love|글이 작품이 되는 공간)/i.test(desc);
  // 유튜브 본문은 조회수·메뉴 같은 화면 글자뿐이라 쓰지 않는다
  const fallback = !desc || generic ? (yt ? '' : firstParagraph(data.content ?? '')) : '';
  const description = clip(fallback || (generic ? '' : desc));

  const rawTitle = clean(meta['og:title'] || data.title);
  return {
    title: rawTitle ? tidyTitle(rawTitle, siteName, host) : undefined,
    description: description || undefined,
    image: image || undefined,
    siteName,
  };
}

/** X(트위터) 게시물 주소면 게시물 id */
export function xStatusId(url: string): string | null {
  try {
    const u = new URL(url);
    const h = u.hostname.replace(/^(www|mobile|m)\./, '');
    if (!['x.com', 'twitter.com', 'fxtwitter.com', 'vxtwitter.com', 'fixupx.com', 'fixvx.com'].includes(h)) return null;
    const m = u.pathname.match(/\/status(?:es)?\/(\d{5,25})/);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

interface FxTweet {
  text?: string;
  author?: {name?: string; screen_name?: string; avatar_url?: string};
  media?: {photos?: {url?: string}[]; videos?: {thumbnail_url?: string}[]; all?: {type?: string; url?: string; thumbnail_url?: string}[]};
}

/** FxTwitter 응답을 PageInfo 로 바꾼다 */
export function parseFxTweet(t: FxTweet): PageInfo {
  const text = (t.text ?? '').replace(/\s*https:\/\/t\.co\/\w+\s*$/g, '').trim();
  const name = clean(t.author?.name);
  const handle = t.author?.screen_name;
  const media = t.media ?? {};
  const image = media.photos?.[0]?.url
    || media.videos?.[0]?.thumbnail_url
    || media.all?.find(m => m.thumbnail_url || m.type === 'photo')?.thumbnail_url
    || media.all?.find(m => m.type === 'photo')?.url
    || t.author?.avatar_url?.replace(/_normal\./, '_200x200.');
  // 게시물은 제목이 따로 없으니 제목은 비우고 글 전체를 내용으로 쓴다
  const body = text ? clip(text.replace(/\n{3,}/g, '\n\n'), 400) : '';
  return {
    title: body ? undefined : name ? `${name}의 게시물` : undefined,
    description: body || undefined,
    image: image || undefined,
    siteName: handle ? `X · @${handle}` : 'X',
  };
}

/** X 는 로그인 없이 글을 읽을 수 없어서 FxTwitter 공개 API 로 가져온다 */
async function fetchX(id: string, signal?: AbortSignal): Promise<PageInfo | null> {
  try {
    const res = await fetch(`https://api.fxtwitter.com/status/${id}`, {signal});
    if (!res.ok) return null;
    const body = (await res.json()) as {tweet?: FxTweet | null};
    return body.tweet ? parseFxTweet(body.tweet) : null;
  } catch {
    return null;
  }
}

export async function fetchPageInfo(url: string, signal?: AbortSignal): Promise<PageInfo | null> {
  const xid = xStatusId(url);
  if (xid) {
    const info = await fetchX(xid, signal);
    if (info || signal?.aborted) return info;
  }
  return fetchReader(url, signal);
}

async function fetchReader(url: string, signal?: AbortSignal): Promise<PageInfo | null> {
  // 오래된 브라우저에는 AbortSignal.any/timeout 이 없을 수 있다
  const timeout = typeof AbortSignal.timeout === 'function' ? AbortSignal.timeout(15000) : undefined;
  const any = signal && timeout && typeof AbortSignal.any === 'function' ? AbortSignal.any([signal, timeout]) : signal ?? timeout;
  try {
    const res = await fetch(READER + url, {
      headers: {Accept: 'application/json', 'X-With-Images-Summary': 'true', 'X-Timeout': '10'},
      signal: any,
    });
    if (!res.ok) return null;
    const body = (await res.json()) as {data?: ReaderData};
    return body.data ? parseReader(body.data, url) : null;
  } catch {
    return null;
  }
}
