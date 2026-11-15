//
//  ContactSheetCuration.swift
//  Microfiche
//
//  Pure order transitions for contact sheet curation.
//

import CoreGraphics
import Foundation

enum ContactSheetCuration {
  /// Inserts `movedID` immediately before `referenceID`, preserving all other IDs.
  static func orderedImageIDs(
    _ imageIDs: [UUID],
    moving movedID: UUID,
    before referenceID: UUID
  ) -> [UUID]? {
    guard movedID != referenceID else { return nil }
    guard let fromIndex = imageIDs.firstIndex(of: movedID),
          let referenceIndex = imageIDs.firstIndex(of: referenceID) else {
      return nil
    }

    var next = imageIDs
    next.remove(at: fromIndex)
    let adjustedReference = referenceIndex > fromIndex
      ? referenceIndex - 1
      : referenceIndex
    next.insert(movedID, at: adjustedReference)
    return next
  }

  static func orderedImageIDs(
    _ imageIDs: [UUID],
    moving movedID: UUID,
    toIndex destination: Int
  ) -> [UUID]? {
    guard let fromIndex = imageIDs.firstIndex(of: movedID) else { return nil }

    var next = imageIDs
    next.remove(at: fromIndex)
    let clamped = min(max(0, destination), next.count)
    let insertIndex = fromIndex < clamped ? clamped - 1 : clamped
    next.insert(movedID, at: insertIndex)
    return next
  }
}

enum ContactSheetLayoutMetrics {
  static let gridAspectRatio: CGFloat = 1
  static let gridSpacing: CGFloat = 10
  static let horizontalInset: CGFloat = 20
  static let preferredThumbnailSize: CGFloat = 148
}