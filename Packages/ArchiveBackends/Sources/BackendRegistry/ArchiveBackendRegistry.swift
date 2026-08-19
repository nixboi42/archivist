import ArchiveDomainServices
import BackendProtocol
import Domain
import Foundation

private struct Registration: Sendable {
    let identifier: BackendIdentifier
    let kind: BackendKind
    let backend: (any ArchiveBackend)?
    var availability: BackendAvailability

    func capabilities(for format: ArchiveFormat) -> ArchiveCapabilities {
        if kind == .custom { return backend?.capabilities(for: format) ?? .unsupported }
        let policy = AuthoritativeCapabilities.capabilities(for: format, backend: kind)
        guard let backend else { return policy }
        // Runtime probes may only narrow the authoritative contract.
        let runtime = backend.capabilities(for: format)
        return .init(operations: policy.operations.intersection(runtime.operations),
                     encryptionRead: policy.encryptionRead, encryptionCreate: policy.encryptionCreate,
                     supportsSolidArchives: policy.supportsSolidArchives && runtime.supportsSolidArchives,
                     supportsMultiVolume: policy.supportsMultiVolume && runtime.supportsMultiVolume,
                     supportsUnixMetadata: policy.supportsUnixMetadata && runtime.supportsUnixMetadata,
                     supportsExtendedAttributes: policy.supportsExtendedAttributes && runtime.supportsExtendedAttributes,
                     supportsRandomAccess: policy.supportsRandomAccess && runtime.supportsRandomAccess,
                     requiresSequentialScan: policy.requiresSequentialScan || runtime.requiresSequentialScan,
                     creationOptions: policy.creationOptions)
    }
}

public actor ArchiveBackendRegistry {
    private var registrations: [BackendIdentifier: Registration] = [:]
    private let preferences: BackendPreferencePolicy
    private let detector: FormatDetector

    public init(preferences: BackendPreferencePolicy = .init(), detector: FormatDetector = .init()) {
        self.preferences = preferences; self.detector = detector
    }

    public func register(_ backend: any ArchiveBackend, kind: BackendKind,
                         availability: BackendAvailability = .available) {
        registrations[backend.identifier] = .init(identifier: backend.identifier, kind: kind,
                                                   backend: backend, availability: availability)
    }

    public func registerUnavailable(identifier: BackendIdentifier, kind: BackendKind, reason: String) {
        registrations[identifier] = .init(identifier: identifier, kind: kind, backend: nil,
                                           availability: .unavailable(reason: reason))
    }

    public func updateAvailability(of identifier: BackendIdentifier, to availability: BackendAvailability) throws {
        guard var registration = registrations[identifier] else {
            throw ArchiveBackendError(.backendUnavailable, backendIdentifier: identifier.rawValue,
                                      message: "Backend is not registered", diagnosticCode: "BACKEND_NOT_REGISTERED")
        }
        registration.availability = availability; registrations[identifier] = registration
    }

    public func unregister(_ identifier: BackendIdentifier) { registrations.removeValue(forKey: identifier) }

    public func statuses() -> [BackendStatus] {
        registrations.values.map { .init(identifier: $0.identifier, kind: $0.kind, availability: $0.availability) }
            .sorted { $0.identifier.rawValue < $1.identifier.rawValue }
    }

    public func detectAndSelect(for url: URL, operation: ArchiveOperation,
                                mode: BackendSelectionMode = .allowFallback) throws -> (FormatDetectionResult, BackendSelection) {
        let detection = try detector.detect(url: url)
        return (detection, try select(format: detection.format, operation: operation, mode: mode))
    }

    public func select(format: ArchiveFormat, operation: ArchiveOperation,
                       mode: BackendSelectionMode = .allowFallback) throws -> BackendSelection {
        guard format != .unknown else { throw failure(.unsupportedFormat, format, operation, "Archive format is unknown") }
        let preferred = preferences.identifiers(for: format, operation: operation)
        let capable = registrations.values.filter { $0.capabilities(for: format).supports(operation) }
        guard !capable.isEmpty else { throw failure(.unsupportedOperation, format, operation, "No registered backend supports this operation") }

        let ranked = capable.sorted { lhs, rhs in
            let left = preferred.firstIndex(of: lhs.identifier) ?? Int.max
            let right = preferred.firstIndex(of: rhs.identifier) ?? Int.max
            return left == right ? lhs.identifier.rawValue < rhs.identifier.rawValue : left < right
        }
        guard let primary = ranked.first else { throw failure(.unsupportedOperation, format, operation, "No capable backend") }
        if mode == .preferredOnly, !primary.availability.canSelect {
            throw failure(.preferredBackendUnavailable, format, operation,
                          "Preferred backend \(primary.identifier.rawValue) is unavailable", backend: primary.identifier)
        }
        guard let selected = ranked.first(where: { $0.availability.canSelect && $0.backend != nil }), let backend = selected.backend else {
            throw failure(.noAvailableBackend, format, operation, "All capable backends are unavailable")
        }
        return .init(backend: backend, capabilities: selected.capabilities(for: format), usedFallback: selected.identifier != primary.identifier)
    }

    private func failure(_ code: ArchiveBackendError.Code, _ format: ArchiveFormat, _ operation: ArchiveOperation,
                         _ message: String, backend: BackendIdentifier? = nil) -> ArchiveBackendError {
        .init(code, backendIdentifier: backend?.rawValue, operation: operation,
              message: "\(message) [format=\(format)]", diagnosticCode: "REGISTRY_\(code.rawValue.uppercased())")
    }
}
