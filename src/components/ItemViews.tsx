import {useState, type CSSProperties} from 'react';
import {BookOpen, ChevronRight, CircleCheck, Circle, Copy, ExternalLink, Pencil, Star, Trash2} from 'lucide-react';
import {List, ListItem} from '@astryxdesign/core/List';
import {ContextMenu} from '@astryxdesign/core/ContextMenu';
import {Spinner} from '@astryxdesign/core/Spinner';
import type {Folder, Item} from '../data/types';
import {BUCKETS, bucketOf, domainOf, stamp} from '../lib/format';
import {supportsReader} from '../lib/reader';
import {Block, Meta} from './bits';

export interface ItemActions {
  open: (i: Item) => void;
  openReader: (i: Item) => void;
  openTab: (i: Item) => void;
  edit: (i: Item) => void;
  toggleStar: (i: Item) => void;
  copy: (i: Item) => void;
  remove: (i: Item) => void;
  startSelect: (i: Item) => void;
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
    {label: '여러 개 고르기', icon: <CircleCheck size={16} />, onClick: () => act.startSelect(i)},
    ...(i.kind === 'link' ? [
      ...(supportsReader(i.url) ? [{label: '리더로 보기', icon: <BookOpen size={16} />, onClick: () => act.openReader(i)}] : []),
      {label: '새 탭으로 열기', icon: <ExternalLink size={16} />, onClick: () => act.openTab(i)},
      {label: '주소 복사', icon: <Copy size={16} />, onClick: () => act.copy(i)},
    ] : []),
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

function Card({item: i, folder, showFolder, act}: {item: Item; folder?: Folder; showFolder: boolean; act: ItemActions}) {
  const [coverBroken, setCoverBroken] = useState(false);
  const cover = coverBroken ? null : coverOf(i);
  const sel = act.selection;
  const selected = !!sel?.has(i.id);
  const sub = subOf(i);
  const card = (
    <button type="button" className="card" data-selected={selected || undefined} aria-pressed={sel ? selected : undefined}
      onClick={() => (sel ? act.toggleSelect(i) : act.open(i))}>
      {cover && (
        <span className="card-cover">
          <img src={cover} alt="" loading="lazy" decoding="async" referrerPolicy="no-referrer" onError={() => setCoverBroken(true)} />
          {i.starred && <span className="cover-star"><Star size={14} fill="currentColor" aria-label="즐겨찾기" /></span>}
        </span>
      )}
      <span className="card-body">
        {!cover && (
          <span className="card-head">
            <Block item={i} folder={folder} />
            {i.starred && <Star size={15} fill="currentColor" style={{color: 'var(--star)'}} aria-label="즐겨찾기" />}
          </span>
        )}
        <span className="card-title" data-long={!cover || undefined}>{nameOf(i)}</span>
        {sub && <span className="card-desc" data-long={!cover || undefined}>{sub}</span>}
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
