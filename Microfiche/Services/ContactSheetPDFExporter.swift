//
//  ContactSheetPDFExporter.swift
//  Microfiche
//
//  Deterministic pagination and native PDF rendering for contact sheets.
//

import AppKit
import Foundation
import PDFKit

enum ContactSheetPaperSize: String, CaseIterable, Identifiable, Sendable {
    case letter = "Letter"
    case a4 = "A4"

    var id: String { rawValue }

    var portraitSize: CGSize {
        switch self {
        case .letter:
            CGSize(width: 612, height: 792)
        case .a4:
            CGSize(width: 595.28, height: 841.89)
        }
    }
}

enum ContactSheetPageOrientation: String, CaseIterable, Identifiable, Sendable {
    case portrait = "Portrait"
    case landscape = "Landscape"

    var id: String { rawValue }
}

struct ContactSheetCaptionOptions: Equatable, Hashable, Sendable {
    var includesFilename = true
    var includesFinderLabel = false
    var includesTags = false
    var includesComments = false
    var includesSource = false

    var maximumLineCount: Int {
        [
            includesFilename,
            includesFinderLabel,
            includesTags,
            includesComments,
            includesSource
        ].filter { $0 }.count
    }
}

struct ContactSheetExportOptions: Equatable, Hashable, Sendable {
    var paperSize: ContactSheetPaperSize = .letter
    var orientation: ContactSheetPageOrientation = .portrait
    var margin: CGFloat = 36
    var columns: Int = 4
    var captions = ContactSheetCaptionOptions()

    var pageSize: CGSize {
        let portrait = paperSize.portraitSize
        switch orientation {
        case .portrait:
            return portrait
        case .landscape:
            return CGSize(width: portrait.height, height: portrait.width)
        }
    }

    var normalized: ContactSheetExportOptions {
        var copy = self
        copy.margin = min(max(copy.margin, 24), 72)
        copy.columns = min(max(copy.columns, 2), 6)
        return copy
    }
}

