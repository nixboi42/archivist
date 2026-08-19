import Domain

public enum BackendKind: String, Codable, Hashable, Sendable { case sevenZip, libarchive, xipStack, externalRAR, custom }

/// The single capability policy consumed by concrete backends and, later, BackendRegistry.
public enum AuthoritativeCapabilities {
    private static let allLevels = Set(CompressionLevel.allCases)
    private static let streamLevels: Set<CompressionLevel> = [.store, .fastest, .fast, .normal, .maximum, .ultra]
    private static let sevenZipDictionaries: Set<UInt64> = [1 << 20, 4 << 20, 16 << 20, 32 << 20, 64 << 20, 128 << 20, 256 << 20]
    private static let zipDictionaries: Set<UInt64> = [32 << 10, 64 << 10, 256 << 10, 1 << 20]
    public static func capabilities(for format: ArchiveFormat, backend: BackendKind) -> ArchiveCapabilities {
        switch backend {
        case .sevenZip:
            switch format {
            case .sevenZip:
                return .init(operations: [.read, .list, .extract, .create, .test],
                    encryptionRead: .init(algorithms: [.sevenZipAES256], supportsHeaderEncryption: true),
                    encryptionCreate: .init(algorithms: [.sevenZipAES256], supportsHeaderEncryption: true),
                    supportsSolidArchives: true, supportsMultiVolume: true, supportsUnixMetadata: true, supportsRandomAccess: true,
                    creationOptions: .init(compressionLevels: allLevels,
                        methods: [.copy, .lzma2, .lzma, .ppmd, .bzip2], dictionarySizes: sevenZipDictionaries,
                        wordSizes: [32, 64, 128, 273], supportsSolid: true, supportsThreadCount: true,
                        supportsHeaderEncryption: true, supportsVolumes: true))
            case .zip:
                return .init(operations: [.read, .list, .extract, .create, .test],
                    encryptionRead: .init(algorithms: [.zipCrypto, .aes256]), encryptionCreate: .init(algorithms: [.zipCrypto, .aes256]),
                    supportsMultiVolume: true, supportsUnixMetadata: true, supportsRandomAccess: true,
                    creationOptions: .init(compressionLevels: allLevels,
                        methods: [.copy, .deflate, .deflate64, .bzip2, .lzma, .ppmd], dictionarySizes: zipDictionaries,
                        wordSizes: [32, 64, 128, 258], supportsThreadCount: true, supportsVolumes: true))
            case .rar, .cab, .arj:
                return .init(operations: [.read, .list, .extract, .test], encryptionRead: format == .rar ? .init(algorithms: [.aes256]) : nil,
                    supportsMultiVolume: format == .rar, supportsRandomAccess: true)
            default: return .unsupported
            }
        case .libarchive:
            switch format {
            case .tar, .cpio:
                return .init(operations: [.read, .list, .extract, .create, .test], supportsUnixMetadata: true,
                             requiresSequentialScan: true, creationOptions: .init())
            case .tarGzip:
                return .init(operations: [.read, .list, .extract, .create, .test], supportsUnixMetadata: true,
                    requiresSequentialScan: true, creationOptions: .init(compressionLevels: streamLevels))
            case .tarBzip2:
                return .init(operations: [.read, .list, .extract, .create, .test], supportsUnixMetadata: true,
                    requiresSequentialScan: true, creationOptions: .init(compressionLevels: [.fastest, .fast, .normal, .maximum, .ultra]))
            case .tarXZ:
                return .init(operations: [.read, .list, .extract, .create, .test], supportsUnixMetadata: true,
                    requiresSequentialScan: true, creationOptions: .init(compressionLevels: streamLevels, supportsThreadCount: true))
            case .gzip:
                return .init(operations: [.read, .extract, .create, .test], requiresSequentialScan: true,
                    creationOptions: .init(compressionLevels: streamLevels))
            case .bzip2:
                return .init(operations: [.read, .extract, .create, .test], requiresSequentialScan: true,
                    creationOptions: .init(compressionLevels: [.fastest, .fast, .normal, .maximum, .ultra]))
            case .xz:
                return .init(operations: [.read, .extract, .create, .test], requiresSequentialScan: true,
                    creationOptions: .init(compressionLevels: streamLevels, supportsThreadCount: true))
            default: return .unsupported
            }
        case .xipStack:
            switch format {
            case .xip: return .init(operations: [.read, .list, .extract, .test], supportsUnixMetadata: true, requiresSequentialScan: true)
            case .appleArchive: return .init(operations: [.read, .list, .extract, .test], supportsUnixMetadata: true, requiresSequentialScan: true)
            case .xar: return .init(operations: [.read, .list, .extract, .test], supportsUnixMetadata: true, supportsRandomAccess: true)
            default: return .unsupported
            }
        case .externalRAR:
            return format == .rar ? .init(operations: [.create]) : .unsupported
        case .custom:
            return .unsupported
        }
    }
}
