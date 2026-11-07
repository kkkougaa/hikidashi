import Foundation
import XCTest
@testable import HikidashiCore

final class FormatTests: XCTestCase {
    func testNormalizeURL() {
        XCTAssertEqual(normalizeURL("example.com/a"), "https://example.com/a")
        XCTAssertEqual(normalizeURL("  https://www.figma.com/community "), "https://www.figma.com/community")
        XCTAssertEqual(normalizeURL("https://example.com"), "https://example.com/")
        XCTAssertNil(normalizeURL(""))
        XCTAssertNil(normalizeURL("그냥 메모"))
        XCTAssertNil(normalizeURL("hello"))
        XCTAssertNil(normalizeURL("javascript:alert(1)"))
        XCTAssertNil(normalizeURL("ftp://example.com"))
    }

    func testDomainAndFind() {
        XCTAssertEqual(domain(of: "https://www.youtube.com/watch?v=1"), "youtube.com")
        XCTAssertEqual(domain(of: "not a url"), "")
        XCTAssertEqual(findURL(in: "이거 봐 https://brunch.co.kr/@a/42 재밌음"), "https://brunch.co.kr/@a/42")
        XCTAssertNil(findURL(in: "주소 없음"))
    }

    func testGuessTitleAndTags() {
        XCTAssertEqual(guessTitle("https://ex.com/blog/css-grid_layout.html"), "css grid layout")
        XCTAssertEqual(guessTitle("https://ex.com/posts/12345"), "ex.com")
        XCTAssertEqual(parseTags("참고, #나중에 ,, 참고，ui"), ["참고", "나중에", "ui"])
        XCTAssertEqual(parseTags("   "), [])
    }

    func testDates() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let dt = DateText(calendar: cal)
        func ms(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10, _ mi: Int = 0) -> Millis {
            Millis(cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!.timeIntervalSince1970 * 1000)
        }
        let now = ms(2026, 11, 7, 21, 30)
        XCTAssertEqual(dt.daysAgo(ms(2026, 11, 7, 0, 1), now: now), 0)
        XCTAssertEqual(dt.daysAgo(ms(2026, 11, 6, 23, 59), now: now), 1)
        XCTAssertEqual(dt.bucket(ms(2026, 11, 7), now: now), .today)
        XCTAssertEqual(dt.bucket(ms(2026, 11, 6), now: now), .yesterday)
        XCTAssertEqual(dt.bucket(ms(2026, 11, 2), now: now), .thisWeek)
        XCTAssertEqual(dt.bucket(ms(2026, 10, 20), now: now), .thisMonth)
        XCTAssertEqual(dt.bucket(ms(2026, 6, 1), now: now), .earlier)
        XCTAssertEqual(dt.stamp(ms(2026, 11, 7, 14, 7), now: now), "오후 2:07")
        XCTAssertEqual(dt.stamp(ms(2026, 11, 6), now: now), "어제")
        XCTAssertEqual(dt.stamp(ms(2026, 11, 4), now: now), "수요일")
        XCTAssertEqual(dt.stamp(ms(2026, 10, 28), now: now), "10월 28일")
        XCTAssertEqual(dt.stamp(ms(2025, 1, 3), now: now), "2025년 1월 3일")
    }
}

final class PageInfoTests: XCTestCase {
    func testIDs() {
        XCTAssertEqual(youtubeID("https://www.youtube.com/watch?v=jNQXAC9IVRw"), "jNQXAC9IVRw")
        XCTAssertEqual(youtubeID("https://youtu.be/jNQXAC9IVRw?t=3"), "jNQXAC9IVRw")
        XCTAssertEqual(youtubeID("https://m.youtube.com/shorts/abcDEF12345"), "abcDEF12345")
        XCTAssertNil(youtubeID("https://example.com/watch?v=1"))
        XCTAssertEqual(xStatusID("https://x.com/elonmusk/status/1585341984679469056"), "1585341984679469056")
        XCTAssertEqual(xStatusID("https://mobile.twitter.com/i/web/status/123456789"), "123456789")
        XCTAssertNil(xStatusID("https://x.com/elonmusk"))
        XCTAssertNil(xStatusID("https://example.com/a/status/123456"))
    }

