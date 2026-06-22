// swift-tools-version: 6.0
import PackageDescription

// OpenDisplay monorepo — Swift Package Manager manifest.
//
// This manifest declares the PLATFORM-INDEPENDENT core of OpenDisplay so it can be
// built and unit-tested with `swift test` on any platform (including Linux CI), with
// no dependency on macOS frameworks (CoreGraphics, AppKit, SwiftUI, ScreenCaptureKit).
//
// The macOS-specific targets — concrete providers, the menu-bar/settings app, the
// rescue app, and the SwiftUI design-system package — live under Providers/, Apps/, and
// Packages/OpenDisplayDesignSystem and are wired into the Xcode project on a Mac. They
// depend on the libraries declared here through the protocols in `ProviderInterfaces`.
let package = Package(
    name: "OpenDisplay",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DisplayDomain", targets: ["DisplayDomain"]),
        .library(name: "ProviderInterfaces", targets: ["ProviderInterfaces"]),
        .library(name: "SceneEngine", targets: ["SceneEngine"]),
        .library(name: "AutomationSchema", targets: ["AutomationSchema"]),
        .library(name: "TopologyCore", targets: ["TopologyCore"]),
        .library(name: "SimulatorProvider", targets: ["SimulatorProvider"])
    ],
    targets: [
        // Pure value types, identity scoring, and the lifecycle/transaction state machines.
        .target(
            name: "DisplayDomain",
            path: "Packages/DisplayDomain/Sources/DisplayDomain"
        ),
        // Provider protocols + typed results/failures (no concrete provider logic).
        .target(
            name: "ProviderInterfaces",
            dependencies: ["DisplayDomain"],
            path: "Packages/ProviderInterfaces/Sources/ProviderInterfaces"
        ),
        // Desired-state scene model: diff, deterministic ordering, idempotent planning, dry-run.
        .target(
            name: "SceneEngine",
            dependencies: ["DisplayDomain"],
            path: "Packages/SceneEngine/Sources/SceneEngine"
        ),
        // Stable Codable schemas for the CLI / JSON result envelope and selectors.
        .target(
            name: "AutomationSchema",
            dependencies: ["DisplayDomain"],
            path: "Packages/AutomationSchema/Sources/AutomationSchema"
        ),
        // SafetyEngine + the serialized transaction coordinator (protocol-driven, platform-independent).
        .target(
            name: "TopologyCore",
            dependencies: ["DisplayDomain", "ProviderInterfaces", "SceneEngine"],
            path: "Packages/TopologyCore/Sources/TopologyCore"
        ),
        // A fully in-memory provider that exercises every result and fault state. Used by tests
        // and developer previews; ships in no release build.
        .target(
            name: "SimulatorProvider",
            dependencies: ["DisplayDomain", "ProviderInterfaces"],
            path: "Packages/SimulatorProvider/Sources/SimulatorProvider"
        ),

        // MARK: - Tests
        .testTarget(
            name: "DisplayDomainTests",
            dependencies: ["DisplayDomain"],
            path: "Packages/DisplayDomain/Tests/DisplayDomainTests"
        ),
        .testTarget(
            name: "SceneEngineTests",
            dependencies: ["SceneEngine", "DisplayDomain"],
            path: "Packages/SceneEngine/Tests/SceneEngineTests"
        ),
        .testTarget(
            name: "AutomationSchemaTests",
            dependencies: ["AutomationSchema", "DisplayDomain"],
            path: "Packages/AutomationSchema/Tests/AutomationSchemaTests"
        ),
        .testTarget(
            name: "TopologyCoreTests",
            dependencies: ["TopologyCore", "SimulatorProvider", "DisplayDomain", "ProviderInterfaces"],
            path: "Packages/TopologyCore/Tests/TopologyCoreTests"
        )
    ]
)
