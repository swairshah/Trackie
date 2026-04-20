import AppKit
import SwiftUI

/// Centralises activation-policy logic.
///
/// Trackie normally runs as a menubar-only accessory. Two things can flip it
/// to a regular (dock-visible) app:
///   - The user opening the main window — we need a dock icon so the window
///     behaves like any other macOS window (can cmd-tab, App menu works, etc.).
///   - The user explicitly pinning the dock icon via the menubar toggle
///     (`persistDockIcon` in UserDefaults) so it stays visible all the time.
///
/// Callers should invoke `apply()` after any state change that could affect
/// the expected policy.
enum DockIconManager {
    static let preferenceKey = "persistDockIcon"

    static var persistDockIcon: Bool {
        UserDefaults.standard.bool(forKey: preferenceKey)
    }

    /// Apply the correct activation policy given the current state.
    /// - Parameters:
    ///   - persistDockIcon: user preference snapshot; when `nil` we read it
    ///     from UserDefaults.
    ///   - mainWindowVisible: whether the full Trackie window is currently
    ///     on screen. If `nil`, we infer it from the window list.
    static func apply(persistDockIcon: Bool? = nil, mainWindowVisible: Bool? = nil) {
        let persist = persistDockIcon ?? self.persistDockIcon
        let windowVisible = mainWindowVisible ?? hasMainWindow()

        let desired: NSApplication.ActivationPolicy = (persist || windowVisible) ? .regular : .accessory
        if NSApp.activationPolicy() != desired {
            NSApp.setActivationPolicy(desired)
            if desired == .regular {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private static func hasMainWindow() -> Bool {
        NSApp.windows.contains { w in
            // Filter out status-bar popovers, sheets, and SwiftUI bookkeeping
            // windows — we only care about the real document-style window.
            guard w.isVisible || w.isMiniaturized else { return false }
            if w.className.contains("NSStatusBarWindow") { return false }
            if w is NSPanel { return false }
            if w.frame.width < 400 || w.frame.height < 300 { return false }
            return true
        }
    }
}
