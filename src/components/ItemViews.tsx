import {useEffect, useRef, useState, type CSSProperties} from 'react';
import {BookOpen, CheckCheck, ChevronRight, CircleCheck, Circle, Copy, ExternalLink, EyeOff, Pencil, Star, Trash2, Undo2} from 'lucide-react';
import {List, ListItem} from '@astryxdesign/core/List';
import {ContextMenu} from '@astryxdesign/core/ContextMenu';
import {Spinner} from '@astryxdesign/core/Spinner';
import type {Folder, Item} from '../data/types';
import {BUCKETS, bucketOf, domainOf, stamp} from '../lib/format';
import {supportsReader} from '../lib/reader';
import {Block, Meta} from './bits';
import {logoUrl} from '../lib/pageInfo';
import {isNsfw} from '../data/folders';

export interface ItemActions {
  open: (i: Item) => void;
  openReader: (i: Item) => void;
  openTab: (i: Item) => void;
  edit: (i: Item) => void;
  toggleStar: (i: Item) => void;
  copy: (i: Item) => void;
  remove: (i: Item) => void;
  startSelect: (i: Item) => void;
  /** 확인 완료 ↔ 완료 취소 (완료하면 목록에서 빠지고 완료함으로) */
  toggleDone: (i: Item) => void;
  /** NSFW 태그 달기 ↔ 빼기 */
  toggleNsfw: (i: Item) => void;
  /** 고르는 중이면 고른 id 들 */
  selection: Set<string> | null;
  toggleSelect: (i: Item) => void;
}

/** 항목마다 고유한 전환 이름: 지우거나 넣을 때 다른 줄이 제자리로 미끄러진다 */
const vtName = (i: Item) => ({viewTransitionName: `it-${i.id.replace(/[^a-zA-Z0-9-]/g, '')}`}) as CSSProperties;

const lines = (t: string) => t.split('\n').map(l => l.trim()).filter(Boolean);
/** 제목이 없으면 내용 첫 줄을 제목 자리에 쓴다 (X 게시물처럼 제목이 따로 없는 글) */
export const nameOf = (i: Item) => i.title || lines(i.note)[0] || (i.kind === 'memo' ? '제목 없는 메모' : domainOf(i.url));
/** 제목 아래 줄: 제목이 내용 첫 줄을 빌려 썼으면 그다음 줄부터 */
const subOf = (i: Item) => (i.title ? lines(i.note) : lines(i.note).slice(1)).join(' ');
/** 카드에 크게 보여줄 그림 (프로필 사진 같은 작은 대체 그림은 빼고) */
const coverOf = (i: Item) => (i.kind === 'link' && i.image && !i.image.includes('profile_images') && !i.emoji ? i.image : null);

function menuFor(i: Item, act: ItemActions) {
  return [
    {label: i.starred ? '즐겨찾기 해제' : '즐겨찾기', icon: <Star size={16} />, onClick: () => act.toggleStar(i)},
    {label: '편집', icon: <Pencil size={16} />, onClick: () => act.edit(i)},
    {label: i.doneAt ? '완료 취소' : '확인 완료', icon: i.doneAt ? <Undo2 size={16} /> : <CheckCheck size={16} />, onClick: () => act.toggleDone(i)},
    {label: '여러 개 고르기', icon: <CircleCheck size={16} />, onClick: () => act.startSelect(i)},
    ...(i.kind === 'link' ? [
      ...(supportsReader(i.url) ? [{label: '리더로 보기', icon: <BookOpen size={16} />, onClick: () => act.openReader(i)}] : []),
      {label: '새 탭으로 열기', icon: <ExternalLink size={16} />, onClick: () => act.openTab(i)},
      {label: '주소 복사', icon: <Copy size={16} />, onClick: () => act.copy(i)},
    ] : []),
    {label: isNsfw(i) ? 'NSFW 표시 빼기' : 'NSFW 로 표시', icon: <EyeOff size={16} />, onClick: () => act.toggleNsfw(i)},
    {type: 'divider' as const},
    {label: '삭제', icon: <Trash2 size={16} />, variant: 'destructive' as const, onClick: () => act.remove(i)},
  ];
}

function SelectMark({on}: {on: boolean}) {
  return on
    ? <CircleCheck className="select-mark on" size={22} aria-label="선택됨" />
    : <Circle className="select-mark" size={22} aria-label="선택 안 됨" />;
}