struct ContactSheetExportItem: Equatable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let imageURL: URL
    let finderLabel: String?
    let tags: [String]
    let comments: String
    let source: String

    func captionLines(using options: ContactSheetCaptionOptions) -> [String] {
        var lines: [String] = []
        if options.includesFilename {
            lines.append(fileName)
        }
        if options.includesFinderLabel, let finderLabel, !finderLabel.isEmpty {
            lines.append("Label: \(finderLabel)")
        }
        if options.includesTags, !tags.isEmpty {
            lines.append("Tags: \(tags.joined(separator: ", "))")
        }
        if options.includesComments {
            let normalized = Self.singleLine(comments)
            if !normalized.isEmpty {
                lines.append("Comments: \(normalized)")
            }
        }
        if options.includesSource {
            let normalized = Self.singleLine(source)
            if !normalized.isEmpty {
                lines.append("Source: \(normalized)")
            }
        }
        return lines
    }

    private static func singleLine(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct ContactSheetPDFLayout: Equatable, Sendable {
    static let itemSpacing: CGFloat = 12
    static let headerHeight: CGFloat = 42
    static let footerHeight: CGFloat = 18
    static let captionLineHeight: CGFloat = 12

    let pageSize: CGSize
    let contentRect: CGRect
    let columns: Int
    let rowsPerPage: Int
    let itemsPerPage: Int
    let pageCount: Int
    let cellSize: CGSize
    let imageHeight: CGFloat
    let captionHeight: CGFloat

    init(itemCount: Int, options rawOptions: ContactSheetExportOptions) {
        let options = rawOptions.normalized
        pageSize = options.pageSize
        columns = options.columns

        let contentWidth = max(1, pageSize.width - (options.margin * 2))
        let contentHeight = max(
            1,
            pageSize.height
                - (options.margin * 2)
                - Self.headerHeight
                - Self.footerHeight
        )
        contentRect = CGRect(
            x: options.margin,
            y: options.margin + Self.footerHeight,
            width: contentWidth,
            height: contentHeight
        )

        let horizontalSpacing = CGFloat(max(0, columns - 1)) * Self.itemSpacing
        let cellWidth = max(1, (contentWidth - horizontalSpacing) / CGFloat(columns))
        captionHeight = options.captions.maximumLineCount == 0
            ? 0
            : CGFloat(options.captions.maximumLineCount) * Self.captionLineHeight + 8

        let desiredImageHeight = cellWidth * 0.68
        let desiredCellHeight = max(48, desiredImageHeight + captionHeight)
        let rowEstimate = Int(
            floor((contentHeight + Self.itemSpacing) / (desiredCellHeight + Self.itemSpacing))
        )
        rowsPerPage = max(1, rowEstimate)
        itemsPerPage = max(1, columns * rowsPerPage)
        pageCount = max(1, Int(ceil(Double(itemCount) / Double(itemsPerPage))))

        let verticalSpacing = CGFloat(max(0, rowsPerPage - 1)) * Self.itemSpacing
        let cellHeight = max(1, (contentHeight - verticalSpacing) / CGFloat(rowsPerPage))
        cellSize = CGSize(width: cellWidth, height: cellHeight)
        imageHeight = max(24, cellHeight - captionHeight)
    }

    func itemRect(at indexOnPage: Int) -> CGRect {
        let column = indexOnPage % columns
        let row = indexOnPage / columns
        let x = contentRect.minX + CGFloat(column) * (cellSize.width + Self.itemSpacing)
        let y = contentRect.maxY
            - CGFloat(row + 1) * cellSize.height
            - CGFloat(row) * Self.itemSpacing
        return CGRect(x: x, y: y, width: cellSize.width, height: cellSize.height)
    }
}

struct ContactSheetPDFExport: Equatable, Sendable {
    let data: Data
    let layout: ContactSheetPDFLayout
    let unavailableImageNames: [String]
}

enum ContactSheetPDFExportError: LocalizedError, Equatable, Sendable {
    case unableToCreateConsumer
    case unableToCreateContext

    var errorDescription: String? {
        switch self {
        case .unableToCreateConsumer:
            "The PDF data stream could not be created."
        case .unableToCreateContext:
            "The PDF drawing context could not be created."
        }
    }
}

struct ContactSheetExportPreviewState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case loading
        case ready(ContactSheetPDFExport)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var activeRequestID: UUID?

    @discardableResult
    mutating func beginLoading() -> UUID {
        let requestID = UUID()
        activeRequestID = requestID
        phase = .loading
        return requestID
    }

    @discardableResult
    mutating func finish(
        _ result: Result<ContactSheetPDFExport, ContactSheetPDFExportError>,
        requestID: UUID
    ) -> Bool {
        guard activeRequestID == requestID else { return false }
        activeRequestID = nil
        switch result {
        case .success(let export):
            phase = .ready(export)
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        }
        return true
    }

    @discardableResult
    mutating func cancel(requestID: UUID) -> Bool {
        guard activeRequestID == requestID else { return false }
        activeRequestID = nil
        phase = .idle
        return true
    }
}

enum ContactSheetPDFExporter {
    private static let darkText = NSColor(calibratedWhite: 0.13, alpha: 1)
    private static let secondaryText = NSColor(calibratedWhite: 0.42, alpha: 1)
    private static let tileBackground = NSColor(calibratedWhite: 0.96, alpha: 1)
    private static let tileBorder = NSColor(calibratedWhite: 0.86, alpha: 1)

