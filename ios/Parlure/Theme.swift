//
//  Theme.swift
//  Parlure
//

import SwiftUI

enum Theme {
    // Warm parchment palette inspired by Quebec heritage paper
    static let parchment = Color(red: 0.957, green: 0.914, blue: 0.835) // #F4E9D5
    static let parchmentDeep = Color(red: 0.914, green: 0.843, blue: 0.710) // #E9D7B5
    static let ink = Color(red: 0.106, green: 0.090, blue: 0.078) // #1B1714
    static let inkSoft = Color(red: 0.345, green: 0.298, blue: 0.247) // #584C3F
    static let mapleRed = Color(red: 0.651, green: 0.192, blue: 0.165) // #A6312A
    static let mapleRedDeep = Color(red: 0.498, green: 0.137, blue: 0.118) // #7F231E
    static let moss = Color(red: 0.357, green: 0.443, blue: 0.318) // #5B7151
    static let cream = Color(red: 0.984, green: 0.961, blue: 0.910) // #FBF5E8
    static let divider = Color(red: 0.788, green: 0.722, blue: 0.604) // #C9B89A

    static func paperBackground() -> some View {
        LinearGradient(
            colors: [cream, parchment, parchmentDeep],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay {
            // Subtle vignette
            RadialGradient(
                colors: [.clear, ink.opacity(0.06)],
                center: .center,
                startRadius: 200,
                endRadius: 600
            )
        }
        .ignoresSafeArea()
    }
}

extension Font {
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
