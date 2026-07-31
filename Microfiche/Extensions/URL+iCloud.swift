//
//  URL+iCloud.swift
//  Microfiche
//

import Foundation

enum ICloudItemState: Equatable {
    case local
    case current
    case downloading
    case notDownloaded

    var needsDownload: Bool {
        self == .downloading || self == .notDownloaded
    }
}

enum ICloudItemDownloadError: Error {
    case timedOut
}

actor ICloudItemDownloadCoordinator {
    static let shared = ICloudItemDownloadCoordinator()

    private var downloads: [String: Task<Void, Error>] = [:]

    func prepareForReading(_ url: URL) async throws {
        guard url.iCloudItemState.needsDownload else { return }

        let key = url.standardizedFileURL.path
        if let download = downloads[key] {
            try await download.value
            return
        }

        let download = Task {
            try await url.downloadICloudItemIfNeeded()
        }
        downloads[key] = download

        do {
            try await download.value
            downloads[key] = nil
        } catch {
            downloads[key] = nil
            throw error
        }
    }
}

extension URL {
    var iCloudItemState: ICloudItemState {
        guard FileManager.default.isUbiquitousItem(at: self) else { return .local }
        guard let values = try? resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) else {
            return .downloading
        }

        switch values.ubiquitousItemDownloadingStatus {
        case .current, .downloaded:
            return .current
        case .notDownloaded:
            return .notDownloaded
        default:
            return .downloading
        }
    }

    func requestICloudDownload() throws {
        guard FileManager.default.isUbiquitousItem(at: self) else { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: self)
    }

    func downloadICloudItemIfNeeded() async throws {
        guard iCloudItemState.needsDownload else { return }

        try requestICloudDownload()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(120))

        while iCloudItemState.needsDownload {
            try Task.checkCancellation()
            guard clock.now < deadline else {
                throw ICloudItemDownloadError.timedOut
            }
            try await Task.sleep(for: .milliseconds(250))
        }
    }
}