function Row({item, folder, showFolder, act, loading}: {item: Item; folder?: Folder; showFolder: boolean; act: ItemActions; loading?: boolean}) {
  // 링크의 사이트는 출처 칩에 나오므로 여기엔 내용만
  const sub = subOf(item);
  const sel = act.selection;
  const selected = !!sel?.has(item.id);
  const listItem = (
    <ListItem
      label={<span className="row-title">{nameOf(item)}</span>}
      description={<span className="row-text">{sub && <span className="row-sub">{sub}</span>}<Meta item={item} folder={folder} showFolder={showFolder} /></span>}
      startContent={<span className="row-start">{sel && <SelectMark on={selected} />}<Block item={item} folder={folder} /></span>}
      endContent={
        <span className="row-end">
          {loading && <Spinner size="sm" aria-label="링크 정보를 가져오는 중" />}
          {item.starred && <Star className="star" size={15} fill="currentColor" aria-label="즐겨찾기" />}
          <span className="num">{stamp(item.createdAt)}</span>
          {item.kind === 'memo' && !sel && <ChevronRight className="chev" size={18} aria-hidden="true" />}
        </span>
      }
      onClick={() => (sel ? act.toggleSelect(item) : act.open(item))}
      {...(sel ? {} : {
        swipeActions: {
          leading: [{id: 'star', label: item.starred ? '해제' : '즐겨찾기', icon: <Star size={18} />, variant: 'accent' as const, onActivate: () => act.toggleStar(item)}],
          trailing: [
            {id: 'edit', label: '편집', icon: <Pencil size={18} />, variant: 'neutral' as const, onActivate: () => act.edit(item)},
            {id: 'del', label: '삭제', icon: <Trash2 size={18} />, variant: 'destructive' as const, onActivate: () => act.remove(item)},
          ],
        },
      })}
    />
  );
  return (
    <div className="vt-row" style={vtName(item)} data-selected={selected || undefined}>
      {sel ? listItem : <ContextMenu items={menuFor(item, act)} presentation="adaptive" label={nameOf(item)} menuWidth={200}>{listItem}</ContextMenu>}
    </div>
  );
}

/** 타임라인 보기의 동그란 사진: 고른 이모지 → SNS 프로필 → 사이트 파비콘 → 메모 아이콘 */
function Avatar({item: i, folder}: {item: Item; folder?: Folder}) {
  const [step, setStep] = useState(0);
  if (i.emoji || i.kind === 'memo') return <span className="tl-avatar"><Block item={i} folder={folder} /></span>;
  // 예전에 저장한 X 게시물은 프로필 사진이 image 자리에 들어 있기도 하다
  const sources = [i.avatar, i.image?.includes('profile_images') ? i.image : undefined, logoUrl(i.url, 128)].filter(Boolean) as string[];
  const src = sources[step];
  if (!src) return <span className="tl-avatar"><Block item={i} folder={folder} /></span>;
  const isLogo = src === logoUrl(i.url, 128);
  return (
    <span className="tl-avatar" data-logo={isLogo || undefined}>
      <img src={src} alt="" loading="lazy" decoding="async" referrerPolicy="no-referrer" onError={() => setStep(s => s + 1)} />
    </span>
  );
}

/** X 처럼: 사진 여러 장은 격자로, 영상은 2초 반복, 아니면 대표 그림 한 장 */
function Media({item: i}: {item: Item}) {
  const photos = i.kind === 'link' && !i.emoji ? (i.images?.length ? i.images : []) : [];
  const cover = coverOf(i);
  if (i.kind === 'link' && !i.emoji && i.video) return <span className="tl-media" data-n="video"><LoopClip src={i.video} poster={cover ?? ''} /></span>;
  if (photos.length > 1) {
    return (
      <span className="tl-media" data-n={photos.length}>
        {photos.slice(0, 4).map((u, n) => <img key={u + n} src={u} alt="" loading="lazy" decoding="async" referrerPolicy="no-referrer" />)}
      </span>
    );
  }
  if (cover) return <span className="tl-media" data-n="1"><img src={cover} alt="" loading="lazy" decoding="async" referrerPolicy="no-referrer" /></span>;
  return null;
}

