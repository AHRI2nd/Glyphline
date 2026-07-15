// swift-tools-version: 6.0
import PackageDescription

// Glyphline — native macOS rewrite (Swift/SwiftUI).
// This package holds the pure, testable core (model + format adapters + timing/
// quality logic). The app target (SwiftUI) and the mpv spike are added as the
// migration progresses. The existing Tauri app (../src, ../src-tauri) remains the
// reference spec + source of the ported test vectors until feature parity.
let package = Package(
    name: "Glyphline",
    defaultLocalization: "ko",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "GlyphlineCore", targets: ["GlyphlineCore"]),
        .executable(name: "GlyphlineSpike", targets: ["GlyphlineSpike"]),
        .executable(name: "Glyphline", targets: ["Glyphline"]),
    ],
    targets: [
        .target(name: "GlyphlineCore"),
        .testTarget(
            name: "GlyphlineCoreTests",
            dependencies: ["GlyphlineCore"]
        ),
        // M0 de-risk spike: embed libmpv (render API) into a plain NSView and
        // confirm playback with no overlay window / coordinate hacks. Throwaway.
        .executableTarget(
            name: "GlyphlineSpike",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("OpenGL"),
            ]
        ),
        // The real app: SwiftUI-first shell + AppKit where needed (M2+).
        .executableTarget(
            name: "Glyphline",
            dependencies: ["GlyphlineCore"],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("AppKit")]
        ),
    ]
)
