//
//  NSImage+PNG.swift
//  Microfiche
//

import AppKit

extension NSImage {
    var pngData: Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }
}
