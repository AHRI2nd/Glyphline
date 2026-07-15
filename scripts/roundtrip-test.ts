// Pure round-trip test for the format adapters (no Tauri).
// Run: npx tsx scripts/roundtrip-test.ts
import { parseSrt, serializeSrt } from "../src/formats/srt";
import { parseVtt, serializeVtt } from "../src/formats/vtt";
import { parseAss, serializeAss, embeddedByteSize } from "../src/formats/ass";
import { parseSmi, serializeSmi } from "../src/formats/smi";
import { parseSbv, serializeSbv } from "../src/formats/sbv";
import { parseLrc, serializeLrc } from "../src/formats/lrc";
import { parseTxt, serializeTxt } from "../src/formats/txt";
import { parseGlyph, serializeGlyph } from "../src/formats/glyph";

let failures = 0;
function check(name: string, cond: boolean, detail = "") {
  console.log(`${cond ? "✓" : "✗"} ${name}${cond ? "" : "  — " + detail}`);
  if (!cond) failures++;
}

// ── SRT ───────────────────────────────────────────────────────────────────────
const srt = `1
00:00:01,000 --> 00:00:03,500
Hello world
second line

2
00:00:04,000 --> 00:00:06,000
Goodbye
`;
const srtDoc = parseSrt(srt);
check("SRT: 2 cues parsed", srtDoc.cues.length === 2, `got ${srtDoc.cues.length}`);
check("SRT: times", srtDoc.cues[0].start === 1 && srtDoc.cues[0].end === 3.5);
check("SRT: multiline preserved", srtDoc.cues[0].text === "Hello world\nsecond line", JSON.stringify(srtDoc.cues[0].text));
const srt2 = parseSrt(serializeSrt(srtDoc));
check("SRT: round-trip stable", JSON.stringify(srt2.cues.map(c=>[c.start,c.end,c.text])) === JSON.stringify(srtDoc.cues.map(c=>[c.start,c.end,c.text])));

// ── VTT with inline timestamp tokens ──────────────────────────────────────────
const vtt = `WEBVTT

00:00:01.000 --> 00:00:04.000
Hello <00:00:02.000>brave <00:00:03.000>world
`;
const vttDoc = parseVtt(vtt);
check("VTT: 1 cue", vttDoc.cues.length === 1);
check("VTT: tokens extracted", (vttDoc.cues[0].tokens?.length ?? 0) === 3, JSON.stringify(vttDoc.cues[0].tokens));
check("VTT: token timing", vttDoc.cues[0].tokens?.[1].start === 2);
const vtt2 = parseVtt(serializeVtt(vttDoc));
check("VTT: token round-trip", (vtt2.cues[0].tokens?.length ?? 0) === 3, JSON.stringify(vtt2.cues[0].tokens));

// ── ASS with karaoke ──────────────────────────────────────────────────────────
const ass = `[Script Info]
ScriptType: v4.00+

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\k50}Ka{\\k50}ra{\\k100}oke
Dialogue: 0,0:00:04.00,0:00:05.50,Default,Bob,0,0,0,,Hello, with comma
`;
const assDoc = parseAss(ass);
check("ASS: 1 style", assDoc.styles?.length === 1);
check("ASS: style font", assDoc.styles?.[0].fontName === "Arial");
check("ASS: 2 cues", assDoc.cues.length === 2, `got ${assDoc.cues.length}`);
check("ASS: karaoke tokens", (assDoc.cues[0].tokens?.length ?? 0) === 3, JSON.stringify(assDoc.cues[0].tokens));
check("ASS: comma in text preserved", assDoc.cues[1].text === "Hello, with comma", JSON.stringify(assDoc.cues[1].text));
check("ASS: actor", assDoc.cues[1].actor === "Bob");
const ass2 = parseAss(serializeAss(assDoc));
check("ASS: round-trip cues", ass2.cues.length === 2);
check("ASS: round-trip karaoke", (ass2.cues[0].tokens?.length ?? 0) === 3);

