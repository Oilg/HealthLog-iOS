import Foundation
import os

/// Coordinates one-shot reads of the user's date of birth from HealthKit and
/// pushes it to the backend. The flow runs once per install (or until it
/// succeeds) — after a successful upload we mark it complete in UserDefaults
/// so we do not spam PATCH /users/me on every launch.
///
/// Failure modes are intentionally silent:
/// - HealthKit not authorized → skipped, will retry next launch
/// - DOB not set in the Health app → skipped, will retry next launch
/// - Network/backend error → not marked complete, will retry next launch
@MainActor
final class ProfileSyncService {
    static let shared = ProfileSyncService()

    private let log = Logger(subsystem: "com.healthlogsync", category: "ProfileSync")
    private let healthKit: HealthKitDOBProvider
    private let authService: ProfileUpdating
    private let defaults: UserDefaults

    /// Designated initializer with dependency injection points for unit tests.
    /// Production code uses the parameterless `shared` instance.
    init(
        healthKit: HealthKitDOBProvider = HealthKitManager.shared,
        authService: ProfileUpdating = AuthService.shared,
        defaults: UserDefaults = .standard
    ) {
        self.healthKit = healthKit
        self.authService = authService
        self.defaults = defaults
    }

    private static let dobSyncedKey = "dateOfBirthSyncedToBackend"

    var hasSyncedDOB: Bool {
        defaults.bool(forKey: Self.dobSyncedKey)
    }

    /// Reads DOB from HealthKit and pushes it to the backend if available.
    /// - Returns: `true` if a PATCH /users/me was made and succeeded,
    ///            `false` if DOB unavailable or the call failed.
    @discardableResult
    func fetchAndSyncDOB() async -> Bool {
        guard !hasSyncedDOB else { return false }
        guard let components = healthKit.fetchDateOfBirth() else {
            log.info("DOB not available from HealthKit — skipping sync")
            return false
        }
        guard let isoDate = Self.formatISODate(from: components) else {
            log.error("DOB components could not be formatted as ISO date")
            return false
        }
        do {
            _ = try await authService.updateProfile(timezone: nil, dateOfBirth: isoDate)
            defaults.set(true, forKey: Self.dobSyncedKey)
            log.info("DOB synced to backend successfully")
            return true
        } catch {
            log.error("DOB sync failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Formats `DateComponents` (year/month/day) as ISO 8601 date string `YYYY-MM-DD`.
    /// Returns nil if any component is missing.
    static func formatISODate(from components: DateComponents) -> String? {
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Clears the sync flag — call on logout so the next account triggers a fresh DOB sync.
    func resetSyncFlag() {
        defaults.removeObject(forKey: Self.dobSyncedKey)
    }
}

// MARK: - Protocols for testability

protocol HealthKitDOBProvider {
    func fetchDateOfBirth() -> DateComponents?
}

extension HealthKitManager: HealthKitDOBProvider {}

protocol ProfileUpdating {
    @discardableResult
    func updateProfile(timezone: String?, dateOfBirth: String?) async throws -> UserProfileResponse
}

extension AuthService: ProfileUpdating {}
