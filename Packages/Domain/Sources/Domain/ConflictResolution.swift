public enum ConflictResolution: String, Codable, CaseIterable, Hashable, Sendable {
    case ask, replace, skip, keepBoth
}

public enum ConflictScope: String, Codable, Hashable, Sendable {
    case singleEntry, remainingOperation
}