// ── ASS embedded [Fonts]/[Graphics] (lossless preserve) ───────────────────────
const embedAss = `[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,2,10,10,10,1

[Fonts]
fontname: myfont_0.ttf
!!!!encoded-line-one!!!!
####encoded-line-two####
fontname: other_1.otf
ABCDEF

[Graphics]
filename: logo_0.png
GFXDATA0123

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,hi
`;
const embDoc = parseAss(embedAss);
check("EMBED: 2 fonts parsed", embDoc.fonts?.length === 2, `got ${embDoc.fonts?.length}`);
check("EMBED: font name", embDoc.fonts?.[0].name === "myfont_0.ttf", JSON.stringify(embDoc.fonts?.[0].name));
check("EMBED: font data (2 lines)", embDoc.fonts?.[0].data === "!!!!encoded-line-one!!!!\n####encoded-line-two####", JSON.stringify(embDoc.fonts?.[0].data));
check("EMBED: second font", embDoc.fonts?.[1].name === "other_1.otf" && embDoc.fonts?.[1].data === "ABCDEF");
check("EMBED: 1 graphic parsed", embDoc.graphics?.length === 1 && embDoc.graphics?.[0].name === "logo_0.png");
check("EMBED: cue still parsed", embDoc.cues.length === 1 && embDoc.cues[0].text === "hi");
// header not leaked into assExtra
check("EMBED: no header leak", !(embDoc.meta.assExtra ?? "").toLowerCase().includes("[fonts]"), embDoc.meta.assExtra);
// serialize → reparse: identical fonts/graphics
const embOut = serializeAss(embDoc);
check("EMBED: serialize has [Fonts]", embOut.includes("[Fonts]") && embOut.includes("fontname: myfont_0.ttf"));
check("EMBED: serialize has [Graphics]", embOut.includes("[Graphics]") && embOut.includes("filename: logo_0.png"));
const emb2 = parseAss(embOut);
check("EMBED: round-trip fonts", JSON.stringify(emb2.fonts) === JSON.stringify(embDoc.fonts));
check("EMBED: round-trip graphics", JSON.stringify(emb2.graphics) === JSON.stringify(embDoc.graphics));
// glyph keeps them too
const embGlyph = parseGlyph(serializeGlyph(embDoc));
check("EMBED: glyph preserves fonts", JSON.stringify(embGlyph.fonts) === JSON.stringify(embDoc.fonts));
check("EMBED: byte size estimate", embeddedByteSize("ABCD") === 3 && embeddedByteSize("ABCDEF") === 4, String(embeddedByteSize("ABCDEF")));

// ── ASS edit fidelity: inline tags kept when unedited, dropped when edited ────
const assTagged = `[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\\b1}Bold{\\b0} text
`;
const taggedDoc = parseAss(assTagged);
check("ASS: plain text strips tags", taggedDoc.cues[0].text === "Bold text", JSON.stringify(taggedDoc.cues[0].text));
// Unedited -> original tags preserved on serialize
check("ASS: unedited keeps inline tags", serializeAss(taggedDoc).includes("{\\b1}Bold{\\b0} text"));
// Edited -> honor the new text (tags dropped, no stale text)
taggedDoc.cues[0].text = "Edited text";
const editedDialogue = serializeAss(taggedDoc).split("\n").find((l) => l.startsWith("Dialogue:")) ?? "";
// Edit honored; opening block kept (line-level), un-anchorable mid-text block dropped.
check("ASS: edited text wins", editedDialogue.endsWith("Edited text") && !editedDialogue.includes("{\\b0}"), editedDialogue);

// ── Full inline-tag lossless round-trip ───────────────────────────────────────
// A dialogue line exercising position, fade, colour, transform, clip, drawing,
// karaoke, and an UNKNOWN tag — all must survive parse -> serialize verbatim.
const complexTags =
  "{\\an8\\pos(960,120)\\fad(200,200)\\1c&H00FF00&\\3c&HFF0000&\\b1\\frz12.5\\t(0,500,\\frz0)}" +
  "Hello {\\i1}world{\\i0}{\\xyzCustom123}{\\k50}ka{\\k50}ra{\\clip(0,0,100,100)}end{\\p1}m 0 0 l 10 10{\\p0}";
