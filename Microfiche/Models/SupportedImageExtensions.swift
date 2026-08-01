//
//  SupportedImageExtensions.swift
//  Microfiche
//

import Foundation

enum SupportedImageExtensions {
    static let all: Set<String> = [
        "jpg", "jpeg", "png", "pdf", "svg", "gif", "tiff"
    ]

    static func contains(_ url: URL) -> Bool {
        all.contains(url.pathExtension.lowercased())
    }
}
