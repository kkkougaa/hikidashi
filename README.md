# 서랍

링크와 메모를 모아두는 모바일 웹앱(PWA). 지금은 데이터가 폰 안(IndexedDB)에만 저장된다.

## 할 수 있는 것

- 링크·메모 추가, 편집, 삭제(되돌리기 가능)
- 서랍(폴더) 만들기, 이름·색 바꾸기, 삭제(안의 항목은 미분류로)
- 태그, 즐겨찾기, 검색, 목록/카드 보기
- 밀어서 즐겨찾기·편집·삭제, 길게 눌러 메뉴
- 백업 파일 만들기/가져오기 (같은 항목은 더 최근에 고친 쪽을 남김)
- 오프라인에서도 열림, 홈 화면에 추가하면 앱처럼 동작
- 안드로이드: 다른 앱의 공유 메뉴에서 "서랍"으로 바로 보내기

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
src/
  App.tsx                 화면 전체, 상태 연결
  data/types.ts           Item, Folder, 색
  data/db.ts              IndexedDB 읽기·쓰기
  data/library.ts         useLibrary: 추가·수정·삭제·되돌리기
  data/backup.ts          백업 만들기·검사·합치기
  lib/format.ts           주소·태그·날짜 처리
  components/             목록, 카드, 시트들
```
