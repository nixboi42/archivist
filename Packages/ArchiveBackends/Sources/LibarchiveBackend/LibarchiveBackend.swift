import ArchiveSecurity
import BackendProtocol
import CLibarchiveShim
import Darwin
import Domain
import Foundation

private struct Session: Sendable { let url: URL; let format: ArchiveFormat }
private actor Sessions {
    var values: [UUID: Session] = [:]
    func insert(_ handle: ArchiveHandle, _ session: Session) { values[handle.id] = session }
    func get(_ handle: ArchiveHandle) throws -> Session {
        guard let value = values[handle.id] else { throw ArchiveBackendError(.backendFailure, backendIdentifier: "libarchive", message: "Unknown or closed archive handle", diagnosticCode: "INVALID_HANDLE") }
        return value
    }
    func remove(_ handle: ArchiveHandle) { values.removeValue(forKey: handle.id) }
}

private final class EntryBox: @unchecked Sendable {
    var entries: [ArchiveEntry] = []; var cancelled = false; let standaloneName: String?
    init(standaloneName: String?) { self.standaloneName = standaloneName }
}
private final class ProgressBox: @unchecked Sendable {
    let continuation: AsyncThrowingStream<ProgressEvent, Error>.Continuation; let phase: ProgressEvent.Phase
    var cancelled = false
    init(_ continuation: AsyncThrowingStream<ProgressEvent, Error>.Continuation, _ phase: ProgressEvent.Phase) { self.continuation = continuation; self.phase = phase }
}

private let entryCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<LAEntryInfo>?) -> Int32 = { context, pointer in
    guard let context, let pointer else { return 1 }
    let box = Unmanaged<EntryBox>.fromOpaque(context).takeUnretainedValue(); if box.cancelled { return 1 }
    let value = pointer.pointee
    let original = value.path.map(String.init(cString:)) ?? ""
    let path = box.standaloneName ?? original
    let kind: ArchiveEntryKind = switch value.kind { case LA_ENTRY_REGULAR: .regularFile; case LA_ENTRY_DIRECTORY: .directory; case LA_ENTRY_SYMLINK: .symbolicLink; case LA_ENTRY_HARDLINK: .hardLink; case LA_ENTRY_BLOCK: .blockDevice; case LA_ENTRY_CHARACTER: .characterDevice; case LA_ENTRY_FIFO: .fifo; case LA_ENTRY_SOCKET: .socket; default: .unknown }
    let date = value.mtime_seconds == Int64.min ? nil : Date(timeIntervalSince1970: Double(value.mtime_seconds) + Double(value.mtime_nanoseconds) / 1_000_000_000)
    box.entries.append(.init(path: path, kind: kind, uncompressedSize: value.size < 0 ? nil : UInt64(value.size),
                             modificationDate: date, posixMode: UInt16(value.mode & 0o7777),
                             ownerID: value.uid < 0 ? nil : UInt32(value.uid), groupID: value.gid < 0 ? nil : UInt32(value.gid),
                             linkTarget: value.link_target.map(String.init(cString:))))
    return 0
}

private let progressCallback: @convention(c) (UnsafeMutableRawPointer?, UInt64, UnsafePointer<CChar>?) -> Int32 = { context, bytes, path in
    guard let context else { return 1 }; let box = Unmanaged<ProgressBox>.fromOpaque(context).takeUnretainedValue()
    if box.cancelled { return 1 }
    box.continuation.yield(.init(phase: box.phase, completedUnits: bytes, currentEntryPath: path.map(String.init(cString:))))
    return 0
}

public final class LibarchiveBackend: ArchiveBackend, Sendable {
    public static let pinnedVersion = "libarchive 3.8.4"
    public let identifier = BackendIdentifier(rawValue: "libarchive")
    private let sessions = Sessions()
    public init() throws {
        guard Self.runtimeVersion == Self.pinnedVersion else {
            throw ArchiveBackendError(.backendUnavailable, backendIdentifier: "libarchive", message: "Expected \(Self.pinnedVersion), loaded \(Self.runtimeVersion)", diagnosticCode: "VERSION_CONTRACT")
        }
    }
    public static var runtimeVersion: String { String(cString: la_runtime_version()) }

