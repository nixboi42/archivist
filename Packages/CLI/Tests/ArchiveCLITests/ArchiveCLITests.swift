import ArchiveCLI
import BackendProtocol
import Domain
import Foundation
import Testing

@Test func parsesListAndPasswordInput() throws {
    let cwd = URL(fileURLWithPath: "/tmp/work")
    #expect(try CLIParser().parse(["list", "a.zip", "--password-stdin"], currentDirectory: cwd)
            == .list(archive: URL(fileURLWithPath: "/tmp/work/a.zip"), passwordFromStandardInput: true))
}

@Test func parsesExtractionPolicy() throws {
    let command = try CLIParser().parse(["extract", "/a.zip", "--destination", "/out", "--conflict", "keep-both"])
    #expect(command == .extract(archive: URL(fileURLWithPath: "/a.zip"), destination: URL(fileURLWithPath: "/out"),
                                conflict: .keepBoth, passwordFromStandardInput: false))
}

@Test func parsesCreationOptionsAndSources() throws {
    let command = try CLIParser().parse(["create", "--format", "tar.gz", "--output", "/a.tar.gz", "--level", "7",
                                         "--solid", "one", "two"] , currentDirectory: URL(fileURLWithPath: "/work"))
    #expect(command == .create(format: .tarGzip, destination: URL(fileURLWithPath: "/a.tar.gz"),
                               sources: [URL(fileURLWithPath: "/work/one"), URL(fileURLWithPath: "/work/two")],
                               conflict: .ask, options: .init(level: .maximum, solidMode: .on),
                               passwordFromStandardInput: false))
}

@Test func parsesAdvancedCreationOptions() throws {
    let command = try CLIParser().parse(["create", "--format", "7z", "--output", "a.7z",
        "--compression-level", "ultra", "--method", "lzma2", "--dictionary-size", "64MiB",
        "--word-size", "128", "--threads", "4", "--solid", "--encrypt-file-names",
        "--volume-size", "100MB", "--password-stdin", "input"])
    guard case .create(_, _, _, _, let options, let password) = command else { Issue.record("Expected create"); return }
    #expect(options.level == .ultra); #expect(options.method == .lzma2)
    #expect(options.dictionarySize == 64 << 20); #expect(options.wordSize == 128)
    #expect(options.threads == .explicit(4)); #expect(options.solidMode == .on)
    #expect(options.encryptFileNames); #expect(options.volumeSize?.bytes == 100_000_000); #expect(password)
}

@Test func rejectsUnsupportedFormatAndInvalidLevel() {
    #expect(throws: CLIParseError.self) { try CLIParser().parse(["create", "--format", "rar", "--output", "a.rar", "x"]) }
    #expect(throws: CLIParseError.self) { try CLIParser().parse(["create", "--format", "zip", "--output", "a.zip", "--level", "12", "x"]) }
}

@Test func outputNeverIncludesCredential() {
    let output = CLIOutput().entry(.init(path: "secret.txt", kind: .regularFile, uncompressedSize: 12))
    #expect(output == "regularFile\t12\tsecret.txt")
    #expect(ArchiveCredential(password: "DO_NOT_PRINT").description == "<redacted>")
}
