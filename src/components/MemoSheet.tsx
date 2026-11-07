import {Pencil, Trash2} from 'lucide-react';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {Button} from '@astryxdesign/core/Button';
import {Text} from '@astryxdesign/core/Text';
import type {Folder, Item} from '../data/types';
import {stamp} from '../lib/format';
import {Meta, SheetHead} from './bits';

export function MemoSheet({item, folder, onClose, onEdit, onRemove}: {
  item: Item | null; folder?: Folder; onClose: () => void; onEdit: (i: Item) => void; onRemove: (i: Item) => void;
}) {
  return (
    <BottomSheet label={item?.title || '메모'} isOpen={!!item} onOpenChange={o => { if (!o) onClose(); }} height="hug">
      {item && (
        <>
          <SheetHead title={item.title || '메모'} onClose={onClose} closeLabel="메모 닫기" />
          <div className="form-stack">
            <p className="memo-full">{item.note}</p>
            <Meta item={item} folder={folder} showFolder />
            <Text type="supporting">{stamp(item.createdAt)}에 저장</Text>
            <div className="sheet-actions split">
              <Button label="삭제" variant="ghost" size="lg" icon={<Trash2 size={18} />} onClick={() => onRemove(item)} />
              <Button label="편집" size="lg" icon={<Pencil size={18} />} onClick={() => onEdit(item)} />
            </div>
          </div>
        </>
      )}
    </BottomSheet>
  );
}
