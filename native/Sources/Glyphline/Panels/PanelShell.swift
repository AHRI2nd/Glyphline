// Shared sheet chrome for M5 panels: header + content + footer. SwiftUI's
// `.sheet` already provides the native modal presentation (no hand-rolled
// backdrop/box needed, unlike the web build's Backdrop+rounded-box CSS).

import SwiftUI

struct PanelShell<Content: View, Footer: View>: View {
    let title: String
    var width: CGFloat = 420
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(GlyphFont.display(13)).foregroundStyle(GlyphColor.ink)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border)

            ScrollView {
                content.padding(16)
            }

            Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border)
            HStack { footer }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: width)
        .frame(minHeight: 120, maxHeight: 560)
        .background(GlyphColor.surface)
        .foregroundStyle(GlyphColor.ink)
    }
}

extension PanelShell where Footer == EmptyView {
    init(title: String, width: CGFloat = 420, @ViewBuilder content: () -> Content) {
        self.title = title
        self.width = width
        self.content = content()
        self.footer = EmptyView()
    }
}

/// A labeled numeric field used across several panels (durations, factors…).
struct NumberField: View {
    let label: String
    @Binding var value: String
    var suffix: String = ""
    var width: CGFloat = 64

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(GlyphFont.body(12)).foregroundStyle(GlyphColor.quiet)
            TextField("", text: $value)
                .font(GlyphFont.data(12))
                .multilineTextAlignment(.trailing)
                .frame(width: width)
                .textFieldStyle(.roundedBorder)
            if !suffix.isEmpty {
                Text(suffix).font(GlyphFont.body(11)).foregroundStyle(GlyphColor.quiet)
            }
        }
    }
}
