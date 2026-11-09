import {db} from '../data/db';
import type {Item} from '../data/types';
import {fetchArticle, supportsReader, type Article} from './reader';

/**
 * 오프라인 저장: 항목을 받아 둔 그때 모습 그대로, 본문과 사진·영상까지 기기에 넣어 둔다.
 * 원본 글이 지워져도, 인터넷이 없어도 "오프라인" 에서 볼 수 있다. 동기화하지 않는다 (기기마다).
 */
export interface OfflinePack {
  id: string;
  savedAt: number;
  /** 받은 때의 항목 (나중에 고쳐도 받은 모습은 그대로) */
  item: Item;
  article?: Article | null;
  /** 원래 주소 → 받은 파일 */
  media: Record<string, Blob>;
  /** 받지 못한 그림·영상 수 (브라우저가 막은 경우) */
  failed: number;
}

/** 영상 하나는 이만큼까지만 받는다 (기기 저장 공간 보호) */
const MAX_VIDEO = 300 * 1024 * 1024;

/** 이 항목에서 받아 둘 그림·영상 주소 */
export function mediaUrls(item: Item, article?: Article | null): string[] {
  const list = [
    item.video, item.image, ...(item.images ?? []), item.avatar,
    article?.image, ...(article?.blocks ?? []).flatMap(b => (b.t === 'img' ? [b.src] : [])),
  ].filter((u): u is string => !!u && /^https?:/i.test(u));
  return [...new Set(list)].slice(0, 40);
}

async function grab(url: string, signal?: AbortSignal): Promise<Blob | null> {
  try {
    const res = await fetch(url, {mode: 'cors', referrerPolicy: 'no-referrer', signal});
    if (!res.ok) return null;
    const len = Number(res.headers.get('content-length') ?? 0);
    if (len > MAX_VIDEO) return null;
    const b = await res.blob();
    return b.size > MAX_VIDEO ? null : b;
  } catch {
    return null;
  }
}

/** 받아서 기기에 넣는다. 본문을 못 받아도 항목 모습과 받은 그림·영상은 남긴다 */
export async function downloadOffline(item: Item, existing?: Article | null, signal?: AbortSignal): Promise<OfflinePack> {
  const article = existing ?? (item.kind === 'link' && supportsReader(item.url) ? await fetchArticle(item.url!).catch(() => null) : null);
  const urls = mediaUrls(item, article);
  const media: Record<string, Blob> = {};
  let failed = 0;
  // 서너 개씩 나눠 받는다
  for (let n = 0; n < urls.length; n += 4) {
    const got = await Promise.all(urls.slice(n, n + 4).map(u => grab(u, signal)));
    got.forEach((b, k) => { if (b) media[urls[n + k]] = b; else failed++; });
  }
  const pack: OfflinePack = {id: item.id, savedAt: Date.now(), item: {...item}, article, media, failed};
  await (await db()).put('offline', pack);
  return pack;
}

export async function getOffline(id: string): Promise<OfflinePack | undefined> {
  return (await db()).get('offline', id);
}

export async function offlineIds(): Promise<Set<string>> {
  return new Set((await (await db()).getAllKeys('offline')).map(String));
}

export async function removeOffline(id: string) {
  await (await db()).delete('offline', id);
}
