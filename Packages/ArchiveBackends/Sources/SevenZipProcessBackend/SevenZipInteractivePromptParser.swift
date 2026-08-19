import Foundation

public enum SevenZipInteractiveMode: Sendable { case openingArchive, creatingArchive }
public enum SevenZipInteractiveState: Equatable, Sendable { case starting, waitingForPrompt, secretSent, completed, cancelRequested, terminated, failed }

public struct SevenZipInteractivePromptParser: Sendable {
    private var buffer = Data()
    public let maximumBytes: Int
    public init(maximumBytes: Int = 512) { self.maximumBytes = maximumBytes }
    public mutating func consume(_ bytes: Data) -> Bool {
        buffer.append(bytes)
        if buffer.count > maximumBytes { buffer.removeFirst(buffer.count - maximumBytes) }
        let text = String(decoding: buffer, as: UTF8.self).lowercased()
        return text.hasSuffix("enter password:") || text.hasSuffix("enter password: ")
    }
    public var bufferedByteCount: Int { buffer.count }
}

public struct BoundedTerminalCapture: Sendable {
    private var bytes = Data()
    public let limit: Int
    public init(limit: Int = 65_536) { self.limit = limit }
    public mutating func append(_ chunk: Data) {
        bytes.append(chunk)
        if bytes.count > limit { bytes.removeFirst(bytes.count - limit) }
    }
    public var text: String {
        String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
