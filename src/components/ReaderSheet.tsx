import {useEffect, useState} from 'react';
import {Check, Compass, Copy, Highlighter, Share2, Type} from 'lucide-react';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {MoreMenu} from '@astryxdesign/core/MoreMenu';
import {Spinner} from '@astryxdesign/core/Spinner';
import {getArticle, putArticle} from '../data/db';
import type {Item} from '../data/types';
import {fetchArticle, minutes, textOf, type Article, type ReaderBlock} from '../lib/reader';
import {usePref} from '../lib/prefs';
import {SheetBar, SourceChip} from './bits';
import {nameOf} from './ItemViews';

/** 한 번 받은 본문은 기기(IndexedDB)에 저장해 둔다. 원본이 사라져도, 인터넷이 없어도 읽게 */
export async function loadArticle(item: Item): Promise<Article | null> {
  const saved = await getArticle(item.id).catch(() => undefined);
  if (saved) return saved;
  if (!item.url) return null;
  const a = await fetchArticle(item.url);
  if (a) await putArticle(item.id, a).catch(() => {});
  return a;
}

const check = (on: boolean) => (on ? <Check size={16} aria-label="선택됨" /> : undefined);

const FONTS = {sans: 'var(--font-body, system-ui)', serif: '"Noto Serif KR", "Nanum Myeongjo", "AppleMyungjo", Georgia, serif', rounded: 'ui-rounded, "SF Pro Rounded", system-ui'} as const;

