const DAY = 864e5;

export function domainOf(url = ''): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return '';
  }
}

/** "example.com/a" 처럼 프로토콜 없이 적어도 https 주소로 바꾼다. 주소가 아니면 null */
export function normalizeUrl(input: string): string | null {
  const s = input.trim();
  if (!s || /\s/.test(s)) return null;
  const withProto = /^[a-z][a-z0-9+.-]*:\/\//i.test(s) ? s : `https://${s}`;
  try {
    const u = new URL(withProto);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return null;
    if (!u.hostname.includes('.') && u.hostname !== 'localhost') return null;
    return cleanUrl(u.href);
  } catch {
    return null;
  }
}

/** 어디서나 떼어도 되는 추적용 꼬리 (앱과 같은 목록) */
const TRACKING = new Set([
  'fbclid', 'gclid', 'dclid', 'gbraid', 'wbraid', 'msclkid', 'yclid', 'twclid', 'ttclid', 'li_fat_id',
  'mc_cid', 'mc_eid', 'igshid', 'igsh', '_hsenc', '_hsmi', 'mkt_tok', 'vero_id', 'oly_enc_id', 'oly_anon_id',
  'ref_src', 'ref_url', 'spm', 'scm', '__twitter_impression',
]);
/** 그 사이트에서만 추적용인 꼬리 */
const SITE_TRACKING: Record<string, string[]> = {
  'youtube.com': ['si', 'feature', 'pp'],
  'youtu.be': ['si', 'feature'],
  'music.youtube.com': ['si', 'feature'],
  'open.spotify.com': ['si', 'context'],
  'x.com': ['s', 't'],
  'twitter.com': ['s', 't'],
  'instagram.com': ['igsh', 'img_index'],
  'threads.net': ['igshid', 'xmt', 'slof'],
  'threads.com': ['igshid', 'xmt', 'slof'],
  'linkedin.com': ['trk', 'trackingid', 'lipi'],
  'coupang.com': ['src', 'spec', 'addtag', 'ctag', 'lptag', 'itime', 'pageType', 'pageValue', 'wPcid', 'wRef', 'wTime', 'redirect', 'isAddedCart', 'traceid', 'requestid', 'sourceType'],
};

/** 주소에서 utm_ 같은 추적 꼬리와 글자 위치 조각(#:~:text=)을 뗀다 */
export function cleanUrl(url: string): string {
  try {
    const u = new URL(url);
    const host = u.hostname.replace(/^www\./, '');
    const siteKey = Object.keys(SITE_TRACKING).find(k => host === k || host.endsWith(`.${k}`));
    const site = new Set((siteKey ? SITE_TRACKING[siteKey] : []).flatMap(n => [n, n.toLowerCase()]));
    const keys = [...u.searchParams.keys()];
    let changed = false;
    for (const k of keys) {
      const n = k.toLowerCase();
      if (n.startsWith('utm_') || TRACKING.has(n) || site.has(k) || site.has(n)) { u.searchParams.delete(k); changed = true; }
    }
    if (u.hash.startsWith('#:~:')) { u.hash = ''; changed = true; }
    if (!changed) return url;
    return u.href.replace(/\?(?=#|$)/, '');
  } catch {
    return url;
  }
}

/** 글 안의 모든 주소 (같은 건 한 번만) */
export function findUrls(text = ''): string[] {
  const out: string[] = [];
  for (const m of text.matchAll(/https?:\/\/[^\s<>"'）)\]]+/gi)) {
    const u = normalizeUrl(m[0].replace(/[.,!?;:]+$/, ''));
    if (u && !out.includes(u)) out.push(u);
  }
  return out;
}

/** 공유로 받은 글 안에서 첫 주소를 찾는다 */
export function findUrl(text = ''): string | null {
  const m = text.match(/https?:\/\/[^\s<>"']+/i);
  return m ? normalizeUrl(m[0]) : null;
}

/** 주소에서 제목을 짐작한다: 마지막 경로 조각, 없으면 도메인 */
export function guessTitle(url: string): string {
  try {
    const u = new URL(url);
    const seg = u.pathname.split('/').filter(Boolean).pop();
    if (seg) {
      const t = decodeURIComponent(seg).replace(/\.[a-z0-9]{2,5}$/i, '').replace(/[-_+]+/g, ' ').trim();
      if (t && !/^\d+$/.test(t)) return t;
    }
    return domainOf(url);
  } catch {
    return url;
  }
}

/** "참고, #나중에 ,, 참고" → ["참고", "나중에"] */
export function parseTags(input: string): string[] {
  const out: string[] = [];
  for (const raw of input.split(/[,，\n]/)) {
    const t = raw.trim().replace(/^#+/, '').trim();
    if (t && !out.includes(t)) out.push(t);
  }
  return out;
}

function startOfDay(t: number) {
  const d = new Date(t);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}
export function daysAgo(t: number, now = Date.now()) {
  return Math.round((startOfDay(now) - startOfDay(t)) / DAY);
}

const fmtTime = new Intl.DateTimeFormat('ko-KR', {hour: 'numeric', minute: '2-digit'});
const fmtWeekday = new Intl.DateTimeFormat('ko-KR', {weekday: 'long'});
const fmtDate = new Intl.DateTimeFormat('ko-KR', {month: 'long', day: 'numeric'});
const fmtFull = new Intl.DateTimeFormat('ko-KR', {year: 'numeric', month: 'long', day: 'numeric'});

/** 목록 오른쪽 시각: 오늘은 시간, 어제, 이번 주는 요일, 올해는 월일, 그 전은 연월일 */
export function stamp(t: number, now = Date.now()) {
  const d = daysAgo(t, now);
  if (d === 0) return fmtTime.format(t);
  if (d === 1) return '어제';
  if (d < 7) return fmtWeekday.format(t);
  return new Date(t).getFullYear() === new Date(now).getFullYear() ? fmtDate.format(t) : fmtFull.format(t);
}

export const BUCKETS = ['오늘', '어제', '이번 주', '이번 달', '이전'] as const;
export type Bucket = (typeof BUCKETS)[number];
export function bucketOf(t: number, now = Date.now()): Bucket {
  const d = daysAgo(t, now);
  if (d === 0) return '오늘';
  if (d === 1) return '어제';
  if (d < 7) return '이번 주';
  if (d < 31) return '이번 달';
  return '이전';
}

export function fileStamp(t = Date.now()) {
  const d = new Date(t);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}`;
}
