import {useState} from 'react';
import {Check, ChevronLeft, ChevronRight, Plus} from 'lucide-react';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {COLORS, COLOR_NAMES, type ColorKey, type Folder} from '../data/types';
import {ConfirmButton, cssVar, SheetHead} from './bits';

type Mode = {type: 'list'} | {type: 'edit'; folder: Folder | null};

export function FoldersSheet({isOpen, onClose, folders, counts, onAdd, onUpdate, onRemove}: {
  isOpen: boolean;
  onClose: () => void;
  folders: Folder[];
  counts: Map<string, number>;
  onAdd: (name: string, color: ColorKey) => void;
  onUpdate: (id: string, patch: {name?: string; color?: ColorKey}) => void;
  onRemove: (f: Folder) => void;
}) {
  const [mode, setMode] = useState<Mode>({type: 'list'});
  const close = () => { setMode({type: 'list'}); onClose(); };
  return (
    <BottomSheet label="서랍 편집" isOpen={isOpen} onOpenChange={o => { if (!o) close(); }} purpose={mode.type === 'edit' ? 'form' : 'info'} height="hug">
      {mode.type === 'list' ? (
        <>
          <SheetHead title="서랍 편집" onClose={close} closeLabel="서랍 편집 닫기" />
          <div className="set-group">
            {folders.map(f => (
              <button key={f.id} className="set-row" onClick={() => setMode({type: 'edit', folder: f})}>
                <span className="dot" style={cssVar(COLORS[f.color])} aria-hidden="true" />
                <span className="grow">{f.name}</span>
                <span className="val num">{counts.get(f.id) ?? 0}개</span>
                <ChevronRight className="chev" size={18} aria-hidden="true" />
              </button>
            ))}
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
          onBack={() => setMode({type: 'list'})}
          onSave={(name, color) => {
            if (mode.folder) onUpdate(mode.folder.id, {name, color});
            else onAdd(name, color);
            setMode({type: 'list'});
          }}
          onRemove={() => { if (mode.folder) onRemove(mode.folder); setMode({type: 'list'}); }}
        />
      )}
    </BottomSheet>
  );
}

function FolderForm({folder, count, taken, onBack, onSave, onRemove}: {
  folder: Folder | null; count: number; taken: string[]; onBack: () => void; onSave: (name: string, color: ColorKey) => void; onRemove: () => void;
}) {
  const [name, setName] = useState(folder?.name ?? '');
  const [color, setColor] = useState<ColorKey>(folder?.color ?? 'blue');
  const [err, setErr] = useState<string | null>(null);
  const submit = () => {
    const n = name.trim();
    if (!n) return setErr('서랍 이름을 적어주세요');
    if (taken.includes(n)) return setErr('같은 이름의 서랍이 이미 있어요');
    onSave(n, color);
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
      <div className="form-group">
        <p className="form-row-label" id="color-label">색</p>
        <div className="swatches" role="radiogroup" aria-labelledby="color-label">
          {(Object.keys(COLORS) as ColorKey[]).map(k => (
            <button key={k} type="button" role="radio" aria-checked={color === k} aria-label={COLOR_NAMES[k]}
              className="swatch" style={cssVar(COLORS[k])} onClick={() => setColor(k)}>
              {color === k && <Check strokeWidth={2.6} aria-hidden="true" />}
            </button>
          ))}
        </div>
      </div>
      {folder && (
        <>
          <button type="button" className="danger-btn" onClick={onRemove}>서랍 삭제</button>
          {count > 0 && <p className="form-hint center">안의 항목 {count}개는 미분류로 옮겨져요</p>}
        </>
      )}
    </form>
  );
}
