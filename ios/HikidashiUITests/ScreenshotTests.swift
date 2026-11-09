import XCTest

/// 예시 데이터로 띄워 주요 화면을 찍는다. CI 에서 스크린샷을 꺼내 화면을 확인하는 용도
final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uiTestSample", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testMainScreens() {
        app.launch()
        XCTAssertTrue(app.staticTexts["장보기"].waitForExistence(timeout: 10), "예시 메모가 목록에 보여야 한다")
        sleep(2) // 이미지 불러오기
        snap("01-list")

        // 미디어(카드) 보기: 하단바
        let media = app.buttons["미디어"].firstMatch
        if media.waitForExistence(timeout: 3) {
            media.tap()
            sleep(1)
            snap("02-grid")
            app.buttons["타임라인"].firstMatch.tap()
        }

        // 메모 보기
        app.staticTexts["장보기"].firstMatch.tap()
        XCTAssertTrue(app.buttons["메모 닫기"].waitForExistence(timeout: 5))
        sleep(1)
        snap("03-memo")
        app.buttons["메모 닫기"].tap()

        // 새 항목 시트
        let add = app.otherElements["추가"].firstMatch
        if add.waitForExistence(timeout: 3) { add.tap() } else { app.buttons["추가"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["닫기"].waitForExistence(timeout: 5), "추가 시트가 열려야 한다")
        sleep(1)
        snap("04-editor")
        app.buttons["닫기"].tap()

        // 왼쪽 서랍
        app.buttons["서랍 열기"].firstMatch.tap()
        XCTAssertTrue(app.buttons["아이디어"].waitForExistence(timeout: 3), "서랍이 열려야 한다")
        sleep(1)
        snap("05-drawer")

        // 서랍에서 고르면 그 서랍만 보인다
        app.buttons["아이디어"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["장보기"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["CSS 그리드 레이아웃"].exists, "다른 서랍 항목은 안 보여야 한다")

        // 설정: 하단바
        app.buttons["설정"].firstMatch.tap()
        XCTAssertTrue(app.buttons["설정 닫기"].waitForExistence(timeout: 5))
        sleep(1)
        snap("06-settings")
        // 정리 칸이 아래에 있어서 조금 올린다
        app.swipeUp()
        // 줄 이름이 "태그 관리, 5개" 처럼 개수와 합쳐져 읽힌다
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH '태그 관리'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["태그 관리"].waitForExistence(timeout: 3))
        sleep(1)
        snap("08-tags")
    }

    func testSwipeStarAndDelete() {
        app.launch()
        let row = app.staticTexts["CSS 그리드 레이아웃"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        XCTAssertTrue(app.buttons["삭제"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["삭제"].firstMatch.tap()
        XCTAssertTrue(app.buttons["되돌리기"].waitForExistence(timeout: 3), "삭제하면 되돌리기가 떠야 한다")
        snap("07-undo")
        app.buttons["되돌리기"].tap()
        XCTAssertTrue(app.staticTexts["CSS 그리드 레이아웃"].waitForExistence(timeout: 3), "되돌리면 다시 보여야 한다")
    }

    func testSelectAndReader() {
        app.launch()
        XCTAssertTrue(app.staticTexts["장보기"].waitForExistence(timeout: 10))

        // 여러 개 골라 즐겨찾기
        app.buttons["여러 개 고르기"].firstMatch.tap()
        app.staticTexts["CSS 그리드 레이아웃"].firstMatch.tap()
        app.staticTexts["Me at the zoo"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["2개 선택"].waitForExistence(timeout: 3), "두 개가 골라져야 한다")
        snap("09-select")
        app.buttons["즐겨찾기"].firstMatch.tap()
        XCTAssertTrue(app.buttons["되돌리기"].waitForExistence(timeout: 3))

        // 글 링크는 리더 모드로 열린다 (알림이 첫 줄을 가리니 사라진 뒤에)
        sleep(4)
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'CSS 그리드 레이아웃'")).firstMatch
        row.tap()
        let opened = app.buttons["리더 닫기"].waitForExistence(timeout: 5)
        // 실패하면 원인을 알 수 있게: 화면을 남기고 한 번 더 눌러 본다 (첫 탭이 먹히는지 확인용)
        XCTAssertTrue(opened, "여러 개 고르기를 끝낸 뒤 첫 탭에 리더가 열려야 한다")
        if !opened {
            snap("10-reader-miss")
            row.tap()
            XCTAssertTrue(app.buttons["리더 닫기"].waitForExistence(timeout: 5), "두 번째 탭에는 리더가 열려야 한다")
        }
        sleep(6) // 본문 받기
        snap("10-reader")
        app.buttons["리더 닫기"].tap()
    }

    func testHighlightsAndMemoLinks() {
        app.launch()
        XCTAssertTrue(app.staticTexts["장보기"].waitForExistence(timeout: 10))
        app.buttons["서랍 열기"].firstMatch.tap()
        app.buttons["하이라이트"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["하이라이트"].waitForExistence(timeout: 3))
        sleep(1)
        snap("11-highlights")

        app.buttons["서랍 열기"].firstMatch.tap()
        app.buttons["전체"].firstMatch.tap()
        app.staticTexts["오사카 메모"].firstMatch.tap()
        XCTAssertTrue(app.buttons["메모 닫기"].waitForExistence(timeout: 5))
        sleep(3)
        snap("12-memo-links")
    }
}
