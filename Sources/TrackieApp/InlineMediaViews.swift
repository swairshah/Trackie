import SwiftUI
import AVKit
import AppKit

/// Inline video player embedded in the note preview. Uses AVKit's
/// native controls — play/pause/scrub/fullscreen come for free.
struct InlineVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ProgressView()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear { player = AVPlayer(url: url) }
        .onDisappear { player?.pause(); player = nil }
    }
}

/// Compact inline audio player — a play button, title, and seek bar on
/// one row. Meant to be unobtrusive when multiple audio clips are
/// attached to a note.
struct InlineAudioPlayer: View {
    let url: URL
    let displayName: String
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var duration: Double = 0
    @State private var current: Double = 0
    @State private var timeObserver: Any?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlay()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    Slider(value: Binding(
                        get: { duration > 0 ? current / duration : 0 },
                        set: { newVal in
                            guard let player else { return }
                            let target = CMTime(seconds: newVal * duration, preferredTimescale: 600)
                            player.seek(to: target)
                        }
                    ))
                    .controlSize(.mini)
                    Text(formatTime(current) + " / " + formatTime(duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04))
        )
        .onAppear { setup() }
        .onDisappear { teardown() }
    }

    private func setup() {
        let p = AVPlayer(url: url)
        player = p
        let item = p.currentItem
        Task {
            if let d = try? await item?.asset.load(.duration), d.isNumeric {
                await MainActor.run { duration = CMTimeGetSeconds(d) }
            }
        }
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { t in
            current = CMTimeGetSeconds(t)
            if let d = p.currentItem?.duration, d.isNumeric {
                duration = CMTimeGetSeconds(d)
            }
            if let item = p.currentItem, item.status == .readyToPlay,
               CMTimeGetSeconds(t) >= CMTimeGetSeconds(item.duration) {
                isPlaying = false
            }
        }
    }

    private func teardown() {
        if let o = timeObserver { player?.removeTimeObserver(o) }
        player?.pause()
        player = nil
    }

    private func togglePlay() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    private func formatTime(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

/// Clickable file-attachment chip for non-media attachments (PDFs,
/// archives, anything else). Tapping reveals the file in Finder.
struct InlineFileChip: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
                Text(url.lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}
