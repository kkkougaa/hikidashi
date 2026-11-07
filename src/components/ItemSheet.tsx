import {useEffect, useRef, useState} from 'react';
import {ChevronRight, ClipboardPaste, Link2, RotateCw} from 'lucide-react';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {SegmentedControl, SegmentedControlItem} from '@astryxdesign/core/SegmentedControl';
import {Spinner} from '@astryxdesign/core/Spinner';
import {COLORS, type Folder, type Item, type ItemDraft, type ItemKind} from '../data/types';
import {guessTitle, normalizeUrl} from '../lib/format';
import {fetchPageInfo} from '../lib/pageInfo';
import {Block, ConfirmButton, SheetBar, cssVar} from './bits';
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
    <BottomSheet label={props.editing ? '항목 편집' : '새 항목'} isOpen={props.isOpen} onOpenChange={o => { if (!o) props.onClose(); }} purpose="form" height="tall">
      {props.isOpen && <ItemForm key={props.editing?.id ?? 'new'} {...props} />}
    </BottomSheet>
  );
}

/** 설정 앱 같은 한 줄: 왼쪽 이름, 오른쪽 값. 탭하면 아이폰 기본 선택 휠이 뜬다 */
function FolderRow({folders, value, onChange}: {folders: Folder[]; value: string; onChange: (v: string) => void}) {
  const f = folders.find(x => x.id === value);
  return (
    <label className="form-row tappable">
      <span className="form-row-label">서랍</span>
      <span className="form-row-value">
        <span className="color-bar" style={cssVar(f ? COLORS[f.color] : COLORS.gray)} aria-hidden="true" />
        {f?.name ?? '미분류'}
        <ChevronRight className="chev" size={18} aria-hidden="true" />
      </span>
      <select className="native-select" value={value} onChange={e => onChange(e.target.value)} aria-label="서랍">
        {folders.map(x => <option key={x.id} value={x.id}>{x.name}</option>)}
        <option value={NONE}>미분류</option>
      </select>
    </label>
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
  const [err, setErr] = useState<string | null>(null);
  const [pasteMsg, setPasteMsg] = useState<string | null>(null);
  const [fetchState, setFetchState] = useState<FetchState>('idle');
  // 페이지 정보를 가져오는 중에 저장을 누르면, 다 받은 뒤에 저장한다
  const [saveWhenReady, setSaveWhenReady] = useState(false);
  // 사용자가 직접 고친 칸은 가져온 정보로 덮어쓰지 않는다
  const touched = useRef({title: !!init.title, note: !!init.note});
  const lastFetched = useRef<string | null>(editing?.url ?? null);
  const abort = useRef<AbortController | null>(null);
  const noteRef = useRef<HTMLTextAreaElement>(null);

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
  // 내용 칸은 글 길이에 맞춰 늘어난다
  useEffect(() => {
    const el = noteRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, 320)}px`;
  }, [note, kind]);

  const paste = async () => {
    try {
      const t = (await navigator.clipboard.readText()).trim();
      if (!t) return setPasteMsg('클립보드가 비어 있어요');
      setUrl(t);
      setErr(null);
      setPasteMsg(null);
      void load(t);
    } catch {
      setPasteMsg('붙여넣기 권한이 없어요. 주소 칸을 길게 눌러 붙여넣어 주세요');
    }
  };

  useEffect(() => {
    if (saveWhenReady && (fetchState === 'done' || fetchState === 'failed')) { setSaveWhenReady(false); submit(); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [saveWhenReady, fetchState]);

  const submit = () => {
    const base = {title: title.trim(), note: note.trim(), folderId: folderId === NONE ? null : folderId, tags};
    if (kind === 'link') {
      if (!url.trim()) return setErr('저장할 주소를 넣어주세요');
      const u = normalizeUrl(url);
      if (!u) return setErr('주소 형식을 확인해주세요. 예: example.com/article');
      if (!editing && (fetchState === 'loading' || lastFetched.current !== u)) {
        setSaveWhenReady(true);
        if (fetchState !== 'loading') void load(u);
        return;
      }
      onSave({...base, kind, url: u, title: base.title || guessTitle(u), image, siteName});
    } else {
      if (!base.note && !base.title) return setErr('메모 내용을 적어주세요');
      onSave({...base, kind, url: undefined, image: undefined, siteName: undefined});
    }
  };

  const normalized = kind === 'link' ? normalizeUrl(url) : null;
  const saveLabel = editing ? '변경 사항 저장' : kind === 'link' ? '링크 저장' : '메모 저장';

  return (
    <form noValidate onSubmit={e => { e.preventDefault(); submit(); }} className="sheet-form">
      <SheetBar
        onClose={onClose} closeLabel="닫기"
        center={editing ? <h2 className="sheet-title">항목 편집</h2> : (
          <SegmentedControl label="종류" value={kind} onChange={v => { setKind(v as ItemKind); setErr(null); }} size="sm">
            <SegmentedControlItem value="link" label="링크" />
            <SegmentedControlItem value="memo" label="메모" />
          </SegmentedControl>
        )}
        end={<ConfirmButton label={saveLabel} />}
      />

      <input className="big-input" value={title} aria-label="제목" enterKeyHint="next"
        placeholder={kind === 'link' ? '제목' : '새로운 메모'}
        onChange={e => { setTitle(e.target.value); touched.current.title = true; setErr(null); }} />

      {kind === 'link' && (
        <div className="form-group">
          <div className={err ? 'url-row invalid' : 'url-row'}>
            <Link2 size={20} className="url-icon" aria-hidden="true" />
            <input type="url" inputMode="url" value={url} placeholder="주소 붙여넣기" aria-label="주소" aria-invalid={!!err}
              aria-describedby="url-hint" autoCapitalize="off" autoCorrect="off" spellCheck={false}
              onChange={e => { setUrl(e.target.value); setErr(null); setPasteMsg(null); }} />
            <button type="button" className="chip-btn" onClick={paste}><ClipboardPaste size={16} />붙여넣기</button>
          </div>
          <div id="url-hint" className="form-hint" aria-live="polite">
            {err ? <span className="err">{err}</span>
              : pasteMsg ? <span>{pasteMsg}</span>
              : fetchState === 'loading' ? <><Spinner size="sm" aria-label="가져오는 중" />{saveWhenReady ? '페이지 정보를 받는 대로 저장할게요' : '페이지 정보를 가져오는 중'}</>
              : fetchState === 'failed' ? <>페이지 정보를 가져오지 못했어요<button type="button" className="link-btn" onClick={() => void load(url, true)}><RotateCw size={14} />다시 시도</button></>
              : editing && normalized ? <button type="button" className="link-btn" onClick={() => void load(url, true)}><RotateCw size={14} />페이지 정보 다시 가져오기</button>
              : normalized && (image || fetchState === 'done') ? (
                <span className="fetch-preview">
                  <Block item={{kind: 'link', url: normalized, image, title, note, folderId: null, tags: [], starred: false, id: 'preview', createdAt: 0, updatedAt: 0, deletedAt: null}} />
                  {image ? '글 이미지를 아이콘으로 써요' : '사이트 로고를 아이콘으로 써요'}
                </span>
              ) : null}
          </div>
        </div>
      )}

      <div className="form-group">
        <textarea ref={noteRef} className="note-input" value={note} rows={kind === 'link' ? 2 : 5} aria-label={kind === 'link' ? '내용' : '메모'}
          placeholder={kind === 'link' ? '내용 (페이지 소개문이 자동으로 들어가요)' : '메모'}
          onChange={e => { setNote(e.target.value); touched.current.note = true; setErr(null); }} />
        {kind === 'memo' && err && <p className="form-hint"><span className="err">{err}</span></p>}
      </div>

      <div className="form-group rows">
        <FolderRow folders={folders} value={folderId} onChange={setFolderId} />
        <TagInput value={tags} onChange={setTags} suggestions={allTags} sourceUrl={normalized ?? undefined} siteName={siteName} />
      </div>
    </form>
  );
}
