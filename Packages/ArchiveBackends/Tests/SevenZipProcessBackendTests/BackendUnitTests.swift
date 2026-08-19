import BackendProtocol
import Domain
import Foundation
import Testing
@testable import SevenZipProcessBackend

@Test func argumentsAreStructuredAndDiagnosticsRedacted() throws {
    let source = URL(fileURLWithPath: "/tmp/Türkçe 📦/a '-file")
    let options = CreationOptions(format: .sevenZip, compressionLevel: 7, solid: true, credential: .init(password: "unused"))
    let args = try SevenZipArgumentBuilder().build(.create([source], URL(fileURLWithPath: "/tmp/out file.7z"), options), hasCredential: true)
    #expect(args.values.contains(source.path)); #expect(args.values.contains("-p")); #expect(!args.values.joined().contains("unused"))
    #expect(!args.description.contains("unused")); #expect(args.description.contains("-p<redacted>"))
}

@Test func advancedArgumentsAreDeterministicAndHeaderEncryptionIsExplicit() throws {
    let volume = try VolumeSize(bytes: 100_000_000)
    let options = CreationOptions(format: .sevenZip, compressionLevel: .ultra, method: .lzma2,
        dictionarySize: 64 << 20, wordSize: 128, solidMode: .on, threads: .explicit(4),
        encryptFileNames: true, volumeSize: volume, credential: .init(password: "unused"))
    let args = try SevenZipArgumentBuilder().build(.create([URL(fileURLWithPath: "/tmp/a")],
        URL(fileURLWithPath: "/tmp/out.7z"), options), hasCredential: true)
    #expect(args.values == ["a", "-t7z", "-bsp1", "-bb1", "-mx=9", "-m0=LZMA2",
        "-md=67108864b", "-mfb=128", "-ms=on", "-mmt=4", "-p", "-mhe=on",
        "-v100000000b", "--", "/tmp/out.7z", "/tmp/a"])
}

@Test func unsupportedCreationIsRefused() {
    #expect(throws: ArchiveBackendError.self) {
        try SevenZipArgumentBuilder().build(.create([], URL(fileURLWithPath: "/tmp/a.rar"), .init(format: .rar)))
    }
}

@Test func technicalListingParserMapsAvailableFieldsOnly() {
    let fixture = """
    Path = archive.7z
    Type = 7z

    Path = folder
    Size = 0
    Packed Size = 0
    Folder = +

    Path = folder/çalışma.txt
    Size = 12
    Packed Size = 8
    Modified = 2026-08-17 12:00:00
    CRC = ABCDEF12
    Encrypted = +
    """
    let entries = SevenZipListingParser().parse(fixture)
    #expect(entries.count == 2); #expect(entries[0].kind == .directory); #expect(entries[1].uncompressedSize == 12)
    #expect(entries[1].isEncrypted); #expect(entries[1].checksum == "ABCDEF12")
}

@Test func progressParserHandlesFragmentedChunks() {
    var parser = SevenZipProgressParser()
    #expect(parser.consume(Data("12".utf8), phase: .extracting).isEmpty)
    let events = parser.consume(Data("% file.txt\r".utf8), phase: .extracting)
    #expect(events.first?.completedUnits == 12); #expect(events.first?.currentEntryPath == "file.txt")
}

@Test func exitMappingDistinguishesCancellationAndCrash() {
    let mapper = SevenZipExitCodeMapper()
    #expect(mapper.error(exitCode: 255, signal: nil, cancellationRequested: true, operation: .test)?.code == .cancelled)
    #expect(mapper.error(exitCode: nil, signal: 9, cancellationRequested: false, operation: .test)?.code == .backendCrashed)
    #expect(mapper.error(exitCode: 8, signal: nil, cancellationRequested: false, operation: .test)?.code == .resourceLimitExceeded)
}

@Test func capabilityPolicyDisablesRARCabAndARJCreation() {
    #expect(!SevenZipCapabilities.capabilities(for: .rar).supports(.create))
    #expect(!SevenZipCapabilities.capabilities(for: .cab).supports(.create))
    #expect(!SevenZipCapabilities.capabilities(for: .arj).supports(.create))
    #expect(SevenZipCapabilities.capabilities(for: .sevenZip).supports(.create))
}
