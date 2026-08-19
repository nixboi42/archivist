import Foundation

public struct FinderCapabilityStore: Sendable {
    public let url: URL
    public init(containerURL: URL) { url = containerURL.appendingPathComponent("finder-capabilities.json") }
    public func load(maximumAge: TimeInterval = 24 * 60 * 60, now: Date = Date()) -> FinderCapabilitySnapshot? {
        guard let value = try? JSONDecoder().decode(FinderCapabilitySnapshot.self, from: Data(contentsOf: url)),
              now.timeIntervalSince(value.generatedAt) >= 0,
              now.timeIntervalSince(value.generatedAt) <= maximumAge else { return nil }
        return value
    }
    public func save(_ snapshot: FinderCapabilitySnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}
