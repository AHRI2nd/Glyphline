// Compare the open document against another subtitle file, and the two
// multi-file operations that live next to it (append / split).
//
// Comparison is read-only on purpose: this answers "what changed between v1 and
// v2", which is a review question. Merging changes across would need a whole
// conflict model, and getting that half-right is worse than not offering it —
// so findings are clickable (jump to the cue) but never applied automatically.
//
// The engine is in GlyphlineCore/SubtitleDiff.swift.

import SwiftUI
import UniformTypeIdentifiers
import GlyphlineCore

struct CompareFilesPanel: View {
    let document: DocumentModel
    let media: MediaModel
    var onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var otherName: String?
    @State private var entries: [DiffEntry] = []
    @State private var summary = DiffSummary()
    @State private var appendGap = "1"

    var body: some View {
        PanelShell(title: t("compareFiles"), width: 620) {
            VStack(alignment: .leading, spacing: 14) {
                comparisonSection
                Divider()
                joinSplitSection
            }
        } footer: {
            Spacer()
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    // ── compare ──────────────────────────────────────────────────────────────

    @ViewBuilder
    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t("compareAgainst")).font(GlyphFont.body(12))
                Spacer()
                Button(t("compareChooseFile")) { chooseAndCompare() }.controlSize(.small)
            }
            if let otherName {
                Text(otherName).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
                    .lineLimit(1).truncationMode(.middle)
            } else {
                Text(t("compareHint")).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
            }

            if otherName != nil {
                if entries.isEmpty {
                    Text(t("compareIdentical"))
                        .font(GlyphFont.body(12)).foregroundStyle(GlyphColor.good)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    summaryRow
                    ForEach(entries.prefix(200)) { entry in
                        DiffRow(entry: entry) { jump(entry) }
                        Divider()
                    }
                    if entries.count > 200 {
                        Text(t("compareTruncated", "\(entries.count - 200)"))
                            .font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
                    }
                }
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            counter(t("diffAdded"), summary.added, GlyphColor.good)
            counter(t("diffRemoved"), summary.removed, GlyphColor.warn)
            counter(t("diffTextChanged"), summary.textChanged, GlyphColor.amber)
            counter(t("diffRetimed"), summary.retimed, GlyphColor.signal)
            counter(t("diffChanged"), summary.changed, GlyphColor.accentHover)
            Spacer()
        }
        .font(GlyphFont.data(11))
    }

    private func counter(_ label: String, _ n: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(n)").foregroundStyle(n > 0 ? color : GlyphColor.quiet)
            Text(label).foregroundStyle(GlyphColor.quiet)
        }
    }

    // ── join / split ─────────────────────────────────────────────────────────

    @ViewBuilder
    private var joinSplitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t("appendFile")).font(GlyphFont.body(12))
                Spacer()
                NumberField(label: t("appendGap"), value: $appendGap, suffix: t("secondsSuffix"))
                Button(t("appendChooseFile")) { chooseAndAppend() }.controlSize(.small)
            }
            Text(t("appendHint")).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)

            HStack {
                Text(t("splitAtPlayhead")).font(GlyphFont.body(12))
                Spacer()
                Button(t("splitSaveTail")) { splitAndSave() }
                    .controlSize(.small)
                    .disabled(media.mediaPath == nil)
            }
            Text(t("splitHint")).font(GlyphFont.body(10)).foregroundStyle(GlyphColor.quiet)
        }
    }

    // ── actions ──────────────────────────────────────────────────────────────

    private func pickSubtitle() -> SubtitleDocument? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = openExtensions().compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let doc = try SubtitleFileIO.open(path: url.path)
            otherName = url.lastPathComponent
            return doc
        } catch {
            onError(t("errOpenSubtitle", error.localizedDescription))
            return nil
        }
    }

    private func chooseAndCompare() {
        guard let other = pickSubtitle() else { return }
        entries = diffDocuments(document.doc, other)
        summary = summarize(entries)
    }

    private func chooseAndAppend() {
        guard let other = pickSubtitle() else { return }
        let gap = Double(appendGap) ?? 1
        document.appendDocument(other, offset: appendOffsetAfter(document.doc, gap: gap))
    }

    private func splitAndSave() {
        let tail = document.splitOffTail(at: media.currentTime, rebase: true)
        guard !tail.cues.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: NATIVE_EXT)].compactMap { $0 }
        let base = (document.fileName ?? "untitled").replacingOccurrences(of: ".\(NATIVE_EXT)", with: "")
        panel.nameFieldStringValue = "\(base).part2.\(NATIVE_EXT)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SubtitleFileIO.saveGlyph(tail, to: url.path)
        } catch {
            onError(t("errSaveFailed", error.localizedDescription))
        }
    }

    private func jump(_ entry: DiffEntry) {
        // Only the LEFT side exists in the open document — a cue that's only in
        // the other file has nothing here to select.
        guard let id = entry.left?.id else { return }
        document.setActiveCue(id)
    }
}

private struct DiffRow: View {
    let entry: DiffEntry
    let onJump: () -> Void

    var body: some View {
        Button(action: onJump) {
            HStack(alignment: .top, spacing: 8) {
                Text(label).font(GlyphFont.data(10)).foregroundStyle(color)
                    .frame(width: 54, alignment: .leading)
                Text(formatDisplayTime(entry.time))
                    .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.quiet)
                    .frame(width: 74, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    if let l = entry.left {
                        Text(l.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                            .font(GlyphFont.body(11))
                            .foregroundStyle(entry.kind == .removed ? GlyphColor.warn : GlyphColor.quiet)
                            .lineLimit(1)
                    }
                    if let r = entry.right, entry.kind != .retimed {
                        Text(r.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                            .font(GlyphFont.body(11)).foregroundStyle(GlyphColor.ink)
                            .lineLimit(1)
                    }
                    if entry.kind == .retimed, let r = entry.right {
                        Text("→ \(formatDisplayTime(r.start))")
                            .font(GlyphFont.data(10)).foregroundStyle(GlyphColor.signal)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    private var label: String {
        switch entry.kind {
        case .added: return t("diffAdded")
        case .removed: return t("diffRemoved")
        case .textChanged: return t("diffTextChanged")
        case .retimed: return t("diffRetimed")
        case .changed: return t("diffChanged")
        }
    }

    private var color: Color {
        switch entry.kind {
        case .added: return GlyphColor.good
        case .removed: return GlyphColor.warn
        case .textChanged: return GlyphColor.amber
        case .retimed: return GlyphColor.signal
        case .changed: return GlyphColor.accentHover
        }
    }
}
