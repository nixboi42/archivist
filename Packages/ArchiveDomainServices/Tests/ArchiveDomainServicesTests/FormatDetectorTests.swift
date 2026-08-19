import Domain
import Foundation
import Testing
@testable import ArchiveDomainServices

private final class RecordingSource: ArchiveByteSource, @unchecked Sendable {
    private let lock = NSLock()
    private let bytes: [UInt64: Data]
    private var recorded: [(UInt64, Int)] = []

    init(bytes: [UInt64: Data]) { self.bytes = bytes }
    func read(offset: UInt64, count: Int) throws -> Data {
        lock.withLock { recorded.append((offset, count)) }
        return (bytes[offset] ?? Data()).prefix(count)
    }
    var reads: [(UInt64, Int)] { lock.withLock { recorded } }
}

private func prefix(_ bytes: [UInt8], paddedTo count: Int = 512) -> Data {
    Data(bytes + Array(repeating: 0, count: max(0, count - bytes.count)))
}

@Test(arguments: [
    ([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], ArchiveFormat.sevenZip),
    ([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00], .rar),
    ([0x4D, 0x53, 0x43, 0x46, 0, 0, 0, 0], .cab),
    ([0x60, 0xEA], .arj),
    ([0x1F, 0x9D], .unixCompress),
]) func recognizesPrefixMagic(bytes: [UInt8], expected: ArchiveFormat) throws {
    let result = try FormatDetector().detect(source: RecordingSource(bytes: [0: prefix(bytes)]), filename: "wrong.bin")
    #expect(result.format == expected)
    #expect(result.evidence == .magic)
}

@Test func magicWinsOverContradictoryExtension() throws {
    let source = RecordingSource(bytes: [0: prefix([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])])
    #expect(try FormatDetector().detect(source: source, filename: "fake.zip").format == .sevenZip)
    #expect(source.reads.count == 1)
}

@Test func compoundExtensionsRefineMatchingCompressionMagic() throws {
    let detector = FormatDetector()
    #expect(try detector.detect(source: RecordingSource(bytes: [0: prefix([0x1F, 0x8B, 0x08])]), filename: "a.tar.gz").format == .tarGzip)
    #expect(try detector.detect(source: RecordingSource(bytes: [0: prefix([0x42, 0x5A, 0x68])]), filename: "a.tar.bz2").format == .tarBzip2)
    #expect(try detector.detect(source: RecordingSource(bytes: [0: prefix([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0])]), filename: "a.tar.xz").format == .tarXZ)
    #expect(try detector.detect(source: RecordingSource(bytes: [0: prefix([0x28, 0xB5, 0x2F, 0xFD])]), filename: "a.tar.zst").format == .tarZstandard)
}

@Test func zipDerivedContainersRetainSemanticLabels() throws {
    let zip = prefix([0x50, 0x4B, 0x03, 0x04])
    let detector = FormatDetector()
    #expect(try detector.detect(source: RecordingSource(bytes: [0: zip]), filename: "app.apk").format == .zip(.apk))
    #expect(try detector.detect(source: RecordingSource(bytes: [0: zip]), filename: "book.epub").format == .zip(.epub))
    #expect(try detector.detect(source: RecordingSource(bytes: [0: zip]), filename: "code.jar").format == .zip(.jar))
}

@Test func xarMagicAndXipExtensionProduceXipSemanticType() throws {
    let result = try FormatDetector().detect(source: RecordingSource(bytes: [0: prefix(Array("xar!".utf8))]), filename: "Xcode.xip")
    #expect(result.format == .xip)
    #expect(result.evidence == .magicWithSemanticExtension)
}

@Test func detectsTarAtBoundedOffset() throws {
    var bytes = Data(repeating: 0, count: 512)
    bytes.replaceSubrange(257..<262, with: Data("ustar".utf8))
    #expect(try FormatDetector().detect(source: RecordingSource(bytes: [0: bytes]), filename: "archive.bin").format == .tar)
}

@Test func detectsISOUsingOneSmallSecondaryRead() throws {
    let source = RecordingSource(bytes: [0: Data(), FormatDetector.isoSignatureOffset: Data("CD001".utf8)])
    let result = try FormatDetector().detect(source: source, filename: "disc.bin")
    #expect(result.format == .iso9660)
    #expect(source.reads.count == 2)
    #expect(source.reads[0].0 == 0 && source.reads[0].1 == 512)
    #expect(source.reads[1].0 == 32_769 && source.reads[1].1 == 5)
}

@Test func extensionFallbackAndUnknownAreExplicit() throws {
    let detector = FormatDetector()
    let empty = RecordingSource(bytes: [:])
    #expect(try detector.detect(source: empty, filename: "archive.lzma") == .init(format: .lzma, evidence: .extensionFallback))
    #expect(try detector.detect(source: empty, filename: "mystery.data") == .init(format: .unknown, evidence: .none))
}

@Test func realFileDetectionUsesOnlyBoundedReads() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("7z")
    try Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0, 0]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(try FormatDetector().detect(url: url).format == .sevenZip)
}

@Test func multipartFirstVolumeDetectionRejectsLaterVolumes() throws {
    let detector = FormatDetector()
    let source = RecordingSource(bytes: [:])
    #expect(try detector.detect(source: source, filename: "Archive.7z.001").format == .sevenZip)
    #expect(throws: NonFirstVolumeError.self) {
        try detector.detect(source: source, filename: "Archive.7z.002")
    }
}
