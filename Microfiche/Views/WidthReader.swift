//
//  WidthReader.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI

struct WidthReader: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { onChange(geo.size.width) }
                .onChange(of: geo.size.width) { _, newWidth in
                    onChange(newWidth)
                }
        }
    }
}
