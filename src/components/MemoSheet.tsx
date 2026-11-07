import {Pencil, Star} from 'lucide-react';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {MoreMenu} from '@astryxdesign/core/MoreMenu';
import {COLORS, type Folder, type Item} from '../data/types';
import {stamp} from '../lib/format';
import {SheetBar, cssVar} from './bits';

/** 메모 보기: 화면에서 떠 있는 카드. 오른쪽 위에 [편집 | ⋯], 맨 아래 삭제 */
export function MemoSheet({item, folder, onClose, onEdit, onRemove, onStar}: {
  item: Item | null; folder?: Folder; onClose: () => void; onEdit: (i: Item) => void; onRemove: (i: Item) => void; onStar: (i: Item) => void;
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
          <h2 className="detail-title">{item.title || '제목 없는 메모'}</h2>
          <div className="detail-rows">
            <div className="form-row">
              <span className="form-row-label">서랍</span>
              <span className="form-row-value">
                <span className="color-bar" style={cssVar(folder ? COLORS[folder.color] : COLORS.gray)} aria-hidden="true" />
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
          {item.note && <p className="memo-full">{item.note}</p>}
          <button type="button" className="danger-btn" onClick={() => onRemove(item)}>삭제</button>
        </div>
      )}
    </BottomSheet>
  );
}
