import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private var delegate: WindowDelegate?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = MainWindowView(store: QueueStore.shared)
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
