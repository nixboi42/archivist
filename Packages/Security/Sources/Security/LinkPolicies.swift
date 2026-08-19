import Domain

public struct ValidatedLinkTarget: Codable, Hashable, Sendable { public let path: ValidatedRelativePath }

public struct SymlinkPolicy: Sendable {
    private let validator = PathValidator()
    public init() {}
    // Invariant B: the target resolves lexically inside the archive namespace.
    public func validate(target: String, symlinkPath: ValidatedRelativePath, policy: SecurityPolicy = .secureDefault) throws -> ValidatedLinkTarget {
        let parent = symlinkPath.components.dropLast().joined(separator: "/")
        let combined = parent.isEmpty ? target : parent + "/" + target
        do { return .init(path: try validator.validate(combined, policy: policy)) }
        catch { throw ArchiveSecurityError(.unsafeSymlink, level: policy.restrictUnsafeSymlinks ? .policy : .hardSafety, entryPath: symlinkPath.string) }
    }
}

public struct HardlinkDecision: Codable, Hashable, Sendable {
    public let target: ValidatedRelativePath
    public let requiresDeferredMaterialization: Bool
}

public struct HardlinkPolicy: Sendable {
    private let validator = PathValidator()
    public init() {}
    public func validate(target: String, knownPaths: Set<ValidatedRelativePath>, policy: SecurityPolicy = .secureDefault) throws -> HardlinkDecision {
        do {
            let path = try validator.validate(target, policy: policy)
            return .init(target: path, requiresDeferredMaterialization: !knownPaths.contains(path))
        } catch { throw ArchiveSecurityError(.unsafeHardlink, level: policy.restrictUnsafeHardlinks ? .policy : .hardSafety, entryPath: target) }
    }
}
