//
//  MediaViews.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI
import PDFKit

struct PDFKitView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: self.url)
        pdfView.autoScales = true
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: self.url)
    }
}

struct SVGImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = NSImage(contentsOf: url)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = NSImage(contentsOf: url)
    }
}
