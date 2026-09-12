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

extension Notification.Name {
    static let microficheCloudItemDidBecomeReadable = Notification.Name(
        "microficheCloudItemDidBecomeReadable"
    )
}

enum MicroficheCloudItemNotification {
    static let pathUserInfoKey = "path"

    static func postReadable(url: URL) {
        NotificationCenter.default.post(
            name: .microficheCloudItemDidBecomeReadable,
            object: nil,
            userInfo: [pathUserInfoKey: url.standardizedFileURL.path]
        )
    }

    static func path(from notification: Notification) -> String? {
        notification.userInfo?[pathUserInfoKey] as? String
    }
}

enum LibraryImageReadiness: Equatable {
    case readable
    case placeholder
    case downloading
    case failed(String)
    case missing

    static func resolving(
        url: URL,
        fileManager: FileManager = .default,
        itemState: ICloudItemState? = nil
    ) -> LibraryImageReadiness {
        switch itemState ?? url.iCloudItemState {
        case .notDownloaded:
            return .placeholder
        case .downloading:
            return .downloading
        case .failed(let message):
            return .failed(message)
        case .local, .current:
            return fileManager.fileExists(atPath: url.path) ? .readable : .missing
        }
    }

    var shouldDecodeImage: Bool {
        switch self {
        case .readable, .downloading:
            return true
        case .placeholder, .failed, .missing:
            return false
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .readable:
            return "image-thumb.ready"
        case .placeholder:
            return "image-thumb.placeholder"
        case .downloading:
            return "image-thumb.downloading"
        case .failed:
            return "image-thumb.failed"
        case .missing:
            return "image-thumb.missing"
        }
    }

    static func prepareLocalRead(of url: URL) async -> Bool {
        switch resolving(url: url) {
        case .readable:
            return true
        case .downloading:
            do {
                try await ICloudItemDownloadCoordinator.shared.prepareForReading(url)
                return true
            } catch {
                return false
            }
        case .placeholder, .failed, .missing:
            return false
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

    private struct InFlightDownload {
        let id: UUID
        let task: Task<Void, Error>
    }

    private var downloads: [String: InFlightDownload] = [:]
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
        let initialState = downloader.state(for: url)
        let isRetryingFailure: Bool
        switch initialState {
        case .local, .current:
            return
        case .failed:
            isRetryingFailure = true
        case .downloading, .notDownloaded:
            isRetryingFailure = false
        }

        let key = url.standardizedFileURL.path
        let inFlight: InFlightDownload
        if let existing = downloads[key] {
            inFlight = existing
        } else {
            let downloader = self.downloader
            let maxPollAttempts = self.maxPollAttempts
            let pollInterval = self.pollInterval
            let sleep = self.sleep
            let downloadID = UUID()
            let download = Task {
                try downloader.requestDownload(for: url)

                for attempt in 0..<maxPollAttempts {
                    try Task.checkCancellation()
                    switch downloader.state(for: url) {
                    case .local, .current:
                        MicroficheCloudItemNotification.postReadable(url: url)
                        return
                    case .failed(let message):
                        if isRetryingFailure, attempt == 0 {
                            try await sleep(pollInterval)
                            continue
                        }
                        throw ICloudItemDownloadError.unavailable(message)
                    case .downloading, .notDownloaded:
                        try await sleep(pollInterval)
                    }
                }
                throw ICloudItemDownloadError.timedOut
            }
            inFlight = InFlightDownload(id: downloadID, task: download)
            downloads[key] = inFlight
        }

        do {
            try await inFlight.task.value
            clearIfCurrent(key, id: inFlight.id)
            try Task.checkCancellation()
        } catch is CancellationError {
            if Task.isCancelled && !inFlight.task.isCancelled {
                throw CancellationError()
            }
            clearIfCurrent(key, id: inFlight.id)
            throw CancellationError()
        } catch {
            clearIfCurrent(key, id: inFlight.id)
            throw error
        }
    }

    private func clearIfCurrent(_ key: String, id: UUID) {
        guard downloads[key]?.id == id else { return }
        downloads[key] = nil
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
