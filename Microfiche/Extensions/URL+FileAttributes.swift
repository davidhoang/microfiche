//
//  URL+FileAttributes.swift
//  Microfiche
//
//  Created by David Hoang on 2/7/26.
//

import Foundation

extension URL {
    private static let metadataDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    func formattedFileSize() -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    func formattedCreationDate() -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attributes[.creationDate] as? Date else { return nil }
        return Self.metadataDateFormatter.string(from: date)
    }

    func formattedModificationDate() -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attributes[.modificationDate] as? Date else { return nil }
        return Self.metadataDateFormatter.string(from: date)
    }
}
