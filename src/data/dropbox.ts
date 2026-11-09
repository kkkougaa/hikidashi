import {getMeta, setMeta} from './db';
import type {RemoteFile} from './fileSync';

/**
 * 드롭박스 연결 (서버 없이 브라우저에서 OAuth PKCE).
 * 앱은 "App folder" 권한이라 드롭박스의 /앱/hikidashi 폴더만 보고, 그 안에 잠근 파일 하나만 둔다.
 * 갱신 토큰(refresh token)을 기기에 두므로 연결을 끊기 전까지 다시 로그인하지 않는다.
 * 앱 키는 비밀값이 아니다 (PKCE 는 비밀 없이 동작).
 */
export const DROPBOX_KEY = import.meta.env.VITE_DROPBOX_APP_KEY || '';
export const SYNC_PATH = '/hikidashi-sync.enc';
export const dropboxConfigured = () => !!DROPBOX_KEY;

const API = 'https://api.dropboxapi.com/2/';
const CONTENT = 'https://content.dropboxapi.com/2/';
const NOTIFY = 'https://notify.dropboxapi.com/2/';
const TOKEN_URL = 'https://api.dropboxapi.com/oauth2/token';

interface Tokens {refresh: string}
/** 연결이 끊겼다 (토큰이 취소됐거나 앱 권한을 지웠다) */
export class NotConnected extends Error {
  constructor() { super('드롭박스 연결이 끊겼어요. 다시 연결해주세요'); }
}

const b64url = (u: Uint8Array) => btoa(String.fromCharCode(...u)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const randomText = (n: number) => b64url(crypto.getRandomValues(new Uint8Array(n)));

/** 돌아올 주소: 지금 페이지 (GitHub Pages 하위 경로 포함). 드롭박스 앱 설정에 똑같이 등록해야 한다 */
export const redirectUri = () => location.origin + location.pathname.replace(/index\.html$/, '');

export async function isConnected() {
  return !!(await getMeta<Tokens>('dropbox'))?.refresh;
}

/** 드롭박스 로그인 화면으로 보낸다 */
export async function startLogin() {
  const verifier = randomText(48);
  const challenge = b64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
  const state = randomText(16);
  sessionStorage.setItem('dropboxPkce', JSON.stringify({verifier, state}));
  const q = new URLSearchParams({
    client_id: DROPBOX_KEY,
    response_type: 'code',
    code_challenge: challenge,
    code_challenge_method: 'S256',
    token_access_type: 'offline', // 갱신 토큰을 받아 계속 로그인 상태로
    redirect_uri: redirectUri(),
    state,
  });
  location.assign(`https://www.dropbox.com/oauth2/authorize?${q}`);
}

/** 로그인하고 돌아왔으면 토큰으로 바꾼다. 'none' 이면 돌아온 게 아님 */
export async function finishLogin(): Promise<'none' | 'ok' | 'denied'> {
  const url = new URL(location.href);
  const code = url.searchParams.get('code');
  const error = url.searchParams.get('error');
  const state = url.searchParams.get('state');
  if (!code && !error) return 'none';
  const saved = JSON.parse(sessionStorage.getItem('dropboxPkce') ?? 'null') as {verifier: string; state: string} | null;
  sessionStorage.removeItem('dropboxPkce');
  // 주소창에서 code 를 지운다
  for (const k of ['code', 'state', 'error', 'error_description']) url.searchParams.delete(k);
  history.replaceState(null, '', url.toString());
  // 내가 보낸 요청에 대한 답인지 (state 가 같아야 한다)
  if (error || !code || !saved || saved.state !== state) return 'denied';
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({grant_type: 'authorization_code', code, client_id: DROPBOX_KEY, code_verifier: saved.verifier, redirect_uri: redirectUri()}),
  });
  if (!res.ok) return 'denied';
  const j = await res.json() as {access_token: string; expires_in: number; refresh_token?: string};
  if (!j.refresh_token) return 'denied';
  await setMeta('dropbox', {refresh: j.refresh_token} satisfies Tokens);
  access = {token: j.access_token, until: Date.now() + (j.expires_in - 60) * 1000};
  return 'ok';
}

let access: {token: string; until: number} | null = null;

async function accessToken(force = false): Promise<string> {
  if (access && !force && Date.now() < access.until) return access.token;
  const t = await getMeta<Tokens>('dropbox');
  if (!t?.refresh) throw new NotConnected();
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({grant_type: 'refresh_token', refresh_token: t.refresh, client_id: DROPBOX_KEY}),
  });
  if (res.status === 400 || res.status === 401) { await forget(); throw new NotConnected(); }
  if (!res.ok) throw new Error(`드롭박스에 연결하지 못했어요 (${res.status})`);
  const j = await res.json() as {access_token: string; expires_in: number};
  access = {token: j.access_token, until: Date.now() + (j.expires_in - 60) * 1000};
  return access.token;
}

