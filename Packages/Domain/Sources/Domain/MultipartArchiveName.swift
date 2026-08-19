import Foundation

public struct MultipartArchiveName: Hashable, Sendable {
    public let format: ArchiveFormat
    public let volumeNumber: Int
    public let baseFilename: String
    public var isFirstVolume: Bool { volumeNumber == 1 }
    public var firstVolumeFilename: String { baseFilename + ".001" }

    public static func parse(_ filename: String) -> MultipartArchiveName? {
        let lower = filename.lowercased()
        guard lower.count > 4, lower[lower.index(lower.endIndex, offsetBy: -4)] == ".",
              let number = Int(lower.suffix(3)), number > 0 else { return nil }
        let base = String(filename.dropLast(4))
        let format: ArchiveFormat
        if base.lowercased().hasSuffix(".7z") { format = .sevenZip }
        else if base.lowercased().hasSuffix(".zip") { format = .zip(.zip) }
        else { return nil }
        return .init(format: format, volumeNumber: number, baseFilename: base)
    }
}

public struct NonFirstVolumeError: Error, Hashable, Sendable, CustomStringConvertible {
    public let volume: MultipartArchiveName
    public init(volume: MultipartArchiveName) { self.volume = volume }
    public var description: String {
        "This is volume \(volume.volumeNumber) of a multipart archive. Open \(volume.firstVolumeFilename)."
    }
}
