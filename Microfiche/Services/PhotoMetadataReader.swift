//
//  PhotoMetadataReader.swift
//  Microfiche
//

import Foundation
import ImageIO

enum PhotoMetadataReaderError: LocalizedError, Equatable, Sendable {
    case fileUnavailable

    var errorDescription: String? {
        switch self {
        case .fileUnavailable:
            "The image file is no longer available."
        }
    }
}

struct PhotoTechnicalMetadata: Equatable, Sendable {
    let dimensions: String?
    let captured: String?
    let camera: String?
    let lens: String?
    let iso: String?
    let aperture: String?
    let shutterSpeed: String?

    var rows: [(String, String)] {
        [
            ("Dimensions", dimensions),
            ("Captured", captured),
            ("Camera", camera),
            ("Lens", lens),
            ("ISO", iso),
            ("Aperture", aperture),
            ("Shutter", shutterSpeed)
        ].compactMap { label, value in
            value.map { (label, $0) }
        }
    }
}

enum PhotoTechnicalMetadataReadOutcome: Equatable, Sendable {
    case success(PhotoTechnicalMetadata?)
    case failure(String)
}

struct PhotoTechnicalMetadataLoadState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case loading
        case available(PhotoTechnicalMetadata)
        case unavailable
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
        _ outcome: PhotoTechnicalMetadataReadOutcome,
        requestID: UUID
    ) -> Bool {
        guard activeRequestID == requestID else { return false }
        activeRequestID = nil

        switch outcome {
        case .success(let metadata):
            if let metadata, !metadata.rows.isEmpty {
                phase = .available(metadata)
            } else {
                phase = .unavailable
            }
        case .failure(let message):
            phase = .failed(message)
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

enum PhotoMetadataReader {
    static func read(from url: URL) throws -> PhotoTechnicalMetadata? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PhotoMetadataReaderError.fileUnavailable
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        let width = number(properties[kCGImagePropertyPixelWidth])?.intValue
        let height = number(properties[kCGImagePropertyPixelHeight])?.intValue
        let dimensions = width.flatMap { width in
            height.map { "\(width) × \($0)" }
        }

        let make = string(tiff[kCGImagePropertyTIFFMake])
        let model = string(tiff[kCGImagePropertyTIFFModel])
        let camera = [make, model]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty

        let isoValue: NSNumber? = {
            if let ratings = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber] {
                return ratings.first
            }
            return nil
        }()

        let aperture = number(exif[kCGImagePropertyExifFNumber])
            .map { String(format: "ƒ/%.1f", $0.doubleValue) }
        let shutterSpeed = number(exif[kCGImagePropertyExifExposureTime])
            .map(formatExposureTime)

        return PhotoTechnicalMetadata(
            dimensions: dimensions,
            captured: string(exif[kCGImagePropertyExifDateTimeOriginal]),
            camera: camera,
            lens: string(exif[kCGImagePropertyExifLensModel]),
            iso: isoValue.map { $0.stringValue },
            aperture: aperture,
            shutterSpeed: shutterSpeed
        )
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value.nilIfEmpty }
        return nil
    }

    private static func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }

    private static func formatExposureTime(_ value: NSNumber) -> String {
        let seconds = value.doubleValue
        guard seconds > 0 else { return value.stringValue }
        if seconds >= 1 { return String(format: "%.1f s", seconds) }
        return "1/\(Int((1 / seconds).rounded())) s"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
