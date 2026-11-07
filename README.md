# hikidashi

링크와 메모를 모아두는 모바일 웹앱(PWA). 引き出し(서랍)에서 따온 이름. 지금은 데이터가 폰 안(IndexedDB)에만 저장된다.

## 할 수 있는 것

- 링크·메모 추가, 편집, 삭제(되돌리기 가능)
- + 버튼을 위로 끌어올렸다 놓으면 복사한 링크를 바로 추가 (제목·내용·아이콘은 뒤이어 자동으로 채움)
- 링크를 붙여넣으면 페이지 제목·소개문을 자동으로 채움 (소개문이 없으면 본문 첫 문단)
- 항목 아이콘: 글 대표 이미지 → 본문 이미지 → 사이트 로고 순 (유튜브는 영상 썸네일)
- 태그는 칩으로 입력: 스페이스·쉼표·엔터로 추가, 없는 태그는 새로 만듦, 기존 태그 추천
- 태그 맨 앞에 출처 사이트 칩(로고 + 사이트 이름)
- 항목 아이콘으로 토스페이스 이모지를 고를 수 있음 (메모, 로고 없는 링크 등)
- 서랍(폴더) 만들기, 이름·색 바꾸기, 삭제(안의 항목은 미분류로)
- 태그, 즐겨찾기, 검색, 목록/카드 보기
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

## 나중에 서버를 붙일 때

모든 레코드에 `id`(UUID), `updatedAt`, `deletedAt`(삭제 표시)가 이미 있다. 서버 동기화는
`src/data/backup.ts` 의 `mergeRecords` 와 같은 규칙(더 최근에 고친 쪽이 이김)으로 붙이면 된다.

## 구조

```
assets/icon-source.png    앱 아이콘 원본 (public/icons 의 크기별 파일은 여기서 잘라 만든 것)
src/
  App.tsx                 화면 전체, 상태 연결
  data/types.ts           Item, Folder, 색
  data/db.ts              IndexedDB 읽기·쓰기
  data/library.ts         useLibrary: 추가·수정·삭제·되돌리기
  data/backup.ts          백업 만들기·검사·합치기
  lib/format.ts           주소·태그·날짜 처리
  lib/pageInfo.ts         링크 정보 가져오기·정리, 로고 주소
  components/             목록, 카드, 시트들
```
