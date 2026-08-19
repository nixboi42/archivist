import Foundation

public enum CompressionLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case store, fastest, fast, normal, maximum, ultra
}

public enum CompressionMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case copy, lzma2, lzma, ppmd, deflate, deflate64, bzip2
}

public enum SolidMode: String, Codable, CaseIterable, Hashable, Sendable {
    case automatic, off, on
}

public enum ThreadConfiguration: Codable, Hashable, Sendable {
    case automatic
    case explicit(Int)
}

public struct VolumeSize: Codable, Hashable, Sendable {
    public static let minimumBytes: UInt64 = 64 * 1024
    public static let maximumBytes: UInt64 = 1 << 40
    public let bytes: UInt64

    public init(bytes: UInt64) throws {
        guard bytes >= Self.minimumBytes, bytes <= Self.maximumBytes else {
            throw VolumeSizeError.outOfRange
        }
        self.bytes = bytes
    }

    public init(parsing value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = /^([0-9]+)\s*(KB|KIB|MB|MIB|GB|GIB)?$/
        guard let match = trimmed.wholeMatch(of: pattern), let number = UInt64(match.1) else {
            throw VolumeSizeError.invalidSyntax
        }
        let multiplier: UInt64 = switch String(match.2 ?? "") {
        case "KB": 1_000
        case "KIB": 1 << 10
        case "MB": 1_000_000
        case "MIB": 1 << 20
        case "GB": 1_000_000_000
        case "GIB": 1 << 30
        default: 1
        }
        let (bytes, overflow) = number.multipliedReportingOverflow(by: multiplier)
        guard !overflow else { throw VolumeSizeError.outOfRange }
        try self.init(bytes: bytes)
    }
}

public enum VolumeSizeError: Error, Equatable, Sendable { case invalidSyntax, outOfRange }

public struct CreationOptionCapabilities: Codable, Hashable, Sendable {
    public let compressionLevels: Set<CompressionLevel>
    public let methods: Set<CompressionMethod>
    public let dictionarySizes: Set<UInt64>
    public let wordSizes: Set<Int>
    public let supportsSolid: Bool
    public let supportsThreadCount: Bool
    public let supportsHeaderEncryption: Bool
    public let supportsVolumes: Bool

    public init(compressionLevels: Set<CompressionLevel> = [], methods: Set<CompressionMethod> = [],
                dictionarySizes: Set<UInt64> = [], wordSizes: Set<Int> = [], supportsSolid: Bool = false,
                supportsThreadCount: Bool = false, supportsHeaderEncryption: Bool = false,
                supportsVolumes: Bool = false) {
        self.compressionLevels = compressionLevels; self.methods = methods
        self.dictionarySizes = dictionarySizes; self.wordSizes = wordSizes
        self.supportsSolid = supportsSolid; self.supportsThreadCount = supportsThreadCount
        self.supportsHeaderEncryption = supportsHeaderEncryption; self.supportsVolumes = supportsVolumes
    }
}
