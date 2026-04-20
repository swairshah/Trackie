import SwiftUI
import AppKit
import MarkdownUI
import UniformTypeIdentifiers

/// Broadcast when the user asks to jump into the note editor from a
/// keyboard shortcut. The MainWindow posts it with the item id as the
/// object; NoteEditor observes and flips its mode + focus.
extension Notification.Name {
    static let trackieFocusNoteEditor = Notification.Name("TrackieFocusNoteEditor")
}

/// Note editor with two modes: rendered Preview (MarkdownUI with
/// media-aware image providers) and raw markdown Edit (NSTextView with
/// paste + drop interception for attachments). Attachments are routed
/// through `AttachmentManager` and inserted as markdown at the end of
/// the note.
///
/// Supporting types live in sibling files:
/// - `PasteAwareTextView.swift` — NSTextView + drop delegate + payload
/// - `MarkdownProviders.swift` — image/video/audio renderers
/// - `InlineMediaViews.swift` — the AVKit players themselves
struct NoteEditor: View {
    let itemId: UUID
    @Binding var text: String
    var onCommit: () -> Void

    @State private var mode: Mode = .preview
    @State private var focusEditor = false

    enum Mode { case preview, edit }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolbar
            contentPane
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackieFocusNoteEditor)) { notification in
            if let target = notification.object as? UUID, target == itemId {
                mode = .edit
                focusEditor = true
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text("Notes")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: pickAttachment) {
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
    }

    @ViewBuilder
    private var contentPane: some View {
        switch mode {
        case .preview: previewPane
        case .edit:    editPane
        }
    }

    private var previewPane: some View {
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
        .contentShape(Rectangle())
        // Double-click anywhere in the preview → drop into edit mode
        // with the caret at the end. We can't reliably map a render
        // position back to a markdown source offset, so "caret at end"
        // is the conservative default.
        .onTapGesture(count: 2) {
            mode = .edit
            focusEditor = true
        }
        .onDrop(of: [.image, .movie, .audio, .fileURL], delegate: AttachmentDropDelegate(
            itemId: itemId,
            insert: { insert(snippet: $0) }
        ))
    }

    private var editPane: some View {
        MarkdownTextEditor(
            text: $text,
            onPaste: { handlePasted($0) },
            onCommit: onCommit,
            onEscape: {
                onCommit()
                mode = .preview
            },
            focusRequest: $focusEditor
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

    // MARK: - Attachment actions

    private func pickAttachment() {
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

    private func handlePasted(_ payload: PastePayload) {
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
        let separator = (text.isEmpty || text.hasSuffix("\n")) ? "" : "\n"
        text = text + separator + snippet + "\n"
        onCommit()
    }
}
