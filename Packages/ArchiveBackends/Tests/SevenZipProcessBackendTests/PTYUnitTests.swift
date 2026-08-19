import Foundation
import Testing
@testable import SevenZipProcessBackend

@Test func promptMatcherHandlesFragmentationAndRejectsFalsePositives() {
    var parser = SevenZipInteractivePromptParser(maximumBytes: 64)
    let first = parser.consume(Data("archive contains password.txt\nEn".utf8))
    let second = parser.consume(Data("ter pass".utf8))
    let third = parser.consume(Data("word:".utf8))
    #expect(!first); #expect(!second); #expect(third)
    #expect(parser.bufferedByteCount <= 64)
}

@Test func promptMatcherBufferIsBounded() {
    var parser = SevenZipInteractivePromptParser(maximumBytes: 32)
    let matched = parser.consume(Data(repeating: 0x41, count: 10_000))
    #expect(!matched)
    #expect(parser.bufferedByteCount == 32)
}

@Test func terminalCaptureHandlesUTF8FragmentsAndIsBounded() {
    var capture = BoundedTerminalCapture(limit: 64)
    let bytes = Array("Türkçe 📦\rprogress\r\n".utf8)
    capture.append(Data(bytes.prefix(5))); capture.append(Data(bytes.dropFirst(5)))
    #expect(capture.text.contains("Türkçe 📦\nprogress\n"))
    capture.append(Data(repeating: 0x58, count: 1_000))
    #expect(capture.text.utf8.count <= 64)
}

@Test func secretDescriptionsAreAlwaysRedacted() {
    let secret = SecretBytes("TEST_SECRET_DO_NOT_LEAK_847291")
    #expect(String(describing: secret) == "<redacted>")
    #expect(String(reflecting: secret) == "SecretBytes(<redacted>)")
}
