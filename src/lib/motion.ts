import {flushSync} from 'react-dom';

const reduced = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

interface VT {finished: Promise<void>; ready: Promise<void>; updateCallbackDone: Promise<void>}
type VTDocument = Document & {startViewTransition?: (cb: () => void) => VT};

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
    const vt = doc.startViewTransition(() => flushSync(update));
    // 전환이 건너뛰어지거나 시간이 넘어도 상태는 이미 바뀌었으니 오류로 올리지 않는다
    const quiet = () => {};
    vt.ready.catch(quiet);
    vt.finished.catch(quiet);
    vt.updateCallbackDone.catch(quiet);
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
