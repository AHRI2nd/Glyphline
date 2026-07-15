// NSTableView subclass: intercepts I/O/P before falling through to the default
// key handling (which drives Up/Down selection). Real-time timing keys need the
// current playhead — wired to a closure so this view has zero knowledge of mpv
// (M4 supplies a real provider; until then it's a documented no-op).

import AppKit

final class CueTableView: NSTableView {
    /// Returns the current playhead time in seconds, or nil when no media is
    /// loaded/playing. Injected by the owning coordinator; M4 wires it to mpv.
    var playheadProvider: (() -> Double?)?
    /// (key) → handled? — "i"/"o"/"p" live-timing actions.
    var onTimingKey: ((Character) -> Void)?

    override func keyDown(with event: NSEvent) {
        if let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1,
           let c = chars.first, ["i", "o", "p"].contains(c),
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            onTimingKey?(c)
            return
        }
        super.keyDown(with: event)
    }
}
