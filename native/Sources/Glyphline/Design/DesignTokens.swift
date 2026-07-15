// Design tokens — reverted to Glyphline's original zinc/indigo dark palette
// (matches the Tauri build and Lyrical Sync; see ../../../../CLAUDE.md's 디자인
// section). This is a deliberate, fixed dark theme — not adaptive light/dark —
// same as the app it replaces.
//
// NOTE — typeface commitment: the plan calls for IBM Plex Mono/Commit Mono (data),
// a humanist sans (body), and a characterful grotesque (display), but this
// scaffold pass has no bundled font files to embed. Tokens below map to system
// font *designs* that approximate the intended contrast (monospaced / default /
// rounded) so every call site already routes through GlyphFont — swapping in the
// real faces later is a one-file change, not a UI-wide edit.

import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

public enum GlyphColor {
    // ── backgrounds (zinc) ──────────────────────────────────────────────────────
    /// App background / input fields — zinc-950.
    public static let bg = Color(hex: 0x09090b)
    /// Panel/toolbar/header surfaces — zinc-900.
    public static let surface = Color(hex: 0x18181b)
    /// Hairline borders between chrome regions — zinc-800.
    public static let border = Color(hex: 0x27272a)
    /// Input/field borders — zinc-700.
    public static let borderStrong = Color(hex: 0x3f3f46)

    // ── text ─────────────────────────────────────────────────────────────────────
    /// Primary text — white.
    public static let ink = Color.white
    /// Secondary/meta text, waveform tick marks, inactive chrome — zinc-400.
    public static let quiet = Color(hex: 0xa1a1aa)

    // ── accent — indigo, the app's one accent (title, primary buttons, focus,
    // active states, the waveform/transport/active-row "time spine" motif) ───────
    /// Headers, app title, highlighted text — indigo-400.
    public static let signal = Color(hex: 0x818cf8)
    /// Primary button fill, waveform bars, slider fill — indigo-600/500 family.
    public static let accent = Color(hex: 0x4f46e5)
    /// Primary button hover, sliders, waveform bars — indigo-500.
    public static let accentHover = Color(hex: 0x6366f1)
    /// Waveform playhead/progress line — indigo-300 (lighter than the wave itself
    /// so the cursor reads clearly against it — mirrors wavesurfer's wave/progress
    /// two-tone: wave=indigo-500, progress=indigo-300).
    public static let signalLight = Color(hex: 0xa5b4fc)

    // ── semantic ─────────────────────────────────────────────────────────────────
    /// Dirty state / negative-duration / destructive — rose-400.
    public static let warn = Color(hex: 0xfb7185)
    /// Non-destructive warnings (quality flags) — amber-500.
    public static let amber = Color(hex: 0xf59e0b)
    /// Validated / saved / no-issues state — emerald-400.
    public static let good = Color(hex: 0x34d399)
}

public enum GlyphFont {
    /// Timecodes, cue-grid numeric columns, waveform ruler, transport clock —
    /// anything that measures time. Tabular figures (monospaced digits) so
    /// columns of numbers align.
    public static func data(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Dialogue text, labels, body copy — anything a person said or reads.
    public static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// App identity, panel headers, section titles — used with restraint.
    public static func display(_ size: CGFloat = 15, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

public enum GlyphMetric {
    /// The "time spine" stroke width — kept consistent across ruler/scrubber/row.
    public static let spineWidth: CGFloat = 2
    public static let cornerRadius: CGFloat = 8
    public static let paneSpacing: CGFloat = 1 // hairline gap between docked panes
}
