import XCTest
@testable import HealthLogSync

/// Bug 5 from post-PR33 review: `BGProcessingTask.setTaskCompleted(success:)`
/// was at risk of being called twice — once by the natural sync path and
/// once by the `expirationHandler` if iOS fired it just before the sync
/// finished. The fix introduces a CompleteOnce helper guarded by NSLock.
///
/// Because `BGProcessingTask` cannot be instantiated outside the
/// BackgroundTasks runtime, we re-implement the same lock-and-flag
/// pattern in-test and assert its invariants. This is the same shape
/// of code we ship in `BackgroundTaskManager.handleSyncTask`.
final class BackgroundTaskCompletionTests: XCTestCase {
    /// Two callers from different threads both attempting to complete
    /// must result in exactly one effective completion — the first wins,
    /// the second is silently dropped.
    func test_completeOnce_collapsesConcurrentCallsToOne() {
        let recorder = CompletionRecorder()
        let completer = makeCompleter { success in recorder.record(success) }

        let queue = DispatchQueue(label: "test.completion", attributes: .concurrent)
        let group = DispatchGroup()

        for index in 0 ..< 100 {
            group.enter()
            queue.async {
                completer(index.isMultiple(of: 2))
                group.leave()
            }
        }

        group.wait()
        XCTAssertEqual(recorder.count, 1, "setTaskCompleted must be invoked exactly once under contention")
    }

    /// The expiration-handler flow: sync finishes successfully then the
    /// expiration handler fires. Only the first call wins.
    func test_completeOnce_successWinsWhenItRunsFirst() {
        let recorder = CompletionRecorder()
        let completer = makeCompleter { success in recorder.record(success) }

        completer(true) // natural sync completion
        completer(false) // expiration handler firing later

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.lastSuccess, true)
    }

    /// Reversed order: expiration fires first, sync completes after.
    /// Only the first call wins, even though it reported failure.
    func test_completeOnce_expirationWinsWhenItRunsFirst() {
        let recorder = CompletionRecorder()
        let completer = makeCompleter { success in recorder.record(success) }

        completer(false)
        completer(true)

        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.lastSuccess, false)
    }

    // MARK: - Helpers

    /// Mirror of the production CompleteOnce shape from
    /// `BackgroundTaskManager.handleSyncTask`. Kept in-test so we can
    /// validate the concurrency invariant without `BGProcessingTask`.
    private func makeCompleter(_ onComplete: @escaping (Bool) -> Void) -> (Bool) -> Void {
        let lock = NSLock()
        var completed = false
        return { success in
            lock.lock()
            let alreadyCompleted = completed
            completed = true
            lock.unlock()
            guard !alreadyCompleted else { return }
            onComplete(success)
        }
    }
}

private final class CompletionRecorder {
    private let lock = NSLock()
    private var calls: [Bool] = []

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return calls.count
    }

    var lastSuccess: Bool? {
        lock.lock(); defer { lock.unlock() }
        return calls.last
    }

    func record(_ success: Bool) {
        lock.lock(); defer { lock.unlock() }
        calls.append(success)
    }
}
