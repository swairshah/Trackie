import AppKit
import SwiftUI

enum Theme {
    static let rowRadius: CGFloat = 8
    static let rowSpacing: CGFloat = 4
    static let menubarWidth: CGFloat = 360
    static let menubarMaxHeight: CGFloat = 520
    static let menubarMaxHeightExpanded: CGFloat = 760

    static let accent = Color.accentColor

    static var subtleBackground: Color {
        Color.primary.opacity(0.035)
    }

    static var hoverBackground: Color {
        Color.primary.opacity(0.08)
    }

    static var divider: Color {
        Color.primary.opacity(0.08)
    }

    static func statusColor(_ status: TrackieStatusUI) -> Color {
        switch status {
        case .pending: return .secondary
        case .done: return .green
        case .scratched: return .orange
        }
    }
}

enum TrackieStatusUI {
    case pending, done, scratched
}
