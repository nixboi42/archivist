import BackendRegistry
import Domain

public struct CreationFormatOption: Hashable, Sendable, Identifiable {
    public var id: ArchiveFormat { format }
    public let format: ArchiveFormat
    public let displayName: String
    public let capabilities: ArchiveCapabilities
}

public struct AvailableCreationFormatsUseCase: Sendable {
    private let registry: ArchiveBackendRegistry
    public init(registry: ArchiveBackendRegistry) { self.registry = registry }

    public func execute() async -> [CreationFormatOption] {
        var result: [CreationFormatOption] = []
        for (format, name) in Self.candidates {
            guard let selection = try? await registry.select(format: format, operation: .create) else { continue }
            result.append(.init(format: format, displayName: name, capabilities: selection.capabilities))
        }
        return result
    }

    private static let candidates: [(ArchiveFormat, String)] = [
        (.sevenZip, "7-Zip"), (.zip(.zip), "ZIP"), (.zip(.jar), "JAR"),
        (.zip(.apk), "APK"), (.zip(.epub), "EPUB"), (.tar, "TAR"),
        (.tarGzip, "Compressed TAR (gzip)"), (.tarBzip2, "Compressed TAR (bzip2)"),
        (.tarXZ, "Compressed TAR (XZ)"), (.cpio, "CPIO"), (.gzip, "Gzip"),
        (.bzip2, "Bzip2"), (.xz, "XZ")
    ]
}
