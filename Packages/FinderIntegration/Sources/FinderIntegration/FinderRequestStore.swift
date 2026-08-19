import Foundation
import Darwin

public struct FinderRequestStore: Sendable {
    public static let appGroupIdentifier = "group.J6UMA79JLS.com.archivist.shared"
    public static let activationScheme = "archivist"
    public let rootURL: URL
    public let maximumAge: TimeInterval
    public let maximumURLCount: Int

    public init(rootURL: URL, maximumAge: TimeInterval = 5 * 60, maximumURLCount: Int = 128) {
        self.rootURL = rootURL.standardizedFileURL; self.maximumAge = maximumAge; self.maximumURLCount = maximumURLCount
    }

    public static func appGroupStore(fileManager: FileManager = .default) throws -> FinderRequestStore {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw FinderRequestError.invalidStorageRoot
        }
        return .init(rootURL: container.appendingPathComponent("FinderRequests", isDirectory: true))
    }

    @discardableResult
    public func write(_ request: ArchiveFinderRequest) throws -> URL {
        try FinderRequestValidator(maximumAge: maximumAge, maximumURLCount: maximumURLCount).validate(request)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let destination = requestURL(request.id)
        let temporary = rootURL.appendingPathComponent(".\(request.id.uuidString).tmp")
        let data = try JSONEncoder().encode(request)
        do {
            try data.write(to: temporary, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            if rename(temporary.path, destination.path) != 0 { throw CocoaError(.fileWriteUnknown) }
            return destination
        } catch { try? FileManager.default.removeItem(at: temporary); throw error }
    }

    public func consume(id: UUID, now: Date = Date()) throws -> ArchiveFinderRequest {
        let url = requestURL(id)
        let parentPath = url.deletingLastPathComponent().standardizedFileURL.path
        guard parentPath == rootURL.standardizedFileURL.path else { throw FinderRequestError.invalidStorageRoot }
        guard FileManager.default.fileExists(atPath: url.path) else { throw FinderRequestError.missingRequest }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 256 * 1024 else {
            throw FinderRequestError.malformedRequest
        }
        let consumed = rootURL.appendingPathComponent(".consumed-\(id.uuidString)")
        guard rename(url.path, consumed.path) == 0 else { throw FinderRequestError.replayedRequest }
        defer { try? FileManager.default.removeItem(at: consumed) }
        let request: ArchiveFinderRequest
        do { request = try JSONDecoder().decode(ArchiveFinderRequest.self, from: Data(contentsOf: consumed)) }
        catch { throw FinderRequestError.malformedRequest }
        guard request.id == id else { throw FinderRequestError.identifierMismatch }
        try FinderRequestValidator(maximumAge: maximumAge, maximumURLCount: maximumURLCount).validate(request, now: now)
        return request
    }

    public func activationURL(for id: UUID) -> URL {
        URL(string: "\(Self.activationScheme)://finder-request/\(id.uuidString)")!
    }

    public func requestIdentifier(from activationURL: URL) throws -> UUID {
        guard activationURL.scheme == Self.activationScheme, activationURL.host == "finder-request",
              activationURL.pathComponents.count == 2,
              let id = UUID(uuidString: activationURL.lastPathComponent) else {
            throw FinderRequestError.invalidIdentifier
        }
        return id
    }

    private func requestURL(_ id: UUID) -> URL { rootURL.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}

public struct FinderRequestValidator: Sendable {
    public let maximumAge: TimeInterval
    public let maximumURLCount: Int

    public init(maximumAge: TimeInterval = 5 * 60, maximumURLCount: Int = 128) {
        self.maximumAge = maximumAge; self.maximumURLCount = maximumURLCount
    }

    public func validate(_ request: ArchiveFinderRequest, now: Date = Date()) throws {
        guard !request.urls.isEmpty, request.urls.count <= maximumURLCount else { throw FinderRequestError.invalidURLCount }
        if request.action == .openArchive || request.action == .extractTo {
            guard request.urls.count == 1 else { throw FinderRequestError.invalidURLCount }
        }
        guard request.urls.allSatisfy(\.isFileURL) else { throw FinderRequestError.nonFileURL }
        guard now.timeIntervalSince(request.createdAt) >= -30,
              now.timeIntervalSince(request.createdAt) <= maximumAge else { throw FinderRequestError.expiredRequest }
    }
}
