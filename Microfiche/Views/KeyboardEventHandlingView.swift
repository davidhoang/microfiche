//
//  KeyboardEventHandlingView.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI

enum LibraryKeyboardFocusPolicy {
    static func shouldHandleLibraryKeys(
        isVoiceOverRunning: Bool,
        isTextInputFirstResponder: Bool
    ) -> Bool {
        !isVoiceOverRunning && !isTextInputFirstResponder
    }
}

struct KeyboardEventHandlingView: NSViewRepresentable {
    var onDeletePressed: (_ bypassConfirmation: Bool) -> Void
    var onEscapePressed: () -> Void
    var onSpacebarPressed: () -> Void
    var onArrowPressed: (ArrowDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.setAccessibilityElement(false)
        view.onDeletePressed = onDeletePressed
        view.onEscapePressed = onEscapePressed
        view.onSpacebarPressed = onSpacebarPressed
        view.onArrowPressed = onArrowPressed
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? KeyView else { return }
        view.onDeletePressed = onDeletePressed
        view.onEscapePressed = onEscapePressed
        view.onSpacebarPressed = onSpacebarPressed
        view.onArrowPressed = onArrowPressed

        DispatchQueue.main.async {
            view.claimFirstResponderIfAppropriate()
        }
    }

    class KeyView: NSView {
        var onDeletePressed: ((Bool) -> Void)?
        var onEscapePressed: (() -> Void)?
        var onSpacebarPressed: (() -> Void)?
        var onArrowPressed: ((ArrowDirection) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        func claimFirstResponderIfAppropriate() {
            guard let window else { return }
            let isTextInput = window.firstResponder is NSTextView
                || window.firstResponder is NSTextField
            guard LibraryKeyboardFocusPolicy.shouldHandleLibraryKeys(
                isVoiceOverRunning: NSWorkspace.shared.isVoiceOverEnabled,
                isTextInputFirstResponder: isTextInput
            ) else { return }
            window.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard !NSWorkspace.shared.isVoiceOverEnabled else {
                super.keyDown(with: event)
                return
            }
            switch event.keyCode {
            case 51, 117: // 51: Delete, 117: Forward Delete
                let bypass = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
                onDeletePressed?(bypass)
            case 53: // Escape
                onEscapePressed?()
            case 49: // Spacebar
                if !event.isARepeat {
                    onSpacebarPressed?()
                }
            case 123: // Left arrow
                onArrowPressed?(.left)
            case 124: // Right arrow
                onArrowPressed?(.right)
            case 125: // Down arrow
                onArrowPressed?(.down)
            case 126: // Up arrow
                onArrowPressed?(.up)
            default:
                super.keyDown(with: event)
            }
        }
    }
}