/** 리더 모드: 광고·메뉴 없이 본문만. 글꼴·크기·줄 간격, 문단 형광펜 */
export function ReaderSheet({item, onClose, onHighlight, notify}: {
  item: Item | null;
  onClose: () => void;
  onHighlight: (i: Item, text: string) => void;
  notify: (msg: string) => void;
}) {
  const [article, setArticle] = useState<Article | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'failed'>('loading');
  const [active, setActive] = useState<number | null>(null);
  const [font, setFont] = usePref('readerFont');
  const [size, setSize] = usePref('readerSize');
  const [spacing, setSpacing] = usePref('readerSpacing');
  const id = item?.id;

  useEffect(() => {
    if (!item) return;
    let alive = true;
    setArticle(null); setState('loading'); setActive(null);
    void loadArticle(item).then(a => {
      if (!alive) return;
      setArticle(a);
      setState(a ? 'ready' : 'failed');
    });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  const openOriginal = () => { if (item?.url) window.open(item.url, '_blank', 'noopener'); };
  const highlights = item?.highlights ?? [];

  const block = (b: ReaderBlock, n: number) => {
    const text = textOf(b);
    const on = text != null && highlights.includes(text);
    const inner = (() => {
      switch (b.t) {
        case 'h': return b.level <= 2 ? <h2>{b.text}</h2> : <h3>{b.text}</h3>;
        case 'p': return <p>{b.text}</p>;
        case 'q': return <blockquote>{b.text}</blockquote>;
        case 'li': return <p className="li">{b.text}</p>;
        case 'code': return <pre><code>{b.text}</code></pre>;
        case 'img': return <ReaderImage src={b.src} />;
      }
    })();
    if (text == null) return <div key={n}>{inner}</div>;
    return (
      <div key={n} className="reader-block" data-on={on} data-active={active === n}>
        <div role="button" tabIndex={0} aria-expanded={active === n} onClick={() => setActive(a => (a === n ? null : n))}
          onKeyDown={e => { if (e.key === 'Enter') setActive(a => (a === n ? null : n)); }}>{inner}</div>
        {active === n && (
          <div className="reader-tools">
            <button type="button" onClick={() => { if (item) onHighlight(item, text); setActive(null); }}>
              <Highlighter size={16} aria-hidden="true" />{on ? '형광펜 지우기' : '형광펜 칠하기'}
            </button>
            <button type="button" onClick={() => { void navigator.clipboard?.writeText(text).then(() => notify('복사했어요')); setActive(null); }}>
              <Copy size={16} aria-hidden="true" />복사
            </button>
          </div>
        )}
      </div>
    );
  };

  return (
    <BottomSheet label={item?.title || '리더'} isOpen={!!item} onOpenChange={o => { if (!o) onClose(); }} height="tall">
      {item && (
        <div className="reader">
          <SheetBar onClose={onClose} closeLabel="리더 닫기" end={
            <div className="pill-group">
              <MoreMenu label="글자 설정" size="md" alignment="end" presentation="adaptive" icon={<Type size={19} />}
                items={[
                  {type: 'section', title: '글꼴', items: [
                    {label: '고딕', onClick: () => setFont('sans'), endContent: check(font === 'sans')},
                    {label: '명조', onClick: () => setFont('serif'), endContent: check(font === 'serif')},
                    {label: '둥근', onClick: () => setFont('rounded'), endContent: check(font === 'rounded')},
                  ]},
                  {type: 'section', title: `글자 크기 ${size}`, items: [
                    {label: '크게', onClick: () => setSize(Math.min(28, size + 2)), hasCloseOnSelect: false},
                    {label: '작게', onClick: () => setSize(Math.max(14, size - 2)), hasCloseOnSelect: false},
                  ]},
                  {type: 'section', title: '줄 간격', items: [
                    {label: '좁게', onClick: () => setSpacing(1.5), endContent: check(spacing === 1.5)},
                    {label: '보통', onClick: () => setSpacing(1.75), endContent: check(spacing === 1.75)},
                    {label: '넓게', onClick: () => setSpacing(2.1), endContent: check(spacing === 2.1)},
                  ]},
                ]} />
              {typeof navigator.share === 'function' && item.url && (
                <button type="button" className="pill-btn" aria-label="공유" onClick={() => void navigator.share({url: item.url, title: item.title}).catch(() => {})}><Share2 size={19} /></button>
              )}
              <button type="button" className="pill-btn" aria-label="원본 열기" onClick={openOriginal}><Compass size={19} /></button>
            </div>
          } />
          {state === 'loading' && <div className="loading"><Spinner size="lg" aria-label="본문 불러오는 중" /></div>}
          {state === 'failed' && (
            <div className="reader-failed">
              <p className="reader-failed-title">본문을 가져오지 못했어요</p>
              <p>로그인이 필요하거나 본문이 그림으로만 된 페이지일 수 있어요.</p>
              <button type="button" className="primary-btn" onClick={openOriginal}>원본 열기</button>
            </div>
          )}
          {article && (
            <article className="reader-body" style={{fontFamily: FONTS[font], fontSize: size, lineHeight: spacing}}>
              {item.url && <SourceChip url={item.url} siteName={item.siteName ?? article.siteName} />}
              <h1>{item.title || article.title || nameOf(item)}</h1>
              <p className="reader-meta">
                약 {minutes(article)}분
                {article.savedAt ? ' · 기기에 저장됨' : ''}
                {highlights.length ? ` · 형광펜 ${highlights.length}` : ''}
              </p>
              {item.brokenAt && <p className="reader-warn">원본 페이지가 열리지 않아요. 저장해 둔 본문이에요</p>}
              {(article.image ?? item.image) && <ReaderImage src={(article.image ?? item.image)!} />}
              {article.blocks.map(block)}
              <button type="button" className="secondary-btn" onClick={openOriginal}>원본 페이지에서 보기</button>
              <p className="reader-hint">문단을 누르면 형광펜을 칠할 수 있어요</p>
            </article>
          )}
        </div>
      )}
    </BottomSheet>
  );
}

function ReaderImage({src}: {src: string}) {
  const [broken, setBroken] = useState(false);
  if (broken) return null;
  return <img className="reader-img" src={src} alt="" loading="lazy" referrerPolicy="no-referrer" onError={() => setBroken(true)} />;
}
