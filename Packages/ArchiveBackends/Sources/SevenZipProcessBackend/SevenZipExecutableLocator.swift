import Domain
import Foundation

public enum SevenZipExecutableSource: Sendable { case bundled(Bundle), external(URL) }
public struct SevenZipExecutableLocator: Sendable {
    public let source: SevenZipExecutableSource
    public init(source: SevenZipExecutableSource = .bundled(.main)) { self.source = source }
    public func locate() throws -> URL {
        let url: URL
        switch source {
        case .external(let external): url = external
        case .bundled(let bundle): url = bundle.bundleURL.appendingPathComponent("Contents/Helpers/7zz")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ArchiveBackendError(.backendUnavailable, backendIdentifier: "7zz", message: "7zz executable is unavailable")
        }
        return url
    }
}