    static func render(
        title: String,
        items: [ContactSheetExportItem],
        options rawOptions: ContactSheetExportOptions
    ) throws -> ContactSheetPDFExport {
        let options = rawOptions.normalized
        let layout = ContactSheetPDFLayout(itemCount: items.count, options: options)
        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else {
            throw ContactSheetPDFExportError.unableToCreateConsumer
        }

        var mediaBox = CGRect(origin: .zero, size: layout.pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ContactSheetPDFExportError.unableToCreateContext
        }

        var unavailableNames: [String] = []
        for pageIndex in 0..<layout.pageCount {
            context.beginPDFPage(nil)
            drawPageBackground(in: context, pageSize: layout.pageSize)
            drawHeader(
                title: title,
                itemCount: items.count,
                pageIndex: pageIndex,
                pageCount: layout.pageCount,
                options: options,
                in: context,
                pageSize: layout.pageSize
            )

            let startIndex = pageIndex * layout.itemsPerPage
            let endIndex = min(items.count, startIndex + layout.itemsPerPage)
            if startIndex < endIndex {
                for itemIndex in startIndex..<endIndex {
                    let item = items[itemIndex]
                    let indexOnPage = itemIndex - startIndex
                    let isAvailable = draw(
                        item: item,
                        in: layout.itemRect(at: indexOnPage),
                        layout: layout,
                        options: options,
                        context: context
                    )
                    if !isAvailable, !unavailableNames.contains(item.fileName) {
                        unavailableNames.append(item.fileName)
                    }
                }
            } else {
                drawEmptyState(in: context, rect: layout.contentRect)
            }

            drawFooter(
                pageIndex: pageIndex,
                pageCount: layout.pageCount,
                margin: options.margin,
                in: context,
                pageSize: layout.pageSize
            )
            context.endPDFPage()
        }
        context.closePDF()

        return ContactSheetPDFExport(
            data: mutableData as Data,
            layout: layout,
            unavailableImageNames: unavailableNames
        )
    }

    static func suggestedFilename(for title: String) -> String {
        let disallowed = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-_"))
            .inverted
        let components = title
            .components(separatedBy: disallowed)
            .joined(separator: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = components
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "-")
        let base = collapsed.isEmpty ? "Contact-Sheet" : collapsed
        return "\(base).pdf"
    }

