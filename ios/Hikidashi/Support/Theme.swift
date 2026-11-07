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

/// 미분류 서랍 색
let unfiledColor = FolderColor.gray.color

/// 보고 있는 범위
enum Scope: Hashable {
    case all, starred, unfiled
    case folder(String)
    case tag(String)
}