/** 토큰을 붙여 부른다. 401 이면 토큰을 새로 받아 한 번 더 */
async function call(url: string, init: RequestInit): Promise<Response> {
  for (let i = 0; i < 2; i++) {
    const res = await fetch(url, {...init, headers: {...init.headers, Authorization: `Bearer ${await accessToken(i > 0)}`}});
    if (res.status !== 401) return res;
  }
  await forget();
  throw new NotConnected();
}

/** 드롭박스 오류 본문의 요약 (예: path/not_found/...) */
async function summary(res: Response): Promise<string> {
  try { return ((await res.json()) as {error_summary?: string}).error_summary ?? ''; } catch { return ''; }
}

async function rpc<T>(endpoint: string, body: unknown): Promise<{ok: true; data: T} | {ok: false; status: number; error: string}> {
  const res = await call(API + endpoint, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
  if (res.ok) return {ok: true, data: await res.json() as T};
  return {ok: false, status: res.status, error: await summary(res)};
}

const fail = (status: number, error: string) => new Error(`드롭박스 오류 (${error || status})`);

/** 앱 폴더의 잠근 동기화 파일 */
export const dropboxFile: RemoteFile = {
  async rev() {
    const r = await rpc<{rev: string}>('files/get_metadata', {path: SYNC_PATH});
    if (r.ok) return r.data.rev;
    if (r.error.startsWith('path/not_found')) return null;
    throw fail(r.status, r.error);
  },
  async read() {
    const res = await call(CONTENT + 'files/download', {method: 'POST', headers: {'Dropbox-API-Arg': JSON.stringify({path: SYNC_PATH})}});
    if (res.status === 409) {
      const e = await summary(res);
      if (e.startsWith('path/not_found')) return null;
      throw fail(409, e);
    }
    if (!res.ok) throw fail(res.status, await summary(res));
    const meta = JSON.parse(res.headers.get('Dropbox-API-Result') ?? '{}') as {rev?: string};
    if (!meta.rev) throw new Error('드롭박스 응답을 읽지 못했어요');
    return {text: await res.text(), rev: meta.rev};
  },
  async write(text, rev) {
    const arg = {path: SYNC_PATH, mode: rev ? {'.tag': 'update', update: rev} : {'.tag': 'add'}, autorename: false, mute: true, strict_conflict: true};
    const res = await call(CONTENT + 'files/upload', {
      method: 'POST',
      headers: {'Dropbox-API-Arg': JSON.stringify(arg), 'Content-Type': 'application/octet-stream'},
      body: text,
    });
    if (res.status === 409) {
      const e = await summary(res);
      if (e.includes('conflict')) return 'conflict';
      throw fail(409, e);
    }
    if (!res.ok) throw fail(res.status, await summary(res));
    return ((await res.json()) as {rev: string}).rev;
  },
};

// MARK: 바뀌면 바로 알기 (롱폴링). 앱이 열려 있는 동안만

export async function latestCursor(): Promise<string> {
  const r = await rpc<{cursor: string}>('files/list_folder/get_latest_cursor', {path: ''});
  if (!r.ok) throw fail(r.status, r.error);
  return r.data.cursor;
}

/** 폴더가 바뀔 때까지(최대 timeout 초) 기다린다. 토큰이 필요 없다 */
export async function waitForChange(cursor: string, signal: AbortSignal, timeout = 120): Promise<{changes: boolean; backoff?: number}> {
  const res = await fetch(NOTIFY + 'files/list_folder/longpoll', {
    method: 'POST', signal,
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({cursor, timeout}),
  });
  if (!res.ok) throw fail(res.status, await summary(res));
  return res.json();
}

/** 바뀐 걸 읽어 커서를 앞으로 옮긴다 */
export async function advanceCursor(cursor: string): Promise<string> {
  let c = cursor;
  for (;;) {
    const r = await rpc<{cursor: string; has_more: boolean}>('files/list_folder/continue', {cursor: c});
    if (!r.ok) {
      if (r.error.startsWith('reset')) return latestCursor();
      throw fail(r.status, r.error);
    }
    c = r.data.cursor;
    if (!r.data.has_more) return c;
  }
}

/** 이 기기에서 연결을 끊는다 (드롭박스 쪽 토큰도 취소) */
export async function disconnect() {
  try { await call(API + 'auth/token/revoke', {method: 'POST'}); } catch { /* 이미 끊겼으면 그만 */ }
  await forget();
}

async function forget() {
  access = null;
  await setMeta('dropbox', undefined);
}
