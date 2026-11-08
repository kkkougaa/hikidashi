import {useEffect, useRef, useState} from 'react';
import {ChevronLeft, ChevronRight, Cloud, Download, FolderCog, Hash, RefreshCw, ShieldCheck, Trash2, Upload} from 'lucide-react';
import {SegmentedControl, SegmentedControlItem} from '@astryxdesign/core/SegmentedControl';
import {Switch} from '@astryxdesign/core/Switch';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {clearArticles, countArticles, getMeta, requestPersistence, setMeta} from '../data/db';
import {usePref} from '../lib/prefs';
import {BackupError, makeBackup, parseBackup} from '../data/backup';
import type {Backup, Folder, Item} from '../data/types';
import {fileStamp, stamp} from '../lib/format';
import {SheetBar, SheetHead} from './bits';

const VERSION = '0.1.0';

/** 파일 공유가 되면(iOS) 공유 시트로, 아니면 내려받기로 */
async function saveFile(name: string, text: string): Promise<'shared' | 'downloaded' | 'cancelled'> {
  const blob = new Blob([text], {type: 'application/json'});
  const file = new File([blob], name, {type: 'application/json'});
  if (navigator.canShare?.({files: [file]})) {
    try {
      await navigator.share({files: [file], title: name});
      return 'shared';
    } catch (e) {
      if ((e as DOMException).name === 'AbortError') return 'cancelled';
    }
  }
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
  return 'downloaded';
}

export interface SyncUi {
  supported: boolean;
  /** off: 연결 안 함, ask: 권한을 다시 눌러 줘야 함 */
  state: 'off' | 'ask' | 'idle' | 'syncing' | 'error';
  folder?: string;
  last?: number;
  error?: string;
}

