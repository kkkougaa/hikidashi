import {useEffect, useMemo, useState} from 'react';
import {Compass, Trash2} from 'lucide-react';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {Spinner} from '@astryxdesign/core/Spinner';
import {getOffline, type OfflinePack} from '../lib/offline';
import {stamp} from '../lib/format';
import type {ReaderBlock} from '../lib/reader';
import {RichText, SheetBar, SourceChip} from './bits';
import {nameOf} from './ItemViews';

/** 오프라인 보기: 받아 둔 그때 모습 그대로. 그림·영상은 기기에 받은 파일로 */
export function OfflineSheet({id, onClose, onRemove}: {id: string | null; onClose: () => void; onRemove: (id: string) => void}) {
  const [pack, setPack] = useState<OfflinePack | null | undefined>(undefined);
  useEffect(() => {
    if (!id) return;
    let alive = true;
    setPack(undefined);
    void getOffline(id).then(p => { if (alive) setPack(p ?? null); }, () => { if (alive) setPack(null); });
    return () => { alive = false; };
  }, [id]);

  // 받은 파일을 화면에 쓸 주소로 (닫으면 정리)
  const urls = useMemo(() => {
    const m = new Map<string, string>();
    if (pack) for (const [u, b] of Object.entries(pack.media)) m.set(u, URL.createObjectURL(b));
    return m;
  }, [pack]);
  useEffect(() => () => urls.forEach(u => URL.revokeObjectURL(u)), [urls]);
  const local = (u?: string) => (u ? urls.get(u) : undefined);

  const it = pack?.item;
  const a = pack?.article;
  const photos = it ? [...new Set([...(it.images ?? []), ...(it.image && !it.image.includes('profile_images') ? [it.image] : [])])].map(local).filter(Boolean) as string[] : [];
  const video = local(it?.video);

  const block = (b: ReaderBlock, n: number) => {
    switch (b.t) {
      case 'h': return b.level <= 2 ? <h2 key={n}>{b.text}</h2> : <h3 key={n}>{b.text}</h3>;
      case 'p': return <p key={n}>{b.text}</p>;
      case 'q': return <blockquote key={n}>{b.text}</blockquote>;
      case 'li': return <p key={n} className="li">{b.text}</p>;
      case 'code': return <pre key={n}><code>{b.text}</code></pre>;
      case 'img': { const s = local(b.src); return s ? <img key={n} className="reader-img" src={s} alt="" /> : null; }
    }
  };

  return (
    <BottomSheet label="오프라인 보기" isOpen={!!id} onOpenChange={o => { if (!o) onClose(); }} height="tall">
      {id && (
        <div className="reader">
          <SheetBar onClose={onClose} closeLabel="오프라인 보기 닫기" end={
            <div className="pill-group">
              {it?.url && <button type="button" className="pill-btn" aria-label="원본 열기" onClick={() => window.open(it.url, '_blank', 'noopener')}><Compass size={19} /></button>}
              <button type="button" className="pill-btn" aria-label="오프라인 저장 지우기" onClick={() => onRemove(id)}><Trash2 size={19} /></button>
            </div>
          } />
          {pack === undefined && <div className="loading"><Spinner size="lg" aria-label="불러오는 중" /></div>}
          {pack === null && <div className="reader-failed"><p className="reader-failed-title">오프라인 저장이 없어요</p></div>}
          {it && (
            <article className="reader-body offline-body">
              {it.url && <SourceChip url={it.url} siteName={it.siteName ?? a?.siteName} />}
              <h1>{it.title || a?.title || nameOf(it)}</h1>
              <p className="reader-meta">오프라인 저장 · {stamp(pack!.savedAt)}{pack!.failed ? ` · 받지 못한 그림·영상 ${pack!.failed}개` : ''}</p>
              {video && <video className="offline-video" src={video} controls playsInline poster={local(it.image)} />}
              {it.note && (it.kind === 'memo' ? <div className="memo-full"><RichText text={it.note} block /></div> : <p className="offline-note">{it.note}</p>)}
              {!video && photos.map(s => <img key={s} className="reader-img" src={s} alt="" />)}
              {a && (
                <>
                  {local(a.image) && !photos.includes(local(a.image)!) && <img className="reader-img" src={local(a.image)} alt="" />}
                  {a.blocks.map(block)}
                </>
              )}
            </article>
          )}
        </div>
      )}
    </BottomSheet>
  );
}
