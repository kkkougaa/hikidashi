import {useEffect, useState} from 'react';
import {CircleCheck, Pencil, PlusCircle, Star} from 'lucide-react';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {MoreMenu} from '@astryxdesign/core/MoreMenu';
import {type Folder, type Item} from '../data/types';
import {domainOf, findUrls, guessTitle, stamp} from '../lib/format';
import {fetchPageInfo, logoUrl, type PageInfo} from '../lib/pageInfo';
import {RichText, SheetBar, cssVar, folderColor} from './bits';

/** 메모 보기: 화면에서 떠 있는 카드. 오른쪽 위에 [편집 | ⋯], 맨 아래 삭제 */
export function MemoSheet({item, folder, onClose, onEdit, onRemove, onStar, saved, onOpenLink, onSaveLink}: {
  item: Item | null; folder?: Folder; onClose: () => void; onEdit: (i: Item) => void; onRemove: (i: Item) => void; onStar: (i: Item) => void;
  /** 이미 저장한 링크 찾기 */
  saved: (url: string) => Item | undefined;
  onOpenLink: (url: string) => void;
  onSaveLink: (url: string, info: PageInfo | null, folderId: string | null) => void;
}) {
  return (
    <BottomSheet label={item?.title || '메모'} isOpen={!!item} onOpenChange={o => { if (!o) onClose(); }} height="hug">
      {item && (
        <div className="sheet-float">
          <SheetBar
            onClose={onClose} closeLabel="메모 닫기"
            end={
              <div className="pill-group">
                <button type="button" className="pill-btn" aria-label="편집" onClick={() => onEdit(item)}><Pencil size={20} strokeWidth={1.9} /></button>
                <MoreMenu label="더 보기" size="md" alignment="end" presentation="adaptive"
                  items={[{label: item.starred ? '즐겨찾기 해제' : '즐겨찾기', icon: <Star size={16} />, onClick: () => onStar(item)}]} />
              </div>
            }
          />
          <h2 className="detail-title">{item.emoji && <span className="tossface detail-emoji" aria-hidden="true">{item.emoji}</span>}{item.title || '제목 없는 메모'}</h2>
          <div className="detail-rows">
            <div className="form-row">
              <span className="form-row-label">서랍</span>
              <span className="form-row-value">
                <span className="color-bar" style={cssVar(folderColor(folder))} aria-hidden="true" />
                {folder?.name ?? '미분류'}
              </span>
            </div>
            <div className="form-row">
              <span className="form-row-label">저장한 날</span>
              <span className="form-row-value num">{stamp(item.createdAt)}</span>
            </div>
            {item.tags.length > 0 && (
              <div className="form-row">
                <span className="form-row-label">태그</span>
                <span className="form-row-value wrap">{item.tags.map(t => <span key={t} className="tag-chip static">#{t}</span>)}</span>
              </div>
            )}
            {item.starred && (
              <div className="form-row">
                <span className="form-row-label">즐겨찾기</span>
                <span className="form-row-value"><Star size={18} fill="currentColor" style={{color: 'var(--star)'}} aria-label="켜짐" /></span>
              </div>
            )}
          </div>
          {item.note && <div className="memo-full"><RichText text={item.note} block /></div>}
          {findUrls(item.note).map(u => (
            <LinkPreview key={u} url={u} saved={saved(u)} onOpen={() => onOpenLink(u)} onSave={info => onSaveLink(u, info, item.folderId)} />
          ))}
          <button type="button" className="danger-btn" onClick={() => onRemove(item)}>삭제</button>
        </div>
      )}
    </BottomSheet>
  );
}

const previews = new Map<string, PageInfo | null>();

/** 메모 속 링크 미리보기: 그림, 제목, 사이트. 아직 저장 안 한 링크는 + 로 바로 저장 */
function LinkPreview({url, saved, onOpen, onSave}: {url: string; saved?: Item; onOpen: () => void; onSave: (info: PageInfo | null) => void}) {
  const [info, setInfo] = useState<PageInfo | null | undefined>(() => previews.get(url));
  useEffect(() => {
    if (saved || info !== undefined) return;
    let alive = true;
    void fetchPageInfo(url).then(r => { previews.set(url, r); if (alive) setInfo(r); });
    return () => { alive = false; };
  }, [url, saved, info]);
  const img = saved?.image ?? info?.image;
  const logo = logoUrl(url, 128);
  const title = saved?.title || info?.title || (info === undefined && !saved ? '불러오는 중…' : guessTitle(url));
  return (
    <div className="link-preview">
      <button type="button" className="link-preview-main" onClick={onOpen}>
        <span className={img ? 'lp-thumb' : 'lp-thumb logo'}>{(img || logo) && <img src={(img || logo)!} alt="" loading="lazy" referrerPolicy="no-referrer" />}</span>
        <span className="lp-text">
          <span className="lp-title">{title}</span>
          <span className="lp-site">{saved?.siteName || info?.siteName || domainOf(url)}</span>
        </span>
      </button>
      {saved
        ? <CircleCheck className="lp-saved" size={22} aria-label="저장된 링크" />
        : <button type="button" className="lp-add" aria-label="이 링크 저장" onClick={() => onSave(info ?? null)}><PlusCircle size={24} /></button>}
    </div>
  );
}
