import Foundation
import Darwin

public struct MonitoredRootConfiguration: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var roots: [URL]
    public var allowExternalVolumes: Bool
    public init(enabled: Bool = true, roots: [URL] = Self.defaultRoots(), allowExternalVolumes: Bool = false) {
        self.enabled = enabled; self.roots = roots; self.allowExternalVolumes = allowExternalVolumes
    }
    public static func defaultRoots(fileManager: FileManager = .default) -> [URL] {
        [.desktopDirectory, .downloadsDirectory].compactMap { fileManager.urls(for: $0, in: .userDomainMask).first }
    }
}

/// Roots available to a Personal Team Finder extension without consulting App Group storage.
public enum PersonalTeamMonitoredRoots {
    public static func resolve(userHomeURL: URL? = currentUserHomeURL(), controlRoot: URL? = nil) -> [URL] {
        var roots = userHomeURL.map {
            [$0.appendingPathComponent("Desktop", isDirectory: true),
             $0.appendingPathComponent("Downloads", isDirectory: true)]
        } ?? []
        roots = roots.filter(\.isFileURL).map(\.standardizedFileURL)
        if let controlRoot, controlRoot.isFileURL {
            roots.append(controlRoot.standardizedFileURL)
        }
        return Array(Set(roots)).sorted { $0.path < $1.path }
    }

    /// POSIX account home remains the real user home when Foundation search paths are redirected
    /// into a sandbox container.
    public static func currentUserHomeURL() -> URL? {
        guard let record = getpwuid(getuid()), let directory = record.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true).standardizedFileURL
    }
}

public struct MonitoredRootStore: Sendable {
    public let url: URL
    public init(containerURL: URL) { url = containerURL.appendingPathComponent("monitored-roots.json") }
    public func load() -> MonitoredRootConfiguration {
        (try? JSONDecoder().decode(MonitoredRootConfiguration.self, from: Data(contentsOf: url))) ?? .init()
    }
    public func save(_ configuration: MonitoredRootConfiguration) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(configuration).write(to: url, options: .atomic)
    }
}
