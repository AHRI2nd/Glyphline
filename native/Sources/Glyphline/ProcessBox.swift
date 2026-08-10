// Shared handle for cancelling an in-flight external process (ffmpeg, in
// every current use). Swift's task cancellation is cooperative — cancelling
// the outer Task does NOT by itself stop a process already running inside a
// detached Task or a readabilityHandler-driven continuation, so every long-
// running Process call in this app pairs `withTaskCancellationHandler` with
// one of these to actually terminate the subprocess instead of letting it
// keep burning CPU in the background after the user has moved on.
//
// Originally private to SceneCutExtractor.swift; promoted here once
// BurnInEncoder/DeliveryPipelineRunner needed the identical pattern.

import Foundation

/// Lets the cancellation handler (which can fire concurrently with, or
/// before, the process even launches) reach the `Process` instance safely.
/// `Process.terminate()` is documented as callable from any thread.
final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _process: Process?
    var process: Process? {
        get { lock.lock(); defer { lock.unlock() }; return _process }
        set { lock.lock(); defer { lock.unlock() }; _process = newValue }
    }
    func terminate() {
        lock.lock()
        let p = _process
        lock.unlock()
        p?.terminate()
    }
}
