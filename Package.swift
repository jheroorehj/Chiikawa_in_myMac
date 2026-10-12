// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Chiikawa_in_myMac",
    platforms: [.macOS(.v14)],
    targets: [
        // CLI 실행·출력 해석·세션 저장. Foundation 만 쓴다.
        .target(name: "Chiikawa_in_myMacCore"),
        // 떠 있는 펫과 채팅 창 (AppKit/SwiftUI).
        .executableTarget(name: "Chiikawa_in_myMac", dependencies: ["Chiikawa_in_myMacCore"]),
        .testTarget(name: "Chiikawa_in_myMacCoreTests", dependencies: ["Chiikawa_in_myMacCore"]),
    ]
)
