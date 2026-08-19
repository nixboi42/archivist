import Foundation

public enum ArchiveEntryKind: String, Codable, Hashable, Sendable {
    case regularFile, directory, symbolicLink, hardLink, blockDevice, characterDevice, fifo, socket, unknown
}

public struct ArchiveEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let kind: ArchiveEntryKind
    public let uncompressedSize: UInt64?
    public let compressedSize: UInt64?
    public let modificationDate: Date?
    public let creationDate: Date?
    public let posixMode: UInt16?
    public let ownerID: UInt32?
    public let groupID: UInt32?
    public let linkTarget: String?
    public let checksum: String?
    public let isEncrypted: Bool

    public init(id: String? = nil, path: String, kind: ArchiveEntryKind,
                uncompressedSize: UInt64? = nil, compressedSize: UInt64? = nil,
                modificationDate: Date? = nil, creationDate: Date? = nil,
                posixMode: UInt16? = nil, ownerID: UInt32? = nil, groupID: UInt32? = nil,
                linkTarget: String? = nil, checksum: String? = nil, isEncrypted: Bool = false) {
        self.id = id ?? path
        self.path = path
        self.kind = kind
        self.uncompressedSize = uncompressedSize
        self.compressedSize = compressedSize
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.posixMode = posixMode
        self.ownerID = ownerID
        self.groupID = groupID
        self.linkTarget = linkTarget
        self.checksum = checksum
        self.isEncrypted = isEncrypted
    }
}