    private static func drawPageBackground(in context: CGContext, pageSize: CGSize) {
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: pageSize))
        context.restoreGState()
    }

    private static func drawHeader(
        title: String,
        itemCount: Int,
        pageIndex: Int,
        pageCount: Int,
        options: ContactSheetExportOptions,
        in context: CGContext,
        pageSize: CGSize
    ) {
        let titleRect = CGRect(
            x: options.margin,
            y: pageSize.height - options.margin - 21,
            width: pageSize.width - options.margin * 2,
            height: 21
        )
        drawText(
            title,
            in: titleRect,
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: darkText,
            context: context
        )

        let noun = itemCount == 1 ? "image" : "images"
        let subtitle = "\(itemCount) \(noun)  •  Page \(pageIndex + 1) of \(pageCount)"
        let subtitleRect = CGRect(
            x: options.margin,
            y: titleRect.minY - 15,
            width: titleRect.width,
            height: 14
        )
        drawText(
            subtitle,
            in: subtitleRect,
            font: .systemFont(ofSize: 9),
            color: secondaryText,
            context: context
        )
    }

    private static func drawFooter(
        pageIndex: Int,
        pageCount: Int,
        margin: CGFloat,
        in context: CGContext,
        pageSize: CGSize
    ) {
        let footerRect = CGRect(
            x: margin,
            y: max(4, margin - 14),
            width: pageSize.width - margin * 2,
            height: 12
        )
        drawText(
            "Microfiche  •  \(pageIndex + 1) / \(pageCount)",
            in: footerRect,
            font: .systemFont(ofSize: 8),
            color: secondaryText,
            alignment: .right,
            context: context
        )
    }

    private static func draw(
        item: ContactSheetExportItem,
        in cellRect: CGRect,
        layout: ContactSheetPDFLayout,
        options: ContactSheetExportOptions,
        context: CGContext
    ) -> Bool {
        let imageRect = CGRect(
            x: cellRect.minX,
            y: cellRect.maxY - layout.imageHeight,
            width: cellRect.width,
            height: layout.imageHeight
        )
        drawTile(in: context, rect: imageRect)

        let image = loadPreviewImage(from: item.imageURL, maxPixelSize: max(imageRect.width, imageRect.height) * 2)
        let isAvailable: Bool
        if let image,
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let destination = aspectFit(
                sourceSize: CGSize(width: cgImage.width, height: cgImage.height),
                in: imageRect.insetBy(dx: 3, dy: 3)
            )
            context.saveGState()
            context.interpolationQuality = .high
            context.draw(cgImage, in: destination)
            context.restoreGState()
            isAvailable = true
        } else {
            drawUnavailableImage(fileName: item.fileName, in: imageRect, context: context)
            isAvailable = false
        }

        if layout.captionHeight > 0 {
            let captionRect = CGRect(
                x: cellRect.minX,
                y: cellRect.minY,
                width: cellRect.width,
                height: max(0, layout.captionHeight - 4)
            )
            drawCaption(
                item.captionLines(using: options.captions),
                in: captionRect,
                context: context
            )
        }
        return isAvailable
    }

    private static func drawTile(in context: CGContext, rect: CGRect) {
        let path = CGPath(
            roundedRect: rect,
            cornerWidth: 5,
            cornerHeight: 5,
            transform: nil
        )
        context.saveGState()
        context.addPath(path)
        context.setFillColor(tileBackground.cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(tileBorder.cgColor)
        context.setLineWidth(0.5)
        context.strokePath()
        context.restoreGState()
    }

    private static func drawCaption(
        _ lines: [String],
        in rect: CGRect,
        context: CGContext
    ) {
        guard !lines.isEmpty else { return }
        var currentY = rect.maxY - ContactSheetPDFLayout.captionLineHeight
        for (index, line) in lines.enumerated() where currentY >= rect.minY {
            drawText(
                line,
                in: CGRect(
                    x: rect.minX,
                    y: currentY,
                    width: rect.width,
                    height: ContactSheetPDFLayout.captionLineHeight
                ),
                font: .systemFont(ofSize: index == 0 ? 8.5 : 7.5, weight: index == 0 ? .medium : .regular),
                color: index == 0 ? darkText : secondaryText,
                context: context
            )
            currentY -= ContactSheetPDFLayout.captionLineHeight
        }
    }

    private static func drawUnavailableImage(
        fileName: String,
        in rect: CGRect,
        context: CGContext
    ) {
        let messageRect = rect.insetBy(dx: 8, dy: 8)
        drawText(
            "Image unavailable\n\(fileName)",
            in: messageRect,
            font: .systemFont(ofSize: 8, weight: .medium),
            color: secondaryText,
            alignment: .center,
            lineBreakMode: .byWordWrapping,
            context: context
        )
    }

    private static func drawEmptyState(in context: CGContext, rect: CGRect) {
        drawText(
            "No images in this contact sheet",
            in: rect.insetBy(dx: 20, dy: 20),
            font: .systemFont(ofSize: 13, weight: .medium),
            color: secondaryText,
            alignment: .center,
            context: context
        )
    }

    private static func drawText(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left,
        lineBreakMode: NSLineBreakMode = .byTruncatingTail,
        context: CGContext
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributed.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine]
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func loadPreviewImage(from url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if url.pathExtension.lowercased() == "pdf",
           let document = PDFDocument(url: url),
           let page = document.page(at: 0) {
            return page.thumbnail(
                of: CGSize(width: maxPixelSize, height: maxPixelSize),
                for: .cropBox
            )
        }
        return ImageThumbnailGenerator.thumbnail(from: url, maxPixelSize: maxPixelSize)
            ?? NSImage(contentsOf: url)
    }

    private static func aspectFit(sourceSize: CGSize, in destination: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return destination }
        let scale = min(
            destination.width / sourceSize.width,
            destination.height / sourceSize.height
        )
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: destination.midX - size.width / 2,
            y: destination.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
