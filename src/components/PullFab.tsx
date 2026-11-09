import {useEffect, useRef, useState, type CSSProperties} from 'react';
import {ClipboardPaste, Plus} from 'lucide-react';
import {haptic, hapticRumble, hapticTap} from '../lib/motion';

/** 이만큼 끌어올리면 놓았을 때 클립보드 링크를 추가한다 (화면에 보이는 거리, px) */
const ARM = 84;
/** 끌수록 무거워지는 고무줄: 끌어올린 거리 → 보이는 거리 (최대 150px) */
const rubber = (raw: number) => 150 * (1 - Math.exp(-raw / 150));

type Phase = 'idle' | 'drag' | 'armed' | 'release' | 'launch';

/**
 * 추가 버튼. 누르면 onTap, 위로 끌어올렸다 놓으면 onPull.
 * 끄는 동안 버튼이 같은 두께로 위로 길어지고(리퀴드 글래스), 놓으면 튕기며 돌아온다.
 * onPull 은 손을 떼는 바로 그 이벤트 안에서 부른다 (iOS 클립보드 읽기 조건).
 */
export function PullFab({onTap, onPull}: {onTap: () => void; onPull: () => void}) {
  const wrap = useRef<HTMLDivElement>(null);
  const btn = useRef<HTMLButtonElement>(null);
  const g = useRef({active: false, pointerId: -1, type: '', y0: 0, d: 0, dragging: false, armed: false, done: false});
  const [phase, setPhase] = useState<Phase>('idle');
  /** 닿아 있는 동안 젤리처럼 퍼지고, 떼면 출렁이며 돌아온다 */
  const [press, setPress] = useState<'' | 'down' | 'jelly'>('');
  const reduced = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

  const setPull = (d: number) => {
    const el = wrap.current;
    if (!el) return;
    const shown = reduced ? 0 : d;
    el.style.setProperty('--pull', `${shown}px`);
    el.style.setProperty('--p', String(shown / 150));
  };

  const finish = (cancelled = false) => {
    const s = g.current;
    if (!s.active || s.done) return;
    s.done = true;
    s.active = false;
    setPress('jelly');
    window.setTimeout(() => setPress(p => (p === 'jelly' ? '' : p)), 560);
    if (!cancelled) hapticRumble();
    if (cancelled) {
      setPhase('release');
    } else if (!s.dragging) {
      onTap();
      setPhase('idle');
    } else if (s.armed) {
      onPull();
      setPhase('launch');
    } else {
      setPhase('release');
    }
    setPull(0);
    window.setTimeout(() => setPhase(p => (p === 'release' || p === 'launch' ? 'idle' : p)), 620);
  };

  // 터치는 touchend 에서 마무리해야 iOS 가 클립보드 읽기를 사용자 동작으로 인정한다
  useEffect(() => {
    const el = btn.current;
    if (!el) return;
    const end = () => finish();
    const cancel = () => finish(true);
    el.addEventListener('touchend', end);
    el.addEventListener('touchcancel', cancel);
    return () => {
      el.removeEventListener('touchend', end);
      el.removeEventListener('touchcancel', cancel);
    };
  });

  return (
    <div ref={wrap} className="pull-fab" data-phase={phase} data-press={press || undefined} style={{['--pull']: '0px', ['--p']: '0'} as CSSProperties}>
      <span className="pull-hint" aria-hidden="true">{phase === 'armed' ? '놓으면 복사한 링크 추가' : '위로 끌어 올리면 바로 추가'}</span>
      <button
        ref={btn}
        type="button"
        className="fab"
        aria-label="추가"
        aria-describedby="pull-fab-tip"
        onPointerDown={e => {
          if (e.button !== 0) return;
          e.currentTarget.setPointerCapture(e.pointerId);
          hapticTap();
          setPress('down');
          g.current = {active: true, pointerId: e.pointerId, type: e.pointerType, y0: e.clientY, d: 0, dragging: false, armed: false, done: false};
        }}
        onPointerMove={e => {
          const s = g.current;
          if (!s.active || e.pointerId !== s.pointerId) return;
          const raw = Math.max(0, s.y0 - e.clientY);
          if (!s.dragging && raw > 8) { s.dragging = true; setPhase('drag'); }
          if (!s.dragging) return;
          s.d = rubber(raw);
          setPull(s.d);
          const armed = s.d >= ARM;
          if (armed !== s.armed) {
            s.armed = armed;
            if (armed) haptic(8);
            setPhase(armed ? 'armed' : 'drag');
          }
        }}
        onPointerUp={e => { if (g.current.type !== 'touch' && e.pointerId === g.current.pointerId) finish(); }}
        onPointerCancel={() => { if (g.current.type !== 'touch') finish(true); }}
        // 키보드(Enter/Space)로 누른 경우만 click 으로 처리. 터치·마우스는 위에서 처리한다
        onClick={e => { if (e.detail === 0) onTap(); }}
        onContextMenu={e => e.preventDefault()}
      >
        <span className="fab-icons">
          <Plus className={phase === 'armed' || phase === 'launch' ? 'off' : ''} strokeWidth={2.4} />
          <ClipboardPaste className={phase === 'armed' || phase === 'launch' ? '' : 'off'} strokeWidth={2.2} />
        </span>
      </button>
      <span id="pull-fab-tip" className="sr">누르면 새 항목, 위로 끌어 올렸다 놓으면 복사한 링크를 바로 추가해요</span>
    </div>
  );
}
