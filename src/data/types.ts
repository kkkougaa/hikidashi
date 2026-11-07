/** 서랍 색. 흰 글자가 4.5:1 이상 나오는 진한 색만 쓴다. */
export const COLORS = {
  blue: '#1366E0',
  cyan: '#007F96',
  orange: '#B95300',
  green: '#16804A',
  magenta: '#C2185B',
  purple: '#6B3FD6',
  gray: '#5F646C',
} as const;
export type ColorKey = keyof typeof COLORS;
export const COLOR_NAMES: Record<ColorKey, string> = {
  blue: '파랑', cyan: '청록', orange: '주황', green: '초록', magenta: '자홍', purple: '보라', gray: '회색',
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
  /** null 이면 미분류 */
  folderId: string | null;
  tags: string[];
  starred: boolean;
}

export type ItemDraft = Pick<Item, 'kind' | 'url' | 'title' | 'note' | 'folderId' | 'tags' | 'image' | 'siteName'>;

export interface Backup {
  app: 'hikidashi';
  version: 1;
  exportedAt: number;
  folders: Folder[];
  items: Item[];
}
