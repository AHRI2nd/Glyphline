import Testing
import Foundation
@testable import GlyphlineCore

// Vectors ported from ../../../src-tauri/src/lib.rs's `decode_tests` module.

@Suite("TextEncoding")
struct TextEncodingTests {
    @Test("UTF-8 passthrough")
    func utf8Passthrough() {
        let text = "안녕 <b>자막</b>"
        #expect(TextEncoding.decode(text.data(using: .utf8)!) == text)
    }

    @Test("UTF-8 BOM stripped")
    func utf8BomStripped() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("hello".data(using: .utf8)!)
        #expect(TextEncoding.decode(data) == "hello")
    }

    @Test("CP949 (Korean) detected")
    func cp949Detected() {
        let text = "<SAMI>안녕하세요, 자막 테스트입니다.</SAMI>"
        guard let data = text.data(using: TextEncoding.cp949) else {
            Issue.record("failed to encode test fixture as CP949")
            return
        }
        #expect(TextEncoding.decode(data) == text)
    }

    @Test("Shift_JIS (Japanese) detected")
    func shiftJISDetected() {
        let text = "字幕のテストです。よろしくお願いします。"
        guard let data = text.data(using: .shiftJIS) else {
            Issue.record("failed to encode test fixture as Shift_JIS")
            return
        }
        #expect(TextEncoding.decode(data) == text)
    }

    @Test("export encoding label lookup")
    func exportLabels() {
        #expect(TextEncoding.encoding(forLabel: "euc-kr") == TextEncoding.cp949)
        #expect(TextEncoding.encoding(forLabel: "cp949") == TextEncoding.cp949)
        #expect(TextEncoding.encoding(forLabel: "shift_jis") == .shiftJIS)
        #expect(TextEncoding.encoding(forLabel: "utf-8") == .utf8)
        #expect(TextEncoding.encoding(forLabel: "unknown-label") == .utf8)
    }
}
