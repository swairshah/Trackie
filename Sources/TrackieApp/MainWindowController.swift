import AppKit
import SwiftUI
import Combine

/// Owns the lifecycle of the main window and the currently selected item.
/// The selection is exposed as a published property so the menubar can ask
/// the window to open with a specific item focused.
@MainActor
final class MainWindowController: ObservableObject {
    static let shared = MainWindowController()

    @Published var selection: UUID?

    private var window: NSWindow?
    private var delegate: WindowDelegate?

    private init() {}

    /// Open (or raise) the main window. If `select` is non-nil the item
    /// becomes the window's current selection.
    func show(select id: UUID? = nil) {
        if let id { selection = id }

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = MainWindowView(store: QueueStore.shared, controller: self)
        let hosting = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Trackie"
        window.minSize = NSSize(width: 760, height: 460)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = hosting
        window.center()

        let delegate = WindowDelegate { [weak self] in
            self?.window = nil
            self?.delegate = nil
            NSApp.setActivationPolicy(.accessory)
        }
        window.delegate = delegate
        self.delegate = delegate
        self.window = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
