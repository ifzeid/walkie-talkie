// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "WalkieTalkie",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WalkieTalkie", targets: ["WalkieTalkie"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(name: "WalkieTalkie", dependencies: [.product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "WalkieTalkieTests", dependencies: ["WalkieTalkie"], path: "Tests")
    ]
)
