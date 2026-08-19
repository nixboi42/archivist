import BackendProtocol
import Domain
import Foundation
import LibarchiveBackend
import Testing

@Test func pinnedRuntimeVersionAndCapabilities() throws {
    let backend = try LibarchiveBackend()
    #expect(LibarchiveBackend.runtimeVersion == LibarchiveBackend.pinnedVersion)
    #expect(backend.capabilities(for: .tar).supports(.create))
    #expect(!backend.capabilities(for: .iso9660).supports(.read))
    #expect(!backend.capabilities(for: .gzip).supports(.list))
}

@Test func formatProfilesAreDeliberate() {
    #expect(LibarchiveFormatProfile.profile(for: .tarGzip)?.standaloneStream == false)
    #expect(LibarchiveFormatProfile.profile(for: .gzip)?.standaloneStream == true)
    #expect(LibarchiveFormatProfile.profile(for: .zip(.zip)) == nil)
}

@Test func tarRoundTripAndUnicode() async throws {
    let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }; let source = root.appendingPathComponent("kaynak")
    try fm.createDirectory(at: source.appendingPathComponent("nested"), withIntermediateDirectories: true)
    try Data("Merhaba 世界 🗄️".utf8).write(to: source.appendingPathComponent("nested/İstanbul.txt"))
    try Data().write(to: source.appendingPathComponent("empty"))
    let archive = root.appendingPathComponent("fixture.tar.gz"), backend = try LibarchiveBackend()
    for try await _ in backend.create(from: [source], to: archive, options: .init(format: .tarGzip)) {}
    let handle = try await backend.open(archive, format: .tarGzip, credential: nil)
    var entries: [ArchiveEntry] = []; for try await entry in backend.list(handle) { entries.append(entry) }
    #expect(entries.contains { $0.path.precomposedStringWithCanonicalMapping == "kaynak/nested/İstanbul.txt" })
    let output = root.appendingPathComponent("output")
    for try await _ in backend.extract(handle, entries: nil, to: output, options: .init(conflictResolution: .replace)) {}
    #expect(try Data(contentsOf: output.appendingPathComponent("kaynak/nested/İstanbul.txt")) == Data("Merhaba 世界 🗄️".utf8))
    await backend.close(handle)
}

@Test func cpioAndXZRoundTrips() async throws {
    for format in [ArchiveFormat.cpio, .tarXZ, .tarBzip2] {
        let fm=FileManager.default, root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer{try? fm.removeItem(at:root)}
        try fm.createDirectory(at:root,withIntermediateDirectories:true);let source=root.appendingPathComponent("file");try Data("payload".utf8).write(to:source)
        let archive=root.appendingPathComponent("archive.\(format.canonicalExtension!)"), backend=try LibarchiveBackend()
        for try await _ in backend.create(from:[source],to:archive,options:.init(format:format)){}
        let handle=try await backend.open(archive,format:format,credential:nil);for try await _ in backend.test(handle){};await backend.close(handle)
    }
}

@Test func standaloneBzip2AndXZRoundTrips() async throws {
    for format in [ArchiveFormat.bzip2,.xz]{let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?fm.removeItem(at:root)};try fm.createDirectory(at:root,withIntermediateDirectories:true);let source=root.appendingPathComponent("stream");try Data("codec".utf8).write(to:source);let archive=root.appendingPathComponent("stream.\(format.canonicalExtension!)"),backend=try LibarchiveBackend();for try await _ in backend.create(from:[source],to:archive,options:.init(format:format)){};let handle=try await backend.open(archive,format:format,credential:nil),out=root.appendingPathComponent("out");for try await _ in backend.extract(handle,entries:nil,to:out,options:.init(conflictResolution:.replace)){};#expect(try Data(contentsOf:out.appendingPathComponent("stream"))==Data("codec".utf8));await backend.close(handle)}
}

