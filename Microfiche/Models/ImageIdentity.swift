//
//  ImageIdentity.swift
//  Microfiche
//
//  Deterministic identity for library images so metadata survives rescans.
//

import CryptoKit
import Foundation

enum ImageIdentity {
    /// Stable identity derived from the file's normalized path.
    static func stableID(for url: URL) -> UUID {
        let digest = SHA256.hash(data: Data(normalizedPath(for: url).utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Canonical path used for identity and local metadata keys.
    static func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