/** 이름 자리: 제목 (X 게시물처럼 제목이 없으면 @아이디) */
const tlName = (i: Item) => i.title || (i.siteName?.startsWith('X · ') ? i.siteName.slice(4) : '') || nameOf(i);
/** 이름 옆 작은 글씨: 사이트 */
const tlHandle = (i: Item) => (i.kind === 'memo' ? '메모' : i.siteName?.startsWith('X · ') ? 'X' : i.siteName || domainOf(i.url));
/** 본문: 내용 그대로 (제목이 첫 줄을 빌려 썼으면 그 줄은 빼고) */
const tlText = (i: Item) => (i.title || (i.siteName?.startsWith('X · ') && !i.title) ? i.note : lines(i.note).slice(1).join('\n')).trim();

function TimelineRow({item: i, folder, showFolder, act, loading}: {item: Item; folder?: Folder; showFolder: boolean; act: ItemActions; loading?: boolean}) {
  const sel = act.selection;
  const selected = !!sel?.has(i.id);
  const text = tlText(i);
  const row = (
    <button type="button" className="tl-row" data-selected={selected || undefined} aria-pressed={sel ? selected : undefined}
      onClick={() => (sel ? act.toggleSelect(i) : act.open(i))}>
      <span className="tl-left">{sel ? <SelectMark on={selected} /> : <Avatar item={i} folder={folder} />}</span>
      <span className="tl-main">
        <span className="tl-head">
          <span className="tl-name">{tlName(i)}</span>
          <span className="tl-handle">{tlHandle(i)}</span>
          <span className="tl-dot" aria-hidden="true">·</span>
          <span className="tl-time num">{stamp(i.createdAt)}</span>
          {loading && <Spinner size="sm" aria-label="링크 정보를 가져오는 중" />}
          {i.starred && <Star className="star" size={14} fill="currentColor" aria-label="즐겨찾기" />}
        </span>
        {text && <span className="tl-text">{text}</span>}
        <Media item={i} />
        <Meta item={i} folder={folder} showFolder={showFolder} />
      </span>
    </button>
  );
  return (
    <div className="vt-row" style={vtName(i)}>
      {sel ? row : <ContextMenu items={menuFor(i, act)} presentation="adaptive" label={nameOf(i)} menuWidth={200}>{row}</ContextMenu>}
    </div>
  );
}

/** 타임라인 보기 (목록): X 처럼 프로필 사진 · 이름 · 내용 · 사진. 날짜별이나 사이트별로 묶는다 */
export function TimelineList({items, folderMap, showFolder, act, loadingIds, groupBy}: {items: Item[]; folderMap: Map<string, Folder>; showFolder: boolean; act: ItemActions; loadingIds?: Set<string>; groupBy: 'day' | 'site' | 'none'}) {
  let groups: {key: string; title: string; list: Item[]}[];
  if (groupBy === 'site') {
    const m = new Map<string, Item[]>();
    for (const i of items) { const k = i.kind === 'memo' ? '' : siteKey(i); m.set(k, [...(m.get(k) ?? []), i]); }
    groups = [...m.entries()].sort((a, b) => (a[0] === '' ? 1 : b[0] === '' ? -1 : b[1].length - a[1].length || a[0].localeCompare(b[0], 'ko')))
      .map(([k, list]) => ({key: k || 'memo', title: k || '메모', list}));
  } else if (groupBy === 'day') {
    groups = BUCKETS.map(b => ({key: b, title: b, list: items.filter(i => bucketOf(i.createdAt) === b)})).filter(g => g.list.length);
  } else {
    groups = [{key: 'all', title: '', list: items}];
  }
  return (
    <>
      {groups.map((g, n) => (
        <section className="tl" key={g.key} aria-labelledby={g.title ? `tl-${n}` : undefined}>
          {g.title && <div className="day-head"><h2 id={`tl-${n}`}>{g.title}</h2><span className="num">{g.list.length}개</span></div>}
          {g.list.map(i => <TimelineRow key={i.id} item={i} folder={i.folderId ? folderMap.get(i.folderId) : undefined} showFolder={showFolder} act={act} loading={loadingIds?.has(i.id)} />)}
        </section>
      ))}
    </>
  );
}

