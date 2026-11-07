import {Check} from 'lucide-react';

/** 자주 쓸 만한 이모지를 묶음별로. 모두 토스페이스 글꼴로 그린다 */
const GROUPS: {name: string; list: string[]}[] = [
  {name: '정리', list: ['📌', '📎', '🔖', '📚', '📖', '📝', '✏️', '💡', '⭐', '❤️', '🔥', '✅', '❗', '❓', '🎯', '🏷️']},
  {name: '생활', list: ['🛒', '🍳', '🍜', '🍕', '☕', '🍰', '🏠', '🧺', '💊', '💪', '🏃', '🧘', '🛏️', '🧹', '👕', '🐶']},
  {name: '여행', list: ['✈️', '🗺️', '🏖️', '🏔️', '🚗', '🚆', '🏨', '📷', '🎒', '🌏', '🍣', '🗼']},
  {name: '일·공부', list: ['💻', '📱', '🖥️', '💼', '📊', '📈', '🗂️', '📅', '⏰', '🎓', '🧠', '🔧', '⚙️', '🧪', '📮', '🗒️']},
  {name: '취미', list: ['🎵', '🎬', '🎮', '🎨', '📺', '🎧', '⚽', '🏀', '🎁', '🎉', '🧩', '🎸']},
  {name: '기분', list: ['😀', '😂', '🥹', '😍', '🤔', '😎', '🥳', '😴', '👍', '👀', '🙏', '✨']},
  {name: '자연·돈', list: ['🌱', '🌸', '🍀', '🌙', '☀️', '🌈', '🐱', '🐳', '💰', '💳', '🧾', '🏦']},
];

export function EmojiPicker({value, onChange, autoLabel}: {value?: string; onChange: (e: string | undefined) => void; autoLabel: string}) {
  return (
    <div className="emoji-picker">
      <button type="button" className="emoji-auto" aria-pressed={!value} onClick={() => onChange(undefined)}>
        {!value && <Check size={16} strokeWidth={2.4} aria-hidden="true" />}
        {autoLabel}
      </button>
      {GROUPS.map(g => (
        <div key={g.name} className="emoji-group" role="radiogroup" aria-label={g.name}>
          <p className="emoji-group-name">{g.name}</p>
          <div className="emoji-grid">
            {g.list.map(e => (
              <button key={e} type="button" role="radio" aria-checked={value === e} aria-label={e}
                className="emoji-cell tossface" onClick={() => onChange(value === e ? undefined : e)}>{e}</button>
            ))}
          </div>
        </div>
      ))}
      <p className="emoji-credit">이모지: 토스페이스 © Viva Republica</p>
    </div>
  );
}