export function SettingsSheet({isOpen, onClose, records, liveCount, onImport, notify, folders, tags, onRenameTag, onRemoveTag, onEditFolders, sync, onPickSync, onSyncNow, onForgetSync}: {
  isOpen: boolean;
  onClose: () => void;
  records: () => {items: Item[]; folders: Folder[]};
  liveCount: number;
  onImport: (b: Backup) => {items: number; folders: number};
  notify: (msg: string, type?: 'info' | 'error') => void;
  folders: Folder[];
  tags: [string, number][];
  onRenameTag: (from: string, to: string) => void;
  onRemoveTag: (tag: string) => void;
  onEditFolders: () => void;
  sync: SyncUi;
  onPickSync: () => void;
  onSyncNow: () => void;
  onForgetSync: () => void;
}) {
  const [mode, setMode] = useState<'main' | 'tags'>('main');
  const [theme, setTheme] = usePref('theme');
  const [view, setView] = usePref('view');
  const [linkOpen, setLinkOpen] = usePref('linkOpen');
  const [saveArticles, setSaveArticles] = usePref('saveArticles');
  const [defaultFolder, setDefaultFolder] = usePref('defaultFolder');
  const [articles, setArticles] = useState(0);
  const fileRef = useRef<HTMLInputElement>(null);
  const [lastBackup, setLastBackup] = useState<number | null>(null);
  const [persisted, setPersisted] = useState<boolean | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    void getMeta<number>('lastBackupAt').then(v => setLastBackup(v ?? null));
    void (navigator.storage?.persisted?.() ?? Promise.resolve(false)).then(setPersisted, () => setPersisted(false));
    void countArticles().then(setArticles, () => {});
    setMode('main');
  }, [isOpen]);

  const exportNow = async () => {
    const {items, folders} = records();
    const name = `hikidashi-backup-${fileStamp()}.json`;
    const res = await saveFile(name, JSON.stringify(makeBackup(folders, items), null, 2));
    if (res === 'cancelled') return;
    const now = Date.now();
    await setMeta('lastBackupAt', now);
    setLastBackup(now);
    notify(res === 'shared' ? '백업 파일을 보냈어요' : '백업 파일을 저장했어요');
  };

  const importFile = async (file: File) => {
    try {
      const b = parseBackup(await file.text());
      const r = onImport(b);
      notify(r.items || r.folders ? `항목 ${r.items}개, 서랍 ${r.folders}개를 가져왔어요` : '새로 가져올 내용이 없어요. 이미 최신이에요');
    } catch (e) {
      notify(e instanceof BackupError ? e.message : '백업을 가져오지 못했어요', 'error');
    }
  };

  return (
    <BottomSheet label="설정" isOpen={isOpen} onOpenChange={o => { if (!o) onClose(); }} height="tall">
      {mode === 'tags' ? <TagManager tags={tags} onBack={() => setMode('main')} onRename={onRenameTag} onRemove={onRemoveTag} /> : <>
      <SheetHead title="설정" onClose={onClose} closeLabel="설정 닫기" />
      <div className="set-group">
        <p className="set-label">화면</p>
        <div className="set-row static">
          <span className="grow">화면 모드</span>
          <SegmentedControl label="화면 모드" value={theme} onChange={v => setTheme(v as typeof theme)} size="sm">
            <SegmentedControlItem value="system" label="시스템" />
            <SegmentedControlItem value="light" label="라이트" />
            <SegmentedControlItem value="dark" label="다크" />
          </SegmentedControl>
        </div>
        <div className="set-row static">
          <span className="grow">기본 보기</span>
          <SegmentedControl label="기본 보기" value={view} onChange={v => setView(v as typeof view)} size="sm">
            <SegmentedControlItem value="list" label="목록" />
            <SegmentedControlItem value="card" label="카드" />
          </SegmentedControl>
        </div>
        <div className="set-row static">
          <span className="grow">링크를 누르면<span className="hint">X 와 유튜브는 늘 새 탭으로 열어요</span></span>
          <SegmentedControl label="링크를 누르면" value={linkOpen} onChange={v => setLinkOpen(v as typeof linkOpen)} size="sm">
            <SegmentedControlItem value="reader" label="리더" />
            <SegmentedControlItem value="tab" label="새 탭" />
          </SegmentedControl>
        </div>
        <label className="set-row static">
          <span className="grow">새 글 본문 미리 저장<span className="hint">원본이 지워져도, 인터넷이 없어도 리더로 읽어요</span></span>
          <Switch label="새 글 본문 미리 저장" isLabelHidden value={saveArticles} onChange={v => setSaveArticles(v)} />
        </label>
      </div>
      <div className="set-group">
        <p className="set-label">새 항목</p>
        <label className="set-row static">
          <span className="grow">기본 서랍<span className="hint">+ 버튼과 끌어올려 추가가 넣는 서랍</span></span>
          <select className="set-select" value={defaultFolder} onChange={e => setDefaultFolder(e.target.value)}>
            <option value="">첫 번째 서랍</option>
            {folders.map(f => <option key={f.id} value={f.id}>{f.name}</option>)}
            <option value="none">미분류</option>
          </select>
        </label>
      </div>
      <div className="set-group">
        <p className="set-label">정리</p>
        <button className="set-row" onClick={onEditFolders}>
          <FolderCog size={20} aria-hidden="true" />
          <span className="grow">서랍 관리<span className="hint">이름·색·순서</span></span>
          <span className="val num">{folders.length}개</span>
          <ChevronRight className="chev" size={18} aria-hidden="true" />
        </button>
        <button className="set-row" onClick={() => setMode('tags')}>
          <Hash size={20} aria-hidden="true" />
          <span className="grow">태그 관리<span className="hint">이름 바꾸기·합치기·지우기</span></span>
          <span className="val num">{tags.length}개</span>
          <ChevronRight className="chev" size={18} aria-hidden="true" />
        </button>
      </div>
      <div className="set-group">
        <p className="set-label">동기화 (iCloud Drive)</p>
        {!sync.supported ? (
          <div className="set-row static"><Cloud size={20} aria-hidden="true" />
            <span className="grow">이 브라우저에선 안 돼요<span className="hint">윈도우·맥의 크롬이나 엣지에서 iCloud Drive 폴더를 골라 맞춰요. 아이폰은 앱에서 해주세요</span></span>
          </div>
        ) : sync.state === 'off' ? (
          <button className="set-row" onClick={onPickSync}>
            <Cloud size={20} aria-hidden="true" />
            <span className="grow">iCloud Drive 폴더 고르기<span className="hint">아이폰 앱과 같은 hikidashi 폴더를 골라요 (윈도우: iCloud for Windows 의 iCloudDrive\hikidashi)</span></span>
            <ChevronRight className="chev" size={18} aria-hidden="true" />
          </button>
        ) : (
          <>
            <button className="set-row" onClick={onSyncNow} disabled={sync.state === 'syncing'}>
              <RefreshCw size={20} aria-hidden="true" className={sync.state === 'syncing' ? 'spin' : undefined} />
              <span className="grow">{sync.state === 'ask' ? '동기화 다시 연결' : '지금 동기화'}
                <span className="hint">{sync.state === 'error' ? sync.error : sync.state === 'ask' ? '브라우저를 다시 열면 폴더 권한을 한 번 더 눌러줘야 해요' : sync.last ? `마지막 ${stamp(sync.last)}` : '아직 안 했어요'}</span>
              </span>
              <span className="val">{sync.folder}</span>
            </button>
            <button className="set-row danger" onClick={onForgetSync}>
              <span className="grow">연결 끊기</span>
            </button>
          </>
        )}
      </div>
      <div className="set-group">
        <p className="set-label">백업</p>
        <button className="set-row" onClick={exportNow}>
          <Download size={20} aria-hidden="true" />
          <span className="grow">백업 파일 만들기<span className="hint">{lastBackup ? `마지막 백업 ${stamp(lastBackup)}` : '아직 백업한 적이 없어요'}</span></span>
          <ChevronRight className="chev" size={18} aria-hidden="true" />
        </button>
        <button className="set-row" onClick={() => fileRef.current?.click()}>
          <Upload size={20} aria-hidden="true" />
          <span className="grow">백업에서 가져오기<span className="hint">같은 항목은 더 최근에 고친 쪽을 남겨요</span></span>
          <ChevronRight className="chev" size={18} aria-hidden="true" />
        </button>
        <input ref={fileRef} type="file" accept="application/json,.json" hidden
          onChange={e => { const f = e.target.files?.[0]; e.target.value = ''; if (f) void importFile(f); }} />
      </div>
      <div className="set-group">
        <p className="set-label">저장</p>
        <button className="set-row" disabled={persisted === true}
          onClick={async () => { const ok = await requestPersistence(); setPersisted(ok); notify(ok ? '저장 공간을 보호하도록 설정했어요' : '브라우저가 요청을 받아주지 않았어요. 홈 화면에 추가하면 보호돼요', ok ? 'info' : 'error'); }}>
          <ShieldCheck size={20} aria-hidden="true" />
          <span className="grow">이 기기에만 저장 중<span className="hint">{persisted ? '저장 공간 보호 켜짐' : '홈 화면에 추가하고 가끔 백업해 두세요'}</span></span>
          {!persisted && <span className="val">보호 요청</span>}
        </button>
        <div className="set-row" style={{cursor: 'default'}}>
          <span className="grow">항목</span><span className="val num">{liveCount}개</span>
        </div>
        <div className="set-row" style={{cursor: 'default'}}>
          <span className="grow">저장한 본문</span><span className="val num">{articles}개</span>
        </div>
        <button className="set-row danger" disabled={!articles} onClick={async () => { await clearArticles(); setArticles(0); notify('저장한 본문을 비웠어요'); }}>
          <Trash2 size={20} aria-hidden="true" /><span className="grow">저장한 본문 비우기</span>
        </button>
        <div className="set-row" style={{cursor: 'default'}}>
          <span className="grow">버전</span><span className="val num">{VERSION}</span>
        </div>
      </div>
      </>}
    </BottomSheet>
  );
}

