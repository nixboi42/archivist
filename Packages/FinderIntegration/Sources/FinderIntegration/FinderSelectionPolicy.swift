import Domain
import Foundation

public struct FinderCapabilitySnapshot: Codable, Hashable, Sendable {
    public let readableFormats: Set<ArchiveFormat>
    public let canCreateSevenZip: Bool
    public let canCreateZIP: Bool
    public let generatedAt: Date
    public init(readableFormats: Set<ArchiveFormat>, canCreateSevenZip: Bool, canCreateZIP: Bool, generatedAt: Date = Date()) {
        self.readableFormats = readableFormats; self.canCreateSevenZip = canCreateSevenZip
        self.canCreateZIP = canCreateZIP; self.generatedAt = generatedAt
    }
}

public struct FinderSelectionPolicy: Sendable {
    public init() {}
    public func actions(
        for urls: [URL],
        snapshot: FinderCapabilitySnapshot?,
        developmentCreationShortcuts: Bool = false
    ) -> [FinderArchiveAction] {
        guard !urls.isEmpty else { return [] }
        let multipart = urls.map { MultipartArchiveName.parse($0.lastPathComponent) }
        guard multipart.allSatisfy({ $0 == nil || $0?.isFirstVolume == true }) else { return [] }
        let formats = zip(urls, multipart).map { url, volume in
            volume?.format ?? ArchiveFormat.extensionFallback(for: url.lastPathComponent)
        }
        let archiveFlags = formats.map { $0 != .unknown && (snapshot?.readableFormats.contains($0) ?? conservativeReadable.contains($0)) }
        if archiveFlags.allSatisfy({ $0 }) {
            return urls.count == 1 ? [.openArchive, .extractHere, .extractTo, .extractToNamed] : [.extractHere, .extractToNamed]
        }
        if archiveFlags.allSatisfy({ !$0 }) && formats.allSatisfy({ $0 == .unknown }) {
            var result: [FinderArchiveAction] = []
            if snapshot?.canCreateSevenZip == true || developmentCreationShortcuts { result.append(.createSevenZip) }
            if snapshot?.canCreateZIP == true || developmentCreationShortcuts { result.append(.createZIP) }
            result.append(.createArchive)
            return result
        }
        return []
    }

    private let conservativeReadable: Set<ArchiveFormat> = [
        .sevenZip, .zip(.zip), .zip(.jar), .zip(.apk), .zip(.epub), .rar, .tar, .tarGzip,
        .tarBzip2, .tarXZ, .gzip, .bzip2, .xz, .cpio, .cab, .arj, .xar, .xip, .appleArchive
    ]
}

public enum FinderDestinationPolicy {
    public static func extractHere(for archive: URL) -> URL { archive.deletingLastPathComponent() }
    public static func extractToNamedDirectory(for archive: URL) -> URL {
        let filename = archive.lastPathComponent
        if let multipart = MultipartArchiveName.parse(filename) {
            return archive.deletingLastPathComponent().appendingPathComponent(
                String(multipart.baseFilename.dropLast((multipart.format.canonicalExtension?.count ?? 0) + 1)), isDirectory: true)
        }
        let stem: String
        if let compound = CompoundExtension.detect(in: filename) {
            stem = String(filename.dropLast(compound.rawValue.count + 1))
        } else if !archive.pathExtension.isEmpty {
            stem = archive.deletingPathExtension().lastPathComponent
        } else { stem = filename }
        return archive.deletingLastPathComponent().appendingPathComponent(stem, isDirectory: true)
    }
}
