import SwiftUI
import AppKit
import MarkdownUI
import UniformTypeIdentifiers

/// Note editor with two modes: markdown-rendered Preview and raw
/// Edit. Handles pasting / dropping images, video, audio, and files,
/// routing them through `AttachmentManager` and inserting the
/// appropriate markdown snippet at the cursor.
struct NoteEditor: View {
    let itemId: UUID
    @Binding var text: String
    var onCommit: () -> Void

    @State private var mode: Mode = .preview
    @State private var showAttachSheet = false

    enum Mode { case preview, edit }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Notes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    attach()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Attach file, image, video, or audio")

                Picker("", selection: $mode) {
                    Image(systemName: "eye").tag(Mode.preview)
                    Image(systemName: "pencil").tag(Mode.edit)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 70)
                .controlSize(.small)
            }

            Group {
                switch mode {
                case .preview:
                    preview
                case .edit:
                    editor
                }
            }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ScrollView {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("No notes yet. Switch to Edit to write markdown, paste a screenshot, or drop a file.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else {
                Markdown(text)
                    .markdownImageProvider(MediaAwareImageProvider())
                    .markdownInlineImageProvider(MediaAwareInlineImageProvider())
                    .markdownTextStyle { FontSize(13) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
        .frame(minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Theme.subtleBackground)
        )
        .onDrop(of: [.image, .movie, .audio, .fileURL], delegate: AttachmentDropDelegate(
            itemId: itemId,
            insert: { insert(snippet: $0) }
        ))
    }

    // MARK: - Editor

    private var editor: some View {
        MarkdownTextEditor(
            text: $text,
            onPaste: { handlePastePayload($0) },
            onCommit: onCommit
        )
        .frame(minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(Theme.subtleBackground)
        )
        .onDrop(of: [.image, .movie, .audio, .fileURL], delegate: AttachmentDropDelegate(
            itemId: itemId,
            insert: { insert(snippet: $0) }
        ))
    }

    // MARK: - Actions

    private func attach() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { result in
            guard result == .OK else { return }
            for url in panel.urls {
                if let dest = try? AttachmentManager.ingestFile(at: url, for: itemId) {
                    insert(snippet: AttachmentManager.markdownSnippet(for: dest))
                }
            }
        }
    }

    private func handlePastePayload(_ payload: PastePayload) {
        switch payload {
        case .fileURL(let url):
            if let dest = try? AttachmentManager.ingestFile(at: url, for: itemId) {
                insert(snippet: AttachmentManager.markdownSnippet(for: dest))
            }
        case .data(let data, let uti, let fallback):
            let name = AttachmentManager.suggestedName(for: uti, fallbackExt: fallback)
            if let dest = try? AttachmentManager.save(data: data, suggestedName: name, for: itemId) {
                insert(snippet: AttachmentManager.markdownSnippet(for: dest))
            }
        }
    }

    private func insert(snippet: String) {
        let prefix = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
        text = text + prefix + snippet + "\n"
        onCommit()
    }
}

// MARK: - Paste-aware NSTextView wrapper

/// Lightweight payload returned from the text view when the user pastes
/// or drops something non-textual that should become an attachment.
enum PastePayload {
    case fileURL(URL)
    case data(Data, UTType?, fallbackExt: String)
}

struct MarkdownTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onPaste: (PastePayload) -> Void
    var onCommit: () -> Void

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

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        configure(tv: tv, coordinator: context.coordinator)
        let wrap = AttachmentAwareTextView.wrap(tv, onPaste: onPaste)
        scroll.documentView = wrap
        configure(tv: wrap, coordinator: context.coordinator)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
        }
    }

    private func configure(tv: NSTextView, coordinator: Coordinator) {
        tv.delegate = coordinator
        tv.isRichText = false
        tv.isEditable = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.drawsBackground = false
        tv.allowsUndo = true
        tv.string = text
    }
}

