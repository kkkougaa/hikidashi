import Foundation

/// 메모 서식 한 조각 (굵게인지)
public struct RichSpan: Equatable, Sendable {
    public var text: String
    public var bold: Bool
    public init(_ text: String, bold: Bool = false) { self.text = text; self.bold = bold }
}

/// 메모 한 줄
public enum RichLine: Equatable, Sendable {
    case text([RichSpan])
    case bullet(indent: Int, [RichSpan])
    case number(indent: Int, n: Int, [RichSpan])

    public var spans: [RichSpan] {
        switch self {
        case .text(let s), .bullet(_, let s), .number(_, _, let s): s
        }
    }
}

/// 서식 바꾼 결과. start·end 는 글자(Character) 단위 위치
public struct RichEdit: Equatable, Sendable {
    public var text: String
    public var start: Int
    public var end: Int
    public init(text: String, start: Int, end: Int) { self.text = text; self.start = start; self.end = end }
}

/**
 메모 서식. 본문은 평범한 글자로 저장하고 몇 가지 표시만 읽어서 꾸민다.
 - "- " (또는 "• ", "* ") 로 시작하는 줄 → 글머리 기호 목록
 - "1. " 처럼 숫자와 점으로 시작하는 줄 → 번호 목록
 - **굵게** → 굵은 글자
 웹 `src/lib/richText.ts` 와 같은 규칙이어야 한다.
 */
public enum RichText {
    struct Marker { var indent: String; var mark: String; var number: Int?; var sep: Character?; var body: String }

    /// 줄 앞 표시를 읽는다. 표시 뒤 빈칸까지 있어야 목록
    static func marker(_ line: String) -> Marker? {
        let chars = Array(line)
        var i = 0
        while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
        let indent = String(chars[0..<i])
        guard i < chars.count else { return nil }
        if "-•*".contains(chars[i]), i + 1 < chars.count, chars[i + 1] == " " {
            return Marker(indent: indent, mark: String(chars[i]), number: nil, sep: nil, body: String(chars[(i + 2)...]))
        }
        var j = i
        while j < chars.count, j - i < 4, chars[j].isASCII, chars[j].isNumber { j += 1 }
        if j > i, j + 1 < chars.count, chars[j] == "." || chars[j] == ")", chars[j + 1] == " " {
            return Marker(indent: indent, mark: String(chars[i..<j]), number: Int(String(chars[i..<j])), sep: chars[j], body: String(chars[(j + 2)...]))
        }
        return nil
    }