const ctDoc = parseAss(`[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:05.00,Default,,0,0,0,,${complexTags}
`);
const ctOut = serializeAss(ctDoc).split("\n").find((l) => l.startsWith("Dialogue:")) ?? "";
check("TAGS: complex line round-trips verbatim", ctOut.endsWith(complexTags), `\n  got:  ${ctOut}\n  want: ...${complexTags}`);
check("TAGS: fx indicator (has overrides)", ctDoc.cues[0].assSpans?.some((s) => s.tags));
// Decode coverage
import { decodeTags } from "../src/formats/assTags";
const decoded = decodeTags("\\an8\\pos(960,120)\\1c&H00FF00&\\xyzCustom123");
check("TAGS: decode known \\pos", decoded.find((d) => d.name === "pos")?.arg === "(960,120)");
check("TAGS: decode known \\1c", decoded.find((d) => d.name === "1c")?.known === true);
check("TAGS: unknown tag flagged", decoded.find((d) => d.name === "xyzCustom")?.known === false, JSON.stringify(decoded));

// ── Colour conversion (ASS &HAABBGGRR <-> #RRGGBB) ────────────────────────────
import { assColorToHex, hexToAssColor, assAlpha } from "../src/utils/color";
check("COLOR: ass->hex (BGR reversed)", assColorToHex("&H0000CCFF") === "#FFCC00", assColorToHex("&H0000CCFF"));
check("COLOR: hex->ass preserves alpha", hexToAssColor("#FFCC00", assAlpha("&H800000FF")) === "&H8000CCFF", hexToAssColor("#FFCC00", "80"));

// ── SMI ───────────────────────────────────────────────────────────────────────
const smi = `<SAMI>
<HEAD>
<TITLE>Test</TITLE>
<STYLE TYPE="text/css"><!--
.KRCC { Name: Korean; lang: ko-KR; }
--></STYLE>
</HEAD>
<BODY>
<SYNC Start=1000><P Class=KRCC>안녕하세요
<SYNC Start=3000><P Class=KRCC>&nbsp;
<SYNC Start=4000><P Class=KRCC>두<br>번째 줄
<SYNC Start=6000><P Class=KRCC>&nbsp;
</BODY>
</SAMI>`;
const smiDoc = parseSmi(smi);
check("SMI: 2 cues (blanks excluded)", smiDoc.cues.length === 2, `got ${smiDoc.cues.length}`);
check("SMI: start from ms", smiDoc.cues[0].start === 1);
check("SMI: end from blank marker", smiDoc.cues[0].end === 3, `got ${smiDoc.cues[0].end}`);
check("SMI: <br> -> newline", smiDoc.cues[1].text === "두\n번째 줄", JSON.stringify(smiDoc.cues[1].text));
const smi2 = parseSmi(serializeSmi(smiDoc));
check("SMI: round-trip cues", smi2.cues.length === 2);
check("SMI: round-trip text", smi2.cues[1].text === "두\n번째 줄", JSON.stringify(smi2.cues[1].text));

// ── ASS -> SMI: representable formatting converted, rest dropped + reported ────
import { serializeSmi, spansToSmiHtml, smiExportLoss } from "../src/formats/smi";
const styledAss = parseAss(`[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,{\\pos(10,20)\\b1\\1c&H0000FF&}Red bold{\\b0} plain{\\k50}\\Nline2{\\p1}m 0 0 l 5 5{\\p0}
`);
const conv = spansToSmiHtml(styledAss.cues[0].assSpans!);
check("SMI<-ASS: bold converted", conv.html.includes("<b>Red bold</b>") || conv.html.includes("<b>Red bold"), conv.html);
check("SMI<-ASS: colour converted (#FF0000)", conv.html.toUpperCase().includes('COLOR="#FF0000"'), conv.html);
check("SMI<-ASS: \\N -> <br>", conv.html.includes("<br>"), conv.html);
check("SMI<-ASS: drawing coords dropped", !conv.html.includes("m 0 0"), conv.html);
check("SMI<-ASS: pos reported as loss", conv.dropped.has("position"));
check("SMI<-ASS: karaoke reported as loss", conv.dropped.has("karaoke"));
check("SMI<-ASS: drawing reported as loss", conv.dropped.has("drawing"));
const loss = smiExportLoss(styledAss);
check("SMI<-ASS: smiExportLoss aggregates", loss.includes("position") && loss.includes("drawing"));
check("SMI<-ASS: full serialize has <SYNC>", serializeSmi(styledAss).includes("<SYNC Start=1000>"));

