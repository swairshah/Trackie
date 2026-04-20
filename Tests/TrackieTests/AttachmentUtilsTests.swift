import XCTest
@testable import TrackieClient

final class AttachmentUtilsTests: XCTestCase {

    // MARK: - Kind detection

    func testImageKindDetection() {
        XCTAssertTrue(AttachmentUtils.isImage("png"))
        XCTAssertTrue(AttachmentUtils.isImage("PNG"))    // case-insensitive
        XCTAssertTrue(AttachmentUtils.isImage("jpeg"))
        XCTAssertTrue(AttachmentUtils.isImage("heic"))
        XCTAssertFalse(AttachmentUtils.isImage("mp4"))
        XCTAssertFalse(AttachmentUtils.isImage(""))
    }

    func testVideoKindDetection() {
        XCTAssertTrue(AttachmentUtils.isVideo("mp4"))
        XCTAssertTrue(AttachmentUtils.isVideo("MOV"))
        XCTAssertTrue(AttachmentUtils.isVideo("webm"))
        XCTAssertFalse(AttachmentUtils.isVideo("mp3"))
        XCTAssertFalse(AttachmentUtils.isVideo("png"))
    }

    func testAudioKindDetection() {
        XCTAssertTrue(AttachmentUtils.isAudio("mp3"))
        XCTAssertTrue(AttachmentUtils.isAudio("M4A"))
        XCTAssertTrue(AttachmentUtils.isAudio("flac"))
        XCTAssertFalse(AttachmentUtils.isAudio("mp4"))
    }

    // MARK: - sanitize

    func testSanitizeKeepsAlphanumericAndUnderscoresAndHyphens() {
        XCTAssertEqual(AttachmentUtils.sanitize("Hello_World-2024"), "hello_world-2024")
    }

    func testSanitizeReplacesSpacesAndPunctuation() {
        XCTAssertEqual(AttachmentUtils.sanitize("my fancy file!!"), "my-fancy-file--")
    }

    func testSanitizeCapsLengthAt32() {
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(AttachmentUtils.sanitize(long).count, 32)
    }

    func testSanitizeEmptyString() {
        XCTAssertEqual(AttachmentUtils.sanitize(""), "")
    }

    // MARK: - shortHash

    func testShortHashIsDeterministic() {
        let a = AttachmentUtils.shortHash(Data("hello world".utf8))
        let b = AttachmentUtils.shortHash(Data("hello world".utf8))
        XCTAssertEqual(a, b)
    }

    func testShortHashDiffersForDifferentContent() {
        let a = AttachmentUtils.shortHash(Data("hello".utf8))
        let b = AttachmentUtils.shortHash(Data("world".utf8))
        XCTAssertNotEqual(a, b)
    }

    func testShortHashIsShort() {
        let h = AttachmentUtils.shortHash(Data("trackie".utf8))
        XCTAssertLessThanOrEqual(h.count, 10)
        XCTAssertFalse(h.isEmpty)
    }

    // MARK: - markdownSnippet

    func testMarkdownSnippetForImage() {
        let url = URL(fileURLWithPath: "/tmp/shot-abc.png")
        XCTAssertEqual(
            AttachmentUtils.markdownSnippet(for: url),
            "![shot-abc](file:///tmp/shot-abc.png)"
        )
    }

    func testMarkdownSnippetForVideoUsesVideoTag() {
        let url = URL(fileURLWithPath: "/tmp/demo.mp4")
        let snippet = AttachmentUtils.markdownSnippet(for: url)
        XCTAssertTrue(snippet.hasPrefix("![video:demo]("), "got: \(snippet)")
    }

    func testMarkdownSnippetForAudioUsesAudioTag() {
        let url = URL(fileURLWithPath: "/tmp/clip.mp3")
        XCTAssertTrue(AttachmentUtils.markdownSnippet(for: url).hasPrefix("![audio:clip]("))
    }

    func testMarkdownSnippetForUnknownExtensionIsPlainLink() {
        let url = URL(fileURLWithPath: "/tmp/notes.txt")
        let snippet = AttachmentUtils.markdownSnippet(for: url)
        XCTAssertTrue(snippet.hasPrefix("[notes.txt]("), "got: \(snippet)")
        XCTAssertFalse(snippet.hasPrefix("!"), "plain links shouldn't be image-rendered")
    }

    // MARK: - suggestedName

    func testSuggestedNameForImage() {
        let fixed = Date(timeIntervalSince1970: 100)
        let name = AttachmentUtils.suggestedName(for: .png, fallbackExt: "bin", now: fixed)
        XCTAssertEqual(name, "image-100.png")
    }

    func testSuggestedNameFallbackExtWhenUTIMissing() {
        let fixed = Date(timeIntervalSince1970: 42)
        let name = AttachmentUtils.suggestedName(for: nil, fallbackExt: "zzz", now: fixed)
        XCTAssertEqual(name, "file-42.zzz")
    }

    func testSuggestedNameUsesVideoPrefixForMovieUTI() {
        let fixed = Date(timeIntervalSince1970: 200)
        let name = AttachmentUtils.suggestedName(for: .movie, fallbackExt: "mov", now: fixed)
        XCTAssertTrue(name.hasPrefix("video-200."), "got: \(name)")
    }
}
