// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Preview",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Preview",
            path: "Sources/Preview",
            // 设计稿整份跑在主线程，Swift 5 语言模式免掉 strict concurrency 的样板代码
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
