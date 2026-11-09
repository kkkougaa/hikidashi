/**
 * 동기화 파일 암호화 (종단간). 드롭박스에는 이 봉투만 올라가고, 내용은 동기화 암호를 아는 기기만 연다.
 * 아이폰 앱(HikidashiCore/SyncVault.swift)과 같은 형식:
 *   PBKDF2-SHA256(암호 NFC, salt, iter) → 256비트 키 → AES-GCM(12바이트 iv), data = 암호문 ‖ 16바이트 태그
 */
export const VAULT_ITER = 600_000;

export interface Kdf {name: 'PBKDF2'; hash: 'SHA-256'; iter: number; salt: string}
export interface Envelope {app: 'hikidashi-sync'; v: 1; kdf: Kdf; iv: string; data: string}

/** 이 기기에 남겨 두는 키 (꺼낼 수 없는 CryptoKey) */
export interface Vault {key: CryptoKey; kdf: Kdf}

export class VaultError extends Error {}
/** 암호가 틀렸거나 다른 기기에서 암호를 바꿨다 */
export class WrongPassphrase extends VaultError {
  constructor() { super('동기화 암호가 맞지 않아요'); }
}

export function toB64(u: Uint8Array): string {
  let s = '';
  for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000));
  return btoa(s);
}
export function fromB64(s: string): Uint8Array {
  const bin = atob(s);
  const u = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
  return u;
}

export function newKdf(iter = VAULT_ITER): Kdf {
  return {name: 'PBKDF2', hash: 'SHA-256', iter, salt: toB64(crypto.getRandomValues(new Uint8Array(16)))};
}

/** 암호 → 키. 한글은 입력기마다 조합 방식이 달라서 NFC 로 맞춘다 */
export async function deriveKey(passphrase: string, kdf: Kdf): Promise<CryptoKey> {
  const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(passphrase.normalize('NFC')), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    {name: 'PBKDF2', hash: 'SHA-256', salt: fromB64(kdf.salt), iterations: kdf.iter},
    base, {name: 'AES-GCM', length: 256}, false, ['encrypt', 'decrypt'],
  );
}

export async function seal(v: Vault, text: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = new Uint8Array(await crypto.subtle.encrypt({name: 'AES-GCM', iv}, v.key, new TextEncoder().encode(text)));
  const env: Envelope = {app: 'hikidashi-sync', v: 1, kdf: v.kdf, iv: toB64(iv), data: toB64(data)};
  return JSON.stringify(env);
}

export function readEnvelope(text: string): Envelope {
  let e: Partial<Envelope>;
  try { e = JSON.parse(text); } catch { throw new VaultError('동기화 파일을 읽을 수 없어요'); }
  const k = e?.kdf;
  if (e?.app !== 'hikidashi-sync' || e.v !== 1 || !k || k.name !== 'PBKDF2' || k.hash !== 'SHA-256'
    || typeof k.iter !== 'number' || typeof k.salt !== 'string' || typeof e.iv !== 'string' || typeof e.data !== 'string') {
    throw new VaultError('hikidashi 동기화 파일이 아니에요');
  }
  return e as Envelope;
}

export async function openEnvelope(v: Vault, env: Envelope): Promise<string> {
  // 다른 기기에서 암호를 바꿨으면 salt 가 다르다
  if (env.kdf.salt !== v.kdf.salt || env.kdf.iter !== v.kdf.iter) throw new WrongPassphrase();
  try {
    const plain = await crypto.subtle.decrypt({name: 'AES-GCM', iv: fromB64(env.iv)}, v.key, fromB64(env.data));
    return new TextDecoder().decode(plain);
  } catch {
    throw new WrongPassphrase();
  }
}