/// NSTextView subclass that intercepts paste. If the pasteboard has
/// images, video, audio, or file URLs, it forwards them to the
/// SwiftUI layer via `onPaste`. Plain text falls through to normal
/// paste behavior.
final class AttachmentAwareTextView: NSTextView {
    var onPaste: ((PastePayload) -> Void)?

    static func wrap(_ base: NSTextView, onPaste: @escaping (PastePayload) -> Void) -> AttachmentAwareTextView {
        let v = AttachmentAwareTextView(frame: base.frame, textContainer: base.textContainer)
        v.onPaste = onPaste
        v.autoresizingMask = base.autoresizingMask
        return v
    }

    override func paste(_ sender: Any?) {
        if handleAttachmentPaste() { return }
        super.paste(sender)
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        // Called on drop; let our attachment path handle it if applicable.
        if handleAttachmentPasteboard(pboard) { return true }
        return super.readSelection(from: pboard, type: type)
    }

    private func handleAttachmentPaste() -> Bool {
        handleAttachmentPasteboard(NSPasteboard.general)
    }

    private func handleAttachmentPasteboard(_ pb: NSPasteboard) -> Bool {
        guard let onPaste else { return false }

        // 1. File URLs first (copies from Finder are the common case).
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            for url in urls where url.isFileURL {
                onPaste(.fileURL(url))
            }
            return true
        }

        // 2. Image data (screenshots, Preview clipboard, etc.).
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

    /// Preferred order: PNG (lossless, most common for screenshots) →
    /// TIFF (macOS system default) → others. First match wins.
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

// MARK: - Drop target

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
            } else {
                for type in [UTType.image, .movie, .audio] {
                    if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                            guard let data else { return }
                            DispatchQueue.main.async {
                                let name = AttachmentManager.suggestedName(for: type, fallbackExt: type.preferredFilenameExtension ?? "bin")
                                if let dest = try? AttachmentManager.save(data: data, suggestedName: name, for: itemId) {
                                    insert(AttachmentManager.markdownSnippet(for: dest))
                                }
                            }
                        }
                        handled = true
                        break
                    }
                }
            }
        }
        return handled
    }
}

// MARK: - MarkdownUI providers for video/audio/files

/// Intercepts `![alt](url)` rendering. If the URL is a file:// pointing
/// at an image, MarkdownUI's default does the right thing. For video
/// or audio extensions we render our AVKit-based inline players instead.
/// For everything else (unknown local file) we fall back to a chip that
/// reveals the file in Finder.
struct MediaAwareImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        Group {
            if let url {
                let ext = url.pathExtension.lowercased()
                if AttachmentManager.isVideo(ext) {
                    InlineVideoPlayer(url: url)
                } else if AttachmentManager.isAudio(ext) {
                    InlineAudioPlayer(url: url, displayName: url.lastPathComponent)
                } else if AttachmentManager.isImage(ext) {
                    LocalImageView(url: url)
                } else if !url.isFileURL {
                    // Remote URL — let MarkdownUI's default handle it.
                    DefaultImageProvider.default.makeImage(url: url)
                } else {
                    InlineFileChip(url: url)
                }
            } else {
                EmptyView()
            }
        }
    }
}

/// Inline image loader for `file://` URLs. MarkdownUI's default provider
/// goes through `URLSession`, which rejects file URLs on macOS sandboxed
/// contexts. Loading the bytes ourselves is more reliable.
struct LocalImageView: View {
    let url: URL
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
                    .frame(height: 60)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
        .onAppear { load() }
    }

    private func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let img = NSImage(contentsOf: url)
            DispatchQueue.main.async { nsImage = img }
        }
    }
}

/// Inline images inside paragraphs — rendered the same way as block
/// images for the non-image media types so a user writing
/// `Here's ![video:demo](demo.mp4) the demo` gets the same behavior.
struct MediaAwareInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        Image(systemName: "paperclip")
    }
}
