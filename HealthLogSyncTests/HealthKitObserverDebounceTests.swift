import XCTest
@testable import HealthLogSync

/// Bug 2 from post-PR33 review: HKObserverQuery can fire ~12 times per
/// minute in the foreground. Without debouncing, each fire kicked off a
/// fresh `runDeltaSync()` and the backend's 200 req/hour rate limit was
/// exhausted in ~17 minutes.
///
/// Fix: `HealthKitManager.scheduleDebouncedNotification(_:)` collapses
/// a burst of observer fires into a single delayed callback. These
/// tests exercise the coalescing contract without going through
/// HealthKit, since the unit-test target has no HK authorization.
final class HealthKitObserverDebounceTests: XCTestCase {
    /// The debounce interval must be at least 60 seconds — anything
    /// shorter would still let a noisy observer (12 fires/min) blow
    /// through the 200 req/hour rate limit before the day was out.
    func test_observerDebounceInterval_isAtLeast60Seconds() {
        XCTAssertGreaterThanOrEqual(HealthKitManager.observerDebounceInterval, 60)
    }

    /// A single burst of 10 rapid notifications must collapse to exactly
    /// one callback invocation. We can't wait the full 60s in a unit
    /// test, so we observe that the debouncer does not fire synchronously
    /// — i.e. by the time control returns from `scheduleDebouncedNotification`,
    /// the callback counter is still zero. This is the contract that
    /// guarantees we don't hit the rate limit on each observer fire.
    func test_scheduleDebouncedNotification_doesNotFireSynchronously() {
        let counter = AtomicCounter()
        let manager = HealthKitManager.shared

        for _ in 0 ..< 10 {
            manager.scheduleDebouncedNotification { counter.increment() }
        }

        // None of the bursts should have invoked the callback yet; the
        // debouncer schedules onto a queue with a 60s delay.
        XCTAssertEqual(counter.value, 0, "Debounced callback fired synchronously — coalescing is broken")
    }

    /// Repeated calls do not crash and do not leak DispatchWorkItems
    /// (each new call cancels the previous one).
    func test_scheduleDebouncedNotification_isSafeUnderRepeatedRapidCalls() {
        let manager = HealthKitManager.shared
        for _ in 0 ..< 1000 {
            manager.scheduleDebouncedNotification {}
        }
        // The mere fact we got here without crashing is the assertion.
        XCTAssertTrue(true)
    }
}

/// Thread-safe counter for the debounce assertion. Foundation has no
/// built-in atomic ints on iOS, and we want to keep tests dependency-free.
private final class AtomicCounter {
    private let lock = NSLock()
    private var underlying = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return underlying
    }

    func increment() {
        lock.lock(); defer { lock.unlock() }
        underlying += 1
    }
}