/** 목록을 사이트별로 묶는다 (많은 사이트부터, 메모는 맨 뒤) */
export function SiteList({items, folderMap, showFolder, act, loadingIds}: {items: Item[]; folderMap: Map<string, Folder>; showFolder: boolean; act: ItemActions; loadingIds?: Set<string>}) {
  const groups = new Map<string, Item[]>();
  for (const i of items) {
    const key = i.kind === 'memo' ? '' : siteKey(i);
    groups.set(key, [...(groups.get(key) ?? []), i]);
  }
  const sorted = [...groups.entries()].sort((a, b) => (a[0] === '' ? 1 : b[0] === '' ? -1 : b[1].length - a[1].length || a[0].localeCompare(b[0], 'ko')));
  return (
    <>
      {sorted.map(([site, list], n) => (
        <section className="day" key={site || 'memo'} aria-labelledby={`site-${n}`}>
          <div className="day-head"><h2 id={`site-${n}`}>{site || '메모'}</h2><span className="num">{list.length}개</span></div>
          <List hasDividers density="spacious" edge="flush">
            {list.map(i => <Row key={i.id} item={i} folder={i.folderId ? folderMap.get(i.folderId) : undefined} showFolder={showFolder} act={act} loading={loadingIds?.has(i.id)} />)}
          </List>
        </section>
      ))}
    </>
  );
}
/** 사이트 이름: 출처 칩과 같게 (X 는 계정과 상관없이 X 하나로) */
const siteKey = (i: Item) => (i.siteName?.startsWith('X · ') ? 'X' : i.siteName) || domainOf(i.url) || '알 수 없음';

export function DayList({items, folderMap, showFolder, act, loadingIds}: {items: Item[]; folderMap: Map<string, Folder>; showFolder: boolean; act: ItemActions; loadingIds?: Set<string>}) {
  const groups = BUCKETS.map(b => ({b, list: items.filter(i => bucketOf(i.createdAt) === b)})).filter(g => g.list.length);
  return (
    <>
      {groups.map(g => (
        <section className="day" key={g.b} aria-labelledby={`day-${g.b}`}>
          <div className="day-head"><h2 id={`day-${g.b}`}>{g.b}</h2><span className="num">{g.list.length}개</span></div>
          <List hasDividers density="spacious" edge="flush">
            {g.list.map(i => <Row key={i.id} item={i} folder={i.folderId ? folderMap.get(i.folderId) : undefined} showFolder={showFolder} act={act} loading={loadingIds?.has(i.id)} />)}
          </List>
        </section>
      ))}
    </>
  );
}

/**
 * 영상은 2초만 소리 없이 반복한다. 화면에 보일 때만 받아서 틀고, 움직임 줄이기·데이터 절약이면 첫 장면만.
 * 긴 영상은 앞부분(제목·검은 화면)을 건너뛰고 20% 지점(최대 10초)부터.
 */
const CLIP_SECONDS = 2;
function LoopClip({src, poster}: {src: string; poster: string}) {
  const ref = useRef<HTMLVideoElement>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    const v = ref.current;
    if (!v || failed) return;
    const still = matchMedia('(prefers-reduced-motion: reduce)').matches
      || !!(navigator as Navigator & {connection?: {saveData?: boolean}}).connection?.saveData;
    let start = 0;
    let frame = 0;
    const onMeta = () => {
      const d = v.duration;
      start = Number.isFinite(d) && d > CLIP_SECONDS * 3 ? Math.min(d * 0.2, 10) : 0;
      v.currentTime = start;
    };
    // timeupdate 는 띄엄띄엄 와서, 재생 중엔 매 프레임 확인해 2초에서 바로 되감는다
    const tick = () => {
      if (v.currentTime >= start + CLIP_SECONDS || v.currentTime < start - 0.1) v.currentTime = start;
      frame = requestAnimationFrame(tick);
    };
    const onPlay = () => { cancelAnimationFrame(frame); frame = requestAnimationFrame(tick); };
    const onPause = () => cancelAnimationFrame(frame);
    v.addEventListener('loadedmetadata', onMeta);
    v.addEventListener('playing', onPlay);
    v.addEventListener('pause', onPause);
    const io = new IntersectionObserver(([e]) => {
      if (e.isIntersecting && !still) {
        if (v.preload === 'none') { v.preload = 'auto'; v.load(); }
        void v.play().catch(() => {});
      } else {
        v.pause();
      }
    }, {threshold: 0.4});
    io.observe(v);
    return () => {
      io.disconnect();
      cancelAnimationFrame(frame);
      v.removeEventListener('loadedmetadata', onMeta);
      v.removeEventListener('playing', onPlay);
      v.removeEventListener('pause', onPause);
    };
  }, [src, failed]);
  if (failed) return poster ? <img src={poster} alt="" loading="lazy" decoding="async" referrerPolicy="no-referrer" /> : null;
  return (
    <video ref={ref} src={src} poster={poster || undefined} muted playsInline loop preload="none" disablePictureInPicture
      aria-hidden="true" tabIndex={-1} onError={() => setFailed(true)} />
  );
}

