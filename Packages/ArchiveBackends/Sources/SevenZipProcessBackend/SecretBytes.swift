import Foundation

public struct SecretBytes: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    private let storage: Data
    public init(_ value: String) { storage = Data(value.utf8) }
    public var description: String { "<redacted>" }
    public var debugDescription: String { "SecretBytes(<redacted>)" }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try storage.withUnsafeBytes(body) }
}
