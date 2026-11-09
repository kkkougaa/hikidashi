import {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {CheckCheck, CircleCheck, Eye, EyeOff, Folder as FolderIcon, House, Rows3, StickyNote, Hash, Highlighter, Inbox, LayoutGrid, Link2Off, Menu, Search, Settings, SlidersHorizontal, Star, Tag, Trash2, Tray} from './icons';
import {DropdownMenu} from '@astryxdesign/core/DropdownMenu';
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
import {allArticleTexts, getMeta, hasArticle, putArticle, setMeta} from './data/db';
import {displayFolders, familyOf, isNsfw, orderedFolders, withNsfw} from './data/folders';
import {disconnect, dropboxConfigured, dropboxFile, finishLogin, isConnected, latestCursor, advanceCursor, NotConnected, startLogin, waitForChange} from './data/dropbox';
import {syncFile} from './data/fileSync';
import {deriveKey, newKdf, openEnvelope, readEnvelope, WrongPassphrase, type Kdf, type Vault} from './data/vault';
import {domainOf, findUrl, guessTitle, normalizeUrl, parseTags} from './lib/format';
import {fetchArticle, supportsReader} from './lib/reader';
import {markRecent, usePref} from './lib/prefs';
import {Block, cssVar} from './components/bits';
import {CardGrid, DayList, HighlightList, nameOf, SiteList, TimelineList, type ItemActions} from './components/ItemViews';
import {ItemSheet} from './components/ItemSheet';
import {MemoSheet} from './components/MemoSheet';
import {FoldersSheet} from './components/FoldersSheet';
import {SettingsSheet, type SyncUi} from './components/SettingsSheet';
import {ReaderSheet} from './components/ReaderSheet';
import {PullFab} from './components/PullFab';
import {fetchPageInfo} from './lib/pageInfo';

/** 보고 있는 범위 */
type Scope =
  | {type: 'all'} | {type: 'star'} | {type: 'none'} | {type: 'highlights'} | {type: 'broken'} | {type: 'done'} | {type: 'memos'}
  | {type: 'folder'; id: string} | {type: 'tag'; tag: string};

const dotIcon = (color: string) => {
  const Dot = () => <span className="nav-dot" aria-hidden="true"><span className="dot" style={cssVar(color)} /></span>;
  return Dot;
};
/** 하위 서랍: 들여 쓰고 작은 점 */
const subDotIcon = (color: string) => {
  const Dot = () => <span className="nav-dot sub" aria-hidden="true"><span className="dot" style={cssVar(color)} /></span>;
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

/** 데이터가 바뀌었는지 가볍게 보는 표시 (동기화를 다시 할지 판단) */
const signature = (items: Item[], folders: Folder[]) =>
  `${items.length}:${folders.length}:${Math.max(0, ...items.map(i => i.updatedAt), ...folders.map(f => f.updatedAt))}`;

export function App() {
  const lib = useLibrary();
  const toast = useToast();
  const [scope, setScope] = useState<Scope>({type: 'all'});
  const [q, setQ] = useState('');
  const [view, setView] = usePref('view');
  const [linkOpen] = usePref('linkOpen');
  const [saveArticles] = usePref('saveArticles');
  const [defaultFolderPref] = usePref('defaultFolder');
  const [recent] = usePref('recent');
  const [showNsfw, setShowNsfw] = usePref('showNsfw');
  const [groupBy] = usePref('groupBy');
  const [navOpen, setNavOpen] = useState(false);
  const [sheet, setSheet] = useState<null | 'item' | 'folders' | 'settings'>(null);
  const [editing, setEditing] = useState<Item | null>(null);
  const [prefill, setPrefill] = useState<Partial<ItemDraft> | undefined>();
  const [memo, setMemo] = useState<Item | null>(null);
  const [reader, setReader] = useState<Item | null>(null);
  const [selection, setSelection] = useState<Set<string> | null>(null);
  const [tagging, setTagging] = useState(false);
  const [tagText, setTagText] = useState('');
  const scrollRef = useRef<HTMLElement>(null);
  const [scrolled, setScrolled] = useState(false);
  /** 하단바를 + 버튼으로 접었는지 (아래로 스크롤할 때) */
  const [collapsed, setCollapsed] = useState(false);
  const lastTop = useRef(0);
  const toTop = (smooth = true) => scrollRef.current?.scrollTo({top: 0, behavior: smooth ? 'smooth' : 'auto'});

  useEffect(() => {
    if (!lib.ready) return;
    const shared = readShared();
    if (shared) { setPrefill(shared); setEditing(null); setSheet('item'); }
  }, [lib.ready]);

  // 시트를 연 채로 바뀐 값을 바로 보여 주려고 최신 항목을 다시 찾는다
  const live = (i: Item | null) => (i ? lib.items.find(x => x.id === i.id) ?? null : null);
  const memoLive = live(memo);
  const readerLive = live(reader);
  const folderMap = useMemo(() => displayFolders(lib.folders), [lib.folders]);
  /** 고르기 목록용: 상위 다음에 하위, 이름은 상위-하위 */
  const pickFolders = useMemo(() => orderedFolders(lib.folders).map(({folder}) => folderMap.get(folder.id)!), [lib.folders, folderMap]);
  // NSFW 를 숨기면 어디에도 안 나온다. 확인 완료한 건 완료함에만
  const pool = useMemo(() => (showNsfw ? lib.items : lib.items.filter(i => !isNsfw(i))), [lib.items, showNsfw]);
  const active = useMemo(() => pool.filter(i => !i.doneAt), [pool]);
  const doneItems = useMemo(() => pool.filter(i => i.doneAt).sort((a, b) => (b.doneAt ?? 0) - (a.doneAt ?? 0)), [pool]);
  useEffect(() => { if (scope.type === 'folder' && lib.ready && !folderMap.has(scope.id)) setScope({type: 'all'}); }, [scope, folderMap, lib.ready]);

  const counts = useMemo(() => {
    const m = new Map<string, number>();
    for (const i of active) if (i.folderId) m.set(i.folderId, (m.get(i.folderId) ?? 0) + 1);
    // 상위 서랍 숫자에는 하위 서랍 것도 더한다
    for (const f of lib.folders) if (f.parentId && folderMap.has(f.parentId) && m.get(f.id)) m.set(f.parentId, (m.get(f.parentId) ?? 0) + m.get(f.id)!);
    return m;
  }, [active, lib.folders, folderMap]);
  const tags = useMemo(() => {
    const m = new Map<string, number>();
    for (const i of pool) for (const t of i.tags) m.set(t, (m.get(t) ?? 0) + 1);
    return [...m.entries()].sort((a, b) => a[0].localeCompare(b[0], 'ko'));
  }, [pool]);
  const allTags = useMemo(() => [...tags].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'ko')).map(([t]) => t), [tags]);
  const unfiled = useMemo(() => active.filter(i => !i.folderId || !folderMap.has(i.folderId)).length, [active, folderMap]);
  const highlighted = useMemo(() => pool.filter(i => i.highlights?.length), [pool]);
  const broken = useMemo(() => active.filter(i => i.brokenAt), [active]);
  const recentItems = useMemo(() => recent.map(id => pool.find(i => i.id === id)).filter((i): i is Item => !!i).slice(0, 5), [recent, pool]);
  const family = useMemo(() => (scope.type === 'folder' ? familyOf(scope.id, lib.folders) : null), [scope, lib.folders]);

  const inScope = (i: Item) => {
    switch (scope.type) {
      case 'all': return true;
      case 'star': return i.starred;
      case 'none': return !i.folderId || !folderMap.has(i.folderId);
      case 'highlights': return !!i.highlights?.length;
      case 'broken': return !!i.brokenAt;
      case 'folder': return !!i.folderId && !!family?.has(i.folderId);
      case 'done': return true;
      case 'memos': return i.kind === 'memo';
      case 'tag': return i.tags.includes(scope.tag);
    }
  };
  const query = q.trim().toLowerCase();
  // 본문 검색: 기기에 저장한 리더 본문까지 찾는다 (검색할 때 한 번 읽어 둔다)
  const [bodies, setBodies] = useState<Map<string, string>>(new Map());
  const searching = query.length > 0;
  useEffect(() => { if (searching) void allArticleTexts().then(setBodies, () => {}); }, [searching]);
  const matches = (i: Item) => [i.title, i.note, i.url, domainOf(i.url), i.siteName ?? '', i.tags.join(' '), ...(i.highlights ?? [])].join(' ').toLowerCase().includes(query)
    || !!bodies.get(i.id)?.includes(query);
  const list = (scope.type === 'done' ? doneItems : scope.type === 'highlights' ? highlighted : active).filter(i => inScope(i) && (!query || matches(i)));
  const scopeTitle = {all: '전체', star: '즐겨찾기', none: '미분류', highlights: '하이라이트', broken: '열리지 않는 링크', done: '완료함', memos: '메모'} as Record<string, string>;
  const title = selection ? (selection.size ? `${selection.size}개 선택` : '항목 고르기')
    : scope.type === 'tag' ? `#${scope.tag}` : scope.type === 'folder' ? folderMap.get(scope.id)?.name ?? '서랍' : scopeTitle[scope.type];
  // 상위 서랍을 볼 땐 어느 하위 서랍 것인지 칩으로 보여준다
  const showFolder = scope.type !== 'folder' || (family?.size ?? 0) > 1;

  /** 잠깐 보이고 사라지는 알림 */
  const notify = useCallback((body: string, type: 'info' | 'error' = 'info') =>
    toast({body, type, uniqueID: 'notice', isAutoHide: true, autoHideDuration: type === 'error' ? 4000 : 1800}), [toast]);
  /** 되돌리기가 붙은 알림 (누를 시간만큼 조금 더) */
  const undoable = (body: string, undo: () => void) => {
    const dismiss = toast({
      body, uniqueID: 'undo', isAutoHide: true, autoHideDuration: 3500,
      endContent: <Button label="되돌리기" variant="ghost" size="sm" onClick={() => { undo(); dismiss(); }} />,
    });
  };

  const goto = (s: Scope) => {
    if (JSON.stringify(s) === JSON.stringify(scope)) return toTop();
    setSelection(null);
    animate(() => setScope(s));
    toTop(false);
  };
  const pick = (s: Scope) => { setNavOpen(false); goto(s); };
  const changeView = (v: 'list' | 'rows' | 'card') => { if (v !== view) animate(() => setView(v)); };
  const openAdd = () => { setEditing(null); setPrefill(undefined); setSheet('item'); };

  const defaultFolderId = scope.type === 'folder' ? scope.id
    : defaultFolderPref === 'none' ? null
    : folderMap.has(defaultFolderPref) ? defaultFolderPref : pickFolders[0]?.id ?? null;

  /** 새 글은 본문을 미리 받아 둔다 (설정에서 끌 수 있다) */
  const prefetch = (id: string, url?: string) => {
    if (!saveArticles || !supportsReader(url)) return;
    void hasArticle(id).then(async has => {
      if (has) return;
      const a = await fetchArticle(url!);
      if (a) await putArticle(id, a);
    }).catch(() => {});
  };

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
      const id = uid();
      setLoading(id, true);
      animate(() => lib.addItem({kind: 'link', url: u, title: '', note: '', folderId: defaultFolderId, tags: []}, id));
      undoable('복사한 링크를 추가했어요', () => animate(() => lib.removeItem(id)));
      const info = await fetchPageInfo(u);
      setLoading(id, false);
      const now = lib.allRecords().items.find(i => i.id === id);
      if (!now || now.deletedAt) return;
      // 그사이 사용자가 고친 칸은 건드리지 않는다
      const patch: Partial<ItemDraft> = {};
      if (info?.title && !now.title) patch.title = info.title;
      if (info?.description && !now.note) patch.note = info.description;
      if (info?.image && !now.image) patch.image = info.image;
      if (info?.video && !now.video) patch.video = info.video;
      if (info?.avatar && !now.avatar) patch.avatar = info.avatar;
      if (info?.images && !now.images) patch.images = info.images;
      if (info?.siteName && !now.siteName) patch.siteName = info.siteName;
      if (!info && !now.title && !now.note) patch.title = guessTitle(u);
      if (Object.keys(patch).length) animate(() => lib.updateItem(id, patch));
      prefetch(id, u);
    }, () => notify('클립보드를 읽지 못했어요. 붙여넣기를 허용하거나 + 를 눌러 추가해주세요', 'error'));
  };

  const openTab = (i: Item) => { markRecent(i.id); if (i.url) window.open(i.url, '_blank', 'noopener'); };
  const act: ItemActions = {
    open: i => {
      markRecent(i.id);
      if (i.kind === 'memo') setMemo(i);
      else if (linkOpen === 'reader' && supportsReader(i.url)) setReader(i);
      else openTab(i);
    },
    openReader: i => { markRecent(i.id); setReader(i); },
    openTab,
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
      undoable(`‘${nameOf(i)}’ 삭제함`, () => animate(() => lib.restoreItem(i.id)));
    },
    startSelect: i => { haptic(); setSelection(new Set([i.id])); },
    toggleDone: i => {
      haptic();
      const doneAt = i.doneAt ? null : Date.now();
      animate(() => lib.updateItem(i.id, {doneAt}));
      undoable(doneAt ? `‘${nameOf(i)}’ 확인 완료` : `‘${nameOf(i)}’ 완료 취소`, () => animate(() => lib.updateItem(i.id, {doneAt: i.doneAt ?? null})));
    },
    toggleNsfw: i => {
      const on = !isNsfw(i);
      animate(() => lib.updateItem(i.id, {tags: withNsfw(i.tags, on)}));
      notify(on ? (showNsfw ? 'NSFW 로 표시했어요' : 'NSFW 로 표시해서 숨겼어요') : 'NSFW 표시를 뺐어요');
    },
    selection,
    toggleSelect: i => setSelection(prev => {
      if (!prev) return prev;
      const next = new Set(prev);
      if (next.has(i.id)) next.delete(i.id); else next.add(i.id);
      return next;
    }),
  };

  /** 고른 항목에 한꺼번에 하고 되돌리기를 띄운다 */
  const bulk = (message: string, fn: (i: Item) => Partial<Item>) => {
    if (!selection?.size) return;
    const ids = [...selection];
    let prev: Item[] = [];
    animate(() => { prev = lib.updateMany(ids, fn); });
    setSelection(null);
    setTagging(false);
    undoable(message, () => animate(() => lib.restoreVersions(prev)));
  };

  const save = (d: ItemDraft) => {
    if (editing) { lib.updateItem(editing.id, d); notify('고쳤어요'); }
    else {
      toTop();
      const id = uid();
      afterSheet(() => lib.addItem(d, id));
      prefetch(id, d.url);
    }
    setSheet(null); setEditing(null); setPrefill(undefined);
  };

  const removeFolder = (f: Folder) => {
    const undo = lib.removeFolder(f.id);
    undoable(`‘${f.name}’ 서랍 삭제함`, undo);
  };

  // MARK: 동기화 (드롭박스 앱 폴더의 잠근 파일 하나, docs/SPEC.md)
  const [sync, setSync] = useState<SyncUi>({state: dropboxConfigured() ? 'loading' : 'unset'});
  const vaultRef = useRef<Vault | null>(null);
  const syncingRef = useRef(false);
  const syncedSig = useRef('');
  const errText = (e: unknown, fallback: string) => e instanceof Error && e.message ? e.message : fallback;

  /** 이 기기의 키·판 기록을 지운다 (연결을 끊거나 암호를 다시 받아야 할 때) */
  const dropVault = useCallback(async () => {
    vaultRef.current = null;
    syncedSig.current = '';
    await setMeta('vault', undefined);
    await setMeta('syncRev', undefined);
  }, []);

  const runSync = useCallback(async (loud = false) => {
    const vault = vaultRef.current;
    if (syncingRef.current || !vault) return;
    syncingRef.current = true;
    setSync(s => ({...s, state: 'syncing'}));
    try {
      const before = lib.allRecords();
      const dirty = signature(before.items, before.folders) !== syncedSig.current;
      const lastRev = await getMeta<string>('syncRev');
      const r = await syncFile(dropboxFile, vault, b => { const x = lib.importBackup(b); return x.items + x.folders; }, lib.allRecords, {lastRev, dirty});
      await setMeta('syncRev', r.rev ?? undefined);
      const {items, folders} = lib.allRecords();
      syncedSig.current = signature(items, folders);
      const last = Date.now();
      await setMeta('lastSyncAt', last);
      setSync({state: 'idle', last});
      if (r.changed) notify(`다른 기기에서 ${r.changed}개를 가져왔어요`); else if (loud) notify('동기화했어요');
    } catch (e) {
      if (e instanceof WrongPassphrase) {
        await dropVault();
        setSync({state: 'key', fresh: false, error: '다른 기기에서 동기화 암호를 바꿨어요. 새 암호를 넣어주세요'});
      } else if (e instanceof NotConnected) {
        await dropVault();
        setSync({state: 'off', error: e.message});
        notify(e.message, 'error');
      } else {
        setSync(s => ({...s, state: 'error', error: errText(e, '동기화하지 못했어요')}));
        if (loud) notify('동기화하지 못했어요', 'error');
      }
    } finally {
      syncingRef.current = false;
    }
  }, [lib, notify, dropVault]);
  const runSyncRef = useRef(runSync);
  runSyncRef.current = runSync;

  // 켤 때: 드롭박스 로그인에서 돌아왔으면 마무리하고, 연결돼 있으면 바로 맞춘다. 앱으로 돌아올 때마다 다시
  useEffect(() => {
    if (!lib.ready) return;
    void setMeta('syncDir', undefined); // 예전 iCloud Drive 폴더 방식의 흔적
    if (!dropboxConfigured()) return;
    void (async () => {
      try {
        const back = await finishLogin();
        if (back === 'denied') notify('드롭박스에 연결하지 못했어요', 'error');
        if (!(await isConnected())) { setSync({state: 'off'}); return; }
        const v = await getMeta<Vault>('vault');
        if (v) {
          vaultRef.current = v;
          setSync({state: 'idle', last: await getMeta<number>('lastSyncAt')});
          void runSync(back === 'ok');
        } else {
          setSync({state: 'key', fresh: (await dropboxFile.rev()) === null});
          if (back === 'ok') setSheet('settings');
        }
      } catch (e) {
        if (e instanceof NotConnected) setSync({state: 'off'});
        else setSync({state: 'error', error: errText(e, '드롭박스에 연결하지 못했어요')});
      }
    })();
    const onVisible = () => { if (document.visibilityState === 'visible') void runSyncRef.current(); };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lib.ready]);

  // 열려 있는 동안 다른 기기가 올리면 바로 받는다 (드롭박스 롱폴링)
  const polling = !!vaultRef.current && (sync.state === 'idle' || sync.state === 'syncing' || sync.state === 'error');
  useEffect(() => {
    if (!polling) return;
    const ctl = new AbortController();
    const wait = (ms: number) => new Promise<void>(r => { const t = setTimeout(r, ms); ctl.signal.addEventListener('abort', () => { clearTimeout(t); r(); }); });
    void (async () => {
      let cursor: string | null = null;
      while (!ctl.signal.aborted) {
        if (document.visibilityState !== 'visible') { await wait(2000); continue; }
        try {
          cursor ??= await latestCursor();
          const r = await waitForChange(cursor, ctl.signal);
          if (r.changes) { cursor = await advanceCursor(cursor); await runSyncRef.current(); }
          if (r.backoff) await wait(r.backoff * 1000);
        } catch {
          if (ctl.signal.aborted) break;
          cursor = null;
          await wait(30_000);
        }
      }
    })();
    return () => ctl.abort();
  }, [polling]);

  /** 동기화 암호를 받았을 때. 파일이 있으면 그 암호로 열리는지 확인하고, 없으면 새로 정한다. 틀리면 이유를 돌려준다 */
  const onPassphrase = async (pass: string): Promise<string | null> => {
    try {
      const got = await dropboxFile.read();
      const env = got ? readEnvelope(got.text) : null;
      const kdf: Kdf = env ? env.kdf : newKdf();
      const v: Vault = {key: await deriveKey(pass, kdf), kdf};
      if (env) await openEnvelope(v, env);
      await dropVault();
      await setMeta('vault', v);
      vaultRef.current = v;
      setSync({state: 'idle'});
      void runSync(true);
      return null;
    } catch (e) {
      if (e instanceof WrongPassphrase) return '암호가 맞지 않아요';
      if (e instanceof NotConnected) { setSync({state: 'off', error: e.message}); return e.message; }
      return errText(e, '확인하지 못했어요');
    }
  };

  // 고치면 잠깐 기다렸다 맞춘다 (동기화로 바뀐 건 건너뜀)
  const rawRecords = lib.allRecords();
  const sig = signature(rawRecords.items, rawRecords.folders);
  useEffect(() => {
    if (sync.state !== 'idle' || sig === syncedSig.current) return;
    const t = window.setTimeout(() => void runSync(), 3000);
    return () => window.clearTimeout(t);
  }, [sig, sync.state, runSync]);

  const count = (n: number) => <Text type="supporting" size="sm" hasTabularNumbers>{n}</Text>;

  let body;
  if (!lib.ready) body = <div className="loading"><Spinner size="lg" aria-label="불러오는 중" /></div>;
  else if (!list.length) {
    body = query
      ? <EmptyState title={`‘${q.trim()}’ 검색 결과 없음`} description="다른 단어로 찾아보세요." icon={<Search size={28} />} actions={<Button label="검색 지우기" onClick={() => setQ('')} />} />
      : scope.type === 'star'
        ? <EmptyState title="즐겨찾기가 없어요" description="항목을 오른쪽으로 밀거나 길게 눌러 즐겨찾기에 넣으세요." icon={<Star size={28} />} />
        : scope.type === 'highlights'
          ? <EmptyState title="하이라이트가 없어요" description="리더 모드에서 문단을 눌러 형광펜을 칠해보세요." icon={<Highlighter size={28} />} />
          : scope.type === 'broken'
            ? <EmptyState title="모두 잘 열려요" description="아이폰 앱이 링크를 점검해서, 열리지 않는 링크가 생기면 여기에 모여요." icon={<Link2Off size={28} />} />
            : scope.type === 'done'
              ? <EmptyState title="완료한 항목이 없어요" description="항목을 길게 눌러 ‘확인 완료’ 하면 목록에서 빠지고 여기로 와요." icon={<CheckCheck size={28} />} />
            : <EmptyState title={lib.items.length ? '이 서랍은 비어 있어요' : '서랍이 비어 있어요'} description="아래 + 버튼으로 링크나 메모를 넣어보세요." icon={<Tray size={28} />} actions={<Button label="추가" variant="primary" onClick={openAdd} />} />;
  } else if (scope.type === 'highlights') {
    body = <HighlightList items={list} folderMap={folderMap} onOpen={i => act.openReader(i)} onRemove={(i, h) => lib.toggleHighlight(i.id, h)} />;
  } else {
    body = view === 'card'
      ? <CardGrid items={list} folderMap={folderMap} showFolder={showFolder} act={act} />
      : view === 'rows'
        ? (groupBy === 'site' && scope.type !== 'done'
          ? <SiteList items={list} folderMap={folderMap} showFolder={showFolder} act={act} loadingIds={loadingIds} />
          : <DayList items={list} folderMap={folderMap} showFolder={showFolder} act={act} loadingIds={loadingIds} />)
        : <TimelineList items={list} folderMap={folderMap} showFolder={showFolder} act={act} loadingIds={loadingIds} groupBy={scope.type === 'done' ? 'none' : groupBy} />;
  }

  const allIds = list.map(i => i.id);
  const allPicked = !!selection && selection.size === allIds.length && allIds.length > 0;

  return (
    <div className="app">
      <header className="topbar" data-scrolled={scrolled}>
        {selection
          ? <button className="text-btn" onClick={() => { setSelection(null); setTagging(false); }}>완료</button>
          : <button className="bar-btn" aria-label="서랍 열기" aria-expanded={navOpen} onClick={() => setNavOpen(true)}><Menu strokeWidth={1.8} /></button>}
        <button type="button" className="topbar-title" onClick={() => toTop()} aria-label={`${title}, 맨 위로`}><h1>{title}</h1>{lib.ready && !selection && <span className="num">{list.length}</span>}</button>
        {selection
          ? <button className="text-btn" onClick={() => setSelection(allPicked ? new Set() : new Set(allIds))}>{allPicked ? '선택 해제' : '모두 선택'}</button>
          : <>
            <button className="bar-btn" aria-label="여러 개 고르기" disabled={!list.length || scope.type === 'highlights'} onClick={() => setSelection(new Set())}><CircleCheck strokeWidth={1.8} /></button>
          </>}
      </header>

      <main className="content" ref={scrollRef} onScroll={e => {
        const top = e.currentTarget.scrollTop;
        const s = top > 2;
        if (s !== scrolled) setScrolled(s);
        // 아래로 내리면 하단바가 + 버튼으로 합쳐지고, 위로 올리거나 맨 위면 다시 펼쳐진다
        const d = top - lastTop.current;
        if (Math.abs(d) > 6) {
          const c = d > 0 && top > 48;
          if (c !== collapsed) setCollapsed(c);
          lastTop.current = top;
        }
      }}>
        <div className="content-inner">
          <div className="search-bar">
            <TextInput label="검색" isLabelHidden placeholder="제목, 메모, 태그, 주소, 본문" type="search" value={q} onChange={setQ} startIcon={Search} size="lg" />
          </div>
          {body}
        </div>
      </main>

      {selection ? (
        <div className="select-dock">
          {tagging && (
            <form className="select-tag" noValidate onSubmit={e => {
              e.preventDefault();
              const t = parseTags(tagText);
              if (t.length) bulk(`${selection.size}개에 ${t.map(x => `#${x}`).join(' ')} 달았어요`, i => ({tags: [...new Set([...i.tags, ...t])]}));
              setTagText('');
            }}>
              <input autoFocus value={tagText} onChange={e => setTagText(e.target.value)} placeholder="태그 (띄어 쓰면 여러 개)" aria-label="달 태그" />
              <button type="submit" className="text-btn">달기</button>
            </form>
          )}
          <div className="select-bar" aria-label="고른 항목에 할 일">
            <DropdownMenu placement="above" presentation="adaptive" items={[
              ...pickFolders.map(f => ({label: f.name, icon: <span className="dot" style={cssVar(COLORS[f.color])} />, onClick: () => bulk(`${selection.size}개를 ‘${f.name}’ 로 옮겼어요`, () => ({folderId: f.id}))})),
              {label: '미분류', onClick: () => bulk(`${selection.size}개를 미분류로 옮겼어요`, () => ({folderId: null}))},
            ]} renderTrigger={props => <button type="button" disabled={!selection.size} {...props}><FolderIcon size={19} /><span>옮기기</span></button>} />
            <button type="button" disabled={!selection.size} onClick={() => setTagging(t => !t)}><Tag size={19} /><span>태그</span></button>
            <button type="button" disabled={!selection.size} onClick={() => {
              const all = [...selection].every(id => lib.items.find(i => i.id === id)?.starred);
              bulk(all ? '즐겨찾기에서 뺐어요' : '즐겨찾기에 넣었어요', () => ({starred: !all}));
            }}><Star size={19} /><span>즐겨찾기</span></button>
            <button type="button" disabled={!selection.size} onClick={() => {
              const undo = scope.type === 'done';
              bulk(undo ? `${selection.size}개 완료 취소` : `${selection.size}개 확인 완료`, () => ({doneAt: undo ? null : Date.now()}));
            }}><CheckCheck size={19} /><span>{scope.type === 'done' ? '완료 취소' : '완료'}</span></button>
            <button type="button" className="danger" disabled={!selection.size} onClick={() => bulk(`${selection.size}개 삭제함`, () => ({deletedAt: Date.now()}))}><Trash2 size={19} /><span>삭제</span></button>
          </div>
        </div>
      ) : (
        <div className="fab-dock" data-collapsed={collapsed || undefined}>
          <nav className="dockbar" aria-label="화면" inert={collapsed || undefined}>
            <button type="button" aria-label="홈" aria-pressed={view === 'list'} onClick={() => { if (view === 'list') toTop(); else changeView('list'); }}><House size={24} strokeWidth={2} /></button>
            <button type="button" aria-label="리스트" aria-pressed={view === 'rows'} onClick={() => { if (view === 'rows') toTop(); else changeView('rows'); }}><Rows3 size={24} strokeWidth={2} /></button>
            <button type="button" aria-label="그리드" aria-pressed={view === 'card'} onClick={() => { if (view === 'card') toTop(); else changeView('card'); }}><LayoutGrid size={24} strokeWidth={2} /></button>
            <button type="button" aria-label="설정" onClick={() => setSheet('settings')}><Settings size={24} strokeWidth={2} /></button>
          </nav>
          <PullFab onTap={openAdd} onPull={quickAdd} />
        </div>
      )}

      <MobileNav isOpen={navOpen} onOpenChange={setNavOpen} label="서랍" side="start" header={
        <div className="nav-head">
          <span>hikidashi</span>
          <button type="button" className="nav-gear" aria-pressed={showNsfw} aria-label={showNsfw ? 'NSFW 숨기기' : 'NSFW 보이기'} title={showNsfw ? 'NSFW 보이는 중' : 'NSFW 숨기는 중'}
            data-on={showNsfw || undefined} onClick={() => { setShowNsfw(!showNsfw); notify(showNsfw ? 'NSFW 항목을 숨겼어요' : 'NSFW 항목을 보여줘요'); }}>
            {showNsfw ? <Eye size={19} strokeWidth={2} /> : <EyeOff size={19} strokeWidth={2} />}
          </button>
        </div>
      }>
        <SideNavSection title="보관함">
          <SideNavItem label="전체" icon={Inbox} isSelected={scope.type === 'all'} onClick={() => pick({type: 'all'})} endContent={count(active.length)} />
          {active.some(i => i.kind === 'memo') && <SideNavItem label="메모" icon={StickyNote} isSelected={scope.type === 'memos'} onClick={() => pick({type: 'memos'})} endContent={count(active.filter(i => i.kind === 'memo').length)} />}
          <SideNavItem label="즐겨찾기" icon={Star} isSelected={scope.type === 'star'} onClick={() => pick({type: 'star'})} endContent={count(active.filter(i => i.starred).length)} />
          {unfiled > 0 && <SideNavItem label="미분류" icon={Tray} isSelected={scope.type === 'none'} onClick={() => pick({type: 'none'})} endContent={count(unfiled)} />}
          {highlighted.length > 0 && <SideNavItem label="하이라이트" icon={Highlighter} isSelected={scope.type === 'highlights'} onClick={() => pick({type: 'highlights'})} endContent={count(highlighted.length)} />}
          {broken.length > 0 && <SideNavItem label="열리지 않는 링크" icon={Link2Off} isSelected={scope.type === 'broken'} onClick={() => pick({type: 'broken'})} endContent={count(broken.length)} />}
          {doneItems.length > 0 && <SideNavItem label="완료함" icon={CheckCheck} isSelected={scope.type === 'done'} onClick={() => pick({type: 'done'})} endContent={count(doneItems.length)} />}
        </SideNavSection>
        {recentItems.length > 0 && (
          <SideNavSection title="최근 연 항목">
            {recentItems.map(it => {
              const Icon = () => <span className="nav-thumb"><Block item={it} folder={it.folderId ? folderMap.get(it.folderId) : undefined} /></span>;
              return <SideNavItem key={it.id} label={nameOf(it)} icon={Icon} onClick={() => { setNavOpen(false); act.open(it); }} />;
            })}
          </SideNavSection>
        )}
        <SideNavSection title="서랍">
          {orderedFolders(lib.folders).map(({folder: f, depth}) => (
            <SideNavItem key={f.id} label={f.name} icon={depth ? subDotIcon(COLORS[folderMap.get(f.id)!.color]) : dotIcon(COLORS[f.color])}
              className={depth ? 'nav-sub' : undefined} isSelected={scope.type === 'folder' && scope.id === f.id}
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
        editing={editing} prefill={prefill} folders={pickFolders} defaultFolderId={defaultFolderId} allTags={allTags} onSave={save} />
      <MemoSheet item={memoLive} folder={memoLive?.folderId ? folderMap.get(memoLive.folderId) : undefined} onClose={() => setMemo(null)} onEdit={act.edit} onRemove={act.remove} onStar={act.toggleStar}
        saved={u => lib.items.find(i => i.url === u)}
        onOpenLink={u => {
          const it = lib.items.find(i => i.url === u);
          setMemo(null);
          afterSheet(() => (it ? act.open(it) : window.open(u, '_blank', 'noopener')));
        }}
        onSaveLink={(u, info, folderId) => {
          const id = uid();
          lib.addItem({kind: 'link', url: u, title: info?.title ?? '', note: info?.description ?? '', image: info?.image, video: info?.video, avatar: info?.avatar, images: info?.images, siteName: info?.siteName, folderId, tags: []}, id);
          prefetch(id, u);
          notify('링크를 저장했어요');
        }} />
      <ReaderSheet item={readerLive} onClose={() => setReader(null)} notify={notify}
        onHighlight={(i, text) => lib.toggleHighlight(i.id, text)} />
      <FoldersSheet isOpen={sheet === 'folders'} onClose={() => setSheet(null)} folders={lib.folders} counts={counts}
        onAdd={(n, c, parentId) => { lib.addFolder(n, c, parentId); notify(`‘${n}’ 서랍을 만들었어요`); }}
        onUpdate={(id, p) => lib.updateFolder(id, p)} onRemove={removeFolder} onReorder={lib.reorderFolders} />
      <SettingsSheet isOpen={sheet === 'settings'} onClose={() => setSheet(null)} records={lib.allRecords} liveCount={lib.items.length}
        onImport={lib.importBackup} notify={notify} folders={pickFolders} tags={tags}
        onRenameTag={(from, to) => { const prev = lib.renameTag(from, to); if (prev.length) undoable(`#${from} → #${to.replace(/^#+/, '').trim()}`, () => lib.restoreVersions(prev)); }}
        onRemoveTag={t => { const prev = lib.removeTag(t); if (prev.length) undoable(`#${t} 태그를 항목 ${prev.length}개에서 뺐어요`, () => lib.restoreVersions(prev)); }}
        onEditFolders={() => { setSheet(null); afterSheet(() => setSheet('folders')); }}
        sync={sync}
        onConnect={() => void startLogin()}
        onPassphrase={onPassphrase}
        onSyncNow={() => void runSync(true)}
        onDisconnect={async () => {
          await disconnect();
          await dropVault();
          await setMeta('lastSyncAt', undefined);
          setSync({state: 'off'});
          notify('드롭박스 연결을 끊었어요');
        }} />
    </div>
  );
}
