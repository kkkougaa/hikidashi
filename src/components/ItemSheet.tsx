import {useState} from 'react';
import {ClipboardPaste, Link2} from 'lucide-react';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {SegmentedControl, SegmentedControlItem} from '@astryxdesign/core/SegmentedControl';
import {TextInput} from '@astryxdesign/core/TextInput';
import {TextArea} from '@astryxdesign/core/TextArea';
import {Selector} from '@astryxdesign/core/Selector';
import {Button} from '@astryxdesign/core/Button';
import type {Folder, Item, ItemDraft, ItemKind} from '../data/types';
import {guessTitle, normalizeUrl, parseTags} from '../lib/format';
import {SheetHead} from './bits';

export interface ItemSheetProps {
  isOpen: boolean;
  onClose: () => void;
  /** 편집할 항목. 없으면 새로 추가 */
  editing: Item | null;
  /** 새로 추가할 때 미리 채울 값 (공유로 받은 주소 등) */
  prefill?: Partial<ItemDraft>;
  folders: Folder[];
  defaultFolderId: string | null;
  onSave: (draft: ItemDraft) => void;
}

const NONE = '__none__';

export function ItemSheet(props: ItemSheetProps) {
  // 열릴 때마다 폼을 새로 만든다
  return (
    <BottomSheet label={props.editing ? '항목 편집' : '새 항목'} isOpen={props.isOpen} onOpenChange={o => { if (!o) props.onClose(); }} purpose="form" height="hug">
      {props.isOpen && <ItemForm key={props.editing?.id ?? 'new'} {...props} />}
    </BottomSheet>
  );
}

function ItemForm({onClose, editing, prefill, folders, defaultFolderId, onSave}: ItemSheetProps) {
  const init = editing ?? prefill ?? {};
  const [kind, setKind] = useState<ItemKind>(init.kind ?? 'link');
  const [url, setUrl] = useState(init.url ?? '');
  const [title, setTitle] = useState(init.title ?? '');
  const [note, setNote] = useState(init.note ?? '');
  const [folderId, setFolderId] = useState<string>((editing ? editing.folderId : (prefill?.folderId ?? defaultFolderId)) ?? NONE);
  const [tags, setTags] = useState((init.tags ?? []).join(', '));
  const [urlErr, setUrlErr] = useState<string | null>(null);
  const [noteErr, setNoteErr] = useState<string | null>(null);
  const [pasteMsg, setPasteMsg] = useState<string | null>(null);

  const paste = async () => {
    try {
      const t = (await navigator.clipboard.readText()).trim();
      if (!t) return setPasteMsg('클립보드가 비어 있어요');
      setUrl(t);
      setUrlErr(null);
      setPasteMsg(null);
    } catch {
      setPasteMsg('붙여넣기 권한이 없어요. 주소 칸을 길게 눌러 붙여넣어 주세요');
    }
  };

  const submit = () => {
    const base = {title: title.trim(), note: note.trim(), folderId: folderId === NONE ? null : folderId, tags: parseTags(tags)};
    if (kind === 'link') {
      if (!url.trim()) return setUrlErr('저장할 주소를 넣어주세요');
      const u = normalizeUrl(url);
      if (!u) return setUrlErr('주소 형식을 확인해주세요. 예: example.com/article');
      onSave({...base, kind, url: u, title: base.title || guessTitle(u)});
    } else {
      if (!base.note) return setNoteErr('메모 내용을 적어주세요');
      onSave({...base, kind, url: undefined});
    }
  };

  return (
    <form noValidate onSubmit={e => { e.preventDefault(); submit(); }}>
      <SheetHead title={editing ? '항목 편집' : '새 항목'} onClose={onClose} closeLabel="닫기" />
      <div className="form-stack">
        {!editing && (
          <SegmentedControl label="종류" value={kind} onChange={v => { setKind(v as ItemKind); setUrlErr(null); setNoteErr(null); }} layout="fill">
            <SegmentedControlItem value="link" label="링크" />
            <SegmentedControlItem value="memo" label="메모" />
          </SegmentedControl>
        )}
        {kind === 'link' && (
          <div className="with-action">
            <TextInput label="주소" type="url" placeholder="https://example.com/article" value={url} size="lg"
              onChange={v => { setUrl(v); setUrlErr(null); }} startIcon={Link2}
              status={urlErr ? {type: 'error', message: urlErr} : pasteMsg ? {type: 'warning', message: pasteMsg} : undefined} />
            <Button label="붙여넣기" size="lg" icon={<ClipboardPaste size={18} />} onClick={paste} />
          </div>
        )}
        <TextInput label="제목" placeholder={kind === 'link' ? '비워 두면 주소에서 가져와요' : '예: 장보기'} value={title} onChange={setTitle} size="lg" />
        <TextArea label={kind === 'link' ? '한 줄 메모' : '메모'} rows={kind === 'link' ? 2 : 6} value={note} size="lg"
          placeholder={kind === 'link' ? '왜 저장했는지 적어두면 찾기 쉬워요' : ''}
          onChange={v => { setNote(v); setNoteErr(null); }} status={noteErr ? {type: 'error', message: noteErr} : undefined} />
        <Selector label="서랍" value={folderId} onChange={setFolderId} size="lg"
          options={[...folders.map(f => ({value: f.id, label: f.name})), {type: 'divider' as const}, {value: NONE, label: '미분류'}]} />
        <TextInput label="태그" placeholder="예: 참고, 나중에" value={tags} onChange={setTags} size="lg" />
        <div className="sheet-actions">
          <Button label={editing ? '변경 사항 저장' : kind === 'link' ? '링크 저장' : '메모 저장'} variant="primary" size="lg" type="submit" />
        </div>
      </div>
    </form>
  );
}
