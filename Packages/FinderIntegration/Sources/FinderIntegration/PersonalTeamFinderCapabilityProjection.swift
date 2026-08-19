import BackendProtocol
import Domain
import Foundation

/// Development-only Finder visibility derived directly from the registry's capability authority.
/// Runtime backend availability remains a definitive main-application decision.
public enum PersonalTeamFinderCapabilityProjection {
    public static let sourceName = "personal-team-authoritative-projection"

    public static func makeSnapshot(now: Date = Date()) -> FinderCapabilitySnapshot {
        let formats: [ArchiveFormat] = [
            .sevenZip, .zip(.zip), .zip(.jar), .zip(.apk), .zip(.epub), .rar,
            .tar, .tarGzip, .tarBzip2, .tarXZ, .gzip, .bzip2, .xz, .cpio,
            .cab, .arj, .xar, .xip, .appleArchive
        ]
        let implementedBackends: [BackendKind] = [.sevenZip, .libarchive, .xipStack]
        let readable = Set(formats.filter { format in
            implementedBackends.contains { AuthoritativeCapabilities.capabilities(for: format, backend: $0).supports(.read) }
        })
        return FinderCapabilitySnapshot(
            readableFormats: readable,
            canCreateSevenZip: AuthoritativeCapabilities.capabilities(for: .sevenZip, backend: .sevenZip).supports(.create),
            canCreateZIP: AuthoritativeCapabilities.capabilities(for: .zip(.zip), backend: .sevenZip).supports(.create),
            generatedAt: now
        )
    }

    public static func supportsCreation(of format: ArchiveFormat) -> Bool {
        [.sevenZip, .libarchive, .xipStack].contains {
            AuthoritativeCapabilities.capabilities(for: format, backend: $0).supports(.create)
        }
    }
}