    func testTidyAndClip() {
        XCTAssertEqual(tidyTitle("Me at the zoo - YouTube"), "Me at the zoo")
        XCTAssertEqual(tidyTitle("CSS 그리드 | MDN", siteName: "MDN"), "CSS 그리드")
        XCTAssertEqual(tidyTitle("좋은 글 - brunch", host: "brunch.co.kr"), "좋은 글")
        XCTAssertEqual(tidyTitle("Grid - MDN Web Docs", siteName: "MDN Web Docs"), "Grid")
        XCTAssertEqual(tidyTitle("MDN", siteName: "MDN"), "MDN")
        let long = String(repeating: "가나다 ", count: 60)
        let out = clip(long, 40)
        XCTAssertLessThanOrEqual(out.count, 41)
        XCTAssertTrue(out.hasSuffix("…"))
        XCTAssertEqual(clip("짧은 글"), "짧은 글")
    }

    func testParseHTML() {
        let html = """
        <html><head><title>예전 제목 - Blog</title>
        <meta property="og:title" content="그리드 &amp; 레이아웃 | 사이트">
        <meta content="좋은 소개문입니다" name="description">
        <meta property='og:image' content='/img/cover.jpg'>
        <meta property="og:site_name" content="사이트">
        </head><body><p>짧음</p></body></html>
        """
        let info = parseHTML(html, url: "https://blog.example.com/post/1")
        XCTAssertEqual(info.title, "그리드 & 레이아웃")
        XCTAssertEqual(info.description, "좋은 소개문입니다")
        XCTAssertEqual(info.image, "https://blog.example.com/img/cover.jpg")
        XCTAssertEqual(info.siteName, "사이트")
    }

    func testParseHTMLFallbacks() {
        let html = """
        <title>제목만</title><body><img src="/favicon.png"><img src="https://cdn.ex.com/photo.jpg">
        <p>짧은</p><p>소개문이 없을 때는 본문 첫 번째로 충분히 긴 문단을 내용으로 씁니다.</p></body>
        """
        let info = parseHTML(html, url: "https://ex.com/a")
        XCTAssertEqual(info.title, "제목만")
        XCTAssertEqual(info.description, "소개문이 없을 때는 본문 첫 번째로 충분히 긴 문단을 내용으로 씁니다.")
        XCTAssertEqual(info.image, "https://cdn.ex.com/photo.jpg")
        XCTAssertNil(parseHTML("<title>t</title>", url: "https://ex.com").image)
    }

    func testFxTweet() throws {
        let json = """
        {"text":"오늘 찍은 사진\\n두 번째 줄 https://t.co/abc123","author":{"name":"홍길동","screen_name":"hong","avatar_url":"https://pbs.twimg.com/profile_images/1/a_normal.jpg"},"media":{"photos":[{"url":"https://pbs.twimg.com/media/photo.jpg"}]}}
        """
        let info = parseFxTweet(try JSONDecoder().decode(FxTweet.self, from: Data(json.utf8)))
        XCTAssertEqual(info, PageInfo(title: nil, description: "오늘 찍은 사진\n두 번째 줄", image: "https://pbs.twimg.com/media/photo.jpg", siteName: "X · @hong"))
        let noMedia = parseFxTweet(FxTweet(text: "글만", author: .init(name: "A", screen_name: "a", avatar_url: "https://pbs.twimg.com/profile_images/1/a_normal.jpg"), media: nil))
        XCTAssertEqual(noMedia.image, "https://pbs.twimg.com/profile_images/1/a_200x200.jpg")
        XCTAssertNil(noMedia.title)
        XCTAssertEqual(parseFxTweet(FxTweet(text: "", author: .init(name: "A", screen_name: nil, avatar_url: nil), media: nil)).title, "A의 게시물")
    }
}

