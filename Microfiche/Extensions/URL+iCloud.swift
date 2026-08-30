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
    case failed(String)

    var needsDownload: Bool {
        self == .downloading || self == .notDownloaded
    }
}

enum ICloudItemDownloadError: Error, Equatable, LocalizedError {
    case timedOut
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "The iCloud download timed out."
        case .unavailable(let message):
            return message
        }
    }
}

protocol ICloudItemDownloading: Sendable {
    func state(for url: URL) -> ICloudItemState
    func requestDownload(for url: URL) throws
}

struct SystemICloudItemDownloader: ICloudItemDownloading {
    func state(for url: URL) -> ICloudItemState {
        url.iCloudItemState
    }

    func requestDownload(for url: URL) throws {
        try url.requestICloudDownload()
    }
}

actor ICloudItemDownloadCoordinator {
    static let shared = ICloudItemDownloadCoordinator()

    private var downloads: [String: Task<Void, Error>] = [:]
    private let downloader: any ICloudItemDownloading
    private let maxPollAttempts: Int
    private let pollInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        downloader: any ICloudItemDownloading = SystemICloudItemDownloader(),
        maxPollAttempts: Int = 480,
        pollInterval: Duration = .milliseconds(250),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.downloader = downloader
        self.maxPollAttempts = maxPollAttempts
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    func prepareForReading(_ url: URL) async throws {
        switch downloader.state(for: url) {
        case .local, .current:
            return
        case .failed(let message):
            throw ICloudItemDownloadError.unavailable(message)
        case .downloading, .notDownloaded:
            break
        }

        let key = url.standardizedFileURL.path
        if let download = downloads[key] {
            try await download.value
            try Task.checkCancellation()
            return
        }

        let downloader = self.downloader
        let maxPollAttempts = self.maxPollAttempts
        let pollInterval = self.pollInterval
        let sleep = self.sleep
        let download = Task {
            try downloader.requestDownload(for: url)

            for _ in 0..<maxPollAttempts {
                try Task.checkCancellation()
                switch downloader.state(for: url) {
                case .local, .current:
                    return
                case .failed(let message):
                    throw ICloudItemDownloadError.unavailable(message)
                case .downloading, .notDownloaded:
                    try await sleep(pollInterval)
                }
            }
            throw ICloudItemDownloadError.timedOut
        }
        downloads[key] = download

        do {
            try await download.value
            downloads[key] = nil
            try Task.checkCancellation()
        } catch {
            downloads[key] = nil
            throw error
        }
    }
}

extension URL {
    var iCloudItemState: ICloudItemState {
        guard FileManager.default.isUbiquitousItem(at: self) else { return .local }
        guard let values = try? resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemDownloadingErrorKey
        ]) else {
            return .downloading
        }

        if let error = values.ubiquitousItemDownloadingError {
            return .failed(error.localizedDescription)
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
        try await ICloudItemDownloadCoordinator.shared.prepareForReading(self)
    }
}
