import Domain
import Foundation

public enum CLICommand: Equatable, Sendable {
    case list(archive: URL, passwordFromStandardInput: Bool)
    case extract(archive: URL, destination: URL, conflict: ConflictResolution, passwordFromStandardInput: Bool)
    case create(format: ArchiveFormat, destination: URL, sources: [URL], conflict: ConflictResolution,
                options: CLICreationOptions, passwordFromStandardInput: Bool)
    case test(archive: URL, passwordFromStandardInput: Bool)
    case help
}

public struct CLICreationOptions: Equatable, Sendable {
    public let level: CompressionLevel?
    public let method: CompressionMethod?
    public let dictionarySize: UInt64?
    public let wordSize: Int?
    public let threads: ThreadConfiguration
    public let solidMode: SolidMode
    public let encryptFileNames: Bool
    public let volumeSize: VolumeSize?
    public init(level: CompressionLevel? = nil, method: CompressionMethod? = nil,
                dictionarySize: UInt64? = nil, wordSize: Int? = nil,
                threads: ThreadConfiguration = .automatic, solidMode: SolidMode = .automatic,
                encryptFileNames: Bool = false, volumeSize: VolumeSize? = nil) {
        self.level = level; self.method = method; self.dictionarySize = dictionarySize; self.wordSize = wordSize
        self.threads = threads; self.solidMode = solidMode; self.encryptFileNames = encryptFileNames
        self.volumeSize = volumeSize
    }
}

public struct CLIParseError: Error, Equatable, Sendable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public struct CLIParser: Sendable {
    public init() {}

