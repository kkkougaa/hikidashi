import {useState} from 'react';
import {ArrowDown, ArrowUp, Check, ChevronLeft, ChevronRight, Plus} from 'lucide-react';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {COLORS, COLOR_NAMES, type ColorKey, type Folder} from '../data/types';
import {orderedFolders} from '../data/folders';
import {ConfirmButton, cssVar, SheetHead} from './bits';

type Mode = {type: 'list'} | {type: 'edit'; folder: Folder | null};

export function FoldersSheet({isOpen, onClose, folders, counts, onAdd, onUpdate, onRemove, onReorder}: {
  isOpen: boolean;
  onClose: () => void;
  folders: Folder[];
  counts: Map<string, number>;
  onAdd: (name: string, color: ColorKey, parentId: string | null) => void;
  onUpdate: (id: string, patch: {name?: string; color?: ColorKey; parentId?: string | null}) => void;
  onRemove: (f: Folder) => void;
  onReorder: (ids: string[]) => void;
}) {
  const rows = orderedFolders(folders);
  const byId = new Map(folders.map(f => [f.id, f]));
  /** 같은 단계(같은 상위 서랍) 안에서만 위아래로 */
  const parentKey = (f: Folder) => (rows.find(r => r.folder.id === f.id)?.depth ? f.parentId ?? null : null);
  const siblingsOf = (f: Folder) => rows.filter(r => parentKey(r.folder) === parentKey(f)).map(r => r.folder);
  const move = (f: Folder, d: -1 | 1) => {
    const ids = siblingsOf(f).map(x => x.id);
    const i = ids.indexOf(f.id);
    const j = i + d;
    if (i < 0 || j < 0 || j >= ids.length) return;
    [ids[i], ids[j]] = [ids[j], ids[i]];
    onReorder(ids);
  };
  const [mode, setMode] = useState<Mode>({type: 'list'});
  const close = () => { setMode({type: 'list'}); onClose(); };
  return (
    <BottomSheet label="서랍 편집" isOpen={isOpen} onOpenChange={o => { if (!o) close(); }} purpose={mode.type === 'edit' ? 'form' : 'info'} height="hug">
      {mode.type === 'list' ? (
        <>
          <SheetHead title="서랍 편집" onClose={close} closeLabel="서랍 편집 닫기" />
          <div className="set-group">
            {rows.map(({folder: f, depth}) => {
              const sib = siblingsOf(f);
              const n = sib.findIndex(x => x.id === f.id);
              const color = depth && f.parentId ? byId.get(f.parentId)?.color ?? f.color : f.color;
              return (
                <div key={f.id} className="set-row split" data-depth={depth || undefined}>
                  <button type="button" className="split-main" onClick={() => setMode({type: 'edit', folder: f})}>
                    <span className="dot" data-sub={depth || undefined} style={cssVar(COLORS[color])} aria-hidden="true" />
                    <span className="grow">{f.name}</span>
                    <span className="val num">{counts.get(f.id) ?? 0}개</span>
                    <ChevronRight className="chev" size={18} aria-hidden="true" />
                  </button>
                  <button type="button" className="icon-btn" aria-label={`${f.name} 위로`} disabled={n <= 0} onClick={() => move(f, -1)}><ArrowUp size={17} /></button>
                  <button type="button" className="icon-btn" aria-label={`${f.name} 아래로`} disabled={n === sib.length - 1} onClick={() => move(f, 1)}><ArrowDown size={17} /></button>
                </div>
              );
            })}
            <button className="set-row" onClick={() => setMode({type: 'edit', folder: null})} style={{color: 'var(--color-text-accent)'}}>
              <Plus size={20} aria-hidden="true" />
              <span className="grow">새 서랍</span>
            </button>
          </div>
        </>
      ) : (
        <FolderForm
          key={mode.folder?.id ?? 'new'}
          folder={mode.folder}
          count={mode.folder ? counts.get(mode.folder.id) ?? 0 : 0}
          taken={folders.filter(f => f.id !== mode.folder?.id).map(f => f.name)}
          // 하위 서랍의 상위가 될 수 있는 건 위 단계 서랍만 (자기 자신, 하위 서랍이 있는 서랍은 하위로 못 감)
          parents={rows.filter(r => !r.depth && r.folder.id !== mode.folder?.id).map(r => r.folder)}
          hasChildren={!!mode.folder && folders.some(f => f.parentId === mode.folder!.id)}
          onBack={() => setMode({type: 'list'})}
          onSave={(name, color, parentId) => {
            const parent = parentId ? byId.get(parentId) : undefined;
            if (mode.folder) onUpdate(mode.folder.id, {name, color: parent?.color ?? color, parentId});
            else onAdd(name, color, parentId);
            setMode({type: 'list'});
          }}
          onRemove={() => { if (mode.folder) onRemove(mode.folder); setMode({type: 'list'}); }}
        />
      )}
    </BottomSheet>
  );
}

