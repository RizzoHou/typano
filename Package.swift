// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Typano",
    // String form rather than `.v15`: the enum case requires tools-version
    // 6.0, which would also flip the target to Swift 6 language mode and its
    // strict concurrency checking — a much larger change than raising a
    // deployment target. 15 is required by SCRecordingOutput.
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "Typano",
            path: "Sources/Typano"
        )
    ]
)
