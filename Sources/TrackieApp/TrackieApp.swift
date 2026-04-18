import SwiftUI
import AppKit
import TrackieClient

@main
struct TrackieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = QueueStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            MenuBarLabel(pending: store.items.filter { $0.status == .pending }.count)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Status bar label with an optional count badge.
///
/// The icon is loaded via `NSImage(contentsOf:)` from `Bundle.module` rather
/// than `Image("MenuBarIcon")`. In a SwiftPM-built app, the resource catalog
/// lives in `Trackie_Trackie.bundle`, *not* the main bundle — so the default
/// `Image(_:)` lookup returns nothing and only the count shows in the menubar.
/// Going through Bundle.module finds the PNG reliably and we can force
/// `isTemplate = true` so it tints correctly on light + dark menubars.
struct MenuBarLabel: View {
    let pending: Int

    var body: some View {
        HStack(spacing: 3) {
            if let image = Self.templateIcon {
                Image(nsImage: image)
            }
            if pending > 0 {
                Text(pending > 99 ? "99+" : String(pending))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private static let templateIcon: NSImage? = {
        // Resolve a PNG URL via the SPM resource bundle. We search a few
        // plausible locations because SPM lays `.copy("Resources")` and
        // `.process("Assets.xcassets")` out differently.
        func find(_ name: String) -> URL? {
            let subdirs: [String?] = [
                nil,
                "Resources",
                "Assets.xcassets/MenuBarIcon.imageset",
            ]
            for sub in subdirs {
                if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: sub) {
                    return url
                }
            }
            return nil
        }

        func bitmapRep(from url: URL) -> NSBitmapImageRep? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return NSBitmapImageRep(data: data)
        }

        guard let url1x = find("menubar"),
              let rep1x = bitmapRep(from: url1x)
        else { return nil }

        // Load the @1x and @2x bitmaps as separate representations on a
        // single NSImage. Without the explicit @2x rep, macOS upscales the
        // 22-pixel PNG to 44 physical pixels on a retina menubar, which is
        // what was making the icon look blurry. Both reps share the same
        // *point* size (22×22); the @2x rep has a 44×44 pixel buffer that
        // macOS picks up on retina displays for crisp rendering.
        rep1x.size = NSSize(width: 26, height: 26)
        let image = NSImage(size: NSSize(width: 26, height: 26))
        image.addRepresentation(rep1x)
        if let url2x = find("menubar@2x"), let rep2x = bitmapRep(from: url2x) {
            rep2x.size = NSSize(width: 26, height: 26)
            image.addRepresentation(rep2x)
        }
        image.isTemplate = true
        return image
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var broker: Broker?

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        AppDelegate.shared = self

        // Start as accessory (menubar-only). Main window will flip to regular when opened.
        NSApp.setActivationPolicy(.accessory)

        do {
            let broker = try Broker(port: TrackieDefaults.brokerPort, store: QueueStore.shared)
            broker.start()
            self.broker = broker
        } catch {
            NSLog("Trackie: broker failed to start: \(error)")
            let alert = NSAlert()
            alert.messageText = "Trackie broker could not start"
            alert.informativeText = "Port \(TrackieDefaults.brokerPort) may already be in use.\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        broker?.stop()
    }
}
