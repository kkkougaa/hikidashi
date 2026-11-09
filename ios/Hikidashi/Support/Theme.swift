import SwiftUI
import HikidashiCore

extension Color {
    /// "#RRGGBB" 문자열로 만든다
    init(hex: String) {
        let v = Int(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// 앱 강조색 (웹과 같은 파랑, 다크 모드는 밝게)
    static let brand = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0x4D / 255, green: 0x94 / 255, blue: 1, alpha: 1) : UIColor(red: 0x13 / 255, green: 0x66 / 255, blue: 0xE0 / 255, alpha: 1) })
    /// 즐겨찾기 별
    static let star = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0xF0 / 255, green: 0xB0 / 255, blue: 0, alpha: 1) : UIColor(red: 0xC9 / 255, green: 0x85 / 255, blue: 0, alpha: 1) })
}

extension FolderColor {
    var color: Color { Color(hex: hex) }
}

extension Folder {
    /// 칠할 색: 팔레트로 고른 색이 있으면 그것 (store.folder(_:) 로 받은 서랍은 하위 서랍이면 상위 색)
    var paint: Color { Color(hex: paintHex) }
    /// 이 색 위 글자·아이콘 색
    var ink: Color { whiteReadsOn(paintHex) ? .white : Color(white: 0.11) }
}

extension Library {
    /// 서랍 목록에서 칠할 색 (하위 서랍은 상위 색)
    func paint(_ f: Folder) -> Color { Color(hex: displayHex(f)) }
    func ink(_ f: Folder) -> Color { whiteReadsOn(displayHex(f)) ? .white : Color(white: 0.11) }
}

extension Color {
    /// "#RRGGBB" 로 바꾼다 (팔레트에서 고른 색 저장용)
    var hexString: String {
        let c = UIColor(self).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func h(_ v: CGFloat) -> String { String(format: "%02X", Int((min(max(v, 0), 1) * 255).rounded())) }
        return "#\(h(r))\(h(g))\(h(b))"
    }
}

/// 미분류 서랍 색
let unfiledColor = FolderColor.gray.color

/// 보고 있는 범위
enum Scope: Hashable {
    case all, starred, unfiled, highlights, broken, done, memos, offline
    case folder(String)
    case tag(String)
}
