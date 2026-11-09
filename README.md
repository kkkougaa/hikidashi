# hikidashi

링크와 메모를 모아두는 모바일 웹앱(PWA). 引き出し(서랍)에서 따온 이름. 데이터는 기기 안(IndexedDB)에 저장되고, 원하면 드롭박스로 아이폰 앱·다른 컴퓨터와 맞춘다 (서버 없음, 기기에서 잠가서 올림). 아이폰 앱은 [`ios/`](ios/README.md).

## 할 수 있는 것

- 링크·메모 추가, 편집, 삭제(되돌리기 가능)
- + 버튼을 위로 끌어올렸다 놓으면 복사한 링크를 바로 추가 (제목·내용·아이콘은 뒤이어 자동으로 채움)
- 링크를 붙여넣으면 페이지 제목·소개문을 자동으로 채움 (소개문이 없으면 본문 첫 문단)
- 항목 아이콘: 글 대표 이미지 → 본문 이미지 → 사이트 로고 순 (유튜브는 영상 썸네일)
- 태그는 칩으로 입력: 스페이스·쉼표·엔터로 추가, 없는 태그는 새로 만듦, 기존 태그 추천
- 태그 맨 앞에 출처 사이트 칩(로고 + 사이트 이름)
- 항목 아이콘으로 토스페이스 이모지를 고를 수 있음 (메모, 로고 없는 링크 등)
- 서랍(폴더) 만들기, 이름·색 바꾸기, 삭제(안의 항목은 미분류로)
- 태그, 즐겨찾기, 검색, 목록/카드 보기 (카드는 그림 비율대로 크게, 두 줄 벽돌 쌓기)
- 왼쪽 서랍: 보관함, 하이라이트, 열리지 않는 링크, 최근 연 항목, 서랍, 태그, 설정(톱니)
- 여러 개 골라 옮기기·태그 달기·즐겨찾기·삭제 (되돌리기)
- 리더 모드: 광고·메뉴 없이 본문만, 글꼴·크기·줄 간격, 문단 형광펜. 본문은 기기에 저장돼 원본이 지워져도 읽힘
- 하이라이트 모아 보기, 메모 속 링크 미리보기(바로 저장)
- 저장할 때 주소의 추적 꼬리(utm_, fbclid, 유튜브 si 등) 제거
- 설정: 화면 모드(시스템·라이트·다크), 기본 보기, 기본 서랍, 링크 열기(리더/새 탭), 태그 이름 바꾸기·합치기·지우기, 서랍 순서
- 밀어서 즐겨찾기·편집·삭제, 길게 눌러 메뉴
- 백업 파일 만들기/가져오기 (같은 항목은 더 최근에 고친 쪽을 남김)
- 오프라인에서도 열림, 홈 화면에 추가하면 앱처럼 동작
- 안드로이드: 다른 앱의 공유 메뉴에서 "hikidashi"로 바로 보내기

## 외부 서비스

이 앱에는 서버가 없어서 링크 정보는 아래 무료 서비스를 거친다. 데이터는 여전히 폰에만 저장된다.