    public func capabilities(for format: ArchiveFormat) -> ArchiveCapabilities {
        // ISO parsing is compiled in, but remains disabled until a representative
        // Rock Ridge/Joliet fixture proves the complete list/extract contract.
        if format == .iso9660 { return .unsupported }
        guard let profile = LibarchiveFormatProfile.profile(for: format), la_profile_available(profile.cProfile, 0) != 0 else { return .unsupported }
        var base = AuthoritativeCapabilities.capabilities(for: format, backend: .libarchive)
        if base.supports(.create), la_profile_available(profile.cProfile, 1) == 0 {
            base = .init(operations: base.operations.subtracting([.create]), supportsUnixMetadata: base.supportsUnixMetadata, requiresSequentialScan: true)
        }
        return base
    }

    public func open(_ url: URL, format: ArchiveFormat, credential: ArchiveCredential?) async throws -> ArchiveHandle {
        guard credential == nil else { throw ArchiveBackendError(.unsupportedOperation, backendIdentifier: identifier.rawValue, operation: .read, message: "Password handling is not enabled for libarchive") }
        guard capabilities(for: format).supports(.read), FileManager.default.fileExists(atPath: url.path) else { throw ArchiveBackendError(.unsupportedFormat, backendIdentifier: identifier.rawValue, operation: .read, message: "Unsupported format or missing archive") }
        let handle = ArchiveHandle(backend: identifier, format: format); await sessions.insert(handle, .init(url: url, format: format)); return handle
    }

