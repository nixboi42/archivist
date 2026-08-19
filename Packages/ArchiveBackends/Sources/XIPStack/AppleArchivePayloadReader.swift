import AppleArchive
import Foundation
import System

public struct AppleArchivePayloadReader: Sendable {
    public init() {}
    public func list(_ url: URL) throws -> [AppleArchiveEntry] {
        guard let file=ArchiveByteStream.fileStream(path:FilePath(url.path),mode:.readOnly,options:[],permissions:[]) else{throw XIPStackError.appleArchiveFailure("Unable to open payload")}
        defer{try?file.close()}
        guard let bytes=ArchiveByteStream.decompressionStream(readingFrom:file) else{throw XIPStackError.appleArchiveFailure("Payload is not an Apple Archive stream")}
        defer{try?bytes.close()}
        return try ArchiveStream.withDecodeStream(readingFrom:bytes){stream in
            var result:[AppleArchiveEntry]=[]
            while let header=try stream.readHeader(){guard let path=header.entryPath else{continue};result.append(.init(path:path.string,typeDescription:header.entryType?.description ?? "unknown"))}
            return result
        }
    }
}