- 페이지 제목·소개문·이미지: [Jina Reader](https://jina.ai/reader) (`r.jina.ai`). 키 없이 쓰므로 요청 수 제한이 있다. 실패하면 직접 적으면 된다.
- X(트위터) 게시물: [FxTwitter](https://github.com/FixTweet/FxTwitter) 공개 API (`api.fxtwitter.com`). X 는 로그인 없이 글을 읽을 수 없어서 따로 쓴다. 실패하면 Jina Reader 로 다시 시도.
- 사이트 로고: Google 파비콘 서비스 (`www.google.com/s2/favicons`)
- 저장한 링크 주소가 이 서비스들로 전달된다.
- 동기화를 켜면: 드롭박스 API (`api.dropboxapi.com`, `content.dropboxapi.com`, `notify.dropboxapi.com`). 올라가는 건 동기화 암호로 잠근 파일뿐이라 드롭박스는 내용을 볼 수 없다.

## 사용한 글꼴·이모지

- 이모지: [토스페이스](https://toss.im/tossface) (`cdn.jsdelivr.net/gh/toss/tossface@1.6.1`).
  Copyright (c) 2022, 2023 Viva Republica, with Reserved Font Name Tossface.
  라이선스: https://toss.im/tossface/copyright · 원본 그대로 쓰고 수정하지 않는다.

## 개발

```bash
npm install
npm run dev        # 개발 서버
npm test           # 단위 테스트
npm run build      # 타입 검사 + 배포용 빌드 (dist/)
npm run preview    # 빌드 결과 미리 보기
```

## 배포 (GitHub Pages)

1. 이 폴더를 GitHub 저장소의 `main` 브랜치에 올린다.
2. 저장소 Settings → Pages → Source 를 **GitHub Actions** 로 바꾼다.
3. `main` 에 푸시할 때마다 테스트 후 자동 배포된다. 주소는 `https://<아이디>.github.io/<저장소>/`.

## 폰에 설치

- iPhone: Safari로 주소를 열고 공유 버튼 → **홈 화면에 추가**
- Android: Chrome으로 열고 메뉴 → **앱 설치** (또는 홈 화면에 추가)

홈 화면에 추가해야 저장 공간이 보호된다. 브라우저 탭으로만 쓰면 오래 안 열었을 때 브라우저가 데이터를 지울 수 있으니, 설정에서 가끔 백업 파일을 만들어 두자.

## 동기화 (드롭박스, 종단간 암호화)

아이폰 앱과 웹앱이 드롭박스 **앱 폴더**(`/앱/<앱 이름>`)의 파일 하나 `hikidashi-sync.enc` 를 함께 쓴다. 파일은 각 기기에서 **동기화 암호**로 잠근 뒤 올리므로 드롭박스(와 드롭박스 계정을 턴 사람)는 내용을 볼 수 없다. 서버도 돈도 필요 없다. 규칙은 [`docs/SPEC.md`](docs/SPEC.md#동기화-드롭박스-종단간-암호화).

- 한 번 연결하면 계속 로그인돼 있다 (갱신 토큰을 기기에 둔다. 웹은 브라우저 저장소, 아이폰은 키체인).
- 동기화 암호도 기기마다 처음 한 번만 넣는다 (키를 꺼낼 수 없는 형태로 기기에 둔다).
- 열려 있는 동안 다른 기기가 올리면 몇 초 안에 들어온다 (드롭박스 변경 알림). 그 밖에 열 때, 돌아올 때, 고치고 3초 뒤. 아이폰은 닫혀 있어도 iOS 가 가끔 깨워 줄 때 맞춘다.
- 어느 브라우저든 된다 (크롬·엣지·사파리·파이어폭스).
- **동기화 암호를 잊으면 드롭박스 사본은 아무도 못 연다.** 기기에 있는 데이터는 그대로니, 연결을 끊고 드롭박스 앱 폴더의 파일을 지운 뒤 새 암호로 다시 연결하면 된다.

### 처음 한 번: 드롭박스 앱 만들기 (5분, 무료)

1. <https://www.dropbox.com/developers/apps> → **Create app**
   - Choose an API: **Scoped access**
   - Choose the type of access: **App folder** (이 앱 폴더만 볼 수 있다)
   - Name: 겹치지 않는 이름 (예: `hikidashi-sync-내아이디`). 드롭박스에 `/앱/<이 이름>` 폴더가 생긴다.
2. **Permissions** 탭에서 세 개를 켜고 아래 **Submit**
   - `files.metadata.read`, `files.content.read`, `files.content.write`
   - (로그인하기 전에 해야 한다. 나중에 바꾸면 기기마다 연결을 끊고 다시 연결)
3. **Settings** 탭
   - **OAuth 2 → Redirect URIs** 에 셋을 하나씩 **Add**
     - `https://kkkougaa.github.io/hikidashi/` (웹앱 주소, 끝의 `/` 까지)
     - `http://localhost:5173/` (개발용)
     - `db-<App key>://2/token` (아이폰 앱. `<App key>` 자리에 아래 App key)
   - **Allow public clients (Implicit Grant & PKCE)** 는 **Allow** 로 둔다 (기본값)
   - **App key** 를 복사한다. (App secret 은 쓰지 않는다)
4. GitHub 저장소 → Settings → Secrets and variables → Actions → **Variables** → New repository variable
   - `DROPBOX_APP_KEY` = 위 App key (비밀값이 아니라서 변수로 둔다. 웹앱에도 그대로 실린다)
5. `main` 에 푸시하면 웹(Pages)과 아이폰(TestFlight)이 앱 키를 넣어 새로 나간다.

로컬에서 해 보려면 `.env.local` 에 `VITE_DROPBOX_APP_KEY=앱키` 를 넣고 `npm run dev` (5173 포트).

### 쓰는 법

1. 첫 기기: 서랍 → ⚙︎ → 동기화 → **드롭박스로 동기화** → 드롭박스 로그인·허용 → 돌아오면 **동기화 암호 정하기** (8자 이상, 두 번).
2. 다른 기기: 같은 순서로 연결하고 **같은 동기화 암호**를 넣는다.
3. 끝. 그다음부터는 저절로 맞춘다. 처음 연결하면 그 기기의 항목과 드롭박스의 항목을 합친다 (같은 항목은 더 나중에 고친 쪽).

## 구조

```
assets/icon-source.png    앱 아이콘 원본 (public/icons 의 크기별 파일은 여기서 잘라 만든 것)
src/
  App.tsx                 화면 전체, 상태 연결
  data/types.ts           Item, Folder, 색
  data/db.ts              IndexedDB 읽기·쓰기
  data/library.ts         useLibrary: 추가·수정·삭제·되돌리기
  data/backup.ts          백업 만들기·검사·합치기
  data/vault.ts           동기화 파일 잠그기·열기 (PBKDF2 + AES-GCM)
  data/fileSync.ts        동기화 규칙 (받기·풀기·합치기·올리기)
  data/dropbox.ts         드롭박스 로그인(PKCE)·파일 읽고 쓰기·변경 알림
  lib/format.ts           주소·태그·날짜 처리
  lib/pageInfo.ts         링크 정보 가져오기·정리, 로고 주소
  components/             목록, 카드, 시트들
```
