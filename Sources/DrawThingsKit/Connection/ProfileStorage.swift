//
//  ProfileStorage.swift
//  DrawThingsKit
//
//  Created by euphoriacyberware-ai.
//  Copyright © 2025 euphoriacyberware-ai
//
//  Licensed under the MIT License.
//  See LICENSE file in the project root for license information.
//

import Foundation
import DrawThingsClient

/// Handles persistence of server profiles to UserDefaults.
/// Profiles are stored per-app using the bundle identifier as a key prefix.
/// `@unchecked Sendable`: `UserDefaults` is documented as thread-safe, and it is the only state.
public final class ProfileStorage: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let storageKey: String

    /// Initialize with optional custom UserDefaults and key prefix.
    /// - Parameters:
    ///   - userDefaults: The UserDefaults instance to use. Defaults to `.standard`.
    ///   - keyPrefix: Custom key prefix. Defaults to the app's bundle identifier.
    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String? = nil
    ) {
        self.userDefaults = userDefaults
        let prefix = keyPrefix ?? Bundle.main.bundleIdentifier ?? "DrawThingsKit"
        self.storageKey = "\(prefix).serverProfiles"
    }

    /// Load all saved profiles.
    /// - Returns: Array of saved profiles, or empty array if none exist.
    public func loadProfiles() -> [ServerProfile] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }

        do {
            let profiles = try JSONDecoder().decode([ServerProfile].self, from: data)
            return profiles
        } catch {
            DTLogger.error("Failed to decode profiles: \(error)", category: .connection)
            return []
        }
    }

    /// Save profiles to storage.
    /// - Parameter profiles: The profiles to save.
    public func saveProfiles(_ profiles: [ServerProfile]) {
        do {
            let data = try JSONEncoder().encode(profiles)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            DTLogger.error("Failed to encode profiles: \(error)", category: .connection)
        }
    }

    /// Clear all saved profiles.
    public func clearProfiles() {
        userDefaults.removeObject(forKey: storageKey)
    }
}
