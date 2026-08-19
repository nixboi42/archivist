import CLibarchiveShim
import Domain

public struct LibarchiveFormatProfile: Equatable, Sendable {
    public let format: ArchiveFormat
    public let cProfile: LAProfile
    public let standaloneStream: Bool
    public let writable: Bool

    public static func profile(for format: ArchiveFormat) -> Self? {
        switch format {
        case .tar: .init(format: format, cProfile: LA_TAR, standaloneStream: false, writable: true)
        case .tarGzip: .init(format: format, cProfile: LA_TAR_GZIP, standaloneStream: false, writable: true)
        case .tarBzip2: .init(format: format, cProfile: LA_TAR_BZIP2, standaloneStream: false, writable: true)
        case .tarXZ: .init(format: format, cProfile: LA_TAR_XZ, standaloneStream: false, writable: true)
        case .tarZstandard: .init(format: format, cProfile: LA_TAR_ZSTD, standaloneStream: false, writable: true)
        case .cpio: .init(format: format, cProfile: LA_CPIO, standaloneStream: false, writable: true)
        case .gzip: .init(format: format, cProfile: LA_GZIP, standaloneStream: true, writable: true)
        case .bzip2: .init(format: format, cProfile: LA_BZIP2, standaloneStream: true, writable: true)
        case .xz: .init(format: format, cProfile: LA_XZ, standaloneStream: true, writable: true)
        case .iso9660: .init(format: format, cProfile: LA_ISO, standaloneStream: false, writable: false)
        default: nil
        }
    }
}
