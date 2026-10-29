// Semantic colors. Color carries meaning:
//   claude  – your allowance (plan limits, capacity, primary metrics)
//   cobalt  – history and analytics
//   live    – something is running right now
//   caution / critical – nearing / at a limit

import SwiftUI

enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static let claude   = Color(light: rgb(0.80, 0.42, 0.29), dark: rgb(0.93, 0.56, 0.42))
    static let cobalt   = Color(light: rgb(0.15, 0.38, 0.92), dark: rgb(0.42, 0.62, 1.00))
    static let live     = Color(light: rgb(0.12, 0.60, 0.34), dark: rgb(0.32, 0.84, 0.52))
    static let caution  = Color(light: rgb(0.84, 0.50, 0.04), dark: rgb(1.00, 0.72, 0.28))
    static let critical = Color(light: rgb(0.85, 0.20, 0.18), dark: rgb(1.00, 0.45, 0.40))

    static let surface   = Color(light: rgb(0, 0, 0, 0.035), dark: rgb(1, 1, 1, 0.05))
    static let selection = Color(light: rgb(1, 1, 1, 1), dark: rgb(1, 1, 1, 0.13))
    static let hairline  = Color(light: rgb(0, 0, 0, 0.08), dark: rgb(1, 1, 1, 0.09))
    static let track     = Color(light: rgb(0, 0, 0, 0.11), dark: rgb(1, 1, 1, 0.13))
}
