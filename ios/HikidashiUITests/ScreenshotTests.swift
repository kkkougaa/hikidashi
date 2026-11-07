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

        // 카드 보기
        let grid = app.segmentedControls.buttons.element(boundBy: 1)
        if grid.waitForExistence(timeout: 3) {
            grid.tap()
            sleep(1)
            snap("02-grid")
            app.segmentedControls.buttons.element(boundBy: 0).tap()
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
        XCTAssertTrue(app.buttons["설정"].waitForExistence(timeout: 3), "서랍이 열려야 한다")
        sleep(1)
        snap("05-drawer")

        // 서랍에서 고르면 그 서랍만 보인다
        app.buttons["아이디어"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["장보기"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["CSS 그리드 레이아웃"].exists, "다른 서랍 항목은 안 보여야 한다")

        // 설정
        app.buttons["서랍 열기"].firstMatch.tap()
        app.buttons["설정"].firstMatch.tap()
        XCTAssertTrue(app.buttons["설정 닫기"].waitForExistence(timeout: 5))
        sleep(1)
        snap("06-settings")
        app.buttons["태그 관리"].firstMatch.tap()
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
}
