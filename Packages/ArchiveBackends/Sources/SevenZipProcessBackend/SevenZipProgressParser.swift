import Domain
import Foundation

public struct SevenZipProgressParser: Sendable {
    private var buffer = Data(); public init() {}
    public mutating func consume(_ chunk: Data, phase: ProgressEvent.Phase) -> [ProgressEvent] {
        buffer.append(chunk); var events: [ProgressEvent] = []
        while let boundary = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let line = String(decoding: buffer[..<boundary], as: UTF8.self); buffer.removeSubrange(...boundary)
            if let percentRange = line.range(of: #"\b(\d{1,3})%"#, options: .regularExpression),
               let percent = UInt64(line[percentRange].dropLast()), percent <= 100 {
                let path = line.split(separator: "%", maxSplits: 1).dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) }
                events.append(.init(phase: phase, completedUnits: percent, totalUnits: 100, currentEntryPath: path?.isEmpty == false ? path : nil))
            }
        }
        if buffer.count > 8192 { buffer.removeFirst(buffer.count - 8192) }
        return events
    }
}
