import BackendProtocol
import Domain
import Foundation

public enum SevenZipCommand: Sendable { case list(URL), extract(URL, URL, [String]?), create([URL], URL, CreationOptions), test(URL) }

public struct SevenZipArguments: Sendable, CustomStringConvertible {
    public let values: [String]
    public let requiresCredentialPrompt: Bool
    public var description: String { values.map { $0.hasPrefix("-p") ? "-p<redacted>" : $0 }.joined(separator: " ") }
}

public struct SevenZipArgumentBuilder: Sendable {
    public init() {}
    public func build(_ command: SevenZipCommand, hasCredential: Bool = false) throws -> SevenZipArguments {
        switch command {
        case .list(let archive):
            return .init(values: ["l", "-slt", "--", archive.path], requiresCredentialPrompt: hasCredential)
        case .test(let archive):
            return .init(values: ["t", "-bsp1", "-bb1", "--", archive.path], requiresCredentialPrompt: hasCredential)
        case .extract(let archive, let destination, let selected):
            var values = ["x", "-y", "-bsp1", "-bb1", "-o\(destination.path)", "--", archive.path]
            values.append(contentsOf: selected ?? [])
            return .init(values: values, requiresCredentialPrompt: hasCredential)
        case .create(let sources, let destination, let options):
            guard options.format == .sevenZip || options.format == .zip(.zip) else {
                throw ArchiveBackendError(.unsupportedOperation, backendIdentifier: "7zz", operation: .create, message: "7zz creation is disabled for this format")
            }
            guard let capabilities = AuthoritativeCapabilities.capabilities(for: options.format, backend: .sevenZip).creationOptions else {
                throw ArchiveBackendError(.unsupportedOperation, backendIdentifier: "7zz", operation: .create,
                                          message: "Creation options are not verified for this format")
            }
            do { try options.validate(against: capabilities) }
            catch { throw ArchiveBackendError(.unsupportedOperation, backendIdentifier: "7zz", operation: .create,
                                              message: "Unsupported creation option combination") }
            var values = ["a", options.format == .sevenZip ? "-t7z" : "-tzip", "-bsp1", "-bb1"]
            if let level = options.compressionLevel { values.append("-mx=\(level.sevenZipValue)") }
            if let method = options.method { values.append("-m0=\(method.sevenZipName)") }
            if let dictionary = options.dictionarySize { values.append("-md=\(dictionary)b") }
            if let wordSize = options.wordSize { values.append("-mfb=\(wordSize)") }
            if options.format == .sevenZip {
                switch options.solidMode { case .automatic: break; case .off: values.append("-ms=off"); case .on: values.append("-ms=on") }
            }
            if case .explicit(let count) = options.threads { values.append("-mmt=\(count)") }
            if hasCredential { values.append("-p"); if options.encryptFileNames { values.append("-mhe=on") } }
            if let volume = options.volumeSize { values.append("-v\(volume.bytes)b") }
            values += ["--", destination.path]; values += sources.map(\.path)
            return .init(values: values, requiresCredentialPrompt: hasCredential)
        }
    }
}

private extension CompressionLevel {
    var sevenZipValue: Int { switch self { case .store: 0; case .fastest: 1; case .fast: 3; case .normal: 5; case .maximum: 7; case .ultra: 9 } }
}

private extension CompressionMethod {
    var sevenZipName: String { switch self {
    case .copy: "Copy"; case .lzma2: "LZMA2"; case .lzma: "LZMA"; case .ppmd: "PPMd"
    case .deflate: "Deflate"; case .deflate64: "Deflate64"; case .bzip2: "BZip2"
    } }
}
