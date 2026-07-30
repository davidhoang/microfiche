//
//  SettingsView.swift
//  Microfiche
//
//  App Settings (⌘,) — includes onboarding controls for testing.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var preferences = UserPreferences.shared
    @ObservedObject private var archiveFolder = ArchiveFolderStore.shared

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

                    Text(onboardingStatusLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Onboarding")
            } footer: {
                Text("Turn this off to skip the welcome sequence while testing. Use Replay to walk through it again.")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(archiveFolder.displayName ?? "No archive folder")
                            .font(.system(size: 13, weight: .medium))
                        Text(archiveStatusLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button(archiveFolder.hasConfiguredFolder ? "Change…" : "Choose…") {
                        _ = archiveFolder.chooseFolder()
                    }

                    if archiveFolder.hasConfiguredFolder {
                        Button("Clear", role: .destructive) {
                            archiveFolder.clearFolder()
                        }
                    }
                }
            } header: {
                Text("Archive")
            } footer: {
                Text("Move to Archive relocates selected images into this folder without copying them into the library.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .onAppear {
            archiveFolder.refresh()
        }
    }

    private var onboardingStatusLabel: String {
        if !preferences.isOnboardingEnabled {
            return "Disabled"
        }
        if preferences.isPresentingOnboarding {
            return "Showing now"
        }
        return preferences.hasCompletedOnboarding ? "Completed" : "Pending"
    }

    private var archiveStatusLabel: String {
        if !archiveFolder.hasConfiguredFolder {
            return "Choose a folder to enable Move to Archive"
        }
        if archiveFolder.isAvailable {
            return "Ready"
        }
        return "Unavailable — reconnect or choose a new folder"
    }
}

#Preview {
    SettingsView()
}
