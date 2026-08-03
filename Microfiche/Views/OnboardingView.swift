//
//  OnboardingView.swift
//  Microfiche
//
//  Multi-step welcome sequence that introduces Microfiche's value proposition.
//

import SwiftUI

struct OnboardingView: View {
    let onLinkFolder: () -> Void
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stepIndex = 0

    private var steps: [OnboardingStep] {
        OnboardingStep.all
    }

    private var isLastStep: Bool {
        stepIndex >= steps.count - 1
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            LiquidGlassPanel(cornerRadius: 18) {
                VStack(spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        Button("Skip") {
                            finish()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Skip Welcome Onboarding")
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                    OnboardingStepPage(step: steps[stepIndex], showsBrand: stepIndex == 0)
                        .id(steps[stepIndex].id)
                        .padding(.horizontal, 36)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .trailing)),
                                    removal: .opacity.combined(with: .move(edge: .leading))
                                )
                        )
                        .animation(MicroficheMotion.transition(reducedMotion: reduceMotion), value: stepIndex)

                    VStack(spacing: 18) {
                        HStack(spacing: 7) {
                            ForEach(steps.indices, id: \.self) { index in
                                Circle()
                                    .fill(index == stepIndex ? Color.accentColor : Color.secondary.opacity(0.35))
                                    .frame(width: index == stepIndex ? 8 : 6, height: index == stepIndex ? 8 : 6)
                                    .animation(MicroficheMotion.snap(reducedMotion: reduceMotion), value: stepIndex)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Step \(stepIndex + 1) of \(steps.count)")

                        HStack(spacing: 12) {
                            if stepIndex > 0 {
                                Button("Back") {
                                    withAnimation(MicroficheMotion.transition(reducedMotion: reduceMotion)) {
                                        stepIndex -= 1
                                    }
                                }
                            }

                            Spacer(minLength: 0)

                            if isLastStep {
                                Button("Link a Folder") {
                                    finish()
                                    onLinkFolder()
                                }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut(.defaultAction)

                                Button("Browse Library") {
                                    finish()
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("Continue") {
                                    withAnimation(MicroficheMotion.transition(reducedMotion: reduceMotion)) {
                                        stepIndex += 1
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .keyboardShortcut(.defaultAction)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                    .padding(.top, 8)
                }
            }
            .frame(width: 520, height: 420)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func finish() {
        onFinished()
    }
}

// MARK: - Step Model

struct OnboardingStep: Identifiable, Equatable {
    let id: String
    let symbolName: String
    let title: String
    let message: String

    static let all: [OnboardingStep] = [
        OnboardingStep(
            id: "welcome",
            symbolName: "photo.on.rectangle.angled",
            title: "Your library, left in place",
            message: "Microfiche browses photos where they already live. No import, no copies — just a fast view of your folders and drives."
        ),
        OnboardingStep(
            id: "folders",
            symbolName: "folder.badge.plus",
            title: "Link folders and drives",
            message: "Add folders from your Mac, iCloud Drive, or external volumes. Microfiche remembers them and reconnects when a drive comes back online."
        ),
        OnboardingStep(
            id: "contact-sheets",
            symbolName: "rectangle.stack",
            title: "Keep selects on Contact Sheets",
            message: "Gather images into Contact Sheets from any linked folder. Sheets stay in your library even when a drive is offline."
        ),
        OnboardingStep(
            id: "metadata",
            symbolName: "tag",
            title: "Labels, tags, and comments",
            message: "Edit Finder labels, tags, and comments in the inspector. Changes write to the file so Finder and other apps can see them."
        )
    ]
}

// MARK: - Step Page

private struct OnboardingStepPage: View {
    let step: OnboardingStep
    let showsBrand: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: step.symbolName)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                if showsBrand {
                    Text("Microfiche")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.1)
                }

                Text(step.title)
                    .font(.system(size: 24, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(step.message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingView(onLinkFolder: {}, onFinished: {})
}
