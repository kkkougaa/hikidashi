import {useId, useRef, useState, type KeyboardEvent} from 'react';
import {Plus, X} from 'lucide-react';
import {SourceChip} from './bits';

/** 스페이스·쉼표·줄바꿈이 오면 그 앞까지를 태그로 만든다 */
const SEP = /[\s,，]+/;
const norm = (t: string) => t.trim().replace(/^#+/, '').trim();

export function TagInput({value, onChange, suggestions, sourceUrl, siteName}: {
  value: string[];
  onChange: (tags: string[]) => void;
  /** 이미 쓰고 있는 태그들 (자주 쓴 순) */
  suggestions: string[];
  /** 링크면 맨 앞에 출처 칩을 보여 준다 */
  sourceUrl?: string;
  siteName?: string;
}) {
  const id = useId();
  const [text, setText] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  const add = (raw: string[]) => {
    const next = [...value];
    for (const r of raw) {
      const t = norm(r);
      if (t && !next.includes(t)) next.push(t);
    }
    if (next.length !== value.length) onChange(next);
  };
  const remove = (t: string) => onChange(value.filter(v => v !== t));

  // 모바일 키보드는 keydown 대신 입력값으로 스페이스가 들어오므로 값에서 나눈다
  const onText = (v: string) => {
    if (SEP.test(v)) {
      const parts = v.split(SEP);
      const rest = parts.pop() ?? '';
      add(parts);
      setText(rest);
    } else {
      setText(v);
    }
  };
  const onKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.nativeEvent.isComposing) return;
    if (e.key === 'Enter') {
      if (text.trim()) { e.preventDefault(); add([text]); setText(''); }
    } else if (e.key === 'Backspace' && !text && value.length) {
      e.preventDefault();
      remove(value[value.length - 1]);
    }
  };

  const q = norm(text).toLowerCase();
  const picks = suggestions.filter(s => !value.includes(s) && (!q || s.toLowerCase().includes(q))).slice(0, 8);
  const isNew = q && !suggestions.some(s => s.toLowerCase() === q) && !value.includes(norm(text));

  return (
    <div className="tag-field">
      <label className="tag-label" htmlFor={id}>태그</label>
      <div className="tag-box" onClick={() => inputRef.current?.focus()}>
        {sourceUrl && <SourceChip url={sourceUrl} siteName={siteName} />}
        {value.map(t => (
          <span key={t} className="tag-chip">
            #{t}
            <button type="button" aria-label={`${t} 태그 빼기`} onClick={e => { e.stopPropagation(); remove(t); }}><X size={14} strokeWidth={2.2} /></button>
          </span>
        ))}
        <input
          ref={inputRef} id={id} value={text} enterKeyHint="done" autoCapitalize="off" autoCorrect="off" spellCheck={false}
          placeholder={value.length ? '' : '태그 입력 후 스페이스'}
          onChange={e => onText(e.target.value)} onKeyDown={onKeyDown}
          onBlur={() => { if (text.trim()) { add([text]); setText(''); } }}
        />
      </div>
      {(picks.length > 0 || isNew) && (
        <div className="tag-suggest" aria-label="태그 추천">
          {isNew && (
            <button type="button" className="tag-suggest-chip new" onMouseDown={e => e.preventDefault()} onClick={() => { add([text]); setText(''); }}>
              <Plus size={14} strokeWidth={2.2} />새 태그 #{norm(text)}
            </button>
          )}
          {picks.map(s => (
            <button key={s} type="button" className="tag-suggest-chip" onMouseDown={e => e.preventDefault()} onClick={() => { add([s]); setText(''); inputRef.current?.focus(); }}>#{s}</button>
          ))}
        </div>
      )}
    </div>
  );
}
