// Tracking for long-running background operations — burn-in encoding, batch
// conversion, shot-change detection. Each of these already ran as a fire-and-
// forget `Task` before this file existed; the gap was that their progress
// lived in a panel's local `@State`, which is torn down the moment the user
// closes that panel. The `Task` itself keeps running (nothing here changes
// that), but there was no way to check on it, or learn it finished, once the
// triggering sheet was gone. `AppState.backgroundJobs` is the fix: state that
// outlives any one panel, shown persistently by ActivityWindow.

import Foundation

struct BackgroundJob: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var status: Status
    let startedAt = Date()

    enum Status: Equatable {
        case running(progress: Double?)
        case succeeded(String?)
        case failed(String)
    }
}

extension AppState {
    /// Registers a new running job and returns its id for follow-up updates.
    @discardableResult
    func startBackgroundJob(_ title: String) -> UUID {
        let job = BackgroundJob(title: title, status: .running(progress: nil))
        backgroundJobs.insert(job, at: 0)
        return job.id
    }

    func updateBackgroundJob(_ id: UUID, progress: Double?) {
        guard let idx = backgroundJobs.firstIndex(where: { $0.id == id }) else { return }
        backgroundJobs[idx].status = .running(progress: progress)
    }

    func finishBackgroundJob(_ id: UUID, success: Bool, message: String? = nil) {
        guard let idx = backgroundJobs.firstIndex(where: { $0.id == id }) else { return }
        backgroundJobs[idx].status = success ? .succeeded(message) : .failed(message ?? "")
    }

    /// Drops every job that isn't currently running — "clear" in the Activity window.
    func clearFinishedBackgroundJobs() {
        backgroundJobs.removeAll { if case .running = $0.status { return false }; return true }
    }

    var runningBackgroundJobCount: Int {
        backgroundJobs.reduce(0) { count, job in
            if case .running = job.status { return count + 1 }
            return count
        }
    }
}
