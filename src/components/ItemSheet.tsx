import {useEffect, useRef, useState} from 'react';
import {ClipboardPaste, Link2, RotateCw} from 'lucide-react';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {SegmentedControl, SegmentedControlItem} from '@astryxdesign/core/SegmentedControl';
import {TextInput} from '@astryxdesign/core/TextInput';
import {TextArea} from '@astryxdesign/core/TextArea';
import {Selector} from '@astryxdesign/core/Selector';
import {Button} from '@astryxdesign/core/Button';
import {Spinner} from '@astryxdesign/core/Spinner';
import type {Folder, Item, ItemDraft, ItemKind} from '../data/types';
import {guessTitle, normalizeUrl} from '../lib/format';
import {fetchPageInfo} from '../lib/pageInfo';
import {Block, SheetHead} from './bits';
import {TagInput} from './TagInput';

export interface ItemSheetProps {
  isOpen: boolean;
  onClose: () => void;
  /** 편집할 항목. 없으면 새로 추가 */
  editing: Item | null;
  /** 새로 추가할 때 미리 채울 값 (공유로 받은 주소 등) */
  prefill?: Partial<ItemDraft>;
  folders: Folder[];
  defaultFolderId: string | null;
  /** 이미 쓰고 있는 태그 (자주 쓴 순) */
  allTags: string[];
  onSave: (draft: ItemDraft) => void;
}

const NONE = '__none__';
type FetchState = 'idle' | 'loading' | 'done' | 'failed';

export function ItemSheet(props: ItemSheetProps) {
  return (
    <BottomSheet label={props.editing ? '항목 편집' : '새 항목'} isOpen={props.isOpen} onOpenChange={o => { if (!o) props.onClose(); }} purpose="form" height="hug">
      {props.isOpen && <ItemForm key={props.editing?.id ?? 'new'} {...props} />}
    </BottomSheet>
  );
}

