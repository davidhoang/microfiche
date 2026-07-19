//
//  LiquidGlassDesign.swift
//  Microfiche
//
//  Liquid Glass design helpers with fallbacks for macOS 15+.
//

import SwiftUI

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

    /// A quiet content selection that remains distinct without framing the image heavily.
    @ViewBuilder
    func contentSelectionChrome(isSelected: Bool, cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if isSelected {
            self
                .padding(4)
                .background(Color.accentColor.opacity(0.12), in: shape)
                .overlay {
                    shape
                        .inset(by: 0.75)
                        .stroke(Color.accentColor.opacity(0.62), lineWidth: 1.5)
                }
                .shadow(color: Color.accentColor.opacity(0.12), radius: 6, y: 2)
        } else {
            self.padding(4)
        }
    }
}

// MARK: - Hover Dynamics

private extension Animation {
    static let microficheHover = Animation.easeOut(duration: 0.18)
}

extension View {
    /// Subtle lift and highlight when hovering grid content cells.
    @ViewBuilder
    func contentHoverDynamics(isHovered: Bool, isSelected: Bool, cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let scale: CGFloat = isHovered ? (isSelected ? 1.01 : 1.02) : 1.0

        self
            .scaleEffect(scale, anchor: .center)
            .background {
                if isHovered && !isSelected {
                    shape.fill(Color.primary.opacity(0.05))
                }
            }
            .overlay {
                if isHovered {
                    shape.stroke(
                        isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.1),
                        lineWidth: 1
                    )
                }
            }
            .shadow(
                color: Color.black.opacity(isHovered ? 0.08 : 0),
                radius: isHovered ? 8 : 0,
                y: isHovered ? 3 : 0
            )
            .animation(.microficheHover, value: isHovered)
    }

    /// Subtle background tint for sidebar/list rows on hover.
    @ViewBuilder
    func sidebarHoverBackground(isHovered: Bool, isSelected: Bool, cornerRadius: CGFloat = 6) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        self
            .background {
                if isHovered && !isSelected {
                    shape.fill(Color.primary.opacity(0.06))
                } else if isHovered && isSelected {
                    shape.fill(Color.accentColor.opacity(0.24))
                }
            }
            .animation(.microficheHover, value: isHovered)
    }
}

// MARK: - Floating Panel

struct LiquidGlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(cornerRadius: CGFloat = 16, @ViewBuilder content: () -> Content) {
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
                .overlay(shape.stroke(Color(NSColor.separatorColor), lineWidth: 2))
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
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: -2, y: 0)
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
        }
    }
}