final class LibraryTests: XCTestCase {
    func testSeedAndMutations() {
        var lib = Library.seeded(now: 1000)
        XCTAssertEqual(lib.liveFolders.map(\.name), ["나중에 읽기", "참고", "아이디어"])
        let f = lib.liveFolders[1]
        let a = lib.addItem(ItemDraft(kind: .memo, title: "장보기", note: "계란", folderId: f.id), now: 2000)
        lib.toggleStar(a.id, now: 2100)
        XCTAssertTrue(lib.item(a.id)!.starred)
        XCTAssertGreaterThan(lib.item(a.id)!.updatedAt, 2000)
        lib.remove(a.id, now: 2200)
        XCTAssertTrue(lib.liveItems.isEmpty)
        XCTAssertNotNil(lib.item(a.id)?.deletedAt, "삭제는 표시만 한다")
        lib.restore(a.id, now: 2300)
        XCTAssertEqual(lib.liveItems.map(\.id), [a.id])
    }

    func testRemoveFolderAndUndo() {
        var lib = Library.seeded(now: 1)
        let f = lib.liveFolders[0]
        lib.addItem(ItemDraft(kind: .link, url: "https://a.com/", title: "a", folderId: f.id), now: 2)
        lib.addItem(ItemDraft(kind: .link, url: "https://b.com/", title: "b", folderId: f.id), now: 3)
        let moved = lib.removeFolder(f.id, now: 4)
        XCTAssertEqual(moved.count, 2)
        XCTAssertFalse(lib.liveFolders.contains { $0.id == f.id })
        XCTAssertEqual(lib.unfiled.count, 2)
        lib.restoreFolder(f.id, moved: moved, now: 5)
        XCTAssertTrue(lib.liveItems.allSatisfy { $0.folderId == f.id })
    }

    func testDisplayTitle() {
        let x = Item(kind: .link, url: "https://x.com/a/status/1", title: "", note: "첫 줄\n둘째 줄")
        XCTAssertEqual(x.displayTitle, "첫 줄")
        XCTAssertEqual(x.displaySubtitle, "둘째 줄")
        XCTAssertEqual(Item(kind: .link, url: "https://www.ex.com/").displayTitle, "ex.com")
        XCTAssertEqual(Item(kind: .memo).displayTitle, "제목 없는 메모")
    }

    func testTagsByUse() {
        var lib = Library()
        lib.addItem(ItemDraft(kind: .memo, note: "1", tags: ["b", "a"]))
        lib.addItem(ItemDraft(kind: .memo, note: "2", tags: ["b"]))
        XCTAssertEqual(lib.tagsByUse, ["b", "a"])
        XCTAssertEqual(lib.tagCounts.map(\.tag), ["a", "b"])
    }

    func testRenameRemoveTag() {
        var lib = Library()
        lib.addItem(ItemDraft(kind: .memo, title: "a", tags: ["css", "참고"]))
        lib.addItem(ItemDraft(kind: .memo, title: "b", tags: ["CSS", "참고"]))
        lib.addItem(ItemDraft(kind: .memo, title: "c", tags: ["etc"]))
        XCTAssertEqual(lib.renameTag("CSS", to: "#css "), 1)
        XCTAssertEqual(lib.tagCounts.first { $0.tag == "css" }?.count, 2)
        XCTAssertNil(lib.tagCounts.first { $0.tag == "CSS" })
        // 합쳐질 때 같은 태그가 두 번 들어가지 않는다
        XCTAssertEqual(lib.renameTag("참고", to: "css"), 2)
        XCTAssertTrue(lib.liveItems.allSatisfy { $0.tags.filter { $0 == "css" }.count <= 1 })
        XCTAssertEqual(lib.renameTag("css", to: "  "), 0)
        XCTAssertEqual(lib.removeTag("css"), 2)
        XCTAssertEqual(lib.tagCounts.map(\.tag), ["etc"])
    }

    func testReorderFolders() {
        var lib = Library.seeded(now: 1)
        let ids = lib.liveFolders.map(\.id)
        lib.reorderFolders([ids[2], ids[0], ids[1]], now: 5)
        XCTAssertEqual(lib.liveFolders.map(\.id), [ids[2], ids[0], ids[1]])
        XCTAssertTrue(lib.folders.allSatisfy { $0.updatedAt == 5 })
    }
}

