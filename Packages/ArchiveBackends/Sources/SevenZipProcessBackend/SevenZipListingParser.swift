import Domain
import Foundation

public struct SevenZipListingParser: Sendable {
    public init() {}
    public func parse(_ output: String) -> [ArchiveEntry] {
        let blocks = output.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        return blocks.compactMap { block in
            var fields: [String: String] = [:]
            for line in block.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { fields[parts[0]] = parts[1] }
            }
            guard let path = fields["Path"], fields["Type"] == nil else { return nil }
            let folder = fields["Folder"] == "+" || fields["Attributes"]?.hasPrefix("D") == true
            return ArchiveEntry(path: path, kind: folder ? .directory : .regularFile,
                                uncompressedSize: fields["Size"].flatMap(UInt64.init),
                                compressedSize: fields["Packed Size"].flatMap(UInt64.init),
                                modificationDate: fields["Modified"].flatMap(parseDate),
                                posixMode: nil, checksum: fields["CRC"], isEncrypted: fields["Encrypted"] == "+")
        }
    }
    private func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value)
    }
}