    public func list(_ handle: ArchiveHandle) -> AsyncThrowingStream<ArchiveEntry, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do { try requireOwnedHandle(handle); let session = try await sessions.get(handle)
                    guard capabilities(for: session.format).supports(.list) else { throw unsupported(.list) }
                    for entry in try await readEntries(session) { try Task.checkCancellation(); continuation.yield(entry) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }; continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func extract(_ handle: ArchiveHandle, entries selected: [ArchiveEntry]?, to destination: URL, options: ExtractionOptions) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var partials: [URL] = []
                do { try requireOwnedHandle(handle); let session = try await sessions.get(handle); guard capabilities(for: session.format).supports(.extract) else { throw unsupported(.extract) }
                    let all = try await readEntries(session); let wanted = selected.map { Set($0.map(\.id)) }; let chosen = wanted.map { ids in all.filter { ids.contains($0.id) } } ?? all
                    let plans = try SecureExtractionPlanner(policy: options.securityPolicy).plan(destinationRoot: destination, entries: chosen)
                    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                    for plan in plans where plan.entry.kind == .directory { try FileManager.default.createDirectory(at: plan.destinationURL, withIntermediateDirectories: true) }
                    let regular = plans.filter { $0.entry.kind == .regularFile }; partials = regular.map { $0.destinationURL.appendingPathExtension("archiveutil-partial") }
                    for plan in regular { try FileManager.default.createDirectory(at: plan.destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true); try resolveConflict(at: plan.destinationURL, options.conflictResolution); try? FileManager.default.removeItem(at: plan.destinationURL.appendingPathExtension("archiveutil-partial")) }
                    try await runExtract(session, plans: regular, partials: partials, continuation: continuation)
                    for (plan, partial) in zip(regular, partials) { try FileManager.default.moveItem(at: partial, to: plan.destinationURL); if options.preserveMetadata { try restoreMetadata(plan.entry, at: plan.destinationURL) } }
                    for plan in plans where plan.entry.kind == .symbolicLink { guard plan.symlinkTarget != nil, let target = plan.entry.linkTarget else { continue }; try FileManager.default.createDirectory(at: plan.destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true); try FileManager.default.createSymbolicLink(atPath: plan.destinationURL.path, withDestinationPath: target) }
                    for plan in plans where plan.entry.kind == .hardLink { guard let decision = plan.hardlink else { continue }; try FileManager.default.linkItem(at: decision.target.appending(to: destination), to: plan.destinationURL) }
                    continuation.finish()
                } catch { for url in partials { try? FileManager.default.removeItem(at: url) }; continuation.finish(throwing: error) }
            }; continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func create(from sources: [URL], to destination: URL, options: CreationOptions) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let partial = destination.appendingPathExtension("archiveutil-partial")
                do { guard let profile = LibarchiveFormatProfile.profile(for: options.format), capabilities(for: options.format).supports(.create) else { throw unsupported(.create) }
                    guard options.credential == nil, !options.solid, options.method == nil,
                          options.dictionarySize == nil, options.wordSize == nil,
                          !options.encryptFileNames, options.volumeSize == nil else { throw unsupported(.create) }
                    guard let verified = capabilities(for: options.format).creationOptions else { throw unsupported(.create) }
                    try options.validate(against: verified)
                    let enumerated = try enumerate(sources, standalone: profile.standaloneStream); try? FileManager.default.removeItem(at: partial)
                    try await runCreate(enumerated, partial, profile, options, continuation); try? FileManager.default.removeItem(at: destination); try FileManager.default.moveItem(at: partial, to: destination); continuation.finish()
                } catch { try? FileManager.default.removeItem(at: partial); continuation.finish(throwing: error) }
            }; continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func test(_ handle: ArchiveHandle) -> AsyncThrowingStream<ProgressEvent, Error> {
        AsyncThrowingStream { continuation in let task = Task { do { try requireOwnedHandle(handle); let s = try await sessions.get(handle); try await runTest(s, continuation); continuation.finish() } catch { continuation.finish(throwing: error) } }; continuation.onTermination = { _ in task.cancel() } }
    }
    public func close(_ handle: ArchiveHandle) async { if handle.backend == identifier { await sessions.remove(handle) } }

    private func readEntries(_ session: Session) async throws -> [ArchiveEntry] {
        guard let profile = LibarchiveFormatProfile.profile(for: session.format) else { throw unsupported(.list) }
        return try await Task.detached {
            let name = profile.standaloneStream ? session.url.deletingPathExtension().lastPathComponent : nil; let box = EntryBox(standaloneName: name)
            let retained = Unmanaged.passRetained(box); defer { retained.release() }
            let r = session.url.path.withCString { la_list($0, profile.cProfile, entryCallback, retained.toOpaque()) }
            if let error = LibarchiveStatusMapper.error(status: r.status, systemErrno: r.system_errno, message: withUnsafePointer(to: r.message) { $0.withMemoryRebound(to: CChar.self, capacity: 512) { String(cString: $0) } }, operation: .list) { throw error }
            return box.entries
        }.value
    }

    private func runExtract(_ session: Session, plans: [ValidatedExtractionEntry], partials: [URL], continuation: AsyncThrowingStream<ProgressEvent, Error>.Continuation) async throws {
        let profile = LibarchiveFormatProfile.profile(for: session.format)!; let box = ProgressBox(continuation, .extracting); let retained = Unmanaged.passRetained(box); defer { retained.release() }
        let result = await withTaskCancellationHandler(operation: { await Task.detached {
            let archiveStrings = plans.map { strdup(profile.standaloneStream ? "data" : $0.entry.path)! }; defer { archiveStrings.forEach { free($0) } }; let partialStrings = partials.map { strdup($0.path)! }; defer { partialStrings.forEach { free($0) } }
            let cplans = zip(archiveStrings, partialStrings).map { LAExtractionPlan(archive_path: UnsafePointer($0.0), partial_path: UnsafePointer($0.1)) }
            return session.url.path.withCString { path in cplans.withUnsafeBufferPointer { la_extract(path, profile.cProfile, $0.baseAddress, $0.count, progressCallback, retained.toOpaque()) } }
        }.value }, onCancel: { box.cancelled = true })
        try throwMapped(result, .extract)
    }

    private func runCreate(_ sources: [(URL,String)], _ destination: URL, _ profile: LibarchiveFormatProfile,
                           _ options: CreationOptions, _ continuation: AsyncThrowingStream<ProgressEvent, Error>.Continuation) async throws {
        let box = ProgressBox(continuation, .creating), retained = Unmanaged.passRetained(box); defer { retained.release() }
        let result = await withTaskCancellationHandler(operation: { await Task.detached {
            let sourceStrings=sources.map{strdup($0.0.path)!}; defer{sourceStrings.forEach { free($0) }}; let archiveStrings=sources.map{strdup($0.1)!}; defer{archiveStrings.forEach { free($0) }}
            let values=zip(sourceStrings,archiveStrings).map{LACreationSource(source_path:UnsafePointer($0.0),archive_path:UnsafePointer($0.1))}
            let level: Int32 = options.compressionLevel.map { Int32($0.libarchiveValue) } ?? -1
            let threads: Int32 = switch options.threads { case .automatic: -1; case .explicit(let count): Int32(count) }
            return destination.path.withCString { path in values.withUnsafeBufferPointer { la_create(path,profile.cProfile,$0.baseAddress,$0.count,level,threads,progressCallback,retained.toOpaque()) } }
        }.value }, onCancel: { box.cancelled=true }); try throwMapped(result,.create)
    }

    private func runTest(_ session: Session, _ continuation: AsyncThrowingStream<ProgressEvent, Error>.Continuation) async throws {
        guard let p=LibarchiveFormatProfile.profile(for:session.format) else{throw unsupported(.test)}; let box=ProgressBox(continuation,.testing), retained=Unmanaged.passRetained(box); defer{retained.release()}
        let r = await withTaskCancellationHandler(operation:{await Task.detached{session.url.path.withCString{la_test($0,p.cProfile,progressCallback,retained.toOpaque())}}.value},onCancel:{box.cancelled=true}); try throwMapped(r,.test)
    }

    private func throwMapped(_ r: LAResult, _ operation: ArchiveOperation) throws { let message=withUnsafePointer(to:r.message){$0.withMemoryRebound(to:CChar.self,capacity:512){String(cString:$0)}}; if let e=LibarchiveStatusMapper.error(status:r.status,systemErrno:r.system_errno,message:message,operation:operation){throw e} }
    private func unsupported(_ operation: ArchiveOperation) -> ArchiveBackendError { .init(.unsupportedOperation,backendIdentifier:identifier.rawValue,operation:operation,message:"Operation is not enabled for this format") }
}

