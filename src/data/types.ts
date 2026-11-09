/** 서랍 색. 흰 굵은 글자가 3:1 이상 나오는 밝은 색만 쓴다 (17가지, 무지개 순). */
export const COLORS = {
  red: '#F04D4D',
  orange: '#E8690A',
  brown: '#BA7A3E',
  mustard: '#B38400',
  lime: '#5C9A16',
  green: '#1E9E55',
  forest: '#2F9459',
  teal: '#14988F',
  cyan: '#0B97B8',
  sky: '#2B8FD9',
  blue: '#3D7FF5',
  navy: '#5B6AE6',
  purple: '#9168F7',
  plum: '#B654CA',
  magenta: '#E3478A',
  gray: '#7F858F',
  charcoal: '#565D68',
} as const;
export type ColorKey = keyof typeof COLORS;

const rgbOf = (hex: string) => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16));
/** 팔레트로 직접 고른 색에 가장 가까운 기본 색 (옛 앱은 이 색으로 보인다) */
export function nearestColor(hex: string): ColorKey {
  const [r, g, b] = rgbOf(hex);
  let best: ColorKey = 'blue', d = Infinity;
  for (const [k, v] of Object.entries(COLORS) as [ColorKey, string][]) {
    const [x, y, z] = rgbOf(v);
    const e = (r - x) ** 2 * 2 + (g - y) ** 2 * 4 + (b - z) ** 2 * 3;
    if (e < d) { d = e; best = k; }
  }
  return best;
}
/** 이 색 위에 올릴 글자 색: 밝은 색이면 검정 */
export function inkOn(hex: string): string {
  const [r, g, b] = rgbOf(hex).map(c => c / 255).map(c => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  const l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  return 1.05 / (l + 0.05) >= 2.6 ? '#FFFFFF' : '#1B1D21';
}
export const isHex = (s: unknown): s is string => typeof s === 'string' && /^#[0-9A-Fa-f]{6}$/.test(s);
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
  /** 팔레트로 직접 고른 색 "#RRGGBB". 있으면 color 대신 쓴다 (color 는 가장 가까운 기본 색) */
  hex?: string | null;
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
  /** 사진에서 잘라 만든 아이콘 (작은 data URL). emoji 다음으로, 글 이미지·로고보다 먼저 쓴다 */
  icon?: string;
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

export type ItemDraft = Pick<Item, 'kind' | 'url' | 'title' | 'note' | 'folderId' | 'tags' | 'image' | 'video' | 'avatar' | 'images' | 'siteName' | 'emoji' | 'icon'>;

export interface Backup {
  app: 'hikidashi';
  version: 1;
  exportedAt: number;
  folders: Folder[];
  items: Item[];
}
