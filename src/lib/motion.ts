import {flushSync} from 'react-dom';

const reduced = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

type VTDocument = Document & {startViewTransition?: (cb: () => void) => {finished: Promise<void>}};

/**
 * 화면이 바뀌는 상태 변경을 View Transitions 로 감싼다.
 * 지원하지 않는 브라우저나 "동작 줄이기" 설정에서는 그냥 바로 바꾼다.
 */
export function animate(update: () => void) {
  const doc = document as VTDocument;
  if (!doc.startViewTransition || reduced() || document.visibilityState !== 'visible') {
    update();
    return;
  }
  try {
    doc.startViewTransition(() => flushSync(update));
  } catch {
    update();
  }
}

/** 시트가 닫히는 동안 기다렸다가 목록 변화를 보여 준다 */
export function afterSheet(update: () => void, ms = 260) {
  setTimeout(() => animate(update), reduced() ? 0 : ms);
}

/** 안드로이드에서만 짧게 진동 (iOS 웹은 지원하지 않아 아무 일도 없다) */
export function haptic(ms = 10) {
  try {
    navigator.vibrate?.(ms);
  } catch { /* 무시 */ }
}
