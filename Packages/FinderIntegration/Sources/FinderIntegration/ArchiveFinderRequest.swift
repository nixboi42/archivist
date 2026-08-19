import Foundation

public enum FinderArchiveAction: String, Codable, CaseIterable, Hashable, Sendable {
    case openArchive, extractHere, extractTo, extractToNamed
    case createSevenZip, createZIP, createArchive
}

public struct ArchiveFinderRequest: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let action: FinderArchiveAction
    public let urls: [URL]
    public let createdAt: Date

    public init(id: UUID = UUID(), action: FinderArchiveAction, urls: [URL], createdAt: Date = Date()) {
        self.id = id; self.action = action; self.urls = urls; self.createdAt = createdAt
    }
}

public enum FinderRequestError: Error, Equatable, Sendable {
    case invalidIdentifier, invalidStorageRoot, missingRequest, malformedRequest, expiredRequest
    case invalidURLCount, nonFileURL, identifierMismatch, replayedRequest
}
