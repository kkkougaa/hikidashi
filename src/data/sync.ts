import {getMeta, setMeta} from './db';
import {parseBackup} from './backup';
import type {Backup} from './types';

/**
 * 서버 없는 동기화: 아이폰 앱과 같은 iCloud Drive 폴더의 hikidashi-sync.json 하나를 함께 쓴다.
 * 윈도우는 iCloud for Windows 가 그 폴더를 내 컴퓨터에 맞춰 주고, 웹앱은 크롬·엣지의
 * 파일 시스템 접근(File System Access)으로 그 폴더를 읽고 쓴다. 데이터는 형의 iCloud 밖으로 나가지 않는다.
 */
export const SYNC_FILE = 'hikidashi-sync.json';

type Perm = 'granted' | 'prompt' | 'denied';
interface DirHandle {
  name: string;
  values(): AsyncIterable<{kind: 'file' | 'directory'; name: string; getFile?: () => Promise<File>}>;
  getFileHandle(name: string, o?: {create?: boolean}): Promise<{createWritable(): Promise<{write(d: string): Promise<void>; close(): Promise<void>}>}>;
  removeEntry(name: string): Promise<void>;
  queryPermission(o: {mode: 'readwrite'}): Promise<Perm>;
  requestPermission(o: {mode: 'readwrite'}): Promise<Perm>;
}
type Picker = (o: {id?: string; mode?: 'readwrite'}) => Promise<DirHandle>;

/** 크롬·엣지(데스크톱)만 된다. 사파리·파이어폭스·아이폰은 안 됨 */
export const syncSupported = () => typeof window !== 'undefined' && 'showDirectoryPicker' in window;

/** 아이폰 앱과 같은 규칙: hikidashi-sync 로 시작하는 .json (충돌 사본 포함) */
export const isSyncFile = (name: string) => /^hikidashi-sync.*\.json$/i.test(name);

export async function savedFolder(): Promise<DirHandle | undefined> {
  return getMeta<DirHandle>('syncDir');
}

export async function pickFolder(): Promise<DirHandle> {
  const dir = await (window as unknown as {showDirectoryPicker: Picker}).showDirectoryPicker({id: 'hikidashi-sync', mode: 'readwrite'});
  await setMeta('syncDir', dir);
  return dir;
}

export async function forgetFolder() {
  await setMeta('syncDir', undefined);
  await setMeta('lastSyncAt', undefined);
}

/** 권한 확인. ask 는 사용자가 누른 그 순간에만 (브라우저 규칙) */
export async function permission(dir: DirHandle, ask = false): Promise<Perm> {
  const p = await dir.queryPermission({mode: 'readwrite'});
  if (p === 'granted' || !ask) return p;
  return dir.requestPermission({mode: 'readwrite'});
}

/** 폴더의 동기화 파일들을 모두 읽는다 */
export async function readAll(dir: DirHandle): Promise<{backups: Backup[]; extras: string[]}> {
  const backups: Backup[] = [];
  const extras: string[] = [];
  for await (const entry of dir.values()) {
    if (entry.kind !== 'file' || !isSyncFile(entry.name) || !entry.getFile) continue;
    try {
      backups.push(parseBackup(await (await entry.getFile()).text()));
      if (entry.name !== SYNC_FILE) extras.push(entry.name);
    } catch { /* 깨진 파일은 건너뛴다 */ }
  }
  return {backups, extras};
}

/** 합친 결과를 쓰고, 다 합친 충돌 사본은 지운다 */
export async function writeAll(dir: DirHandle, text: string, extras: string[]) {
  const fh = await dir.getFileHandle(SYNC_FILE, {create: true});
  const w = await fh.createWritable();
  await w.write(text);
  await w.close();
  for (const name of extras) await dir.removeEntry(name).catch(() => {});
}
