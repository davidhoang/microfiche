//
//  ImageDropSupport.swift
//  Microfiche
//
//  Shared drag payload support for image files moved between the library,
//  Finder, and contact sheets.
//

import Foundation
import UniformTypeIdentifiers

enum ImageDropSupport {
    static let acceptedContentTypes: [UTType] = [.fileURL, .url]

    static func itemProvider(for url: URL) -> NSItemProvider {
        NSItemProvider(
            item: url as NSURL,
            typeIdentifier: UTType.fileURL.identifier
        )
    }

    static func canLoadFileURL(from providers: [NSItemProvider]) -> Bool {
        providers.contains { preferredTypeIdentifier(for: $0) != nil }
    }

    /// Loads one callback for the complete drag, preserving provider order and
    /// removing repeated file URLs before contact-sheet persistence begins.
    static func loadFileURLs(
        from providers: [NSItemProvider],
        completion: @escaping ([URL]) -> Void
    ) {
        let loadableProviders = providers.enumerated().compactMap { index, provider in
            preferredTypeIdentifier(for: provider).map { (index, provider, $0) }
        }

        guard !loadableProviders.isEmpty else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var loadedURLs: [Int: URL] = [:]

        for (index, provider, typeIdentifier) in loadableProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                defer { group.leave() }
                guard error == nil,
                      let fileURL = fileURL(from: item),
                      fileURL.isFileURL else { return }

                lock.lock()
                loadedURLs[index] = fileURL.standardizedFileURL
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            var seenPaths = Set<String>()
            let urls = loadedURLs
                .sorted { $0.key < $1.key }
                .map(\.value)
                .filter { seenPaths.insert($0.path).inserted }
            completion(urls)
        }
    }

    private static func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return UTType.fileURL.identifier
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return UTType.url.identifier
        }
        return nil
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let url = item as? NSURL {
            return url as URL
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let string = item as? String {
            return URL(string: string).flatMap { $0.isFileURL ? $0 : nil }
                ?? URL(fileURLWithPath: string)
        }
        if let string = item as? NSString {
            return fileURL(from: string as String as NSSecureCoding)
        }
        return nil
    }
}
