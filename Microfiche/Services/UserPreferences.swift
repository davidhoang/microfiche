//
//  UserPreferences.swift
//  Microfiche
//
//  App-wide preferences persisted via UserDefaults.
//

import Combine
import Foundation

@MainActor
final class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let isOnboardingEnabled = "isOnboardingEnabled"
    }

    private let defaults: UserDefaults

    /// Master switch for the welcome sequence. Off hides onboarding (useful while testing).
    @Published var isOnboardingEnabled: Bool {
        didSet {
            defaults.set(isOnboardingEnabled, forKey: Keys.isOnboardingEnabled)
            if !isOnboardingEnabled {
                isPresentingOnboarding = false
            } else if shouldPresentOnboarding {
                isPresentingOnboarding = true
            }
        }
    }

    /// True after the user finishes or skips the welcome sequence.
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    /// Live presentation flag for the onboarding overlay.
    @Published var isPresentingOnboarding = false

    var shouldPresentOnboarding: Bool {
        isOnboardingEnabled && !hasCompletedOnboarding
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Keys.isOnboardingEnabled) == nil {
            defaults.set(true, forKey: Keys.isOnboardingEnabled)
        }

        self.isOnboardingEnabled = defaults.bool(forKey: Keys.isOnboardingEnabled)
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
    }

    /// Call once at launch to surface onboarding for first-time (or reset) users.
    func evaluateLaunchPresentation() {
        guard shouldPresentOnboarding else { return }
        isPresentingOnboarding = true
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        isPresentingOnboarding = false
    }

    /// Testing helper: clear completion and show the sequence immediately.
    func replayOnboarding() {
        guard isOnboardingEnabled else { return }
        hasCompletedOnboarding = false
        isPresentingOnboarding = true
    }
}
