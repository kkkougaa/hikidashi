import {useEffect, useMemo, useRef, useState} from 'react';
import {flushSync} from 'react-dom';
import {Hash, Inbox, LayoutGrid, Menu, Rows3, Search, Settings, SlidersHorizontal, Star, Tray} from './icons';
import {SegmentedControl, SegmentedControlItem} from '@astryxdesign/core/SegmentedControl';
import {afterSheet, animate, haptic} from './lib/motion';
import {MobileNav} from '@astryxdesign/core/MobileNav';
import {SideNavItem, SideNavSection} from '@astryxdesign/core/SideNav';
import {TextInput} from '@astryxdesign/core/TextInput';
import {EmptyState} from '@astryxdesign/core/EmptyState';
import {Button} from '@astryxdesign/core/Button';
import {Spinner} from '@astryxdesign/core/Spinner';
import {Text} from '@astryxdesign/core/Text';
import {useToast} from '@astryxdesign/core/Toast';
import {uid, useLibrary} from './data/library';
import {COLORS, type Folder, type Item, type ItemDraft} from './data/types';
import {domainOf, findUrl, guessTitle, normalizeUrl} from './lib/format';
import {cssVar} from './components/bits';
import {CardGrid, DayList, type ItemActions} from './components/ItemViews';
import {ItemSheet} from './components/ItemSheet';
import {MemoSheet} from './components/MemoSheet';
import {FoldersSheet} from './components/FoldersSheet';
import {SettingsSheet} from './components/SettingsSheet';
import {PullFab} from './components/PullFab';
import {fetchPageInfo} from './lib/pageInfo';

/** 보고 있는 범위: 전체, 즐겨찾기, 미분류, 특정 서랍, 특정 태그 */
type Scope = {type: 'all'} | {type: 'star'} | {type: 'none'} | {type: 'folder'; id: string} | {type: 'tag'; tag: string};
const VIEW_KEY = 'hikidashi-view';

const dotIcon = (color: string) => {
  const Dot = () => <span className="nav-dot" aria-hidden="true"><span className="dot" style={cssVar(color)} /></span>;
  return Dot;
};

/** 공유 메뉴(안드로이드)나 ?url= 로 들어온 값을 읽는다 */
function readShared(): Partial<ItemDraft> | null {
  const p = new URLSearchParams(location.search);
  const url = p.get('url'), text = p.get('text'), title = p.get('title');
  if (!url && !text && !title) return null;
  const found = (url && normalizeUrl(url)) || findUrl(text ?? '');
  history.replaceState(null, '', location.pathname);
  if (found) {
    const note = (text ?? '').replace(found, '').trim();
    return {kind: 'link', url: found, title: title?.trim() || '', note};
  }
  return {kind: 'memo', title: title?.trim() || '', note: (text ?? '').trim()};
}

