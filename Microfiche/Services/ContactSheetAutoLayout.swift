//
//  ContactSheetAutoLayout.swift
//  Microfiche
//
//  Justified-row layout for contact sheet canvases.
//

import CoreGraphics
import Foundation
import ImageIO

struct ContactSheetLayoutItem: Equatable, Sendable, Identifiable {
    let id: UUID
    let aspectRatio: CGFloat

    init(id: UUID, aspectRatio: CGFloat) {
        let clamped = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1
        self.id = id
        self.aspectRatio = clamped
    }
}

struct ContactSheetLayoutPlacement: Equatable, Sendable, Identifiable {
    let id: UUID
    let width: CGFloat
    let height: CGFloat
}

struct ContactSheetLayoutRow: Equatable, Sendable {
    let placements: [ContactSheetLayoutPlacement]
    let height: CGFloat
}

struct ContactSheetLayoutPlan: Equatable, Sendable {
    let rows: [ContactSheetLayoutRow]
    let contentHeight: CGFloat
    let contentWidth: CGFloat
}

enum ContactSheetAutoLayout {
    struct Configuration: Equatable, Sendable {
        var targetRowHeight: CGFloat = ContactSheetLayoutMetrics.preferredThumbnailSize
        var minRowHeight: CGFloat = 92
        var maxRowHeight: CGFloat = 300
        var spacing: CGFloat = ContactSheetLayoutMetrics.gridSpacing
        var horizontalInset: CGFloat = ContactSheetLayoutMetrics.horizontalInset
        var maxItemsPerRow: Int = 9
    }

    static func plan(
        items: [ContactSheetLayoutItem],
        availableWidth: CGFloat,
        configuration: Configuration = Configuration()
    ) -> ContactSheetLayoutPlan {
        let contentWidth = max(0, availableWidth - configuration.horizontalInset * 2)
        guard !items.isEmpty, contentWidth > 0 else {
            return ContactSheetLayoutPlan(rows: [], contentHeight: 0, contentWidth: contentWidth)
        }

        var rows: [ContactSheetLayoutRow] = []
        var index = 0
        var y: CGFloat = 0

        while index < items.count {
            var rowItems: [ContactSheetLayoutItem] = [items[index]]
            index += 1

            while index < items.count, rowItems.count < configuration.maxItemsPerRow {
                let trial = rowItems + [items[index]]
                let trialHeight = justifiedRowHeight(
                    items: trial,
                    contentWidth: contentWidth,
                    spacing: configuration.spacing
                )
                if trialHeight < configuration.minRowHeight {
                    break
                }
                rowItems = trial
                index += 1
            }

            let placements = justifiedPlacements(
                items: rowItems,
                contentWidth: contentWidth,
                configuration: configuration
            )
            let rowHeight = placements.map(\.height).max() ?? configuration.targetRowHeight
            rows.append(ContactSheetLayoutRow(placements: placements, height: rowHeight))
            y += rowHeight + configuration.spacing
        }

        if rows.isEmpty {
            return ContactSheetLayoutPlan(rows: [], contentHeight: 0, contentWidth: contentWidth)
        }

        let totalHeight = y - configuration.spacing
        return ContactSheetLayoutPlan(
            rows: rows,
            contentHeight: max(0, totalHeight),
            contentWidth: contentWidth
        )
    }

    static func justifiedRowHeight(
        items: [ContactSheetLayoutItem],
        contentWidth: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        let sumAspect = items.reduce(CGFloat.zero) { $0 + $1.aspectRatio }
        guard sumAspect > 0 else { return 0 }
        let gaps = CGFloat(max(0, items.count - 1)) * spacing
        return (contentWidth - gaps) / sumAspect
    }

    private static func justifiedPlacements(
        items: [ContactSheetLayoutItem],
        contentWidth: CGFloat,
        configuration: Configuration
    ) -> [ContactSheetLayoutPlacement] {
        guard !items.isEmpty else { return [] }

        let rawHeight = justifiedRowHeight(
            items: items,
            contentWidth: contentWidth,
            spacing: configuration.spacing
        )

        let rowHeight: CGFloat
        if items.count == 1 {
            rowHeight = min(max(rawHeight, configuration.minRowHeight), configuration.maxRowHeight)
        } else {
            rowHeight = min(
                max(rawHeight, configuration.minRowHeight),
                configuration.maxRowHeight
            )
        }

        return items.map { item in
            ContactSheetLayoutPlacement(
                id: item.id,
                width: rowHeight * item.aspectRatio,
                height: rowHeight
            )
        }
    }
}

enum ContactSheetImageDimensions {
    static func aspectRatio(for url: URL) -> CGFloat? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }

        let width = numericPixelValue(properties[kCGImagePropertyPixelWidth])
        let height = numericPixelValue(properties[kCGImagePropertyPixelHeight])
        guard let width, let height, height > 0, width > 0 else { return nil }
        return width / height
    }

    private static func numericPixelValue(_ value: Any?) -> CGFloat? {
        if let number = value as? CGFloat { return number }
        if let number = value as? Double { return CGFloat(number) }
        if let number = value as? Int { return CGFloat(number) }
        return nil
    }
}