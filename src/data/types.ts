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
  /** 하위 서랍은 화면에서 상위 서랍 색을 따른다 (값은 만들 때 상위 색을 넣어 둔다) */
  color: ColorKey;
  /** 순서. 하위 서랍은 같은 상위 서랍 안에서의 순서 */
  order: number;
  /** 하위 서랍이면 상위 서랍 id (한 단계만). 없거나 null 이면 위 단계 */
  parentId?: string | null;
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
  /** 링크에 딸린 영상 주소 (mp4 등). 카드에서 2초만 소리 없이 반복 재생한다 */
  video?: string;
  /** 글 쓴 사람 프로필 사진 (X 등 SNS). 타임라인 보기의 동그란 사진 자리 */
  avatar?: string;
  /** 게시물에 붙은 사진 전부 (X 는 최대 4장). 타임라인 보기에서 다 보여준다 */
  images?: string[];
  /** 사이트가 밝힌 이름 (예: MDN Web Docs) */
  siteName?: string;
  /** 직접 고른 아이콘 이모지 (토스페이스로 그린다). 있으면 이미지·로고보다 먼저 쓴다 */
  emoji?: string;
  /** null 이면 미분류 */
  folderId: string | null;
  tags: string[];
  starred: boolean;
  /** 리더에서 형광펜 친 문단들 */
  highlights?: string[];
  /** 링크가 열리지 않는 걸 처음 알게 된 때 (앱이 점검한다. 열리면 없음) */
  brokenAt?: number | null;
  /** 링크 점검을 마지막으로 한 때 */
  checkedAt?: number;
  /** 확인 완료한 때. 있으면 목록에서 빠지고 "완료함" 에만 보인다 */
  doneAt?: number | null;
}

export type ItemDraft = Pick<Item, 'kind' | 'url' | 'title' | 'note' | 'folderId' | 'tags' | 'image' | 'video' | 'avatar' | 'images' | 'siteName' | 'emoji'>;

export interface Backup {
  app: 'hikidashi';
  version: 1;
  exportedAt: number;
  folders: Folder[];
  items: Item[];
}
