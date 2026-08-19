import BackendProtocol
import Domain
import Foundation

public enum BackendAvailability: Codable, Hashable, Sendable {
    case available
    case degraded(reason: String)
    case unavailable(reason: String)

    public var canSelect: Bool {
        switch self { case .available, .degraded: true; case .unavailable: false }
    }
}

public struct BackendStatus: Codable, Hashable, Sendable {
    public let identifier: BackendIdentifier
    public let kind: BackendKind
    public let availability: BackendAvailability
}

public enum BackendSelectionMode: Sendable { case allowFallback, preferredOnly }

public struct BackendSelection: Sendable {
    public let backend: any ArchiveBackend
    public let capabilities: ArchiveCapabilities
    public let usedFallback: Bool
}