function ItemForm({onClose, editing, prefill, folders, defaultFolderId, allTags, onSave}: ItemSheetProps) {
  const init = editing ?? prefill ?? {};
  const [kind, setKind] = useState<ItemKind>(init.kind ?? 'link');
  const [url, setUrl] = useState(init.url ?? '');
  const [title, setTitle] = useState(init.title ?? '');
  const [note, setNote] = useState(init.note ?? '');
  const [image, setImage] = useState(init.image);
  const [siteName, setSiteName] = useState(init.siteName);
  const [folderId, setFolderId] = useState<string>((editing ? editing.folderId : (prefill?.folderId ?? defaultFolderId)) ?? NONE);
  const [tags, setTags] = useState<string[]>(init.tags ?? []);
  const [urlErr, setUrlErr] = useState<string | null>(null);
  const [noteErr, setNoteErr] = useState<string | null>(null);
  const [pasteMsg, setPasteMsg] = useState<string | null>(null);
  const [fetchState, setFetchState] = useState<FetchState>('idle');
  // 사용자가 직접 고친 칸은 가져온 정보로 덮어쓰지 않는다
  const touched = useRef({title: !!init.title, note: !!init.note});
  const lastFetched = useRef<string | null>(editing?.url ?? null);
  const abort = useRef<AbortController | null>(null);

  const load = async (raw: string, force = false) => {
    const u = normalizeUrl(raw);
    if (!u || (!force && lastFetched.current === u)) return;
    lastFetched.current = u;
    abort.current?.abort();
    const ctrl = new AbortController();
    abort.current = ctrl;
    setFetchState('loading');
    const info = await fetchPageInfo(u, ctrl.signal);
    if (ctrl.signal.aborted) return;
    if (!info) return setFetchState('failed');
    if (info.title && (force || !touched.current.title)) setTitle(info.title);
    if (info.description && (force || !touched.current.note)) setNote(info.description);
    setImage(info.image);
    setSiteName(info.siteName);
    setFetchState('done');
  };

  // 공유로 들어왔거나, 주소를 적고 잠시 멈추면 자동으로 가져온다
  useEffect(() => {
    if (kind !== 'link' || editing) return;
    const t = setTimeout(() => void load(url), url === init.url ? 0 : 700);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [url, kind]);
  useEffect(() => () => abort.current?.abort(), []);

  const paste = async () => {
    try {
      const t = (await navigator.clipboard.readText()).trim();
      if (!t) return setPasteMsg('클립보드가 비어 있어요');
      setUrl(t);
      setUrlErr(null);
      setPasteMsg(null);
      void load(t);
    } catch {
      setPasteMsg('붙여넣기 권한이 없어요. 주소 칸을 길게 눌러 붙여넣어 주세요');
    }
  };

  const submit = () => {
    const base = {title: title.trim(), note: note.trim(), folderId: folderId === NONE ? null : folderId, tags};
    if (kind === 'link') {
      if (!url.trim()) return setUrlErr('저장할 주소를 넣어주세요');
      const u = normalizeUrl(url);
      if (!u) return setUrlErr('주소 형식을 확인해주세요. 예: example.com/article');
      onSave({...base, kind, url: u, title: base.title || guessTitle(u), image, siteName});
    } else {
      if (!base.note) return setNoteErr('메모 내용을 적어주세요');
      onSave({...base, kind, url: undefined, image: undefined, siteName: undefined});
    }
  };

  const normalized = kind === 'link' ? normalizeUrl(url) : null;
  const status = fetchState === 'loading'
    ? <span className="fetch-status"><Spinner size="sm" aria-label="가져오는 중" />페이지 정보를 가져오는 중</span>
    : fetchState === 'failed'
      ? <span className="fetch-status">페이지 정보를 가져오지 못했어요. 직접 적어주세요<button type="button" className="link-btn" onClick={() => void load(url, true)}><RotateCw size={14} />다시 시도</button></span>
      : editing && normalized
        ? <span className="fetch-status"><button type="button" className="link-btn" onClick={() => void load(url, true)}><RotateCw size={14} />페이지 정보 다시 가져오기</button></span>
        : null;

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
          <div className="form-stack" style={{gap: 8}}>
            <div className="with-action">
              <TextInput label="주소" type="url" placeholder="https://example.com/article" value={url} size="lg"
                onChange={v => { setUrl(v); setUrlErr(null); }} startIcon={Link2}
                status={urlErr ? {type: 'error', message: urlErr} : pasteMsg ? {type: 'warning', message: pasteMsg} : undefined} />
              <Button label="붙여넣기" size="lg" icon={<ClipboardPaste size={18} />} onClick={paste} />
            </div>
            {status}
          </div>
        )}
        {kind === 'link' && normalized && fetchState !== 'loading' && (image || fetchState === 'done') && (
          <div className="fetch-preview">
            <Block item={{kind: 'link', url: normalized, image, title, note, folderId: null, tags: [], starred: false, id: 'preview', createdAt: 0, updatedAt: 0, deletedAt: null}} />
            <span className="fetch-preview-text">{image ? '글 이미지를 아이콘으로 써요' : '글 이미지가 없어서 사이트 로고를 써요'}</span>
          </div>
        )}
        <TextInput label="제목" placeholder={kind === 'link' ? '비워 두면 페이지 제목을 써요' : '예: 장보기'} value={title} size="lg"
          onChange={v => { setTitle(v); touched.current.title = true; }} />
        <TextArea label={kind === 'link' ? '내용' : '메모'} rows={kind === 'link' ? 3 : 6} value={note} size="lg"
          placeholder={kind === 'link' ? '페이지 소개문이 자동으로 들어가요' : ''}
          onChange={v => { setNote(v); setNoteErr(null); touched.current.note = true; }} status={noteErr ? {type: 'error', message: noteErr} : undefined} />
        <Selector label="서랍" value={folderId} onChange={setFolderId} size="lg"
          options={[...folders.map(f => ({value: f.id, label: f.name})), {type: 'divider' as const}, {value: NONE, label: '미분류'}]} />
        <TagInput value={tags} onChange={setTags} suggestions={allTags} sourceUrl={kind === 'link' ? normalized ?? undefined : undefined} siteName={siteName} />
        <div className="sheet-actions">
          <Button label={editing ? '변경 사항 저장' : kind === 'link' ? '링크 저장' : '메모 저장'} variant="primary" size="lg" type="submit" />
        </div>
      </div>
    </form>
  );
}
