import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Payload returned from the text view when the user pastes or drops
/// something non-textual that should become an attachment.
enum PastePayload {
    case fileURL(URL)
    case data(Data, UTType?, fallbackExt: String)
}

/// SwiftUI wrapper around `AttachmentAwareTextView`. Plain markdown text
/// goes through the standard binding; images / files / media hit
/// `onPaste` so the SwiftUI layer can route them through
/// `AttachmentManager`.
struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onPaste: (PastePayload) -> Void
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let contentSize = scroll.contentSize
        let container = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false

        let layout = NSLayoutManager()
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let tv = AttachmentAwareTextView(frame: .zero, textContainer: container)
        tv.delegate = context.coordinator
        tv.onPaste = onPaste
        tv.isEditable = true
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.drawsBackground = false
        tv.allowsUndo = true
        tv.autoresizingMask = [.width]
        tv.string = text

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextEditor
        init(_ parent: MarkdownTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onCommit()
        }
    }
}

/// NSTextView subclass that intercepts paste. If the pasteboard has
/// images, video, audio, or file URLs, it forwards them to the SwiftUI
/// layer via `onPaste`. Plain text falls through to normal paste.
final class AttachmentAwareTextView: NSTextView {
    var onPaste: ((PastePayload) -> Void)?

    override func paste(_ sender: Any?) {
        if handle(NSPasteboard.general) { return }
        super.paste(sender)
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        // Called on drop; our attachment path takes precedence if applicable.
        if handle(pboard) { return true }
        return super.readSelection(from: pboard, type: type)
    }

    private func handle(_ pb: NSPasteboard) -> Bool {
        guard let onPaste else { return false }

        // File URLs first — the common case for copies from Finder.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            for url in urls where url.isFileURL {
                onPaste(.fileURL(url))
            }
            return true
        }

        // Raw image data (screenshots, Preview clipboard, etc.).
        if let types = pb.types {
            for (pbType, ext, uti) in Self.imageTypePriority where types.contains(pbType) {
                if let data = pb.data(forType: pbType) {
                    onPaste(.data(data, uti, fallbackExt: ext))
                    return true
                }
            }
        }

        return false
    }

    /// Preferred order: PNG (lossless, screenshot default) → TIFF
    /// (macOS system default) → everything else. First match wins.
    private static let imageTypePriority: [(NSPasteboard.PasteboardType, String, UTType?)] = [
        (.png, "png", .png),
        (.tiff, "tiff", .tiff),
        (NSPasteboard.PasteboardType("public.jpeg"), "jpg", .jpeg),
        (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif", .gif),
        (NSPasteboard.PasteboardType("public.mpeg-4"), "mp4", .mpeg4Movie),
        (NSPasteboard.PasteboardType("public.movie"), "mov", .movie),
        (NSPasteboard.PasteboardType("public.audio"), "m4a", .audio),
    ]
}

/// Accepts dropped items in either the Preview or Edit pane. Anything
/// droppable becomes an attachment and gets a markdown snippet inserted
/// at the end of the note.
struct AttachmentDropDelegate: DropDelegate {
    let itemId: UUID
    let insert: (String) -> Void

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL, .image, .movie, .audio])
        guard !providers.isEmpty else { return false }

        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        if let dest = try? AttachmentManager.ingestFile(at: url, for: itemId) {
                            insert(AttachmentManager.markdownSnippet(for: dest))
                        }
                    }
                }
                handled = true
                continue
            }
            for type in [UTType.image, .movie, .audio] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async {
                        let name = AttachmentManager.suggestedName(
                            for: type,
                            fallbackExt: type.preferredFilenameExtension ?? "bin"
                        )
                        if let dest = try? AttachmentManager.save(data: data, suggestedName: name, for: itemId) {
                            insert(AttachmentManager.markdownSnippet(for: dest))
                        }
                    }
                }
                handled = true
                break
            }
        }
        return handled
    }
}
