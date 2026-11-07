/** 서랍 색. 흰 글자가 4.5:1 이상 나오는 진한 색만 쓴다 (17가지, 무지개 순). */
export const COLORS = {
  red: '#D02B2B',
  orange: '#B95300',
  brown: '#8B5A2B',
  mustard: '#8A6A00',
  lime: '#4D7C0F',
  green: '#16804A',
  forest: '#166534',
  teal: '#0F766E',
  cyan: '#007F96',
  sky: '#0369A1',
  blue: '#1366E0',
  navy: '#1E3A8A',
  purple: '#6B3FD6',
  plum: '#86198F',
  magenta: '#C2185B',
  gray: '#5F646C',
  charcoal: '#2F343B',
} as const;
export type ColorKey = keyof typeof COLORS;
export const COLOR_NAMES: Record<ColorKey, string> = {
  red: '빨강', orange: '주황', brown: '갈색', mustard: '겨자', lime: '연두', green: '초록', forest: '숲초록',
  teal: '청록', cyan: '하늘청록', sky: '하늘', blue: '파랑', navy: '남색', purple: '보라', plum: '자두',
  magenta: '자홍', gray: '회색', charcoal: '먹색',
};

/**
 * 나중에 서버와 동기화할 수 있게 모든 레코드는
 * 고유 id, 수정 시각, 삭제 표시(deletedAt)를 갖는다. 삭제는 표시만 하고 지우지 않는다.
 */
export interface Base {
  id: string;
  createdAt: number;
  updatedAt: number;
  deletedAt: number | null;
}

export interface Folder extends Base {
  name: string;
  color: ColorKey;
  order: number;
}

export type ItemKind = 'link' | 'memo';

export interface Item extends Base {
  kind: ItemKind;
  /** 링크 주소. 메모는 없음 */
  url?: string;
  title: string;
  /** 링크는 한 줄 메모, 메모는 본문 */
  note: string;
  /** 링크 글의 대표 이미지 주소. 없으면 사이트 로고를 쓴다 */
  image?: string;
  /** 사이트가 밝힌 이름 (예: MDN Web Docs) */
  siteName?: string;
  /** 직접 고른 아이콘 이모지 (토스페이스로 그린다). 있으면 이미지·로고보다 먼저 쓴다 */
  emoji?: string;
  /** null 이면 미분류 */
  folderId: string | null;
  tags: string[];
  starred: boolean;
}

export type ItemDraft = Pick<Item, 'kind' | 'url' | 'title' | 'note' | 'folderId' | 'tags' | 'image' | 'siteName' | 'emoji'>;

export interface Backup {
  app: 'hikidashi';
  version: 1;
  exportedAt: number;
  folders: Folder[];
  items: Item[];
}
