// Launches a built Glyphline.app and checks, via the Accessibility API, that
// it actually comes up: a window exists, the menu bar built out, nothing
// crashed on startup. This is deliberately shallow — it is NOT a click-through
// interaction test — because getting real XCUITest running against a pure-SPM
// package (no .xcodeproj) would mean reintroducing exactly the second build
// system this project's native rewrite was written to get away from (see
// README's "Why native, why macOS-only"). See CLAUDE.md's testing section:
// `swift test` covers GlyphlineCore's pure logic; building and running the app
// was already the verification method for the AppKit/mpv layer this checks —
// this just automates the first few seconds of that "does it come up" step.
//
// NOT wired into CI: GitHub Actions runners have no Accessibility (TCC)
// permission to grant non-interactively, and no display session worth
// launching a real window on. This is a local, manual verification tool —
// run it after `./scripts/release.sh` or a debug build, the same moment
// you'd otherwise eyeball the app yourself.
//
// Usage:
//   swift run GlyphlineUISmoke [path/to/Glyphline.app]
//   (defaults to .build/Glyphline-release.app, then /Applications/Glyphline.app)
//
// One-time setup: grant Accessibility permission to whatever runs this
// (Terminal, iTerm, etc.) in System Settings → Privacy & Security →
// Accessibility — the same permission any UI-automation tool needs, and not
// something this process can grant itself.

import AppKit
import ApplicationServices
import Foundation

struct SmokeTestFailure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("FAIL: \(message)\n".data(using: .utf8)!)
    exit(1)
}

func step(_ label: String) {
    print("== \(label)")
}

func resolveAppURL() -> URL {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1])
    }
    let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let repoRoot = scriptDir
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let candidates = [
        repoRoot.appendingPathComponent(".build/Glyphline-release.app"),
        URL(fileURLWithPath: "/Applications/Glyphline.app"),
    ]
    for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
    }
    fail("""
        No built app found. Tried:
        \(candidates.map { "  " + $0.path }.joined(separator: "\n"))
        Build one first (./scripts/release.sh) or pass a path explicitly.
        """)
}

func axAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    return result == .success ? value : nil
}

@MainActor
func run() async throws {
    guard AXIsProcessTrusted() else {
        fail("""
            Accessibility permission not granted to this process.
            Grant it in System Settings → Privacy & Security → Accessibility \
            (add Terminal/iTerm/whatever ran `swift run`), then re-run.
            """)
    }

    let appURL = resolveAppURL()
    step("Launching \(appURL.path)")

    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    let runningApp = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    defer { runningApp.terminate() }

    step("Waiting for the app to finish launching")
    let pid = runningApp.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    // Poll rather than assume a fixed delay is enough — mpv/GL setup and
    // first-launch recovery/autosave checks (AppState.startUp) make the first
    // frame's timing genuinely variable.
    var windows: [AXUIElement] = []
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
        if let list = axAttribute(appElement, kAXWindowsAttribute as String) as? [AXUIElement], !list.isEmpty {
            windows = list
            break
        }
        if runningApp.isTerminated {
            fail("App terminated on its own before any window appeared — likely a launch-time crash.")
        }
        try await Task.sleep(nanoseconds: 200_000_000)
    }
    guard !windows.isEmpty else {
        fail("No window appeared within 15s of launch.")
    }
    step("Found \(windows.count) window(s)")

    guard let title = axAttribute(windows[0], kAXTitleAttribute as String) as? String, !title.isEmpty else {
        fail("Main window has no title — expected at least the app/document name.")
    }
    step("Main window title: \"\(title)\"")

    guard let menuBar = axAttribute(appElement, kAXMenuBarAttribute as String) else {
        fail("No menu bar found for the app.")
    }
    guard let menuItems = axAttribute(menuBar as! AXUIElement, kAXChildrenAttribute as String) as? [AXUIElement] else {
        fail("Menu bar has no children.")
    }
    // Not checking exact titles — they're localized (t()) and depend on the
    // system language this ran under. Just enough top-level menus (File,
    // Edit, Subtitle, Playback, View, Window, Help) that a menu-building
    // regression (a crash inside .commands{}, a missing CommandGroup) shows
    // up as a low count instead of silently passing.
    guard menuItems.count >= 6 else {
        fail("Menu bar only has \(menuItems.count) top-level items — expected at least 6 (File/Edit/Subtitle/Playback/View/Window/Help).")
    }
    step("Menu bar has \(menuItems.count) top-level items")

    print("PASS: app launched, window appeared, menu bar built out.")
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        try await run()
    } catch {
        fail("\(error)")
    }
    semaphore.signal()
}
semaphore.wait()
