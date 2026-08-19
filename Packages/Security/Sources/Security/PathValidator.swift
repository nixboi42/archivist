import Domain
import Foundation

public struct ValidatedRelativePath: Codable, Hashable, Sendable, CustomStringConvertible {
    public let components: [String]
    public init(components: [String]) { self.components = components }
    public var string: String { components.joined(separator: "/") }
    public var description: String { string }
    public func appending(to root: URL) -> URL { components.reduce(root) { $0.appendingPathComponent($1, isDirectory: false) } }
}

public struct PathValidator: Sendable {
    public init() {}
    // Invariant A: accepted paths are nonempty, relative, and have no unresolved parent components.
    public func validate(_ raw: String, policy: SecurityPolicy = .secureDefault) throws -> ValidatedRelativePath {
        if raw.isEmpty || raw.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 0x20 && $0.value != 0x09) }) {
            throw ArchiveSecurityError(.invalidPath, level: .hardSafety, entryPath: raw)
        }
        let path = raw.replacingOccurrences(of: "\\", with: "/")
        if path.hasPrefix("/") || path.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) != nil {
            throw ArchiveSecurityError(.absolutePath, level: .hardSafety, entryPath: raw)
        }
        var result: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            if component == "." { continue }
            if component == ".." {
                guard !result.isEmpty else {
                    throw ArchiveSecurityError(.pathTraversal, level: policy.preventPathTraversal ? .policy : .hardSafety, entryPath: raw)
                }
                result.removeLast()
            } else { result.append(component.precomposedStringWithCanonicalMapping) }
        }
        guard !result.isEmpty else { throw ArchiveSecurityError(.invalidPath, level: .hardSafety, entryPath: raw) }
        return ValidatedRelativePath(components: result)
    }
}
