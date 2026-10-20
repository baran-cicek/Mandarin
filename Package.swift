// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Mandarin",
    platforms: [.macOS(.v13)],
    targets: [
        // Library target: all app logic lives here so both the real app
        // executable and the self-test executable can `import Mandarin`.
        .target(
            name: "Mandarin",
            path: "Sources/Mandarin"
        ),
        .executableTarget(
            name: "MandarinApp",
            dependencies: ["Mandarin"],
            path: "Sources/MandarinAppExecutable"
        ),
        .executableTarget(
            name: "MandarinSelfTests",
            dependencies: ["Mandarin"],
            path: "Tests/MandarinSelfTests"
        ),
        // Headless CLI that drives the exact ConverterRegistry/JobQueue a
        // real drop uses, for scripted end-to-end verification without a
        // GUI session. Doesn't change app behavior — see PROGRESS.md.
        .executableTarget(
            name: "MandarinConvert",
            dependencies: ["Mandarin"],
            path: "Sources/MandarinConvertCLI"
        ),
    ]
)
