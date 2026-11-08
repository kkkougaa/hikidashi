# hikidashi iOS

SwiftUI 로 만든 아이폰 앱. 웹앱과 같은 데이터 형식을 쓰고, 백업 파일로 서로 옮길 수 있다. 두 앱이 지켜야 할 약속은 [`docs/SPEC.md`](../docs/SPEC.md).

## 구조

```
ios/
  project.yml              XcodeGen 설정 (Xcode 프로젝트는 여기서 만든다)
  HikidashiCore/           화면과 상관없는 로직: 데이터, 링크 정보, 백업 (리눅스에서도 테스트됨)
  Shared/                  앱과 공유 확장이 같이 쓰는 저장소 (App Group 의 library.json)
  ShareExtension/          공유 시트의 hikidashi: 누르면 정보까지 채워 바로 저장
  Hikidashi/
    App/                   앱 시작, 왼쪽 서랍, 시트 연결
    Store/LibraryStore     상태와 저장 (앱 폴더의 library.json, 백업과 같은 형식)
    Views/                 목록·카드(벽돌 쌓기), 추가/편집, 메모 보기, 서랍, 설정(테마·태그·서랍 관리), + 버튼
    Resources/             앱 아이콘, 강조색
  HikidashiUITests/        예시 데이터로 화면을 띄워 스크린샷을 찍는 테스트
```

## 맥에서 열기

```bash
brew install xcodegen
```

```bash
cd ios && xcodegen generate && open Hikidashi.xcodeproj
```

1. Xcode 에서 Hikidashi 타깃 → Signing & Capabilities → Team 에 내 애플 계정을 고른다 (무료 계정도 된다).
2. 아이폰을 연결하고 실행. 무료 계정은 7일마다 다시 설치해야 하고, 오래 쓰려면 Apple Developer Program 이 필요하다.

## 테스트

- 공통 로직: `cd ios/HikidashiCore && swift test` (맥·리눅스 모두)
- 앱 전체: Xcode 에서 ⌘U, 또는 GitHub Actions 의 iOS 워크플로가 시뮬레이터에서 돌리고 스크린샷을 `ios-screenshots` 로 올린다.

## 동기화

설정 → 동기화에서 iCloud Drive 의 폴더(예: `hikidashi`)를 고르면, 그 폴더의 `hikidashi-sync.json` 으로 웹앱(윈도우 크롬·엣지)과 맞춘다. 서버도 iCloud 권한(entitlement)도 필요 없다. 자세한 건 저장소 맨 위 README.

## 웹앱과 다른 점

- 링크 정보와 리더 본문을 페이지에서 직접 읽는다 (웹은 CORS 때문에 Jina Reader 를 거친다). X 는 똑같이 FxTwitter.
- 링크 점검(지워진 페이지에 "안 열림" 표시)은 앱이 하루 한 번 한다. 웹은 동기화로 결과만 받는다.
- 공유 시트 확장이 있다: 서랍·태그를 고르고, 손대지 않으면 3초 뒤 저절로 저장. 앱을 열 때 들어간다.
- 붙여넣기는 애플 기본 붙여넣기 버튼이라 권한 창이 뜨지 않는다. + 버튼을 끌어올리는 빠른 추가는 클립보드를 읽어서 iOS 가 한 번 묻는다.
- 이모지는 애플 이모지로 보인다 (웹은 토스페이스).
- 공유 시트에서 hikidashi 를 누르면 바로 저장된다 (웹은 홈 화면에 추가한 PWA 의 공유 대상으로 시트가 열린다).
- iOS 26 에서는 + 버튼과 알림에 진짜 리퀴드 글래스를 쓰고, 그 전 버전은 비슷하게 흉내 낸다.

## TestFlight

`main` 에 iOS 코드가 바뀌어 올라가면 `.github/workflows/testflight.yml` 이 서명하고 TestFlight 에 올린다 (Actions 탭에서 손으로 돌려도 된다). 처음 한 번만 준비하면 된다.

1. [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list) → Identifiers 에서 `com.kkkougaa.hikidashi` 를 App ID 로 등록.
2. [App Store Connect](https://appstoreconnect.apple.com) → 앱 → + 새로운 앱 → 번들 ID 에서 위 ID 를 고른다 (이름 hikidashi, SKU 아무거나).
3. App Store Connect → 사용자 및 액세스 → 통합 → App Store Connect API → 키 생성 (액세스: **관리자**, 클라우드 서명 인증서를 만들 수 있어야 해서). `.p8` 파일은 한 번만 받을 수 있다.
4. GitHub 저장소 Settings → Secrets and variables → Actions 에 넣는다.
   - `APPLE_TEAM_ID`: 개발자 계정 Membership 의 Team ID
   - `ASC_KEY_ID`, `ASC_ISSUER_ID`: 키 화면에 보이는 값
   - `ASC_KEY_P8_BASE64`: `base64 -i AuthKey_XXXX.p8 | pbcopy` 로 복사한 값

시크릿이 없으면 이 워크플로는 실패하지 않고 건너뛴다. 빌드 번호는 실행 횟수로 자동으로 올라간다.
