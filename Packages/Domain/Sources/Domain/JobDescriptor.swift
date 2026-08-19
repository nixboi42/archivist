import Foundation

public enum JobKind: String, Codable, Hashable, Sendable { case browse, extract, create, test, modify }

public struct JobDescriptor: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: JobKind
    public let sourceURLs: [URL]
    public let destinationURL: URL?
    public let format: ArchiveFormat?
    public let createdAt: Date

    public init(id: UUID = UUID(), kind: JobKind, sourceURLs: [URL], destinationURL: URL? = nil,
                format: ArchiveFormat? = nil, createdAt: Date = Date()) {
        self.id = id
        self.kind = kind
        self.sourceURLs = sourceURLs
        self.destinationURL = destinationURL
        self.format = format
        self.createdAt = createdAt
    }
}
