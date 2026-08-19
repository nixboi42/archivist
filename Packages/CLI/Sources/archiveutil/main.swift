import ArchiveApplication
import ArchiveCLI
import BackendProtocol
import BackendRegistry
import CrashSafeFilesystem
import Darwin
import Domain
import Foundation
import LibarchiveBackend
import SevenZipProcessBackend
import XIPStack

@main
struct ArchiveUtilCommand {
    static func main() async {
        let code = await run()
        Darwin.exit(code)
    }

    private static func run() async -> Int32 {
        do {
            let command = try CLIParser().parse(Array(CommandLine.arguments.dropFirst()))
            if command == .help { print(CLIOutput.usage); return 0 }
            let registry = await productionRegistry()
            let filesystem = CrashSafeFilesystem()
            let output = CLIOutput()

            switch command {
            case .list(let archive, let passwordFromStandardInput):
                let credential = try credential(requested: passwordFromStandardInput)
                for try await entry in BrowseUseCase(registry: registry).execute(.init(archiveURL: archive, credential: credential)) {
                    print(output.entry(entry))
                }
            case .extract(let archive, let destination, let conflict, let passwordFromStandardInput):
                let options = ExtractionOptions(conflictResolution: conflict,
                                                credential: try credential(requested: passwordFromStandardInput))
                let request = ExtractionRequest(archiveURL: archive, destinationURL: destination, options: options)
                for try await progress in ExtractionUseCase(registry: registry, filesystem: filesystem).execute(request) {
                    writeError(output.progress(progress))
                }
            case .create(let format, let destination, let sources, let conflict, let semantic, let passwordFromStandardInput):
                let options = CreationOptions(format: format, compressionLevel: semantic.level,
                                              method: semantic.method, dictionarySize: semantic.dictionarySize,
                                              wordSize: semantic.wordSize, solidMode: semantic.solidMode,
                                              threads: semantic.threads, encryptFileNames: semantic.encryptFileNames,
                                              volumeSize: semantic.volumeSize,
                                              credential: try credential(requested: passwordFromStandardInput))
                let request = CreationRequest(sourceURLs: sources, destinationURL: destination,
                                              options: options, overwritePolicy: conflict)
                for try await progress in CreationUseCase(registry: registry, filesystem: filesystem).execute(request) {
                    writeError(output.progress(progress))
                }
            case .test(let archive, let passwordFromStandardInput):
                let result = try await TestArchiveUseCase(registry: registry).execute(
                    archive, credential: try credential(requested: passwordFromStandardInput))
                print("ok\t\(result.format.canonicalExtension ?? "unknown")\t\(result.backendIdentifier.rawValue)")
                for warning in result.warnings { writeError("warning[\(warning.code.rawValue)]: \(warning.message)") }
            case .help: break
            }
            return 0
        } catch let error as CLIParseError {
            writeError("archiveutil: \(error.message)\n\n\(CLIOutput.usage)")
            return 64
        } catch {
            let mapped = ApplicationError.map(error)
            let diagnostic = mapped.diagnosticCode.map { " [\($0)]" } ?? ""
            writeError("archiveutil: \(mapped.code.rawValue): \(mapped.message)\(diagnostic)")
            return mapped.code == .cancelled ? 130 : 1
        }
    }

    private static func productionRegistry() async -> ArchiveBackendRegistry {
        let registry = ArchiveBackendRegistry()
        do { await registry.register(try LibarchiveBackend(), kind: .libarchive) }
        catch { await registry.registerUnavailable(identifier: .init(rawValue: "libarchive"), kind: .libarchive,
                                                     reason: String(describing: error)) }

        let environmentPath = ProcessInfo.processInfo.environment["ARCHIVEUTIL_7ZZ"].map(URL.init(fileURLWithPath:))
        let locator = environmentPath.map { SevenZipExecutableLocator(source: .external($0)) } ?? SevenZipExecutableLocator()
        do { await registry.register(try await SevenZipProcessBackend(locator: locator), kind: .sevenZip) }
        catch { await registry.registerUnavailable(identifier: .init(rawValue: "7zz"), kind: .sevenZip,
                                                     reason: String(describing: error)) }

        await registry.register(XIPArchiveBackend(), kind: .xipStack)
        return registry
    }

    private static func credential(requested: Bool) throws -> ArchiveCredential? {
        guard requested else { return nil }
        guard let password = readLine(strippingNewline: true), !password.isEmpty else {
            throw CLIParseError("--password-stdin requires a non-empty line on standard input")
        }
        return ArchiveCredential(password: password)
    }

    private static func writeError(_ string: String) {
        FileHandle.standardError.write(Data((string + "\n").utf8))
    }
}