export function App() {
  const lib = useLibrary();
  const toast = useToast();
  const [scope, setScope] = useState<Scope>({type: 'all'});
  const [q, setQ] = useState('');
  const [searching, setSearching] = useState(false);
  const [view, setView] = useState<'list' | 'card'>(() => { try { return localStorage.getItem(VIEW_KEY) === 'card' ? 'card' : 'list'; } catch { return 'list'; } });
  const [navOpen, setNavOpen] = useState(false);
  const [sheet, setSheet] = useState<null | 'item' | 'folders' | 'settings'>(null);
  const [editing, setEditing] = useState<Item | null>(null);
  const [prefill, setPrefill] = useState<Partial<ItemDraft> | undefined>();
  const [memo, setMemo] = useState<Item | null>(null);
  const searchRef = useRef<HTMLDivElement>(null);
  const scrollRef = useRef<HTMLElement>(null);
  const [scrolled, setScrolled] = useState(false);
  const toTop = (smooth = true) => scrollRef.current?.scrollTo({top: 0, behavior: smooth ? 'smooth' : 'auto'});

  useEffect(() => { try { localStorage.setItem(VIEW_KEY, view); } catch { /* 저장 못 해도 동작엔 지장 없음 */ } }, [view]);
  useEffect(() => {
    if (!lib.ready) return;
    const shared = readShared();
    if (shared) { setPrefill(shared); setEditing(null); setSheet('item'); }
  }, [lib.ready]);

  // 즐겨찾기처럼 시트를 연 채로 바뀐 값을 바로 보여 주려고 최신 항목을 다시 찾는다
  const memoLive = memo ? lib.items.find(i => i.id === memo.id) ?? null : null;
  const folderMap = useMemo(() => new Map(lib.folders.map(f => [f.id, f])), [lib.folders]);
  // 지워진 서랍을 보고 있었다면 전체로
  useEffect(() => { if (scope.type === 'folder' && lib.ready && !folderMap.has(scope.id)) setScope({type: 'all'}); }, [scope, folderMap, lib.ready]);

  const counts = useMemo(() => {
    const m = new Map<string, number>();
    for (const i of lib.items) if (i.folderId) m.set(i.folderId, (m.get(i.folderId) ?? 0) + 1);
    return m;
  }, [lib.items]);
  const tags = useMemo(() => {
    const m = new Map<string, number>();
    for (const i of lib.items) for (const t of i.tags) m.set(t, (m.get(t) ?? 0) + 1);
    return [...m.entries()].sort((a, b) => a[0].localeCompare(b[0], 'ko'));
  }, [lib.items]);
  // 태그 추천: 자주 쓴 순
  const allTags = useMemo(() => [...tags].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'ko')).map(([t]) => t), [tags]);
  const unfiled = useMemo(() => lib.items.filter(i => !i.folderId || !folderMap.has(i.folderId)).length, [lib.items, folderMap]);

  const inScope = (i: Item) => {
    switch (scope.type) {
      case 'all': return true;
      case 'star': return i.starred;
      case 'none': return !i.folderId || !folderMap.has(i.folderId);
      case 'folder': return i.folderId === scope.id;
      case 'tag': return i.tags.includes(scope.tag);
    }
  };
  const query = q.trim().toLowerCase();
  const list = lib.items.filter(i => inScope(i) && (!query || [i.title, i.note, i.url, domainOf(i.url), i.tags.join(' ')].join(' ').toLowerCase().includes(query)));
  const title = scope.type === 'all' ? '전체' : scope.type === 'star' ? '즐겨찾기' : scope.type === 'none' ? '미분류'
    : scope.type === 'tag' ? `#${scope.tag}` : folderMap.get(scope.id)?.name ?? '서랍';
  const showFolder = scope.type !== 'folder';

  const notify = (body: string, type: 'info' | 'error' = 'info') => toast({body, type, uniqueID: 'notice'});
  /** 범위를 바꾼다. 같은 탭을 다시 누르면 맨 위로 */
  const goto = (s: Scope) => {
    if (JSON.stringify(s) === JSON.stringify(scope)) return toTop();
    animate(() => setScope(s));
    toTop(false);
  };
  const pick = (s: Scope) => { setNavOpen(false); goto(s); };
  // iOS 는 사용자가 누른 그 순간에 포커스해야 키보드가 올라와서 동기로 처리한다
  const toggleSearch = () => {
    if (searching) { setQ(''); setSearching(false); searchRef.current?.querySelector('input')?.blur(); return; }
    flushSync(() => setSearching(true));
    searchRef.current?.querySelector('input')?.focus({preventScroll: true});
    toTop();
  };
  const changeView = (v: 'list' | 'card') => { if (v !== view) animate(() => setView(v)); };
  const openAdd = () => { setEditing(null); setPrefill(undefined); setSheet('item'); };

  // 링크 정보를 가져오는 중인 항목 (목록에 작은 회전 표시)
  const [loadingIds, setLoadingIds] = useState<Set<string>>(() => new Set());
  const setLoading = (id: string, on: boolean) => setLoadingIds(prev => {
    const next = new Set(prev);
    if (on) next.add(id); else next.delete(id);
    return next;
  });

  /** + 버튼을 끌어올렸다 놓으면: 복사한 링크를 바로 추가하고 정보는 뒤이어 채운다 */
  const quickAdd = () => {
    // 손을 뗀 그 이벤트 안에서 바로 읽어야 iOS 가 허락한다
    const reading = navigator.clipboard?.readText?.();
    if (!reading) return notify('이 브라우저는 클립보드를 읽을 수 없어요. + 를 눌러 붙여넣어 주세요', 'error');
    reading.then(async text => {
      const u = normalizeUrl(text.trim()) ?? findUrl(text);
      if (!u) return notify('복사한 링크가 없어요. 링크를 복사한 뒤 다시 해보세요');
      const current = lib.allRecords().items.filter(i => !i.deletedAt);
      if (current.some(i => i.url === u)) return notify('이미 저장한 링크예요');
      toTop();
      // 화면 전환 애니메이션은 추가를 한 박자 늦게 실행하므로 id 를 먼저 정해 둔다
      const item = {id: uid()};
      setLoading(item.id, true);
      animate(() => lib.addItem({kind: 'link', url: u, title: '', note: '', folderId: defaultFolderId, tags: []}, item.id));
      const dismiss = toast({
        body: '복사한 링크를 추가했어요', uniqueID: 'undo', isAutoHide: false,
        endContent: <Button label="되돌리기" variant="ghost" size="sm" onClick={() => { animate(() => lib.removeItem(item.id)); dismiss(); }} />,
      });
      const info = await fetchPageInfo(u);
      setLoading(item.id, false);
      const now = lib.allRecords().items.find(i => i.id === item.id);
      if (!now || now.deletedAt) return;
      // 그사이 사용자가 고친 칸은 건드리지 않는다
      const patch: Partial<ItemDraft> = {};
      if (info?.title && !now.title) patch.title = info.title;
      if (info?.description && !now.note) patch.note = info.description;
      if (info?.image && !now.image) patch.image = info.image;
      if (info?.siteName && !now.siteName) patch.siteName = info.siteName;
      if (!info && !now.title && !now.note) patch.title = guessTitle(u);
      if (Object.keys(patch).length) animate(() => lib.updateItem(item.id, patch));
    }, () => notify('클립보드를 읽지 못했어요. 붙여넣기를 허용하거나 + 를 눌러 추가해주세요', 'error'));
  };

  const act: ItemActions = {
    open: i => setMemo(i),
    edit: i => { setMemo(null); setEditing(i); setPrefill(undefined); setSheet('item'); },
    toggleStar: i => { haptic(); animate(() => lib.updateItem(i.id, {starred: !i.starred})); },
    copy: i => {
      navigator.clipboard.writeText(i.url ?? '').then(
        () => notify('주소를 복사했어요'),
        () => notify('복사하지 못했어요. 항목을 열어 주소를 복사해주세요', 'error'),
      );
    },
    remove: i => {
      haptic(15);
      // 메모 시트에서 지웠으면 시트가 닫힌 뒤에 목록에서 빠지게
      if (memo) { setMemo(null); afterSheet(() => lib.removeItem(i.id)); } else animate(() => lib.removeItem(i.id));
      const dismiss = toast({
        body: `‘${i.title || '메모'}’ 삭제함`, uniqueID: 'undo', isAutoHide: false,
        endContent: <Button label="되돌리기" variant="ghost" size="sm" onClick={() => { animate(() => lib.restoreItem(i.id)); dismiss(); }} />,
      });
    },
  };

  const save = (d: ItemDraft) => {
    if (editing) { lib.updateItem(editing.id, d); notify('고쳤어요'); }
    else { toTop(); afterSheet(() => lib.addItem(d)); }
    setSheet(null); setEditing(null); setPrefill(undefined);
  };

  const removeFolder = (f: Folder) => {
    const undo = lib.removeFolder(f.id);
    const dismiss = toast({
      body: `‘${f.name}’ 서랍 삭제함`, uniqueID: 'undo', isAutoHide: false,
      endContent: <Button label="되돌리기" variant="ghost" size="sm" onClick={() => { undo(); dismiss(); }} />,
    });
  };

  const defaultFolderId = scope.type === 'folder' ? scope.id : lib.folders[0]?.id ?? null;
  const count = (n: number) => <Text type="supporting" size="sm" hasTabularNumbers>{n}</Text>;

  let body;
  if (!lib.ready) body = <div className="loading"><Spinner size="lg" aria-label="불러오는 중" /></div>;
  else if (!list.length) {
    body = query
      ? <EmptyState title={`‘${q.trim()}’ 검색 결과 없음`} description="다른 단어로 찾아보세요." icon={<Search size={28} />} actions={<Button label="검색 지우기" onClick={() => setQ('')} />} />
      : scope.type === 'star'
        ? <EmptyState title="즐겨찾기가 없어요" description="항목을 오른쪽으로 밀거나 길게 눌러 즐겨찾기에 넣으세요." icon={<Star size={28} />} />
        : <EmptyState title={lib.items.length ? '이 서랍은 비어 있어요' : '서랍이 비어 있어요'} description="아래 + 버튼으로 링크나 메모를 넣어보세요." icon={<Tray size={28} />} actions={<Button label="추가" variant="primary" onClick={openAdd} />} />;
  } else {
    body = view === 'list'
      ? <DayList items={list} folderMap={folderMap} showFolder={showFolder} act={act} loadingIds={loadingIds} />
      : <CardGrid items={list} folderMap={folderMap} showFolder={showFolder} act={act} />;
  }

  return (
    <div className="app">
      <header className="topbar" data-scrolled={scrolled}>
        <button className="bar-btn" aria-label="서랍 목록 열기" aria-expanded={navOpen} onClick={() => setNavOpen(true)}><Menu strokeWidth={1.8} /></button>
        <button type="button" className="topbar-title" onClick={() => toTop()} aria-label={`${title}, 맨 위로`}><h1>{title}</h1>{lib.ready && <span className="num">{list.length}</span>}</button>
        <div className="view-switch">
          <SegmentedControl label="보기 방식" value={view} onChange={v => changeView(v as 'list' | 'card')} size="sm">
            <SegmentedControlItem value="list" label="목록" isLabelHidden icon={<Rows3 size={17} strokeWidth={2} />} />
            <SegmentedControlItem value="card" label="카드" isLabelHidden icon={<LayoutGrid size={17} strokeWidth={2} />} />
          </SegmentedControl>
        </div>
        <button className="bar-btn" aria-label="설정" onClick={() => setSheet('settings')}><Settings strokeWidth={1.8} /></button>
      </header>

      <main className="content" ref={scrollRef} onScroll={e => { const s = e.currentTarget.scrollTop > 2; if (s !== scrolled) setScrolled(s); }}>
        <div className="content-inner">
          <div className="search-reveal" data-open={searching || !!q} ref={searchRef} inert={!(searching || q)}>
            <div>
              <TextInput label="검색" isLabelHidden placeholder="제목, 메모, 태그, 주소" type="search" value={q} onChange={setQ} startIcon={Search} size="lg" />
            </div>
          </div>
          {body}
        </div>
      </main>

      <nav className="tabbar" aria-label="빠른 메뉴">
        <button className="tab" aria-pressed={scope.type === 'all'} onClick={() => goto({type: 'all'})}><Inbox strokeWidth={1.8} /><span>전체</span></button>
        <button className="tab" aria-pressed={scope.type === 'star'} onClick={() => goto({type: 'star'})}><Star strokeWidth={1.8} /><span>즐겨찾기</span></button>
        <button className="tab" aria-pressed={searching} onClick={toggleSearch}><Search strokeWidth={1.8} /><span>검색</span></button>
        <button className="tab" aria-expanded={navOpen} onClick={() => setNavOpen(true)}><Tray strokeWidth={1.8} /><span>서랍</span></button>
        <PullFab onTap={openAdd} onPull={quickAdd} />
      </nav>

      <MobileNav isOpen={navOpen} onOpenChange={setNavOpen} header="hikidashi" side="start">
        <SideNavSection title="보관함">
          <SideNavItem label="전체" icon={Inbox} isSelected={scope.type === 'all'} onClick={() => pick({type: 'all'})} endContent={count(lib.items.length)} />
          <SideNavItem label="즐겨찾기" icon={Star} isSelected={scope.type === 'star'} onClick={() => pick({type: 'star'})} endContent={count(lib.items.filter(i => i.starred).length)} />
          {unfiled > 0 && <SideNavItem label="미분류" icon={Tray} isSelected={scope.type === 'none'} onClick={() => pick({type: 'none'})} endContent={count(unfiled)} />}
        </SideNavSection>
        <SideNavSection title="서랍">
          {lib.folders.map(f => (
            <SideNavItem key={f.id} label={f.name} icon={dotIcon(COLORS[f.color])} isSelected={scope.type === 'folder' && scope.id === f.id}
              onClick={() => pick({type: 'folder', id: f.id})} endContent={count(counts.get(f.id) ?? 0)} />
          ))}
          <SideNavItem label="서랍 편집" icon={SlidersHorizontal} onClick={() => { setNavOpen(false); setSheet('folders'); }} />
        </SideNavSection>
        {tags.length > 0 && (
          <SideNavSection title="태그">
            {tags.map(([t, n]) => (
              <SideNavItem key={t} label={t} icon={Hash} isSelected={scope.type === 'tag' && scope.tag === t} onClick={() => pick({type: 'tag', tag: t})} endContent={count(n)} />
            ))}
          </SideNavSection>
        )}
      </MobileNav>

      <ItemSheet isOpen={sheet === 'item'} onClose={() => { setSheet(null); setEditing(null); setPrefill(undefined); }}
        editing={editing} prefill={prefill} folders={lib.folders} defaultFolderId={defaultFolderId} allTags={allTags} onSave={save} />
      <MemoSheet item={memoLive} folder={memoLive?.folderId ? folderMap.get(memoLive.folderId) : undefined} onClose={() => setMemo(null)} onEdit={act.edit} onRemove={act.remove} onStar={act.toggleStar} />
      <FoldersSheet isOpen={sheet === 'folders'} onClose={() => setSheet(null)} folders={lib.folders} counts={counts}
        onAdd={(n, c) => { lib.addFolder(n, c); notify(`‘${n}’ 서랍을 만들었어요`); }}
        onUpdate={(id, p) => lib.updateFolder(id, p)} onRemove={removeFolder} />
      <SettingsSheet isOpen={sheet === 'settings'} onClose={() => setSheet(null)} records={lib.allRecords} liveCount={lib.items.length}
        onImport={lib.importBackup} notify={notify} />
    </div>
  );
}
