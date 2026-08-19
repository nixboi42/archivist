public enum ArchiveOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case read, list, extract, create, modify, test
}
