import SwiftUI
import AppKit
import MarkdownUI

/// Routes `![alt](url)` rendering by file extension. Images go through
/// `LocalImageView` (reliable for `file://`) or MarkdownUI's default
/// for remote URLs. Video and audio get inline AVKit-backed players.
/// Unknown local files fall back to a clickable file chip.
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

/// Placeholder inline-image provider. MarkdownUI requires an
/// `InlineImageProvider` for images that appear mid-paragraph; we don't
/// have a great inline UX for video/audio yet, so we just render a small
/// paperclip. Block-level attachments (the common case) go through
/// `MediaAwareImageProvider` above.
struct MediaAwareInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        Image(systemName: "paperclip")
    }
}

/// Inline image loader for local `file://` URLs. MarkdownUI's default
/// provider goes through `URLSession`, which can reject file URLs in
/// sandboxed contexts — loading via `NSImage(contentsOf:)` on a
/// background queue is more reliable.
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
