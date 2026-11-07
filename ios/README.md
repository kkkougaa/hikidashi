# hikidashi iOS

SwiftUI 로 만든 아이폰 앱. 웹앱과 같은 데이터 형식을 쓰고, 백업 파일로 서로 옮길 수 있다. 두 앱이 지켜야 할 약속은 [`docs/SPEC.md`](../docs/SPEC.md).

## 구조

```
ios/
  project.yml              XcodeGen 설정 (Xcode 프로젝트는 여기서 만든다)
  HikidashiCore/           화면과 상관없는 로직: 데이터, 링크 정보, 백업 (리눅스에서도 테스트됨)
  Hikidashi/
    App/                   앱 시작, 탭, 시트 연결
    Store/LibraryStore     상태와 저장 (앱 폴더의 library.json, 백업과 같은 형식)
    Views/                 목록·카드, 추가/편집, 메모 보기, 서랍, 설정, + 버튼
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

## 웹앱과 다른 점

- 링크 정보를 페이지에서 직접 읽는다 (웹은 CORS 때문에 Jina Reader 를 거친다). X 는 똑같이 FxTwitter.
- 붙여넣기는 애플 기본 붙여넣기 버튼이라 권한 창이 뜨지 않는다. + 버튼을 끌어올리는 빠른 추가는 클립보드를 읽어서 iOS 가 한 번 묻는다.
- 이모지는 애플 이모지로 보인다 (웹은 토스페이스).
- iOS 26 에서는 + 버튼에 진짜 리퀴드 글래스를 쓰고, 그 전 버전은 비슷하게 흉내 낸다.
