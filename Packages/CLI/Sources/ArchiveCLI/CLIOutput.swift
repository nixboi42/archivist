import Domain
import Foundation

public struct CLIOutput: Sendable {
    public init() {}
    public func entry(_ entry: ArchiveEntry) -> String {
        let size = entry.uncompressedSize.map(String.init) ?? "-"
        return "\(entry.kind.rawValue)\t\(size)\t\(entry.path)"
    }
    public func progress(_ event: ProgressEvent) -> String {
        let total = event.totalUnits.map { "/\($0)" } ?? ""
        let path = event.currentEntryPath.map { " \($0)" } ?? ""
        return "\(event.phase.rawValue) \(event.completedUnits)\(total)\(path)"
    }

    public static let usage = """
    Archivist command-line interface

    Usage:
      archiveutil list <archive> [--password-stdin]
      archiveutil extract <archive> --destination <directory> [--conflict ask|replace|skip|keep-both] [--password-stdin]
      archiveutil create --format <format> --output <archive> [--conflict ask|replace|skip]
          [--compression-level store|fastest|fast|normal|maximum|ultra]
          [--method <method>] [--dictionary-size <size>] [--word-size <n>]
          [--threads auto|<n>] [--solid|--no-solid] [--encrypt-file-names]
          [--volume-size <size>] [--password-stdin] <sources...>
      archiveutil test <archive> [--password-stdin]
    """
}
