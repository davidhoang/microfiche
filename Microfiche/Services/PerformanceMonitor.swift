//
//  PerformanceMonitor.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import Foundation
import SwiftUI

class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()

    @Published private(set) var totalRequests: Int = 0
    @Published private(set) var cacheHits: Int = 0

    private init() {}

    var cacheHitRate: Double {
        guard totalRequests > 0 else { return 0.0 }
        return Double(cacheHits) / Double(totalRequests)
    }

    func reset() {
        DispatchQueue.main.async {
            self.totalRequests = 0
            self.cacheHits = 0
        }
    }

    func recordCacheHit() {
        totalRequests += 1
        cacheHits += 1
    }

    func recordCacheMiss() {
        totalRequests += 1
    }
}
