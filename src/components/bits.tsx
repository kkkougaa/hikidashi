import {useState, type CSSProperties, type ReactNode} from 'react';
import {Check, StickyNote, X} from 'lucide-react';
import {COLORS, type Folder, type Item} from '../data/types';
import {domainOf} from '../lib/format';
import {logoUrl} from '../lib/pageInfo';

export const cssVar = (c: string) => ({['--c']: c}) as CSSProperties;
export const folderColor = (f?: Folder | null) => (f ? COLORS[f.color] : COLORS.gray);

/**
 * 항목 아이콘: 글 대표 이미지 → 사이트 로고 → 서랍 색 블록 순으로 쓴다.
 * 외부 이미지라 깨질 수 있어서 실패하면 다음 단계로 넘어간다.
 */
export function Block(props: {item: Item; folder?: Folder | null}) {
  // 이미지가 바뀌면 실패 단계를 처음부터 다시
  // 직접 고른 이모지가 있으면 그것부터 (토스페이스)
  if (props.item.emoji) return <span className="block emoji tossface" aria-hidden="true">{props.item.emoji}</span>;
  return <BlockInner key={`${props.item.url ?? ''}|${props.item.image ?? ''}`} {...props} />;
}

function BlockInner({item, folder}: {item: Item; folder?: Folder | null}) {
  const logo = item.kind === 'link' ? logoUrl(item.url, 128) : null;
  const sources = [item.kind === 'link' ? item.image : undefined, logo].filter(Boolean) as string[];
  const [step, setStep] = useState(0);
  const src = sources[step];
  if (item.kind === 'link' && src) {
    const isLogo = src === logo;
    return (
      <span className={isLogo ? 'block thumb logo' : 'block thumb'} aria-hidden="true">
        <img src={src} alt="" loading="lazy" decoding="async" referrerPolicy="no-referrer" onError={() => setStep(s => s + 1)} />
      </span>
    );
  }
  return (
    <span className="block" style={cssVar(folderColor(folder))} aria-hidden="true">
      {item.kind === 'memo' ? <StickyNote strokeWidth={2.2} /> : (domainOf(item.url).charAt(0) || '?').toUpperCase()}
    </span>
  );
}

/** 출처 사이트 칩: 로고 + 사이트 이름(없으면 도메인) */
export function SourceChip({url, siteName}: {url: string; siteName?: string}) {
  const [broken, setBroken] = useState(false);
  const host = domainOf(url);
  const logo = logoUrl(url, 32);
  if (!host) return null;
  return (
    <span className="source-chip" title={host}>
      {logo && !broken
        ? <img src={logo} alt="" width={14} height={14} referrerPolicy="no-referrer" onError={() => setBroken(true)} />
        : <span className="source-dot" aria-hidden="true">{host.charAt(0).toUpperCase()}</span>}
      <span className="source-name">{siteName || host}</span>
    </span>
  );
}

export function Meta({item, folder, showFolder}: {item: Item; folder?: Folder | null; showFolder: boolean}) {
  const hasSource = item.kind === 'link' && !!item.url;
  if (!showFolder && !item.tags.length && !hasSource) return null;
  return (
    <span className="row-meta">
      {showFolder && (folder ? <span className="pill" style={cssVar(folderColor(folder))}>{folder.name}</span> : <span className="pill none">미분류</span>)}
      {hasSource && <SourceChip url={item.url!} siteName={item.siteName} />}
      {item.tags.map(t => <span key={t} className="tag">#{t}</span>)}
    </span>
  );
}

/**
 * 시트 머리: 왼쪽 동그란 닫기, 가운데(제목이나 전환 알약), 오른쪽(✓ 저장이나 동작 묶음).
 * 캘린더 앱처럼 저장 버튼을 아래에 따로 두지 않는다.
 */
export function SheetBar({onClose, closeLabel, center, end}: {onClose: () => void; closeLabel: string; center?: ReactNode; end?: ReactNode}) {
  return (
    <div className="sheet-bar">
      <button type="button" className="round-btn" aria-label={closeLabel} onClick={onClose}><X strokeWidth={1.8} /></button>
      <div className="sheet-bar-center">{center}</div>
      <div className="sheet-bar-end">{end}</div>
    </div>
  );
}

/** 오른쪽 위 동그란 ✓ (폼 제출) */
export function ConfirmButton({label}: {label: string}) {
  return <button type="submit" className="round-btn confirm" aria-label={label}><Check strokeWidth={2} /></button>;
}

/** 예전 머리 모양: 가운데 제목 + 오른쪽 닫기 */
export function SheetHead({title, onClose, closeLabel, start}: {title: string; onClose: () => void; closeLabel: string; start?: ReactNode}) {
  return (
    <SheetBar onClose={onClose} closeLabel={closeLabel} center={<h2 className="sheet-title">{title}</h2>} end={start} />
  );
}
