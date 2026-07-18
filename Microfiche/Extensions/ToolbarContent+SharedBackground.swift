//
//  ToolbarContent+SharedBackground.swift
//  Microfiche
//

import SwiftUI

extension ToolbarContent {
    @ToolbarContentBuilder
    func hideSharedBackgroundIfAvailable() -> some ToolbarContent {
        if #available(macOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