    public func parse(_ arguments: [String], currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> CLICommand {
        guard let verb = arguments.first else { return .help }
        if verb == "help" || verb == "--help" || verb == "-h" { return .help }
        var cursor = Cursor(Array(arguments.dropFirst()))
        switch verb {
        case "list":
            let archive = try cursor.path("archive", relativeTo: currentDirectory)
            let password = cursor.takeFlag("--password-stdin")
            try cursor.requireEnd()
            return .list(archive: archive, passwordFromStandardInput: password)
        case "test":
            let archive = try cursor.path("archive", relativeTo: currentDirectory)
            let password = cursor.takeFlag("--password-stdin")
            try cursor.requireEnd()
            return .test(archive: archive, passwordFromStandardInput: password)
        case "extract":
            let archive = try cursor.path("archive", relativeTo: currentDirectory)
            guard let destinationValue = cursor.takeOption("--destination") ?? cursor.takeOption("-d") else {
                throw CLIParseError("extract requires --destination <directory>")
            }
            let conflict = try parseConflict(cursor.takeOption("--conflict") ?? "ask")
            let password = cursor.takeFlag("--password-stdin")
            try cursor.requireEnd()
            return .extract(archive: archive, destination: resolve(destinationValue, against: currentDirectory),
                            conflict: conflict, passwordFromStandardInput: password)
        case "create":
            guard let formatValue = cursor.takeOption("--format") ?? cursor.takeOption("-f") else {
                throw CLIParseError("create requires --format <format>")
            }
            let format = try parseFormat(formatValue)
            guard let destinationValue = cursor.takeOption("--output") ?? cursor.takeOption("-o") else {
                throw CLIParseError("create requires --output <archive>")
            }
            let conflict = try parseConflict(cursor.takeOption("--conflict") ?? "ask")
            let level: CompressionLevel?
            if let semantic = cursor.takeOption("--compression-level") { level = try parseLevel(semantic) }
            else if let legacy = cursor.takeOption("--level") {
                guard let value = Int(legacy), (0...9).contains(value) else { throw CLIParseError("--level must be between 0 and 9") }
                level = legacyLevel(value)
            } else { level = nil }
            let method = try cursor.takeOption("--method").map(parseMethod)
            let dictionary = try cursor.takeOption("--dictionary-size").map(parseByteSize)
            let wordSize = try cursor.takeOption("--word-size").map { raw in
                guard let value = Int(raw), value > 0 else { throw CLIParseError("--word-size requires a positive integer") }
                return value
            }
            let threads: ThreadConfiguration = try cursor.takeOption("--threads").map { raw in
                if raw.lowercased() == "automatic" || raw.lowercased() == "auto" { return .automatic }
                guard let count = Int(raw), count > 0 else { throw CLIParseError("--threads requires auto or a positive integer") }
                return .explicit(count)
            } ?? .automatic
            let solidMode: SolidMode = cursor.takeFlag("--solid") ? .on :
                (cursor.takeFlag("--no-solid") ? .off : .automatic)
            let encryptFileNames = cursor.takeFlag("--encrypt-file-names")
            let volumeSize = try cursor.takeOption("--volume-size").map { raw in
                do { return try VolumeSize(parsing: raw) }
                catch { throw CLIParseError("--volume-size requires 64 KiB...1 TiB with an optional KB/MB/GB unit") }
            }
            let password = cursor.takeFlag("--password-stdin")
            let sources = cursor.remaining.map { resolve($0, against: currentDirectory) }
            guard !sources.isEmpty else { throw CLIParseError("create requires at least one source") }
            return .create(format: format, destination: resolve(destinationValue, against: currentDirectory), sources: sources,
                           conflict: conflict,
                           options: .init(level: level, method: method, dictionarySize: dictionary,
                                          wordSize: wordSize, threads: threads, solidMode: solidMode,
                                          encryptFileNames: encryptFileNames, volumeSize: volumeSize),
                           passwordFromStandardInput: password)
        default: throw CLIParseError("Unknown command: \(verb)")
        }
    }

    private func parseLevel(_ value: String) throws -> CompressionLevel {
        guard let level = CompressionLevel(rawValue: value.lowercased()) else {
            throw CLIParseError("Unknown compression level: \(value)")
        }
        return level
    }
    private func legacyLevel(_ value: Int) -> CompressionLevel {
        switch value { case ...0: .store; case 1...2: .fastest; case 3...4: .fast
        case 5...6: .normal; case 7...8: .maximum; default: .ultra }
    }
    private func parseMethod(_ value: String) throws -> CompressionMethod {
        guard let method = CompressionMethod(rawValue: value.lowercased()) else { throw CLIParseError("Unknown method: \(value)") }
        return method
    }
    private func parseByteSize(_ value: String) throws -> UInt64 {
        do { return try VolumeSize(parsing: value).bytes }
        catch { throw CLIParseError("Size requires a value with an optional KB/MB/GB unit") }
    }

    private func parseConflict(_ value: String) throws -> ConflictResolution {
        switch value.lowercased() {
        case "ask": .ask
        case "replace": .replace
        case "skip": .skip
        case "keep-both", "keepboth": .keepBoth
        default: throw CLIParseError("Unknown conflict policy: \(value)")
        }
    }

    private func parseFormat(_ value: String) throws -> ArchiveFormat {
        switch value.lowercased() {
        case "7z": .sevenZip
        case "zip": .zip(.zip)
        case "jar": .zip(.jar)
        case "apk": .zip(.apk)
        case "epub": .zip(.epub)
        case "tar": .tar
        case "tar.gz", "tgz": .tarGzip
        case "tar.bz2", "tbz2": .tarBzip2
        case "tar.xz", "txz": .tarXZ
        case "gz", "gzip": .gzip
        case "bz2", "bzip2": .bzip2
        case "xz": .xz
        case "lzma": .lzma
        case "cpio": .cpio
        default: throw CLIParseError("Unsupported creation format: \(value)")
        }
    }

    private func resolve(_ path: String, against directory: URL) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path).standardizedFileURL
    }
}

private struct Cursor {
    private(set) var remaining: [String]
    init(_ values: [String]) { remaining = values }
    mutating func path(_ label: String, relativeTo directory: URL) throws -> URL {
        guard let value = remaining.first, !value.hasPrefix("-") else { throw CLIParseError("Missing \(label) path") }
        remaining.removeFirst()
        return value.hasPrefix("/") ? URL(fileURLWithPath: value) : directory.appendingPathComponent(value).standardizedFileURL
    }
    mutating func takeFlag(_ flag: String) -> Bool {
        guard let index = remaining.firstIndex(of: flag) else { return false }
        remaining.remove(at: index); return true
    }
    mutating func takeOption(_ option: String) -> String? {
        guard let index = remaining.firstIndex(of: option), remaining.indices.contains(index + 1) else { return nil }
        remaining.remove(at: index); return remaining.remove(at: index)
    }
    func requireEnd() throws {
        guard remaining.isEmpty else { throw CLIParseError("Unexpected argument: \(remaining[0])") }
    }
}
