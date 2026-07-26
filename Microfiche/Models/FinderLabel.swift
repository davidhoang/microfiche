//
//  FinderLabel.swift
//  Microfiche
//
//  Finder color labels (NSURL.labelNumberKey values 0–7).
//

import SwiftUI

enum FinderLabel: Int, CaseIterable, Codable, Sendable, Identifiable {
    case none = 0
    case gray = 1
    case green = 2
    case purple = 3
    case blue = 4
    case yellow = 5
    case orange = 6
    case red = 7

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .gray: "Gray"
        case .green: "Green"
        case .purple: "Purple"
        case .blue: "Blue"
        case .yellow: "Yellow"
        case .orange: "Orange"
        case .red: "Red"
        }
    }

    /// Finder-accurate swatch colors for the label picker.
    var swatchColor: Color? {
        switch self {
        case .none: nil
        case .gray: Color(red: 0.65, green: 0.65, blue: 0.67)
        case .green: Color(red: 0.30, green: 0.85, blue: 0.39)
        case .purple: Color(red: 0.69, green: 0.32, blue: 0.87)
        case .blue: Color(red: 0.20, green: 0.48, blue: 0.96)
        case .yellow: Color(red: 1.00, green: 0.80, blue: 0.00)
        case .orange: Color(red: 1.00, green: 0.58, blue: 0.00)
        case .red: Color(red: 1.00, green: 0.23, blue: 0.19)
        }
    }

    /// Colored labels in Finder’s usual left-to-right order (excluding None).
    static var coloredCases: [FinderLabel] {
        [.gray, .green, .purple, .blue, .yellow, .orange, .red]
    }

    /// Map legacy Microfiche free-text labels (e.g. "Red") onto a Finder color.
    static func migrating(from legacyLabels: [String]) -> FinderLabel? {
        for raw in legacyLabels {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty else { continue }
            if let match = FinderLabel.allCases.first(where: {
                $0 != .none && $0.displayName.lowercased() == name
            }) {
                return match
            }
        }
        return nil
    }

    init(labelNumber: Int?) {
        if let labelNumber, let label = FinderLabel(rawValue: labelNumber) {
            self = label
        } else {
            self = .none
        }
    }
}