@Test func corruptedArchiveFails() async throws {
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:url)};try Data("not tar".utf8).write(to:url)
    let backend=try LibarchiveBackend(), handle=try await backend.open(url,format:.tar,credential:nil)
    await #expect(throws: ArchiveBackendError.self) { for try await _ in backend.list(handle) {} }
}

@Test func standaloneGzipIsOneStreamNotAContainer() async throws {
    let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?fm.removeItem(at:root)};try fm.createDirectory(at:root,withIntermediateDirectories:true)
    let source=root.appendingPathComponent("single.txt");try Data("single stream".utf8).write(to:source);let archive=root.appendingPathComponent("single.txt.gz"),backend=try LibarchiveBackend()
    #expect(!backend.capabilities(for:.gzip).supports(.list));for try await _ in backend.create(from:[source],to:archive,options:.init(format:.gzip)){}
    let handle=try await backend.open(archive,format:.gzip,credential:nil),output=root.appendingPathComponent("out");for try await _ in backend.extract(handle,entries:nil,to:output,options:.init(conflictResolution:.replace)){}
    #expect(try Data(contentsOf:output.appendingPathComponent("single.txt")) == Data("single stream".utf8));await backend.close(handle)
}

@Test func symlinkRoundTripIsPlannerValidated() async throws {
    let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?fm.removeItem(at:root)};let source=root.appendingPathComponent("tree");try fm.createDirectory(at:source,withIntermediateDirectories:true)
    try Data("target".utf8).write(to:source.appendingPathComponent("target"));try fm.createSymbolicLink(atPath:source.appendingPathComponent("link").path,withDestinationPath:"target")
    let archive=root.appendingPathComponent("links.tar"),backend=try LibarchiveBackend();for try await _ in backend.create(from:[source],to:archive,options:.init(format:.tar)){}
    let handle=try await backend.open(archive,format:.tar,credential:nil),out=root.appendingPathComponent("out");for try await _ in backend.extract(handle,entries:nil,to:out,options:.init(conflictResolution:.replace)){}
    #expect(try fm.destinationOfSymbolicLink(atPath:out.appendingPathComponent("tree/link").path) == "target");await backend.close(handle)
}

@Test func largeFileUsesBoundedStreaming() async throws {
    let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?fm.removeItem(at:root)};try fm.createDirectory(at:root,withIntermediateDirectories:true)
    let source=root.appendingPathComponent("large.bin");fm.createFile(atPath:source.path,contents:nil);let writer=try FileHandle(forWritingTo:source);let chunk=Data(repeating:0xA5,count:64*1024);for _ in 0..<256{try writer.write(contentsOf:chunk)};try writer.close()
    let archive=root.appendingPathComponent("large.tar"),backend=try LibarchiveBackend();for try await _ in backend.create(from:[source],to:archive,options:.init(format:.tar)){}
    let handle=try await backend.open(archive,format:.tar,credential:nil),out=root.appendingPathComponent("out");for try await _ in backend.extract(handle,entries:nil,to:out,options:.init(conflictResolution:.replace)){}
    #expect((try fm.attributesOfItem(atPath:out.appendingPathComponent("large.bin").path)[.size] as? NSNumber)?.uint64Value == 16*1024*1024);await backend.close(handle)
}

@Test func cancellationRemovesPartialOutput() async throws {
    let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?fm.removeItem(at:root)};try fm.createDirectory(at:root,withIntermediateDirectories:true)
    let source=root.appendingPathComponent("cancel.bin");fm.createFile(atPath:source.path,contents:nil);let writer=try FileHandle(forWritingTo:source);let chunk=Data(repeating:0x5A,count:64*1024);for _ in 0..<512{try writer.write(contentsOf:chunk)};try writer.close()
    let archive=root.appendingPathComponent("cancel.tar"),backend=try LibarchiveBackend()
    for try await _ in backend.create(from:[source],to:archive,options:.init(format:.tar)){break}
    try await Task.sleep(for:.milliseconds(25))
    #expect(!fm.fileExists(atPath:archive.path))
    #expect(!fm.fileExists(atPath:archive.appendingPathExtension("archiveutil-partial").path))
}