final class BackupTests: XCTestCase {
    /// 웹앱이 내보낸 백업 그대로
    let webBackup = """
    {"app":"hikidashi","version":1,"exportedAt":1762500000000,
     "folders":[{"id":"f1","name":"참고","color":"cyan","order":0,"createdAt":1762400000000,"updatedAt":1762400000000,"deletedAt":null},
                {"id":"bad","name":"x","color":"neon","order":1,"createdAt":1,"updatedAt":1,"deletedAt":null}],
     "items":[{"id":"i1","kind":"link","url":"https://x.com/a/status/1","title":"","note":"글","image":"https://pbs.twimg.com/a.jpg","siteName":"X · @a","folderId":"f1","tags":["참고"],"starred":true,"createdAt":1762450000000,"updatedAt":1762450000000.0,"deletedAt":null},
              {"id":"i2","kind":"memo","title":"장보기","note":"계란","emoji":"🛒","folderId":null,"tags":[],"starred":false,"createdAt":1762460000000,"updatedAt":1762460000000,"deletedAt":null,"futureField":42},
              {"id":"i3","kind":"video","title":"x","note":"","folderId":null,"tags":[],"starred":false,"createdAt":1,"updatedAt":1,"deletedAt":null}]}
    """

    func testReadsWebBackupAndSkipsBrokenRecords() throws {
        let b = try parseBackup(Data(webBackup.utf8))
        XCTAssertEqual(b.folders.map(\.id), ["f1"])
        XCTAssertEqual(b.items.map(\.id), ["i1", "i2"])
        XCTAssertEqual(b.items[0].siteName, "X · @a")
        XCTAssertEqual(b.items[1].emoji, "🛒")
        XCTAssertNil(b.items[1].folderId)
        XCTAssertEqual(b.exportedAt, 1762500000000)
    }

    func testWritesWhatTheWebReaderExpects() throws {
        let b = try parseBackup(Data(webBackup.utf8))
        let json = try JSONSerialization.jsonObject(with: try b.encoded()) as! [String: Any]
        XCTAssertEqual(json["app"] as? String, "hikidashi")
        XCTAssertEqual(json["version"] as? Int, 1)
        let memo = (json["items"] as! [[String: Any]])[1]
        // 웹 검사기: deletedAt 은 null 이거나 숫자, folderId 는 null 이거나 문자열이어야 한다
        XCTAssertTrue(memo["deletedAt"] is NSNull)
        XCTAssertTrue(memo["folderId"] is NSNull)
        XCTAssertEqual((memo["createdAt"] as? NSNumber)?.int64Value, 1762460000000)
        XCTAssertNil(memo["url"], "메모는 url 을 쓰지 않는다")
        // 다시 읽어도 같다
        XCTAssertEqual(try parseBackup(try b.encoded()).items, b.items)
    }