/** 태그 관리: 눌러서 이름 바꾸기(같은 이름이면 합치기), 휴지통으로 지우기 */
function TagManager({tags, onBack, onRename, onRemove}: {tags: [string, number][]; onBack: () => void; onRename: (from: string, to: string) => void; onRemove: (tag: string) => void}) {
  const [editing, setEditing] = useState<string | null>(null);
  const [value, setValue] = useState('');
  return (
    <>
      <SheetBar onClose={onBack} closeLabel="설정으로" center={<h2 className="sheet-title">태그 관리</h2>} />
      <div className="sheet-back-hint"><button type="button" className="link-btn" onClick={onBack}><ChevronLeft size={16} aria-hidden="true" />설정</button></div>
      {!tags.length && <p className="form-hint center">태그가 없어요. 항목을 추가할 때 달면 여기서 정리할 수 있어요.</p>}
      <div className="set-group">
        {tags.map(([t, n]) => editing === t ? (
          <form key={t} className="set-row static" noValidate onSubmit={e => { e.preventDefault(); onRename(t, value); setEditing(null); }}>
            <input className="tag-edit" autoFocus value={value} aria-label={`#${t} 새 이름`} onChange={e => setValue(e.target.value)} />
            <button type="submit" className="link-btn">바꾸기</button>
            <button type="button" className="link-btn muted" onClick={() => setEditing(null)}>취소</button>
          </form>
        ) : (
          <div key={t} className="set-row static">
            <button type="button" className="grow tag-name" onClick={() => { setEditing(t); setValue(t); }}>#{t}</button>
            <span className="val num">{n}</span>
            <button type="button" className="icon-btn" aria-label={`#${t} 지우기`} onClick={() => onRemove(t)}><Trash2 size={17} /></button>
          </div>
        ))}
      </div>
      {tags.length > 0 && <p className="form-hint center">이미 있는 이름으로 바꾸면 두 태그가 합쳐져요. 지우면 항목에서 태그만 빠져요.</p>}
    </>
  );
}