function Card({item: i, folder, showFolder, act}: {item: Item; folder?: Folder; showFolder: boolean; act: ItemActions}) {
  const [coverBroken, setCoverBroken] = useState(false);
  const clip = i.kind === 'link' && !i.emoji ? i.video : undefined;
  const image = coverBroken ? null : coverOf(i);
  // 영상만 있고 그림이 없어도(영상 파일 링크) 카드 위에 크게 보인다
  const cover = clip ? image ?? '' : image;
  const hasCover = cover !== null;
  const sel = act.selection;
  const selected = !!sel?.has(i.id);
  const sub = subOf(i);
  const card = (
    <button type="button" className="card" data-selected={selected || undefined} aria-pressed={sel ? selected : undefined}
      onClick={() => (sel ? act.toggleSelect(i) : act.open(i))}>
      {hasCover && (
        <span className="card-cover">
          {clip
            ? <LoopClip src={clip} poster={cover} />
            : <img src={cover} alt="" loading="lazy" decoding="async" referrerPolicy="no-referrer" onError={() => setCoverBroken(true)} />}
          {i.starred && <span className="cover-star"><Star size={14} fill="currentColor" aria-label="즐겨찾기" /></span>}
        </span>
      )}
      <span className="card-body">
        {!hasCover && (
          <span className="card-head">
            <Block item={i} folder={folder} />
            {i.starred && <Star size={15} fill="currentColor" style={{color: 'var(--star)'}} aria-label="즐겨찾기" />}
          </span>
        )}
        <span className="card-title" data-long={!hasCover || undefined}>{nameOf(i)}</span>
        {sub && <span className="card-desc" data-long={!hasCover || undefined}>{sub}</span>}
        <Meta item={i} folder={folder} showFolder={showFolder} />
        <span className="card-src num">{i.kind === 'memo' ? `메모 · ${stamp(i.createdAt)}` : stamp(i.createdAt)}</span>
      </span>
      {sel && <span className="card-select"><SelectMark on={selected} /></span>}
    </button>
  );
  return (
    <div className="vt-row card-wrap" style={vtName(i)}>
      {sel ? card : <ContextMenu items={menuFor(i, act)} presentation="adaptive" label={nameOf(i)} menuWidth={200}>{card}</ContextMenu>}
    </div>
  );
}

/** 카드 보기: 두 줄 벽돌 쌓기. 그림이 있으면 그림 비율대로 크게 */
export function CardGrid({items, folderMap, showFolder, act}: {items: Item[]; folderMap: Map<string, Folder>; showFolder: boolean; act: ItemActions}) {
  return (
    <div className="cards">
      {items.map(i => <Card key={i.id} item={i} folder={i.folderId ? folderMap.get(i.folderId) : undefined} showFolder={showFolder} act={act} />)}
    </div>
  );
}

/** 하이라이트 모아 보기: 항목별로 칠한 문단 */
export function HighlightList({items, folderMap, onOpen, onRemove}: {items: Item[]; folderMap: Map<string, Folder>; onOpen: (i: Item) => void; onRemove: (i: Item, text: string) => void}) {
  return (
    <div className="hl-list">
      {[...items].sort((a, b) => b.updatedAt - a.updatedAt).map(i => (
        <section key={i.id} className="hl-group">
          <button type="button" className="hl-head" onClick={() => onOpen(i)}>
            <Block item={i} folder={i.folderId ? folderMap.get(i.folderId) : undefined} />
            <span className="hl-title">{nameOf(i)}</span>
            <ChevronRight className="chev" size={18} aria-hidden="true" />
          </button>
          {(i.highlights ?? []).map(h => (
            <div key={h} className="hl-quote">
              <p>{h}</p>
              <button type="button" className="hl-remove" aria-label="형광펜 지우기" onClick={() => onRemove(i, h)}><Trash2 size={15} /></button>
            </div>
          ))}
        </section>
      ))}
    </div>
  );
}
