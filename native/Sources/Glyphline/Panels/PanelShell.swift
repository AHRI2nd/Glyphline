// Shared sheet chrome for M5 panels: header + content + footer. SwiftUI's
// `.sheet` already provides the native modal presentation (no hand-rolled
// backdrop/box needed, unlike the web build's Backdrop+rounded-box CSS).

import SwiftUI

/// Where a panel is being shown. The same panel body serves both: several of
/// them ("find a problem → fix it → next") are useless as modals because you
/// have to close them to do the fixing, so they live in the dock — while
/// one-shot dialogs (batch cleanup, point sync) stay sheets.
enum PanelPresentation { case sheet, pane }

private struct PanelPresentationKey: EnvironmentKey {
    static let defaultValue = PanelPresentation.sheet
}

extension EnvironmentValues {
    var panelPresentation: PanelPresentation {
        get { self[PanelPresentationKey.self] }
        set { self[PanelPresentationKey.self] = newValue }
    }
}

/// Close button that disappears when the panel is docked — a docked pane has
/// no sheet to dismiss, and `dismiss` there is a no-op that would render a
/// dead control.
struct PanelCloseButton: View {
    @Environment(\.panelPresentation) private var presentation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if presentation == .sheet {
            Button(t("close")) { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }
}

struct PanelShell<Content: View, Footer: View>: View {
    let title: String
    var width: CGFloat = 420
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @Environment(\.panelPresentation) private var presentation

    private var isPane: Bool { presentation == .pane }

    var body: some View {
        VStack(spacing: 0) {
            // A docked pane already shows its name on the tab, so repeating it
            // here would just spend vertical space saying the same thing twice.
            if !isPane {
                HStack {
                    Text(title).font(GlyphFont.display(13)).foregroundStyle(GlyphColor.ink)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border)
            }

            ScrollView {
                content.padding(isPane ? 10 : 16)
            }

            Rectangle().frame(height: 0.5).foregroundStyle(GlyphColor.border)
            HStack { footer }
                .padding(.horizontal, isPane ? 10 : 16)
                .padding(.vertical, isPane ? 6 : 10)
        }
        .modifier(PanelSizing(width: width, isPane: isPane))
        .background(GlyphColor.surface)
        .foregroundStyle(GlyphColor.ink)
    }
}

/// A sheet is sized to its content; a pane fills whatever the dock gives it.
private struct PanelSizing: ViewModifier {
    let width: CGFloat
    let isPane: Bool

    func body(content: Content) -> some View {
        if isPane {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content.frame(width: width).frame(minHeight: 120, maxHeight: 560)
        }
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
