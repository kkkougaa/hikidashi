import {useEffect, useRef, useState} from 'react';
import {ChevronRight, Download, ShieldCheck, Upload} from 'lucide-react';
import {BottomSheet} from '@astryxdesign/core/BottomSheet';
import {getMeta, requestPersistence, setMeta} from '../data/db';
import {BackupError, makeBackup, parseBackup} from '../data/backup';
import type {Backup, Folder, Item} from '../data/types';
import {fileStamp, stamp} from '../lib/format';
import {SheetHead} from './bits';

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

export function SettingsSheet({isOpen, onClose, records, liveCount, onImport, notify}: {
  isOpen: boolean;
  onClose: () => void;
  records: () => {items: Item[]; folders: Folder[]};
  liveCount: number;
  onImport: (b: Backup) => {items: number; folders: number};
  notify: (msg: string, type?: 'info' | 'error') => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [lastBackup, setLastBackup] = useState<number | null>(null);
  const [persisted, setPersisted] = useState<boolean | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    void getMeta<number>('lastBackupAt').then(v => setLastBackup(v ?? null));
    void (navigator.storage?.persisted?.() ?? Promise.resolve(false)).then(setPersisted, () => setPersisted(false));
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
    <BottomSheet label="설정" isOpen={isOpen} onOpenChange={o => { if (!o) onClose(); }} height="hug">
      <SheetHead title="설정" onClose={onClose} closeLabel="설정 닫기" />
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
          <span className="grow">버전</span><span className="val num">{VERSION}</span>
        </div>
      </div>
    </BottomSheet>
  );
}
