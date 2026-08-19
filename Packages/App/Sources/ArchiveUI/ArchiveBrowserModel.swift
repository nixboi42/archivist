import Domain
import Foundation

public struct ArchiveBrowserModel: Sendable {
    public private(set) var entries: [ArchiveEntry] = []
    public private(set) var currentPath: [String] = []
    public var searchText = ""

    public init() {}

    public mutating func reset() { entries.removeAll(keepingCapacity: true); currentPath = []; searchText = "" }
    public mutating func append(contentsOf batch: [ArchiveEntry]) { entries.append(contentsOf: batch) }
    public mutating func enter(_ entry: ArchiveEntry) {
        guard entry.kind == .directory else { return }
        currentPath = entry.path.split(separator: "/").map(String.init)
    }
    public mutating func goBack() { if !currentPath.isEmpty { currentPath.removeLast() } }
    public mutating func goRoot() { currentPath = [] }
    public mutating func navigate(to count: Int) { currentPath = Array(currentPath.prefix(max(0, count))) }

    public var visibleEntries: [ArchiveEntry] {
        if !searchText.isEmpty {
            return entries.filter { $0.path.localizedCaseInsensitiveContains(searchText) }
        }
        let prefix = currentPath.joined(separator: "/")
        return entries.filter { entry in
            let components = entry.path.split(separator: "/").map(String.init)
            guard components.count == currentPath.count + 1 else { return false }
            return prefix.isEmpty || components.dropLast().joined(separator: "/") == prefix
        }
    }

    public func entry(id: ArchiveEntry.ID) -> ArchiveEntry? { entries.first { $0.id == id } }
}
