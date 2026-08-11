// "Help ▸ Check for Updates…" — Sparkle's own SwiftUI-without-Interface-Builder
// pattern (https://sparkle-project.org/documentation/programmatic-setup/). The
// Combine bridge is needed because `SPUUpdater.canCheckForUpdates` is a KVO
// property on an NSObject subclass, not an @Observable one — this is the
// smallest wrapper that lets the menu item disable itself while a check is
// already in flight.

import SwiftUI
import Combine
import Sparkle

@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: \.canCheckForUpdates, on: self)
    }
}

struct CheckForUpdatesView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button(t("checkForUpdates")) { updater.checkForUpdates() }
            .disabled(!viewModel.canCheckForUpdates)
    }
}
