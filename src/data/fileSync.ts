import {makeBackup, mergeRecords, parseBackup} from './backup';
import type {Backup, Folder, Item} from './types';
import {openEnvelope, readEnvelope, seal, type Vault} from './vault';

/**
 * 파일 하나로 맞추는 동기화 (아이폰 앱과 같은 규칙, docs/SPEC.md).
 * 받기 → 풀기 → 합치기 → 이 기기에 더 새것이 있으면 잠가서 올리기. 올리는 사이 다른 기기가 먼저 올렸으면 다시.
 */
export interface RemoteFile {
  /** 지금 판(rev). 파일이 없으면 null */
  rev(): Promise<string | null>;
  read(): Promise<{text: string; rev: string} | null>;
  /** rev 가 지금 판과 같을 때만 쓴다 (null 이면 새로 만들기). 어긋나면 'conflict' */
  write(text: string, rev: string | null): Promise<string | 'conflict'>;
}

type Records = {items: Item[]; folders: Folder[]};

/** 이 기기에만 있거나 더 나중에 고친 레코드가 있는지 */
export function hasNewer(local: Records, remote: Backup): boolean {
  return mergeRecords(remote.folders, local.folders).changed.length > 0
    || mergeRecords(remote.items, local.items).changed.length > 0;
}

export async function syncFile(
  remote: RemoteFile,
  vault: Vault,
  apply: (b: Backup) => number,
  local: () => Records,
  opts: {lastRev?: string; dirty?: boolean} = {},
): Promise<{changed: number; uploaded: boolean; rev: string | null}> {
  // 지난번 맞춘 뒤로 양쪽 다 그대로면 내려받지 않는다
  if (opts.lastRev && !opts.dirty && (await remote.rev()) === opts.lastRev) return {changed: 0, uploaded: false, rev: opts.lastRev};
  let changed = 0;
  for (let round = 0; round < 3; round++) {
    const got = await remote.read();
    let theirs: Backup | null = null;
    if (got) {
      theirs = parseBackup(await openEnvelope(vault, readEnvelope(got.text)));
      changed += apply(theirs);
    }
    const mine = local();
    if (theirs && !hasNewer(mine, theirs)) return {changed, uploaded: false, rev: got!.rev};
    const text = await seal(vault, JSON.stringify(makeBackup(mine.folders, mine.items)));
    const rev = await remote.write(text, got?.rev ?? null);
    if (rev !== 'conflict') return {changed, uploaded: true, rev};
  }
  throw new Error('다른 기기와 동시에 고치고 있어요. 잠시 뒤에 다시 해주세요');
}
