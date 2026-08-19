public enum ZIPSemanticKind: String, Codable, CaseIterable, Hashable, Sendable {
    case zip, jar, apk, epub
}

public enum ArchiveFormat: Hashable, Sendable, Codable {
    case sevenZip
    case zip(ZIPSemanticKind)
    case rar
    case tar
    case tarGzip
    case tarBzip2
    case tarXZ
    case tarZstandard
    case gzip
    case bzip2
    case xz
    case lzma
    case lzip
    case unixCompress
    case zstandard
    case cab
    case cpio
    case arj
    case iso9660
    case xar
    case xip
    case appleArchive
    case unknown

    public var canonicalExtension: String? {
        switch self {
        case .sevenZip: "7z"
        case .zip(let kind): kind.rawValue
        case .rar: "rar"
        case .tar: "tar"
        case .tarGzip: "tar.gz"
        case .tarBzip2: "tar.bz2"
        case .tarXZ: "tar.xz"
        case .tarZstandard: "tar.zst"
        case .gzip: "gz"
        case .bzip2: "bz2"
        case .xz: "xz"
        case .lzma: "lzma"
        case .lzip: "lz"
        case .unixCompress: "Z"
        case .zstandard: "zst"
        case .cab: "cab"
        case .cpio: "cpio"
        case .arj: "arj"
        case .iso9660: "iso"
        case .xar: "xar"
        case .xip: "xip"
        case .appleArchive: "aar"
        case .unknown: nil
        }
    }

    public var isArchiveContainer: Bool {
        switch self {
        case .gzip, .bzip2, .xz, .lzma, .lzip, .unixCompress, .zstandard, .unknown: false
        default: true
        }
    }
}