private extension CompressionLevel {
    var libarchiveValue: Int { switch self { case .store: 0; case .fastest: 1; case .fast: 3; case .normal: 5; case .maximum: 7; case .ultra: 9 } }
}

private func enumerate(_ roots: [URL], standalone: Bool) throws -> [(URL,String)] {
    if standalone { guard roots.count == 1, (try roots[0].resourceValues(forKeys:[.isRegularFileKey])).isRegularFile == true else { throw ArchiveBackendError(.unsupportedOperation,backendIdentifier:"libarchive",operation:.create,message:"Standalone compression requires exactly one regular file") }; return [(roots[0], "data")] }
    var out:[(URL,String)]=[]; let fm=FileManager.default
    for root in roots { out.append((root,root.lastPathComponent)); if (try root.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])).isDirectory == true { let keys:[URLResourceKey]=[.isDirectoryKey,.isSymbolicLinkKey]; guard let e=fm.enumerator(at:root,includingPropertiesForKeys:keys,options:[.skipsPackageDescendants,.skipsHiddenFiles]) else{continue}; for case let child as URL in e { let values=try child.resourceValues(forKeys:Set(keys)); if values.isSymbolicLink == true { e.skipDescendants() }; let components=child.pathComponents; guard let rootIndex=components.lastIndex(of:root.lastPathComponent) else{continue}; let rel=components.dropFirst(rootIndex+1).joined(separator:"/"); out.append((child,root.lastPathComponent+"/"+rel)) } } }
    return out.sorted{$0.1<$1.1}
}
private func resolveConflict(at url:URL,_ resolution:ConflictResolution)throws{guard FileManager.default.fileExists(atPath:url.path)else{return};switch resolution{case .replace:try FileManager.default.removeItem(at:url);case .skip:throw ArchiveBackendError(.destinationUnavailable,backendIdentifier:"libarchive",operation:.extract,message:"Destination exists: \(url.path)");case .keepBoth,.ask:throw ArchiveBackendError(.destinationUnavailable,backendIdentifier:"libarchive",operation:.extract,message:"Conflict resolution requires the application layer")}}
private func restoreMetadata(_ entry:ArchiveEntry,at url:URL)throws{var attributes:[FileAttributeKey:Any]=[:];if let mode=entry.posixMode{attributes[.posixPermissions]=NSNumber(value:mode)};if let date=entry.modificationDate{attributes[.modificationDate]=date};if !attributes.isEmpty{try FileManager.default.setAttributes(attributes,ofItemAtPath:url.path)}}
