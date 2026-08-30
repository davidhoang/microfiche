//
//  ImageLoadState.swift
//  Microfiche
//

import AppKit
import Foundation

enum ImageLoadPhase: Equatable {
    case idle
    case placeholder
    case downloading
    case loading
    case loaded
    case failed(String)
    case cancelled
}

struct ImageLoadState: Equatable {
    private(set) var phase: ImageLoadPhase = .idle
    private(set) var requestID: UUID?

    mutating func observe(_ itemState: ICloudItemState) {
        requestID = nil
        switch itemState {
        case .notDownloaded:
            phase = .placeholder
        case .failed(let message):
            phase = .failed(message)
        case .downloading:
            phase = .downloading
        case .local, .current:
            phase = .idle
        }
    }

    mutating func begin(for itemState: ICloudItemState) -> UUID {
        let id = UUID()
        requestID = id
        phase = itemState.needsDownload ? .downloading : .loading
        return id
    }

    @discardableResult
    mutating func finish(
        _ result: Result<Void, Error>,
        requestID: UUID
    ) -> Bool {
        guard self.requestID == requestID else { return false }
        self.requestID = nil
        switch result {
        case .success:
            phase = .loaded
        case .failure(let error as CancellationError):
            _ = error
            phase = .cancelled
        case .failure(let error):
            phase = .failed(error.localizedDescription)
        }
        return true
    }

    @discardableResult
    mutating func cancel(requestID: UUID) -> Bool {
        guard self.requestID == requestID else { return false }
        self.requestID = nil
        phase = .cancelled
        return true
    }
}

enum PreviewImageLoadError: Error, LocalizedError {
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let fileName):
            return "Microfiche couldn’t load \(fileName)."
        }
    }
}

@MainActor
final class PreviewImageLoadModel: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var state = ImageLoadState()

    private var task: Task<Void, Never>?
    private var url: URL?

    func prepare(url: URL) {
        guard self.url != url || state.phase == .idle else { return }
        task?.cancel()
        self.url = url
        image = nil

        let itemState = url.iCloudItemState
        var nextState = state
        nextState.observe(itemState)
        state = nextState

        switch itemState {
        case .notDownloaded, .failed:
            return
        case .local, .current, .downloading:
            load()
        }
    }

    func load() {
        guard let url else { return }
        task?.cancel()

        var nextState = state
        let requestID = nextState.begin(for: url.iCloudItemState)
        state = nextState

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await PreviewImageCache.shared.image(for: url)
                try Task.checkCancellation()
                guard self.url == url else { return }
                image = loaded
                var completedState = state
                _ = completedState.finish(.success(()), requestID: requestID)
                state = completedState
            } catch {
                guard self.url == url else { return }
                var completedState = state
                _ = completedState.finish(.failure(error), requestID: requestID)
                state = completedState
            }
        }
    }

    func cancel() {
        task?.cancel()
        guard let requestID = state.requestID else { return }
        var nextState = state
        _ = nextState.cancel(requestID: requestID)
        state = nextState
    }
}
