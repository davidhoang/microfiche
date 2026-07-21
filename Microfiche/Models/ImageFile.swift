//
//  ImageFile.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import Foundation

struct ImageFile: Identifiable, Equatable, Hashable {
    let id: UUID
    let url: URL
    var name: String { url.lastPathComponent }

    init(url: URL) {
        let normalizedURL = url.standardizedFileURL
        self.url = normalizedURL
        self.id = ImageIdentity.stableID(for: normalizedURL)
    }

    static func == (lhs: ImageFile, rhs: ImageFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
