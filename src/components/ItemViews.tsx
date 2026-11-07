import type {CSSProperties} from 'react';
import {ChevronRight, Copy, Pencil, Star, Trash2} from 'lucide-react';
import {List, ListItem} from '@astryxdesign/core/List';
import {ClickableCard} from '@astryxdesign/core/ClickableCard';
import {ContextMenu} from '@astryxdesign/core/ContextMenu';
import type {Folder, Item} from '../data/types';
import {BUCKETS, bucketOf, domainOf, stamp} from '../lib/format';
import {Block, Meta} from './bits';

export interface ItemActions {
  open: (i: Item) => void;
  edit: (i: Item) => void;
  toggleStar: (i: Item) => void;
  copy: (i: Item) => void;
  remove: (i: Item) => void;
}

/** 항목마다 고유한 전환 이름: 지우거나 넣을 때 다른 줄이 제자리로 미끄러진다 */
const vtName = (i: Item) => ({viewTransitionName: `it-${i.id.replace(/[^a-zA-Z0-9-]/g, '')}`}) as CSSProperties;

const nameOf = (i: Item) => i.title || (i.kind === 'memo' ? '제목 없는 메모' : domainOf(i.url));

function menuFor(i: Item, act: ItemActions) {
  return [
    {label: i.starred ? '즐겨찾기 해제' : '즐겨찾기', icon: <Star size={16} />, onClick: () => act.toggleStar(i)},
    {label: '편집', icon: <Pencil size={16} />, onClick: () => act.edit(i)},
    ...(i.kind === 'link' ? [{label: '주소 복사', icon: <Copy size={16} />, onClick: () => act.copy(i)}] : []),
    {type: 'divider' as const},
    {label: '삭제', icon: <Trash2 size={16} />, variant: 'destructive' as const, onClick: () => act.remove(i)},
  ];
}

function Row({item, folder, showFolder, act}: {item: Item; folder?: Folder; showFolder: boolean; act: ItemActions}) {
  // 링크의 사이트는 출처 칩에 나오므로 여기엔 내용만
  const sub = item.kind === 'memo' ? item.note.split('\n').find(l => l.trim()) ?? '' : item.note.split('\n')[0] ?? '';
  return (
    <div className="vt-row" style={vtName(item)}>
    <ContextMenu items={menuFor(item, act)} presentation="adaptive" label={nameOf(item)} menuWidth={190}>
      <ListItem
        label={<span className="row-title">{nameOf(item)}</span>}
        description={<span className="row-text">{sub && <span className="row-sub">{sub}</span>}<Meta item={item} folder={folder} showFolder={showFolder} /></span>}
        startContent={<Block item={item} folder={folder} />}
        endContent={
          <span className="row-end">
            {item.starred && <Star className="star" size={15} fill="currentColor" aria-label="즐겨찾기" />}
            <span className="num">{stamp(item.createdAt)}</span>
            {item.kind === 'memo' && <ChevronRight className="chev" size={18} aria-hidden="true" />}
          </span>
        }
        {...(item.kind === 'link' ? {href: item.url, target: '_blank' as const} : {onClick: () => act.open(item)})}
        swipeActions={{
          leading: [{id: 'star', label: item.starred ? '해제' : '즐겨찾기', icon: <Star size={18} />, variant: 'accent', onActivate: () => act.toggleStar(item)}],
          trailing: [
            {id: 'edit', label: '편집', icon: <Pencil size={18} />, variant: 'neutral', onActivate: () => act.edit(item)},
            {id: 'del', label: '삭제', icon: <Trash2 size={18} />, variant: 'destructive', onActivate: () => act.remove(item)},
          ],
        }}
      />
    </ContextMenu>
    </div>
  );
}

export function DayList({items, folderMap, showFolder, act}: {items: Item[]; folderMap: Map<string, Folder>; showFolder: boolean; act: ItemActions}) {
  const groups = BUCKETS.map(b => ({b, list: items.filter(i => bucketOf(i.createdAt) === b)})).filter(g => g.list.length);
  return (
    <>
      {groups.map(g => (
        <section className="day" key={g.b} aria-labelledby={`day-${g.b}`}>
          <div className="day-head"><h2 id={`day-${g.b}`}>{g.b}</h2><span className="num">{g.list.length}개</span></div>
          <List hasDividers density="spacious" edge="flush">
            {g.list.map(i => <Row key={i.id} item={i} folder={i.folderId ? folderMap.get(i.folderId) : undefined} showFolder={showFolder} act={act} />)}
          </List>
        </section>
      ))}
    </>
  );
}

export function CardGrid({items, folderMap, showFolder, act}: {items: Item[]; folderMap: Map<string, Folder>; showFolder: boolean; act: ItemActions}) {
  return (
    <div className="cards">
      {items.map(i => {
        const folder = i.folderId ? folderMap.get(i.folderId) : undefined;
        const body = (
          <div className="card-body">
            <div className="card-head">
              <Block item={i} folder={folder} />
              {i.starred && <Star size={15} fill="currentColor" style={{color: 'var(--star)'}} aria-label="즐겨찾기" />}
            </div>
            <p className="card-title">{nameOf(i)}</p>
            {i.note && <p className="card-desc">{i.note}</p>}
            <span className="card-src">{i.kind === 'memo' ? '메모' : domainOf(i.url)} · {stamp(i.createdAt)}</span>
            <Meta item={i} folder={folder} showFolder={showFolder} />
          </div>
        );
        return (
          <div key={i.id} className="vt-row" style={vtName(i)}>
          <ContextMenu items={menuFor(i, act)} presentation="adaptive" label={nameOf(i)} menuWidth={190}>
            {i.kind === 'link'
              ? <ClickableCard label={nameOf(i)} href={i.url} target="_blank" padding={3}>{body}</ClickableCard>
              : <ClickableCard label={nameOf(i)} onClick={() => act.open(i)} padding={3}>{body}</ClickableCard>}
          </ContextMenu>
          </div>
        );
      })}
    </div>
  );
}
