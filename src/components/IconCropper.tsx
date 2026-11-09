import {useEffect, useRef, useState} from 'react';
import {ZoomIn, ZoomOut} from 'lucide-react';

/** 잘라 낸 아이콘 크기 (px). 동기화 파일에 그대로 들어가서 작게 둔다 */
export const ICON_SIZE = 192;

/**
 * 고른 사진을 정사각형으로 잘라 아이콘으로 쓴다.
 * 끌어서 옮기고, 두 손가락(또는 휠·막대)으로 키운다. 결과는 작은 data URL.
 */
export function IconCropper({file, onDone, onCancel}: {file: File; onDone: (dataUrl: string) => void; onCancel: () => void}) {
  const [src, setSrc] = useState<string | null>(null);
  const [nat, setNat] = useState<{w: number; h: number} | null>(null);
  const [view, setView] = useState({zoom: 1, x: 0, y: 0});
  const box = useRef<HTMLDivElement>(null);
  const pts = useRef(new Map<number, {x: number; y: number}>());
  const pinch = useRef<{d: number; zoom: number} | null>(null);
  const SIZE = 260;

  useEffect(() => {
    const u = URL.createObjectURL(file);
    setSrc(u);
    return () => URL.revokeObjectURL(u);
  }, [file]);

  // 짧은 변이 틀을 꽉 채우는 배율이 1배
  const base = nat ? SIZE / Math.min(nat.w, nat.h) : 1;
  const clamp = (v: {zoom: number; x: number; y: number}) => {
    if (!nat) return v;
    const zoom = Math.min(6, Math.max(1, v.zoom));
    const w = nat.w * base * zoom, h = nat.h * base * zoom;
    const mx = (w - SIZE) / 2, my = (h - SIZE) / 2;
    return {zoom, x: Math.min(mx, Math.max(-mx, v.x)), y: Math.min(my, Math.max(-my, v.y))};
  };
  const set = (f: (v: typeof view) => typeof view) => setView(v => clamp(f(v)));

  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const wheel = (e: WheelEvent) => { e.preventDefault(); set(v => ({...v, zoom: v.zoom * Math.exp(-e.deltaY / 400)})); };
    el.addEventListener('wheel', wheel, {passive: false});
    return () => el.removeEventListener('wheel', wheel);
  });

  const down = (e: React.PointerEvent) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    pts.current.set(e.pointerId, {x: e.clientX, y: e.clientY});
    if (pts.current.size === 2) {
      const [a, b] = [...pts.current.values()];
      pinch.current = {d: Math.hypot(a.x - b.x, a.y - b.y), zoom: view.zoom};
    }
  };
  const move = (e: React.PointerEvent) => {
    const prev = pts.current.get(e.pointerId);
    if (!prev) return;
    const cur = {x: e.clientX, y: e.clientY};
    pts.current.set(e.pointerId, cur);
    if (pts.current.size === 2 && pinch.current) {
      const [a, b] = [...pts.current.values()];
      const z = pinch.current.zoom * (Math.hypot(a.x - b.x, a.y - b.y) / pinch.current.d);
      set(v => ({...v, zoom: z}));
    } else if (pts.current.size === 1) {
      set(v => ({...v, x: v.x + cur.x - prev.x, y: v.y + cur.y - prev.y}));
    }
  };
  const up = (e: React.PointerEvent) => {
    pts.current.delete(e.pointerId);
    if (pts.current.size < 2) pinch.current = null;
  };
  const key = (e: React.KeyboardEvent) => {
    const step = e.shiftKey ? 30 : 8;
    const m: Record<string, (v: typeof view) => typeof view> = {
      ArrowLeft: v => ({...v, x: v.x + step}), ArrowRight: v => ({...v, x: v.x - step}),
      ArrowUp: v => ({...v, y: v.y + step}), ArrowDown: v => ({...v, y: v.y - step}),
      '+': v => ({...v, zoom: v.zoom * 1.15}), '=': v => ({...v, zoom: v.zoom * 1.15}), '-': v => ({...v, zoom: v.zoom / 1.15}),
    };
    if (m[e.key]) { e.preventDefault(); set(m[e.key]); }
  };

  const apply = (img: HTMLImageElement) => {
    if (!nat) return;
    const c = document.createElement('canvas');
    c.width = c.height = ICON_SIZE;
    const ctx = c.getContext('2d')!;
    const scale = base * view.zoom;
    // 틀 가운데 기준으로 원본에서 잘라 낼 영역
    const side = SIZE / scale;
    const sx = nat.w / 2 - view.x / scale - side / 2;
    const sy = nat.h / 2 - view.y / scale - side / 2;
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(img, sx, sy, side, side, 0, 0, ICON_SIZE, ICON_SIZE);
    const webp = c.toDataURL('image/webp', 0.85);
    onDone(webp.startsWith('data:image/webp') ? webp : c.toDataURL('image/jpeg', 0.85));
  };
  const imgRef = useRef<HTMLImageElement>(null);

  return (
    <div className="cropper">
      <div ref={box} className="crop-box" style={{width: SIZE, height: SIZE}} tabIndex={0} role="application"
        aria-label="아이콘 자르기. 화살표로 옮기고 + − 로 키우거나 줄여요"
        onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up} onKeyDown={key}>
        {src && (
          <img ref={imgRef} src={src} alt="" draggable={false}
            onLoad={e => { const i = e.currentTarget; setNat({w: i.naturalWidth, h: i.naturalHeight}); setView({zoom: 1, x: 0, y: 0}); }}
            style={nat ? {width: nat.w * base * view.zoom, height: nat.h * base * view.zoom, translate: `calc(-50% + ${view.x}px) calc(-50% + ${view.y}px)`} : {opacity: 0}} />
        )}
        <span className="crop-mask" aria-hidden="true" />
      </div>
      <div className="crop-zoom">
        <ZoomOut size={18} aria-hidden="true" />
        <input type="range" min={1} max={6} step={0.01} value={view.zoom} aria-label="확대"
          onChange={e => set(v => ({...v, zoom: Number(e.target.value)}))} />
        <ZoomIn size={18} aria-hidden="true" />
      </div>
      <div className="crop-actions">
        <button type="button" className="chip-btn" onClick={onCancel}>취소</button>
        <button type="button" className="chip-btn primary" disabled={!nat} onClick={() => imgRef.current && apply(imgRef.current)}>이 부분으로 쓰기</button>
      </div>
    </div>
  );
}
