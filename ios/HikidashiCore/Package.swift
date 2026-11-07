// swift-tools-version:5.9
// 앱 화면과 상관없는 로직(데이터, 링크 정보, 백업). 리눅스에서도 빌드·테스트된다.
import PackageDescription

let package = Package(
    name: "HikidashiCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "HikidashiCore", targets: ["HikidashiCore"])],
    targets: [
        .target(name: "HikidashiCore"),
        .testTarget(name: "HikidashiCoreTests", dependencies: ["HikidashiCore"]),
    ]
)
