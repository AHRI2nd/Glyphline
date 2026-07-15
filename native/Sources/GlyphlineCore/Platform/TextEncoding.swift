// Legacy-encoding-aware text I/O (ported from ../../../src-tauri/src/lib.rs's
// decode_text / write_text_file_encoded).
//
// Korean subtitle files (especially .smi) are very often CP949/EUC-KR, and
// Japanese ones Shift_JIS — a strict-UTF-8 read rejects them outright.
//
// ENCODING-DETECTION TRADE-OFF (see the migration plan's Risk section): the
// Rust build used `chardetng` (Firefox's statistical detector), which has no
// Swift equivalent without an external dependency. This implementation uses
// Foundation's `String(data:encoding:)`, which for these legacy multi-byte
// encodings either decodes the ENTIRE buffer validly or returns nil — there is
// no partial/lossy success. That full-buffer-validity requirement is a
// reasonably strong signal for well-formed CP949/Shift_JIS text (malformed byte
// sequences under the wrong encoding almost always fail outright), so trying
// candidates in order and taking the first clean decode works well in practice
// for the two encodings the original test suite covered. If real-world files
// prove this insufficient, revisit with a bundled statistical detector (e.g.
// uchardet via SPM).

import Foundation

public enum TextEncoding {
    /// Decode `data` to a `String`: BOM → strict UTF-8 → CP949/Shift_JIS (see
    /// below) → UTF-8 with lossy replacement (always succeeds).
    public static func decode(_ data: Data) -> String {
        if let (encoding, bomLength) = detectBOM(data) {
            let body = data.dropFirst(bomLength)
            if let s = String(data: body, encoding: encoding) { return s }
        }
        if let s = String(data: data, encoding: .utf8) { return s }

        // CP949/UHC and Shift_JIS byte ranges overlap — worse, CP949's trail-byte
        // range is famously broad (it was extended past plain EUC-KR specifically
        // to pack in ~8800 extra Hangul syllables), so it will often "validly"
        // full-buffer-decode bytes that were actually meant as Shift_JIS, turning
        // them into fluent-looking Hangul garbage. Shift_JIS's narrower, stricter
        // byte-validity table makes ITS success the much more reliable signal —
        // verified empirically: real Shift_JIS bytes decode as "valid" CP949
        // garbage, but real CP949 bytes do NOT decode as "valid" Shift_JIS. So
        // when both succeed, trust Shift_JIS; CP949 is the fallback.
        if let j = String(data: data, encoding: .shiftJIS) { return j }
        if let k = String(data: data, encoding: cp949) { return k }
        return String(decoding: data, as: UTF8.self) // lossy fallback, never fails
    }

    /// CP949 (Windows Korean / Unified Hangul Code) — a superset of EUC-KR with
    /// additional Hangul syllables, matching how real-world Korean `.smi` files
    /// are actually encoded.
    public static let cp949: String.Encoding = {
        let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosKorean.rawValue))
        return String.Encoding(rawValue: cf)
    }()

    private static func detectBOM(_ data: Data) -> (String.Encoding, Int)? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return (.utf8, 3) }
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { return (.utf32LittleEndian, 4) }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return (.utf32BigEndian, 4) }
        if bytes.starts(with: [0xFF, 0xFE]) { return (.utf16LittleEndian, 2) }
        if bytes.starts(with: [0xFE, 0xFF]) { return (.utf16BigEndian, 2) }
        return nil
    }

    /// WHATWG-ish label → `String.Encoding`, for export (e.g. "euc-kr"/"cp949"
    /// for legacy SMI, matching the Tauri app's `write_text_file_encoded`).
    public static func encoding(forLabel label: String) -> String.Encoding {
        switch label.lowercased() {
        case "utf-8", "utf8": return .utf8
        case "euc-kr", "cp949", "ks_c_5601-1987", "dos-korean": return cp949
        case "shift_jis", "shift-jis", "sjis": return .shiftJIS
        default: return .utf8
        }
    }
}
