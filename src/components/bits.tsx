import {Fragment, useState, type CSSProperties, type ReactNode} from 'react';
import {Check, StickyNote, X} from 'lucide-react';
import {COLORS, inkOn, isHex, type Folder, type Item} from '../data/types';
import {domainOf} from '../lib/format';
import {logoUrl} from '../lib/pageInfo';
import {parseRich, type Span} from '../lib/richText';

export const cssVar = (c: string) => ({['--c']: c, ['--on']: inkOn(c)}) as CSSProperties;
/** 서랍 색: 팔레트로 고른 색이 있으면 그것, 없으면 기본 색 */
export const folderColor = (f?: Pick<Folder, 'color' | 'hex'> | null) => (f ? (f.hex && isHex(f.hex) ? f.hex : COLORS[f.color]) : COLORS.gray);

/**
 * 항목 아이콘: 글 대표 이미지 → 사이트 로고 → 서랍 색 블록 순으로 쓴다.
 * 외부 이미지라 깨질 수 있어서 실패하면 다음 단계로 넘어간다.
 */
export function Block(props: {item: Item; folder?: Folder | null}) {
  // 이미지가 바뀌면 실패 단계를 처음부터 다시
  // 직접 고른 이모지가 있으면 그것부터 (토스페이스)
  if (props.item.emoji) return <span className="block emoji tossface" aria-hidden="true">{props.item.emoji}</span>;
  // 사진에서 잘라 만든 아이콘
  if (props.item.icon) return <span className="block thumb" aria-hidden="true"><img src={props.item.icon} alt="" decoding="async" /></span>;
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

/** 글쓴이 프로필 사진 주소 (X 등). 예전에 저장한 X 글은 대표 그림 자리에 들어 있기도 하다 */
export const avatarOf = (i: Item) => (i.kind === 'link' ? i.avatar || (i.image?.includes('profile_images') ? i.image : undefined) : undefined);

/** 동그란 글쓴이 프로필 사진. 못 불러오면 숨긴다 */
export function ProfilePic({item, className = 'profile-pic'}: {item: Item; className?: string}) {
  const src = avatarOf(item);
  const [broken, setBroken] = useState<string | null>(null);
  if (!src || broken === src) return null;
  return <img className={className} src={src} alt="" loading="lazy" decoding="async" referrerPolicy="no-referrer" onError={() => setBroken(src)} />;
}

export function Meta({item, folder, showFolder, avatar = true}: {item: Item; folder?: Folder | null; showFolder: boolean; avatar?: boolean}) {
  const hasSource = item.kind === 'link' && !!item.url;
  if (!showFolder && !item.tags.length && !hasSource && !item.brokenAt) return null;
  return (
    <span className="row-meta">
      {item.brokenAt ? <span className="pill broken" title="링크가 열리지 않아요">안 열림</span> : null}
      {showFolder && (folder ? <span className="pill" style={cssVar(folderColor(folder))}>{folder.name}</span> : <span className="pill none">미분류</span>)}
      {hasSource && avatar && <ProfilePic item={item} />}
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

/** 서식 있는 메모 본문. block 이면 목록 줄을 들여 쓰고, 아니면 한 덩어리 글로 (줄 수 자르기용) */
export function RichText({text, block}: {text: string; block?: boolean}) {
  const ls = parseRich(text);
  const body = (spans: Span[]) => spans.map((s, k) => (s.bold ? <strong key={k}>{s.text}</strong> : s.text));
  if (!block) {
    return <>{ls.map((l, n) => (
      <Fragment key={n}>{n > 0 && '\n'}{l.kind === 'bullet' ? '• ' : l.kind === 'number' ? `${l.n}. ` : ''}{body(l.spans)}</Fragment>
    ))}</>;
  }
  return (
    <div className="rich">
      {ls.map((l, n) => l.kind === 'text'
        ? <p key={n} className="rich-p">{l.spans.some(s => s.text) ? body(l.spans) : ' '}</p>
        : <p key={n} className="rich-li" style={{['--in' as string]: `${l.indent * 0.5}em`}}>
            <span className="rich-mark" aria-hidden="true">{l.kind === 'bullet' ? '•' : `${l.n}.`}</span><span>{body(l.spans)}</span>
          </p>)}
    </div>
  );
}
