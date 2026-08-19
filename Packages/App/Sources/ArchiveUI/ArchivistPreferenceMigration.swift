import Foundation

/// One-time, allow-listed migration from the former development bundle identifier.
public enum ArchivistPreferenceMigration {
    public static let sourceDomain = "com.keremgurevin.ArchiveUtility"
    public static let completionKey = "archivist.preferenceMigration.v1"
    public static let knownKeys = [
        "defaultConflict", "preventPathTraversal", "restrictSymlinks", "restrictHardlinks",
        "rejectUnicodeCollisions", "maximumConcurrentJobs", "externalSevenZipPath"
    ]

    public static func migrateIfNeeded(
        destination: UserDefaults = .standard,
        persistentDomains: UserDefaults = .standard
    ) {
        guard !destination.bool(forKey: completionKey) else { return }
        let oldValues = persistentDomains.persistentDomain(forName: sourceDomain) ?? [:]
        for key in knownKeys where destination.object(forKey: key) == nil {
            if let value = oldValues[key] { destination.set(value, forKey: key) }
        }
        destination.set(true, forKey: completionKey)
    }
}
