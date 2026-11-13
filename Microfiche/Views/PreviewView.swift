//
//  PreviewView.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI

struct PreviewView: View {
    let file: ImageFile
    let onDismiss: () -> Void
    let onNavigate: (ArrowDirection) -> Void
    @FocusState private var isCloseButtonFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .accessibilityHidden(true)

                ZStack {
                    Group {
                        if file.url.pathExtension.lowercased() == "pdf" {
                            PDFKitView(url: file.url)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if file.url.pathExtension.lowercased() == "svg" {
                            SVGImageView(url: file.url)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .aspectRatio(contentMode: .fit)
                        } else {
                            RecoverablePreviewImage(url: file.url)
                        }
                    }
                    .padding(32)
                }
                .background(
                    Color(NSColor.textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(alignment: .topLeading) {
                    Button(action: onDismiss) {
                        Label("Close Preview", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .microficheIconButton()
                    .focused($isCloseButtonFocused)
                    .help("Close Preview")
                    .accessibilityIdentifier("preview.close")
                    .padding(8)
                }
                .frame(width: geometry.size.width * 0.75, height: geometry.size.height * 0.75)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Quick preview of \(file.name)")
        .accessibilityHint("Press Escape to close")
        .accessibilityIdentifier("preview.quick")
        .accessibilityAction(named: "Close Preview") {
            onDismiss()
        }
        .onAppear { isCloseButtonFocused = true }
        .onExitCommand(perform: onDismiss)
        .onKeyPress(.space, phases: .down) { _ in
            onDismiss()
            return .handled
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: onNavigate(.left)
            case .right: onNavigate(.right)
            case .up: onNavigate(.up)
            case .down: onNavigate(.down)
            @unknown default: break
            }
        }
    }
}
