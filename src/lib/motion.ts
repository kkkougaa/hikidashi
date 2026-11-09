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

/**
 * iOS 사파리(18+)는 진동 API 가 없지만, 스위치(<input switch>)를 누르면 시스템이 톡 하고 진동한다.
 * 화면 밖에 숨긴 스위치를 눌러 그 진동을 빌린다. 사용자가 누르는 그 순간에만 된다.
 */
let iosSwitch: HTMLLabelElement | null = null;
function iosTick() {
  if (!iosSwitch) {
    const label = document.createElement('label');
    label.setAttribute('aria-hidden', 'true');
    label.style.cssText = 'position:fixed;left:-9999px;top:0;width:1px;height:1px;overflow:hidden;opacity:0;pointer-events:none';
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.tabIndex = -1;
    input.setAttribute('switch', '');
    label.appendChild(input);
    document.body.appendChild(label);
    iosSwitch = label;
  }
  iosSwitch.click();
}
const isIOS = () => /iP(hone|ad|od)/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

/** 추가 버튼에 닿는 순간: 짧게 톡 */
export function hapticTap() {
  try {
    if (navigator.vibrate) navigator.vibrate(8);
    else if (isIOS()) iosTick();
  } catch { /* 무시 */ }
}

/** 추가 버튼을 뗄 때: 위이잉 (세졌다가 잦아드는 진동). iOS 웹은 톡 한 번 */
export function hapticRumble() {
  try {
    if (navigator.vibrate) navigator.vibrate([14, 16, 24, 12, 34, 10, 12]);
    else if (isIOS()) iosTick();
  } catch { /* 무시 */ }
}

/** 안드로이드에서만 짧게 진동 (iOS 웹은 지원하지 않아 아무 일도 없다) */
export function haptic(ms = 10) {
  try {
    navigator.vibrate?.(ms);
  } catch { /* 무시 */ }
}