    func testErrors() {
        XCTAssertThrowsError(try parseBackup(Data("{oops".utf8))) { XCTAssertEqual($0 as? BackupError, .unreadable) }
        XCTAssertThrowsError(try parseBackup(Data(#"{"app":"other","version":1,"folders":[],"items":[]}"#.utf8))) { XCTAssertEqual($0 as? BackupError, .notHikidashi) }
    }

    func testMergeNewerWins() {
        let older = Item(id: "a", kind: .memo, title: "옛", createdAt: 1, updatedAt: 10)
        let newer = Item(id: "a", kind: .memo, title: "새", createdAt: 1, updatedAt: 20)
        let other = Item(id: "b", kind: .memo, title: "다른", createdAt: 1)
        let r = mergeRecords([older], [newer, other])
        XCTAssertEqual(r.merged.map(\.title), ["새", "다른"])
        XCTAssertEqual(r.changed.count, 2)
        XCTAssertTrue(mergeRecords([newer], [older]).changed.isEmpty)
    }

    func testColorsReadable() {
        func lum(_ c: (r: Double, g: Double, b: Double)) -> Double {
            func ch(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
        }
        XCTAssertEqual(FolderColor.allCases.count, 17)
        for c in FolderColor.allCases {
            XCTAssertGreaterThanOrEqual(1.05 / (lum(c.rgb) + 0.05), 4.5, c.rawValue)
        }
    }
}

/// HIKIDASHI_FIXTURE 가 있으면 iOS 가 만든 백업을 거기에 써서 웹 테스트가 읽어 보게 한다
final class FixtureExport: XCTestCase {
    func testWriteFixtureForWeb() throws {
        guard let path = ProcessInfo.processInfo.environment["HIKIDASHI_FIXTURE"] else { throw XCTSkip("웹 교차 확인용") }
        var lib = Library.seeded(now: 1_762_400_000_000)
        let f = lib.liveFolders[0]
        lib.addItem(ItemDraft(kind: .link, url: "https://x.com/a/status/1", note: "글", image: "https://pbs.twimg.com/a.jpg", siteName: "X · @a", folderId: f.id, tags: ["참고"]), now: 1_762_450_000_000)
        lib.addItem(ItemDraft(kind: .memo, title: "장보기", note: "계란", emoji: "🛒"), now: 1_762_460_000_000)
        let moved = lib.removeFolder(lib.liveFolders[2].id, now: 1_762_470_000_000)
        XCTAssertEqual(moved, [])
        try lib.backup(now: 1_762_500_000_000).encoded().write(to: URL(fileURLWithPath: path))
    }
}

final class ReaderTests: XCTestCase {
    let html = """
    <html><head><title>CSS 그리드 완전 정복 | 개발 블로그</title>
    <meta property="og:image" content="https://ex.com/hero.jpg"><meta property="og:site_name" content="개발 블로그"></head>
    <body><header><a href="/">홈</a></header>
    <nav><ul><li><a href="/a">메뉴 하나</a></li></ul></nav>
    <article>
      <h1>CSS 그리드 완전 정복</h1>
      <p>그리드는 <b>두 방향</b>으로 배치하는 레이아웃 방식이다. 줄과 칸을 한 번에 다룰 수 있어서 편하다.</p>
      <img src="https://ex.com/hero.jpg">
      <p><img data-src="/img/diagram.png" src="data:image/gif;base64,AAA">트랙의 크기는 fr 단위로 나눈다.<br>여러 줄도 된다 &amp; 좋다.</p>
      <h2>예제</h2>
      <pre><code>.grid {
      display: grid;
    }</code></pre>
      <blockquote><p>인용문입니다</p></blockquote>
      <ul><li>첫째 항목</li><li><a href="/x">관련 글 링크만 있는 줄</a></li></ul>
      <script>var x = "<p>스크립트</p>";</script>
      <p>공유하기</p>
    </article>
    <footer><p>© 회사</p></footer></body></html>
    """

    func testExtractArticle() {
        let a = extractArticle(html, url: "https://ex.com/post/1")
        XCTAssertEqual(a.title, "CSS 그리드 완전 정복")
        XCTAssertEqual(a.image, "https://ex.com/hero.jpg")
        XCTAssertEqual(a.blocks, [
            .paragraph("그리드는 두 방향으로 배치하는 레이아웃 방식이다. 줄과 칸을 한 번에 다룰 수 있어서 편하다."),
            .paragraph("트랙의 크기는 fr 단위로 나눈다.\n여러 줄도 된다 & 좋다."),
            .image("https://ex.com/img/diagram.png"),
            .heading("예제", level: 2),
            .code(".grid {\n  display: grid;\n}"),
            .quote("인용문입니다"),
            .listItem("첫째 항목"),
        ])
        XCTAssertEqual(a.minutes, 1)
    }

    func testReaderURLAndSupport() {
        XCTAssertEqual(readerURL("https://blog.naver.com/abc/223"), "https://m.blog.naver.com/abc/223")
        XCTAssertEqual(readerURL("https://ex.com/a"), "https://ex.com/a")
        XCTAssertTrue(supportsReader("https://ex.com/a"))
        XCTAssertFalse(supportsReader("https://x.com/elonmusk/status/1585341984679469056"))
        XCTAssertFalse(supportsReader("https://youtu.be/jNQXAC9IVRw"))
        XCTAssertFalse(supportsReader(nil))
    }
}
