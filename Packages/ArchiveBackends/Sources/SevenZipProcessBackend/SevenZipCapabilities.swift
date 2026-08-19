import BackendProtocol
import Domain

public enum SevenZipCapabilities {
    public static func capabilities(for format: ArchiveFormat) -> ArchiveCapabilities {
        AuthoritativeCapabilities.capabilities(for: format, backend: .sevenZip)
    }
}
