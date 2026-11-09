import {useEffect, useRef, useState, type CSSProperties} from 'react';
import {BookOpen, CheckCheck, ChevronRight, CircleCheck, Circle, Copy, ExternalLink, EyeOff, Pencil, Star, Trash2, Undo2, Download, CloudOff, HardDriveDownload} from 'lucide-react';
import {List, ListItem} from '@astryxdesign/core/List';
import {ContextMenu} from '@astryxdesign/core/ContextMenu';
import {Spinner} from '@astryxdesign/core/Spinner';
import type {Folder, Item} from '../data/types';
import {BUCKETS, bucketOf, domainOf, stamp} from '../lib/format';
import {supportsReader} from '../lib/reader';
import {avatarOf, Block, Meta, ProfilePic} from './bits';
import {plainRich} from '../lib/richText';
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
  /** 오프라인 저장한 항목 id */
  offline: Set<string>;
  /** 오프라인 저장 ↔ 지우기 */
  toggleOffline: (i: Item) => void;
  openOffline: (i: Item) => void;
}

/** 항목마다 고유한 전환 이름: 지우거나 넣을 때 다른 줄이 제자리로 미끄러진다 */
const vtName = (i: Item) => ({viewTransitionName: `it-${i.id.replace(/[^a-zA-Z0-9-]/g, '')}`}) as CSSProperties;

const lines = (t: string) => plainRich(t).split('\n').map(l => l.trim()).filter(Boolean);
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
    ...(act.offline.has(i.id)
      ? [{label: '오프라인 보기', icon: <HardDriveDownload size={16} />, onClick: () => act.openOffline(i)},
         {label: '오프라인 저장 지우기', icon: <CloudOff size={16} />, onClick: () => act.toggleOffline(i)}]
      : [{label: '오프라인 다운로드', icon: <Download size={16} />, onClick: () => act.toggleOffline(i)}]),
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

/** 오프라인 저장한 항목: 오른쪽 위 반투명 체크 */
function OfflineMark() {
  return <span className="offline-mark" title="오프라인 저장됨"><CircleCheck size={18} strokeWidth={2.4} aria-label="오프라인 저장됨" /></span>;
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
      {act.offline.has(item.id) && <OfflineMark />}
      {sel ? listItem : <ContextMenu items={menuFor(item, act)} presentation="adaptive" label={nameOf(item)} menuWidth={200}>{listItem}</ContextMenu>}
    </div>
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
        <Meta item={i} folder={folder} showFolder={showFolder} avatar={false} />
        <span className="card-src num" data-av={avatarOf(i) ? true : undefined}>{i.kind === 'memo' ? `메모 · ${stamp(i.createdAt)}` : stamp(i.createdAt)}</span>
      </span>
      {!sel && <ProfilePic item={i} className="card-avatar" />}
      {sel && <span className="card-select"><SelectMark on={selected} /></span>}
      {act.offline.has(i.id) && <OfflineMark />}
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
