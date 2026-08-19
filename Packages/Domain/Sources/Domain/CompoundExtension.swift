public enum CompoundExtension: String, CaseIterable, Hashable, Sendable, Codable {
    case tarGzip = "tar.gz"
    case tgz
    case tarBzip2 = "tar.bz2"
    case tbz2
    case tbz
    case tarXZ = "tar.xz"
    case txz
    case tarZstandard = "tar.zst"
    case tarZstandardLong = "tar.zstd"
    case tzst

    public var format: ArchiveFormat {
        switch self {
        case .tarGzip, .tgz: .tarGzip
        case .tarBzip2, .tbz2, .tbz: .tarBzip2
        case .tarXZ, .txz: .tarXZ
        case .tarZstandard, .tarZstandardLong, .tzst: .tarZstandard
        }
    }

    public static func detect(in filename: String) -> CompoundExtension? {
        let lowercased = filename.lowercased()
        return allCases
            .sorted { $0.rawValue.count > $1.rawValue.count }
            .first { lowercased.hasSuffix(".\($0.rawValue.lowercased())") }
    }
}

public extension ArchiveFormat {
    static func extensionFallback(for filename: String) -> ArchiveFormat {
        if let compound = CompoundExtension.detect(in: filename) { return compound.format }
        let suffix = filename.split(separator: ".").last?.lowercased() ?? ""
        return switch suffix {
        case "7z": .sevenZip
        case "zip": .zip(.zip)
        case "jar": .zip(.jar)
        case "apk": .zip(.apk)
        case "epub": .zip(.epub)
        case "rar", "r00": .rar
        case "tar": .tar
        case "gz", "gzip": .gzip
        case "bz2", "bzip2": .bzip2
        case "xz": .xz
        case "lzma": .lzma
        case "lz": .lzip
        case "z": .unixCompress
        case "zst", "zstd": .zstandard
        case "cab": .cab
        case "cpio": .cpio
        case "arj": .arj
        case "iso": .iso9660
        case "xar": .xar
        case "xip": .xip
        case "aar": .appleArchive
        default: .unknown
        }
    }
}
