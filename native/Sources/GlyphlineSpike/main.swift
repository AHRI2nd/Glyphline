// M0 spike entry: a bare NSApplication window hosting the mpv video view as a
// normal subview. Run:  swift run GlyphlineSpike /path/to/video.mkv
//
// What to look for (the whole point of the spike):
//   • video shows inside the window's content area (no separate floating window)
//   • resize the window → video follows and repaints (no black/stale frame)
//   • move the window across monitors → no coordinate drift, no "stuck" video
//   • Space toggles play/pause → paused frame stays painted (repaint-on-demand)
// If all clean, the biggest architectural risk of the native rewrite is retired.

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var videoView: MPVOpenGLView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 960, height: 540)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Glyphline mpv spike"
        window.center()

        // A normal container with the video as a subview — no overlay window.
        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = container

        if let view = MPVOpenGLView(mpvFrame: container.bounds) {
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
            videoView = view
        } else {
            let label = NSTextField(labelWithString: "libmpv를 찾을 수 없습니다 (brew install mpv)")
            label.textColor = .white
            label.frame = NSRect(x: 20, y: frame.height / 2, width: frame.width - 40, height: 24)
            container.addSubview(label)
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Load the file passed on the command line, if any.
        let args = CommandLine.arguments
        if args.count > 1, let view = videoView {
            view.open(path: args[1])
            NSLog("[spike] loading \(args[1])")
        } else {
            NSLog("[spike] no file argument — pass a media path to load")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// Space = play/pause, routed to the video view.
final class SpikeApplication: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.charactersIgnoringModifiers == " " {
            (delegate as? AppDelegate)?.videoView?.togglePause()
            return
        }
        super.sendEvent(event)
    }
}

let app = SpikeApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
