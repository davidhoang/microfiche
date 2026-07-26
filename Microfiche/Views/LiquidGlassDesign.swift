//
//  LiquidGlassDesign.swift
//  Microfiche
//
//  Liquid Glass design helpers with fallbacks for macOS 15+.
//  Interaction motion favors short, snappy feedback over soft lift.
//

import SwiftUI

// MARK: - Motion

enum MicroficheMotion {
    /// Instant feedback for selection and chrome changes.
    static let snap = Animation.easeOut(duration: 0.1)
    /// Slightly longer for view transitions that need a beat of continuity.
    static let transition = Animation.easeOut(duration: 0.14)

    static func snap(reducedMotion: Bool) -> Animation? {
        reducedMotion ? nil : snap
    }

    static func transition(reducedMotion: Bool) -> Animation? {
        reducedMotion ? nil : transition
    }
}

// MARK: - Glass-Aware Buttons

extension View {
    @ViewBuilder
    func microficheIconButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderless)
        }
    }
}

// MARK: - Selection Highlight

extension View {
    /// Sidebar/list selection — uses tint on glass sidebars to avoid glass-on-glass stacking.
    @ViewBuilder
    func sidebarSelectionBackground(isSelected: Bool, cornerRadius: CGFloat = 6) -> some View {
        if isSelected {
            self.background(
                Color.accentColor.opacity(0.18),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self
        }
    }

    /// Crisp content selection without glow or lift — planted, high-contrast framing.
    @ViewBuilder
    func contentSelectionChrome(isSelected: Bool, cornerRadius: CGFloat = 8) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if isSelected {
            self
                .padding(3)
                .background(Color.accentColor.opacity(0.1), in: shape)
                .overlay {
                    shape
                        .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 2)
                }
        } else {
            self.padding(3)
        }
    }
}

// MARK: - Hover Dynamics

extension View {
    /// Flat hover highlight for grid cells — tint only, no scale or shadow lift.
    @ViewBuilder
    func contentHoverDynamics(isHovered: Bool, isSelected: Bool, cornerRadius: CGFloat = 8) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        self
            .background {
                if isHovered && !isSelected {
                    shape.fill(Color.primary.opacity(0.045))
                }
            }
            .overlay {
                if isHovered && !isSelected {
                    shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .animation(MicroficheMotion.snap, value: isHovered)
    }

    /// Subtle background tint for sidebar/list rows on hover.
    @ViewBuilder
    func sidebarHoverBackground(isHovered: Bool, isSelected: Bool, cornerRadius: CGFloat = 6) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        self
            .background {
                if isHovered && !isSelected {
                    shape.fill(Color.primary.opacity(0.05))
                } else if isHovered && isSelected {
                    shape.fill(Color.accentColor.opacity(0.22))
                }
            }
            .animation(MicroficheMotion.snap, value: isHovered)
    }
}

// MARK: - Floating Panel

struct LiquidGlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .background {
                    shape
                        .fill(.clear)
                        .glassEffect(.regular, in: shape)
                }
        } else {
            content
                .background(Color(NSColor.controlBackgroundColor), in: shape)
                .overlay(shape.strokeBorder(Color(NSColor.separatorColor), lineWidth: 1))
        }
    }
}

// MARK: - Navigation Chrome

private struct SidebarMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Matches the system material used by a NavigationSplitView sidebar.
    func microficheSidebarChrome() -> some View {
        background {
            SidebarMaterialBackground()
                .ignoresSafeArea()
        }
    }

    /// Removes legacy toolbar backgrounds that interfere with the system scroll-edge glass effect.
    @ViewBuilder
    func microficheToolbarChrome() -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            self
                .toolbarBackground(Color(NSColor.textBackgroundColor), for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
        }
    }

    /// Detail column background — defers to system glass on Tahoe, keeps legacy card on older macOS.
    @ViewBuilder
    func microficheDetailChrome() -> some View {
        if #available(macOS 26.0, *) {
            self
                .background(Color(NSColor.windowBackgroundColor))
        } else {
            self
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.black.opacity(0.1), radius: 6, x: -1, y: 0)
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
        }
    }
}
