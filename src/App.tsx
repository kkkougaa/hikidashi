import {useEffect, useMemo, useRef, useState} from 'react';
import {Hash, Inbox, LayoutGrid, Menu, Plus, Rows3, Search, Settings, SlidersHorizontal, Star, Tray} from './icons';
import {MobileNav} from '@astryxdesign/core/MobileNav';
import {SideNavItem, SideNavSection} from '@astryxdesign/core/SideNav';
import {TextInput} from '@astryxdesign/core/TextInput';
import {EmptyState} from '@astryxdesign/core/EmptyState';
import {Button} from '@astryxdesign/core/Button';
import {Spinner} from '@astryxdesign/core/Spinner';
import {Text} from '@astryxdesign/core/Text';
import {useToast} from '@astryxdesign/core/Toast';
import {useLibrary} from './data/library';
import {COLORS, type Folder, type Item, type ItemDraft} from './data/types';
import {domainOf, findUrl, normalizeUrl} from './lib/format';
import {cssVar} from './components/bits';
import {CardGrid, DayList, type ItemActions} from './components/ItemViews';
import {ItemSheet} from './components/ItemSheet';
import {MemoSheet} from './components/MemoSheet';
import {FoldersSheet} from './components/FoldersSheet';
import {SettingsSheet} from './components/SettingsSheet';

/** 보고 있는 범위: 전체, 즐겨찾기, 미분류, 특정 서랍, 특정 태그 */
type Scope = {type: 'all'} | {type: 'star'} | {type: 'none'} | {type: 'folder'; id: string} | {type: 'tag'; tag: string};
const VIEW_KEY = 'seorap-view';

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

  useEffect(() => { try { localStorage.setItem(VIEW_KEY, view); } catch { /* 저장 못 해도 동작엔 지장 없음 */ } }, [view]);
  useEffect(() => {
    if (!lib.ready) return;
    const shared = readShared();
    if (shared) { setPrefill(shared); setEditing(null); setSheet('item'); }
  }, [lib.ready]);
  useEffect(() => { if (searching) searchRef.current?.querySelector('input')?.focus(); }, [searching]);

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
  const pick = (s: Scope) => { setScope(s); setNavOpen(false); };
  const openAdd = () => { setEditing(null); setPrefill(undefined); setSheet('item'); };

  const act: ItemActions = {
    open: i => setMemo(i),
    edit: i => { setMemo(null); setEditing(i); setPrefill(undefined); setSheet('item'); },
    toggleStar: i => lib.updateItem(i.id, {starred: !i.starred}),
    copy: i => {
      navigator.clipboard.writeText(i.url ?? '').then(
        () => notify('주소를 복사했어요'),
        () => notify('복사하지 못했어요. 항목을 열어 주소를 복사해주세요', 'error'),
      );
    },
    remove: i => {
      setMemo(null);
      lib.removeItem(i.id);
      const dismiss = toast({
        body: `‘${i.title || '메모'}’ 삭제함`, uniqueID: 'undo', isAutoHide: false,
        endContent: <Button label="되돌리기" variant="ghost" size="sm" onClick={() => { lib.restoreItem(i.id); dismiss(); }} />,
      });
    },
  };

  const save = (d: ItemDraft) => {
    if (editing) { lib.updateItem(editing.id, d); notify('고쳤어요'); }
    else { lib.addItem(d); }
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
      ? <DayList items={list} folderMap={folderMap} showFolder={showFolder} act={act} />
      : <CardGrid items={list} folderMap={folderMap} showFolder={showFolder} act={act} />;
  }

  return (
    <div className="app">
      <header className="topbar">
        <button className="bar-btn" aria-label="서랍 목록 열기" aria-expanded={navOpen} onClick={() => setNavOpen(true)}><Menu strokeWidth={1.8} /></button>
        <div className="topbar-title"><h1>{title}</h1>{lib.ready && <span className="num">{list.length}</span>}</div>
        <button className="bar-btn" aria-label="설정" onClick={() => setSheet('settings')}><Settings strokeWidth={1.8} /></button>
      </header>

      <main className="content">
        {(searching || q) && (
          <div ref={searchRef}>
            <TextInput label="검색" isLabelHidden placeholder="제목, 메모, 태그, 주소" type="search" value={q} onChange={setQ} startIcon={Search} size="lg" />
          </div>
        )}
        {body}
      </main>

      <nav className="tabbar" aria-label="빠른 메뉴">
        <button className="tab" aria-pressed={scope.type === 'all'} aria-label="전체" onClick={() => setScope({type: 'all'})}><Inbox strokeWidth={1.8} /></button>
        <button className="tab" aria-pressed={scope.type === 'star'} aria-label="즐겨찾기" onClick={() => setScope({type: 'star'})}><Star strokeWidth={1.8} /></button>
        <button className="tab" aria-pressed={searching} aria-label="검색" onClick={() => { if (searching) setQ(''); setSearching(s => !s); }}><Search strokeWidth={1.8} /></button>
        <button className="tab" aria-pressed={view === 'list'} aria-label="목록으로 보기" onClick={() => setView('list')}><Rows3 strokeWidth={1.8} /></button>
        <button className="tab" aria-pressed={view === 'card'} aria-label="카드로 보기" onClick={() => setView('card')}><LayoutGrid strokeWidth={1.8} /></button>
        <button className="fab" aria-label="추가" onClick={openAdd}><Plus strokeWidth={2.4} /></button>
      </nav>

      <MobileNav isOpen={navOpen} onOpenChange={setNavOpen} header="서랍" side="start">
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
        editing={editing} prefill={prefill} folders={lib.folders} defaultFolderId={defaultFolderId} onSave={save} />
      <MemoSheet item={memo} folder={memo?.folderId ? folderMap.get(memo.folderId) : undefined} onClose={() => setMemo(null)} onEdit={act.edit} onRemove={act.remove} />
      <FoldersSheet isOpen={sheet === 'folders'} onClose={() => setSheet(null)} folders={lib.folders} counts={counts}
        onAdd={(n, c) => { lib.addFolder(n, c); notify(`‘${n}’ 서랍을 만들었어요`); }}
        onUpdate={(id, p) => lib.updateFolder(id, p)} onRemove={removeFolder} />
      <SettingsSheet isOpen={sheet === 'settings'} onClose={() => setSheet(null)} records={lib.allRecords} liveCount={lib.items.length}
        onImport={lib.importBackup} notify={notify} />
    </div>
  );
}
