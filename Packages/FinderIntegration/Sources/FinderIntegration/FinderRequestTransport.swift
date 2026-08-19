import Foundation

public protocol FinderRequestTransport: Sendable {
    func submit(_ request: ArchiveFinderRequest) async throws -> URL
    func receive(from activationURL: URL, now: Date) async throws -> ArchiveFinderRequest
}

public extension FinderRequestTransport {
    func receive(from activationURL: URL) async throws -> ArchiveFinderRequest {
        try await receive(from: activationURL, now: Date())
    }
}

public enum FinderRequestTransportMode: String, Codable, Sendable {
    case appGroup = "app-group"
    case personalTeamDevelopment = "personal-team-development"

    public var displayName: String {
        switch self {
        case .appGroup: "App Group"
        case .personalTeamDevelopment: "Personal Team Development Fallback"
        }
    }
}

public enum FinderRequestTransportConfiguration {
    public static let infoKey = "ArchivistFinderTransport"

    public static func mode(bundle: Bundle) throws -> FinderRequestTransportMode {
        guard let raw = bundle.object(forInfoDictionaryKey: infoKey) as? String,
              let mode = FinderRequestTransportMode(rawValue: raw) else {
            throw FinderRequestError.invalidStorageRoot
        }
        return mode
    }

    public static func make(bundle: Bundle) throws -> any FinderRequestTransport {
        switch try mode(bundle: bundle) {
        case .appGroup: AppGroupFinderRequestTransport()
        case .personalTeamDevelopment: PersonalTeamDevelopmentTransport()
        }
    }
}

public enum FinderRequestBuildGuard {
    public static func validate(mode: FinderRequestTransportMode, configuration: String) throws {
        if configuration.caseInsensitiveCompare("Release") == .orderedSame,
           mode == .personalTeamDevelopment {
            throw FinderRequestError.invalidStorageRoot
        }
    }
}

public struct AppGroupFinderRequestTransport: FinderRequestTransport {
    public init() {}

    public func submit(_ request: ArchiveFinderRequest) async throws -> URL {
        let store = try FinderRequestStore.appGroupStore()
        try store.write(request)
        return store.activationURL(for: request.id)
    }

    public func receive(from activationURL: URL, now: Date) async throws -> ArchiveFinderRequest {
        let store = try FinderRequestStore.appGroupStore()
        return try store.consume(id: store.requestIdentifier(from: activationURL), now: now)
    }
}

/// Explicitly local-development-only transport. The bounded request is carried in the custom URL
/// because a sandboxed Personal Team extension has no provisioned shared container or Mach service.
public struct PersonalTeamDevelopmentTransport: FinderRequestTransport {
    public static let activationHost = "finder-dev-request"
    public static let maximumPayloadBytes = 32 * 1024
    private let validator: FinderRequestValidator

    public init(maximumAge: TimeInterval = 5 * 60, maximumURLCount: Int = 32) {
        validator = .init(maximumAge: maximumAge, maximumURLCount: maximumURLCount)
    }

    public func submit(_ request: ArchiveFinderRequest) async throws -> URL {
        try validator.validate(request)
        let data = try JSONEncoder().encode(request)
        guard data.count <= Self.maximumPayloadBytes else { throw FinderRequestError.malformedRequest }
        let payload = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard let url = URL(string: "\(FinderRequestStore.activationScheme)://\(Self.activationHost)/\(request.id.uuidString)?payload=\(payload)") else {
            throw FinderRequestError.malformedRequest
        }
        return url
    }

    public func receive(from activationURL: URL, now: Date) async throws -> ArchiveFinderRequest {
        guard activationURL.scheme == FinderRequestStore.activationScheme,
              activationURL.host == Self.activationHost,
              activationURL.pathComponents.count == 2,
              let id = UUID(uuidString: activationURL.lastPathComponent),
              let components = URLComponents(url: activationURL, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == "payload" })?.value,
              encoded.count <= Self.maximumPayloadBytes * 2 else {
            throw FinderRequestError.invalidIdentifier
        }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), data.count <= Self.maximumPayloadBytes,
              let request = try? JSONDecoder().decode(ArchiveFinderRequest.self, from: data) else {
            throw FinderRequestError.malformedRequest
        }
        guard request.id == id else { throw FinderRequestError.identifierMismatch }
        try validator.validate(request, now: now)
        guard await PersonalTeamReplayRegistry.shared.consume(id, at: now) else {
            throw FinderRequestError.replayedRequest
        }
        return request
    }
}

private actor PersonalTeamReplayRegistry {
    static let shared = PersonalTeamReplayRegistry()
    private var consumed: [UUID: Date] = [:]

    func consume(_ id: UUID, at now: Date) -> Bool {
        consumed = consumed.filter { now.timeIntervalSince($0.value) <= 10 * 60 }
        guard consumed[id] == nil else { return false }
        consumed[id] = now
        return true
    }
}
