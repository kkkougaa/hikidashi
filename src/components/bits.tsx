import type {CSSProperties, ReactNode} from 'react';
import {StickyNote, X} from 'lucide-react';
import {COLORS, type Folder, type Item} from '../data/types';
import {domainOf} from '../lib/format';

export const cssVar = (c: string) => ({['--c']: c}) as CSSProperties;
export const folderColor = (f?: Folder | null) => (f ? COLORS[f.color] : COLORS.gray);

export function Block({item, folder}: {item: Item; folder?: Folder | null}) {
  return (
    <span className="block" style={cssVar(folderColor(folder))} aria-hidden="true">
      {item.kind === 'memo' ? <StickyNote strokeWidth={2.2} /> : (domainOf(item.url).charAt(0) || '?').toUpperCase()}
    </span>
  );
}

export function Meta({item, folder, showFolder}: {item: Item; folder?: Folder | null; showFolder: boolean}) {
  if (!showFolder && !item.tags.length) return null;
  return (
    <span className="row-meta">
      {showFolder && (folder ? <span className="pill" style={cssVar(folderColor(folder))}>{folder.name}</span> : <span className="pill none">미분류</span>)}
      {item.tags.map(t => <span key={t} className="tag">#{t}</span>)}
    </span>
  );
}

export function SheetHead({title, onClose, closeLabel, start}: {title: string; onClose: () => void; closeLabel: string; start?: ReactNode}) {
  return (
    <div className="sheet-head">
      {start}
      <h2>{title}</h2>
      <button type="button" className="round-btn end" aria-label={closeLabel} onClick={onClose}><X strokeWidth={1.8} /></button>
    </div>
  );
}
