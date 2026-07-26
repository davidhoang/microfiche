//
//  SettingsView.swift
//  Microfiche
//
//  App Settings (⌘,) — includes onboarding controls for testing.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var preferences = UserPreferences.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show welcome onboarding", isOn: $preferences.isOnboardingEnabled)
                    .help("When enabled, Microfiche presents the welcome sequence until it is completed or skipped.")

                HStack {
                    Button("Replay Onboarding") {
                        preferences.replayOnboarding()
                    }
                    .disabled(!preferences.isOnboardingEnabled)

                    Spacer(minLength: 0)

                    Text(statusLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Onboarding")
            } footer: {
                Text("Turn this off to skip the welcome sequence while testing. Use Replay to walk through it again.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }

    private var statusLabel: String {
        if !preferences.isOnboardingEnabled {
            return "Disabled"
        }
        if preferences.isPresentingOnboarding {
            return "Showing now"
        }
        return preferences.hasCompletedOnboarding ? "Completed" : "Pending"
    }
}

#Preview {
    SettingsView()
}
