import Domain
import Foundation

public enum FormatDetectionEvidence: String, Codable, Hashable, Sendable {
    case magic, magicWithSemanticExtension, extensionFallback, none
}

public struct FormatDetectionResult: Codable, Hashable, Sendable {
    public let format: ArchiveFormat
    public let evidence: FormatDetectionEvidence

    public init(format: ArchiveFormat, evidence: FormatDetectionEvidence) {
        self.format = format
        self.evidence = evidence
    }
}

public protocol ArchiveByteSource: Sendable {
    func read(offset: UInt64, count: Int) throws -> Data
}

public struct FileArchiveByteSource: ArchiveByteSource, Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func read(offset: UInt64, count: Int) throws -> Data {
        guard count >= 0 else { throw CocoaError(.fileReadInvalidFileName) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }
}

public struct FormatDetector: Sendable {
    public static let prefixReadLimit = 512
    public static let isoSignatureOffset: UInt64 = 32_769
    public static let isoSignatureLength = 5

    public init() {}

    public func detect(url: URL) throws -> FormatDetectionResult {
        try detect(source: FileArchiveByteSource(url: url), filename: url.lastPathComponent)
    }

    public func detect(source: some ArchiveByteSource, filename: String) throws -> FormatDetectionResult {
        if let multipart = MultipartArchiveName.parse(filename) {
            guard multipart.isFirstVolume else { throw NonFirstVolumeError(volume: multipart) }
            return .init(format: multipart.format, evidence: .extensionFallback)
        }
        let prefix = try source.read(offset: 0, count: Self.prefixReadLimit)
        if let magic = detectPrefix(prefix) {
            return semanticResult(for: magic, filename: filename)
        }

        let iso = try source.read(offset: Self.isoSignatureOffset, count: Self.isoSignatureLength)
        if iso == Data("CD001".utf8) {
            return .init(format: .iso9660, evidence: .magic)
        }

        let fallback = ArchiveFormat.extensionFallback(for: filename)
        return .init(format: fallback, evidence: fallback == .unknown ? .none : .extensionFallback)
    }

    private func semanticResult(for magic: ArchiveFormat, filename: String) -> FormatDetectionResult {
        let extensionFormat = ArchiveFormat.extensionFallback(for: filename)
        switch (magic, extensionFormat) {
        case (.gzip, .tarGzip), (.bzip2, .tarBzip2), (.xz, .tarXZ), (.zstandard, .tarZstandard):
            return .init(format: extensionFormat, evidence: .magicWithSemanticExtension)
        case (.zip, .zip(let semantic)):
            return .init(format: .zip(semantic), evidence: semantic == .zip ? .magic : .magicWithSemanticExtension)
        case (.xar, .xip):
            return .init(format: .xip, evidence: .magicWithSemanticExtension)
        default:
            return .init(format: magic, evidence: .magic)
        }
    }

    private func detectPrefix(_ data: Data) -> ArchiveFormat? {
        if data.hasPrefix(bytes: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .sevenZip }
        if data.hasAnyPrefix([[0x50, 0x4B, 0x03, 0x04], [0x50, 0x4B, 0x05, 0x06],
                              [0x50, 0x4B, 0x06, 0x06], [0x50, 0x4B, 0x07, 0x08]]) { return .zip(.zip) }
        if data.hasPrefix(bytes: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]) ||
           data.hasPrefix(bytes: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]) { return .rar }
        if data.hasPrefix(bytes: [0x1F, 0x8B, 0x08]) { return .gzip }
        if data.hasPrefix(bytes: [0x42, 0x5A, 0x68]) { return .bzip2 }
        if data.hasPrefix(bytes: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .xz }
        if data.hasPrefix(bytes: [0x28, 0xB5, 0x2F, 0xFD]) { return .zstandard }
        if data.hasPrefix(bytes: [0x4C, 0x5A, 0x49, 0x50]) { return .lzip }
        if data.hasPrefix(bytes: [0x1F, 0x9D]) { return .unixCompress }
        if data.hasPrefix(bytes: Array("MSCF\0\0\0\0".utf8)) { return .cab }
        if data.hasPrefix(bytes: [0x60, 0xEA]) { return .arj }
        if data.hasPrefix(bytes: Array("xar!".utf8)) { return .xar }
        if data.hasAnyPrefix([Array("070701".utf8), Array("070702".utf8), Array("070707".utf8),
                              [0x71, 0xC7], [0xC7, 0x71]]) { return .cpio }
        if data.count >= 262, data.subdata(in: 257..<262) == Data("ustar".utf8) { return .tar }
        return nil
    }
}

private extension Data {
    func hasPrefix(bytes: [UInt8]) -> Bool {
        count >= bytes.count && prefix(bytes.count).elementsEqual(bytes)
    }

    func hasAnyPrefix(_ candidates: [[UInt8]]) -> Bool {
        candidates.contains { hasPrefix(bytes: $0) }
    }
}
