//
//  KeyboardEventHandlingView.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI

struct KeyboardEventHandlingView: NSViewRepresentable {
    var onDeletePressed: (_ bypassConfirmation: Bool) -> Void
    var onEscapePressed: () -> Void
    var onSpacebarPressed: () -> Void
    var onArrowPressed: (ArrowDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
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
            guard let window, !(window.firstResponder is NSTextView) else { return }
            window.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
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
