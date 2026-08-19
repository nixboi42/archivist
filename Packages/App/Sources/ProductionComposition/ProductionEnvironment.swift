import BackendRegistry
import Foundation
import LibarchiveBackend
import SevenZipProcessBackend
import XIPStack

public enum ProductionEnvironment {
    public static func makeRegistry(externalSevenZip: URL? = nil) async -> ArchiveBackendRegistry {
        let registry = ArchiveBackendRegistry()
        await configure(registry, externalSevenZip: externalSevenZip)
        return registry
    }

    public static func configure(_ registry: ArchiveBackendRegistry, externalSevenZip: URL? = nil) async {
        do { await registry.register(try LibarchiveBackend(), kind: .libarchive) }
        catch { await registry.registerUnavailable(identifier: .init(rawValue: "libarchive"), kind: .libarchive, reason: String(describing: error)) }

        let locator = externalSevenZip.map { SevenZipExecutableLocator(source: .external($0)) } ?? SevenZipExecutableLocator()
        do { await registry.register(try await SevenZipProcessBackend(locator: locator), kind: .sevenZip) }
        catch { await registry.registerUnavailable(identifier: .init(rawValue: "7zz"), kind: .sevenZip, reason: String(describing: error)) }

        await registry.register(XIPArchiveBackend(), kind: .xipStack)
    }
}