// ── Native .glyph lossless (tokens included) ──────────────────────────────────
const glyphStr = serializeGlyph(vttDoc);
const glyphDoc = parseGlyph(glyphStr);
check("GLYPH: lossless cues", JSON.stringify(glyphDoc.cues) === JSON.stringify(vttDoc.cues));
check("GLYPH: tokens preserved", (glyphDoc.cues[0].tokens?.length ?? 0) === 3);
// translation field is .glyph-only and must survive
const transDoc = parseSrt(srt);
transDoc.cues[0].translation = "안녕 세계\n둘째 줄";
const transGlyph = parseGlyph(serializeGlyph(transDoc));
check("GLYPH: translation preserved", transGlyph.cues[0].translation === "안녕 세계\n둘째 줄", JSON.stringify(transGlyph.cues[0].translation));

// ── SBV (YouTube) ─────────────────────────────────────────────────────────────
const sbv = `0:00:01.000,0:00:03.500
Hello world
second line

0:00:04.000,0:00:06.000
Goodbye
`;
const sbvDoc = parseSbv(sbv);
check("SBV: 2 cues parsed", sbvDoc.cues.length === 2, `got ${sbvDoc.cues.length}`);
check("SBV: times", sbvDoc.cues[0].start === 1 && sbvDoc.cues[0].end === 3.5);
check("SBV: multiline preserved", sbvDoc.cues[0].text === "Hello world\nsecond line");
const sbv2 = parseSbv(serializeSbv(sbvDoc));
check("SBV: round-trip stable", JSON.stringify(sbv2.cues.map(c=>[c.start,c.end,c.text])) === JSON.stringify(sbvDoc.cues.map(c=>[c.start,c.end,c.text])));

// ── LRC ───────────────────────────────────────────────────────────────────────
const lrc = `[ti:Song]
[00:01.00]first line
[00:03.50]second line
`;
const lrcDoc = parseLrc(lrc);
check("LRC: metadata ignored, 2 cues", lrcDoc.cues.length === 2, `got ${lrcDoc.cues.length}`);
check("LRC: start time + implied end", lrcDoc.cues[0].start === 1 && lrcDoc.cues[0].end === 3.5);
check("LRC: text", lrcDoc.cues[0].text === "first line");
const lrc2 = parseLrc(serializeLrc(lrcDoc));
check("LRC: round-trip start stable", Math.abs(lrc2.cues[0].start - lrcDoc.cues[0].start) < 0.01);

// ── TXT ───────────────────────────────────────────────────────────────────────
const txt = `line one\nline two\n\nline three`;
const txtDoc = parseTxt(txt);
check("TXT: 3 non-empty lines → 3 cues", txtDoc.cues.length === 3, `got ${txtDoc.cues.length}`);
check("TXT: sequential timing", txtDoc.cues[0].start === 0 && txtDoc.cues[1].start === 2);
check("TXT: export is text-only", serializeTxt(txtDoc).includes("line one") && !serializeTxt(txtDoc).includes("00:"));

// ── Cross-format conversion: SRT -> ASS ───────────────────────────────────────
const asAss = parseAss(serializeAss(srtDoc));
check("CONVERT: SRT->ASS preserves times", asAss.cues[0].start === 1 && asAss.cues[0].end === 3.5);
check("CONVERT: SRT->ASS default style created", (asAss.styles?.length ?? 0) >= 1);

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
