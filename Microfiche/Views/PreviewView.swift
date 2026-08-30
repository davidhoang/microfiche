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

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                LiquidGlassPanel(cornerRadius: 16) {
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
    }
}