function FolderForm({folder, count, taken, parents, hasChildren, onBack, onSave, onRemove}: {
  folder: Folder | null; count: number; taken: string[]; parents: Folder[]; hasChildren: boolean;
  onBack: () => void; onSave: (name: string, color: ColorKey, parentId: string | null) => void; onRemove: () => void;
}) {
  const [name, setName] = useState(folder?.name ?? '');
  const [color, setColor] = useState<ColorKey>(folder?.color ?? 'blue');
  const [parentId, setParentId] = useState<string>(folder?.parentId && parents.some(p => p.id === folder.parentId) ? folder.parentId : '');
  const [err, setErr] = useState<string | null>(null);
  const submit = () => {
    const n = name.trim();
    if (!n) return setErr('서랍 이름을 적어주세요');
    if (taken.includes(n)) return setErr('같은 이름의 서랍이 이미 있어요');
    onSave(n, color, parentId || null);
  };
  return (
    <form noValidate onSubmit={e => { e.preventDefault(); submit(); }} className="sheet-form">
      <div className="sheet-bar">
        <button type="button" className="round-btn" aria-label="서랍 목록으로" onClick={onBack}><ChevronLeft strokeWidth={1.8} /></button>
        <div className="sheet-bar-center"><h2 className="sheet-title">{folder ? '서랍 수정' : '새 서랍'}</h2></div>
        <div className="sheet-bar-end"><ConfirmButton label={folder ? '변경 사항 저장' : '서랍 만들기'} /></div>
      </div>
      <input className="big-input" value={name} placeholder="서랍 이름" aria-label="이름" aria-invalid={!!err} aria-describedby="folder-err"
        onChange={e => { setName(e.target.value); setErr(null); }} />
      <p id="folder-err" className="form-hint" aria-live="polite">{err && <span className="err">{err}</span>}</p>
      {!hasChildren && parents.length > 0 && (
        <div className="form-group">
          <label className="form-row-label" htmlFor="parent-pick">상위 서랍</label>
          <select id="parent-pick" className="set-select wide" value={parentId} onChange={e => setParentId(e.target.value)}>
            <option value="">없음 (맨 위)</option>
            {parents.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
          </select>
        </div>
      )}
      {!parentId && <div className="form-group">
        <p className="form-row-label" id="color-label">색</p>
        <div className="swatches" role="radiogroup" aria-labelledby="color-label">
          {(Object.keys(COLORS) as ColorKey[]).map(k => (
            <button key={k} type="button" role="radio" aria-checked={color === k} aria-label={COLOR_NAMES[k]}
              className="swatch" style={cssVar(COLORS[k])} onClick={() => setColor(k)}>
              {color === k && <Check strokeWidth={2.6} aria-hidden="true" />}
            </button>
          ))}
        </div>
      </div>}
      {folder && (
        <>
          <button type="button" className="danger-btn" onClick={onRemove}>서랍 삭제</button>
          {(count > 0 || hasChildren) && <p className="form-hint center">{hasChildren ? '하위 서랍도 같이 지워지고, ' : ''}안의 항목 {count}개는 미분류로 옮겨져요</p>}
        </>
      )}
    </form>
  );
}