    static func indentWidth(_ s: String) -> Int { s.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } }

    public static func spans(_ text: String) -> [RichSpan] {
        let c = Array(text)
        var out: [RichSpan] = []
        var plain = ""
        var i = 0
        func closing(from k: Int) -> Int? {
            var k = k
            while k + 1 < c.count { if c[k] == "*", c[k + 1] == "*" { return k }; k += 1 }
            return nil
        }
        while i < c.count {
            if i + 1 < c.count, c[i] == "*", c[i + 1] == "*", let j = closing(from: i + 3) {
                if !plain.isEmpty { out.append(RichSpan(plain)); plain = "" }
                out.append(RichSpan(String(c[(i + 2)..<j]), bold: true))
                i = j + 2
            } else {
                plain.append(c[i]); i += 1
            }
        }
        if !plain.isEmpty || out.isEmpty { out.append(RichSpan(plain)) }
        return out
    }

    public static func parse(_ text: String) -> [RichLine] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { sub in
            let line = String(sub)
            guard let m = marker(line) else { return .text(spans(line)) }
            if let n = m.number { return .number(indent: indentWidth(m.indent), n: n, spans(m.body)) }
            return .bullet(indent: indentWidth(m.indent), spans(m.body))
        }
    }

    /// 목록·카드 미리보기용: 표시를 지우고 글머리는 • 로
    public static func plain(_ text: String) -> String {
        parse(text).map { l in
            let t = l.spans.map(\.text).joined()
            switch l {
            case .bullet: return "• \(t)"
            case .number(_, let n, _): return "\(n). \(t)"
            case .text: return t
            }
        }.joined(separator: "\n")
    }

    static func lineStart(_ c: [Character], _ pos: Int) -> Int {
        var i = pos
        while i > 0, c[i - 1] != "\n" { i -= 1 }
        return i
    }

    static func lineEnd(_ c: [Character], _ pos: Int) -> Int {
        var i = pos
        while i < c.count, c[i] != "\n" { i += 1 }
        return i
    }

    /// 목록 줄에서 엔터를 쳤을 때: 다음 줄에 같은 기호(번호는 +1). 기호만 있는 줄이면 기호를 지우고 목록을 끝낸다
    public static func enterInList(_ text: String, at pos: Int) -> RichEdit? {
        let c = Array(text)
        guard pos >= 0, pos <= c.count else { return nil }
        let s = lineStart(c, pos)
        let before = String(c[s..<pos])
        let rest = String(c[pos..<lineEnd(c, pos)])
        guard let m = marker(before) else { return nil }
        if m.body.trimmingCharacters(in: .whitespaces).isEmpty, rest.trimmingCharacters(in: .whitespaces).isEmpty {
            return RichEdit(text: String(c[..<s]) + String(c[pos...]), start: s, end: s)
        }
        let ins = m.number.map { "\n\(m.indent)\($0 + 1)\(m.sep!) " } ?? "\n\(m.indent)\(m.mark) "
        let at = pos + ins.count
        return RichEdit(text: String(c[..<pos]) + ins + String(c[pos...]), start: at, end: at)
    }

    /// 입력으로 글이 바뀌었을 때: 줄바꿈 하나만 들어왔고 목록 줄이었으면 기호를 이어 준 글. 아니면 nil
    public static func continueList(old: String, new: String) -> RichEdit? {
        let a = Array(old), b = Array(new)
        guard b.count == a.count + 1 else { return nil }
        var p = 0
        while p < a.count, a[p] == b[p] { p += 1 }
        guard b[p] == "\n", Array(b[(p + 1)...]) == Array(a[p...]) else { return nil }
        return enterInList(old, at: p)
    }

    /// 고른 글자를 ** 로 감싸거나 푼다. 고른 게 없으면 **** 를 넣고 가운데에 커서
    public static func toggleBold(_ text: String, start: Int, end: Int) -> RichEdit {
        let c = Array(text)
        let sel = String(c[start..<end])
        if sel.count >= 4, sel.hasPrefix("**"), sel.hasSuffix("**") {
            let inner = String(sel.dropFirst(2).dropLast(2))
            return RichEdit(text: String(c[..<start]) + inner + String(c[end...]), start: start, end: start + inner.count)
        }
        if start >= 2, end + 2 <= c.count, String(c[(start - 2)..<start]) == "**", String(c[end..<(end + 2)]) == "**" {
            return RichEdit(text: String(c[..<(start - 2)]) + sel + String(c[(end + 2)...]), start: start - 2, end: end - 2)
        }
        return RichEdit(text: String(c[..<start]) + "**" + sel + "**" + String(c[end...]), start: start + 2, end: end + 2)
    }

    public enum ListKind: Sendable { case bullet, number }

    /// 고른 줄들을 목록으로 바꾸거나, 이미 그 목록이면 기호를 뗀다
    public static func toggleList(_ text: String, start: Int, end: Int, kind: ListKind) -> RichEdit {
        let c = Array(text)
        let s = lineStart(c, start)
        let e = lineEnd(c, max(start, end))
        let lines = String(c[s..<e]).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        func strip(_ l: String) -> String { marker(l).map { $0.indent + $0.body } ?? l }
        let all = lines.allSatisfy { l in marker(l).map { (kind == .number) == ($0.number != nil) } ?? false }
        let next: [String] = all ? lines.map(strip) : lines.enumerated().map { i, l in
            let t = strip(l)
            let lead = t.prefix { $0 == " " || $0 == "\t" }
            return "\(lead)\(kind == .bullet ? "-" : "\(i + 1).") \(t.dropFirst(lead.count))"
        }
        let block = next.joined(separator: "\n")
        let out = String(c[..<s]) + block + String(c[e...])
        if lines.count == 1, start == end { return RichEdit(text: out, start: s + block.count, end: s + block.count) }
        return RichEdit(text: out, start: s, end: e + block.count - (e - s))
    }
}
