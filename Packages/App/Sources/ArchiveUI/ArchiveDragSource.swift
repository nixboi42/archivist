import AppKit
import ArchiveApplication
import BackendProtocol
import Domain
import SwiftUI
import UniformTypeIdentifiers

final class ArchiveDragExportSession: @unchecked Sendable {
    private let useCase: ArchiveDragExportUseCase
    private let archiveURL: URL
    private let selectedEntryIDs: Set<ArchiveEntry.ID>
    private let initialCredential: ArchiveCredential?
    private let securityPolicy: SecurityPolicy
    private let queue: JobQueue
    private let requestCredential: @MainActor @Sendable () async -> ArchiveCredential?
    private let presentError: @MainActor @Sendable (ApplicationError) -> Void
    private let lock = NSLock()
    private var artifactTask: Task<ArchiveDragExportArtifact, Error>?
    private var artifact: ArchiveDragExportArtifact?
    private var ended = false
    private var activeWrites = 0

    init(useCase: ArchiveDragExportUseCase, archiveURL: URL, selectedEntryIDs: Set<ArchiveEntry.ID>,
         initialCredential: ArchiveCredential?, securityPolicy: SecurityPolicy, queue: JobQueue,
         requestCredential: @escaping @MainActor @Sendable () async -> ArchiveCredential?,
         presentError: @escaping @MainActor @Sendable (ApplicationError) -> Void) {
        self.useCase = useCase; self.archiveURL = archiveURL; self.selectedEntryIDs = selectedEntryIDs
        self.initialCredential = initialCredential; self.securityPolicy = securityPolicy
        self.queue = queue
        self.requestCredential = requestCredential; self.presentError = presentError
    }

    func promisedURL(for entryID: ArchiveEntry.ID) async throws -> URL {
        beginWrite()
        defer { finishWrite() }
        do {
            let artifact = try await sharedArtifact()
            guard let url = artifact.promisedURLsByEntryID[entryID] else {
                throw ApplicationError(.backendFailure, message: "The dragged archive item was not exported",
                                       diagnosticCode: "DRAG_EXPORT_PROMISE_MISSING")
            }
            return url
        } catch {
            let mapped = ApplicationError.map(error)
            await presentError(mapped)
            throw mapped
        }
    }

    func end() {
        lock.withLock { ended = true }
        scheduleCleanupIfFinished()
    }

    func cancel() {
        let values = lock.withLock { () -> (Task<ArchiveDragExportArtifact, Error>?, ArchiveDragExportArtifact?) in
            ended = true; return (artifactTask, artifact)
        }
        values.0?.cancel(); values.1?.cleanup()
    }

    private func sharedArtifact() async throws -> ArchiveDragExportArtifact {
        let task: Task<ArchiveDragExportArtifact, Error> = lock.withLock {
            if let artifactTask { return artifactTask }
            let task = Task { [useCase, archiveURL, selectedEntryIDs, initialCredential, securityPolicy, requestCredential, queue] in
                func run(_ credential: ArchiveCredential?) async throws -> ArchiveDragExportArtifact {
                    let relay = DragArtifactRelay()
                    let descriptor = JobDescriptor(kind: .extract, sourceURLs: [archiveURL])
                    await queue.enqueue(descriptor) { report in
                        do {
                            let artifact = try await useCase.execute(
                                .init(archiveURL: archiveURL, selectedEntryIDs: selectedEntryIDs,
                                      credential: credential, securityPolicy: securityPolicy), onProgress: report)
                            relay.resolve(.success(artifact))
                        } catch { relay.resolve(.failure(error)); throw error }
                    }
                    return try await withTaskCancellationHandler {
                        try await relay.value()
                    } onCancel: { Task { await queue.cancel(descriptor.id) } }
                }
                do { return try await run(initialCredential) }
                catch let error as ApplicationError where error.code == .wrongPassword {
                    guard let credential = await requestCredential() else {
                        throw ApplicationError(.cancelled, message: "Password entry was cancelled",
                                               diagnosticCode: "DRAG_EXPORT_PASSWORD_CANCELLED")
                    }
                    return try await run(credential)
                }
            }
            artifactTask = task; return task
        }
        let value = try await task.value
        lock.withLock { artifact = value }
        return value
    }

    private func beginWrite() { lock.withLock { activeWrites += 1 } }
    private func finishWrite() { lock.withLock { activeWrites = max(0, activeWrites - 1) }; scheduleCleanupIfFinished() }
    private func scheduleCleanupIfFinished() {
        let value = lock.withLock { ended && activeWrites == 0 ? artifact : nil }
        guard let value else { return }
        Task { try? await Task.sleep(for: .seconds(30)); value.cleanup() }
    }
}

private final class DragArtifactRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<ArchiveDragExportArtifact, Error>?
    private var continuation: CheckedContinuation<ArchiveDragExportArtifact, Error>?
    func resolve(_ result: Result<ArchiveDragExportArtifact, Error>) {
        let waiter = lock.withLock { () -> CheckedContinuation<ArchiveDragExportArtifact, Error>? in
            guard self.result == nil else { return nil }
            self.result = result; let value = continuation; continuation = nil; return value
        }
        waiter?.resume(with: result)
    }
    func value() async throws -> ArchiveDragExportArtifact {
        try await withCheckedThrowingContinuation { continuation in
            let ready = lock.withLock { () -> Result<ArchiveDragExportArtifact, Error>? in
                if let result { return result }
                self.continuation = continuation; return nil
            }
            if let ready { continuation.resume(with: ready) }
        }
    }
}

private final class ArchiveFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let entry: ArchiveEntry
    let session: ArchiveDragExportSession
    private let promiseQueue: OperationQueue
    init(entry: ArchiveEntry, session: ArchiveDragExportSession) {
        self.entry = entry; self.session = session
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        self.promiseQueue = queue
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        entry.path.split(separator: "/").last.map(String.init) ?? entry.path
    }

    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        let session = session, entryID = entry.id
        let completion = PromiseCompletion(completionHandler)
        Task.detached {
            do {
                let staged = try await session.promisedURL(for: entryID)
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: staged, to: url)
                completion.call(nil)
            } catch { completion.call(error) }
        }
    }

    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        promiseQueue
    }
}

private final class PromiseCompletion: @unchecked Sendable {
    private let callback: (Error?) -> Void
    init(_ callback: @escaping (Error?) -> Void) { self.callback = callback }
    func call(_ error: Error?) { callback(error) }
}

struct ArchiveEntryTable: NSViewRepresentable {
    @ObservedObject var model: ArchiveAppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.doubleAction = #selector(Coordinator.doubleClick(_:)); table.target = context.coordinator
        for (id, title, width) in [("name", "Name", 280.0), ("size", "Size", 90), ("packed", "Packed Size", 100),
                                   ("kind", "Kind", 110), ("modified", "Modified", 150), ("checksum", "Checksum", 120)] {
            let column = NSTableColumn(identifier: .init(id)); column.title = title; column.width = width
            if id == "name" { column.minWidth = 180 }
            table.addTableColumn(column)
        }
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.model = model
        let visibleEntries = model.browser.visibleEntries
        if context.coordinator.entrySnapshot != visibleEntries.map({ EntrySnapshot($0) }) {
            context.coordinator.entries = visibleEntries
            context.coordinator.entrySnapshot = visibleEntries.map({ EntrySnapshot($0) })
            context.coordinator.table?.reloadData()
        }
        let indexes = IndexSet(context.coordinator.entries.indices.filter { model.selection.contains(context.coordinator.entries[$0].id) })
        if context.coordinator.table?.selectedRowIndexes != indexes {
            context.coordinator.isApplyingSwiftUIState = true
            context.coordinator.table?.selectRowIndexes(indexes, byExtendingSelection: false)
            context.coordinator.isApplyingSwiftUIState = false
        }
    }

    fileprivate struct EntrySnapshot: Equatable {
        let id: ArchiveEntry.ID
        let path: String
        let kind: ArchiveEntryKind
        let uncompressedSize: UInt64?
        let compressedSize: UInt64?
        let modificationDate: Date?
        let checksum: String?
        init(_ entry: ArchiveEntry) {
            id = entry.id; path = entry.path; kind = entry.kind
            uncompressedSize = entry.uncompressedSize; compressedSize = entry.compressedSize
            modificationDate = entry.modificationDate; checksum = entry.checksum
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var model: ArchiveAppModel
        var entries: [ArchiveEntry] = []
        fileprivate var entrySnapshot: [EntrySnapshot] = []
        var isApplyingSwiftUIState = false
        weak var table: NSTableView?
        private var session: ArchiveDragExportSession?
        private var promiseDelegates: [ArchiveFilePromiseDelegate] = []
        private var retainedPromiseDelegates: [ArchiveFilePromiseDelegate] = []
        init(model: ArchiveAppModel) { self.model = model }

        func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSwiftUIState, let table else { return }
            model.selection = Set(table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0].id : nil })
        }
        @objc func doubleClick(_ sender: NSTableView) {
            guard sender.clickedRow >= 0, entries.indices.contains(sender.clickedRow) else { return }
            model.activate(entries[sender.clickedRow])
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard entries.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
            let entry = entries[row], text: String
            switch identifier.rawValue {
            case "name": text = entry.path.split(separator: "/").last.map(String.init) ?? entry.path
            case "size": text = formatBytes(entry.uncompressedSize)
            case "packed": text = formatBytes(entry.compressedSize)
            case "kind": text = kindName(entry.kind)
            case "modified": text = entry.modificationDate?.formatted(date: .numeric, time: .shortened) ?? "—"
            default: text = entry.checksum ?? "—"
            }
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView) ?? NSTableCellView()
            cell.identifier = identifier
            let field = cell.textField ?? NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingMiddle
            if cell.textField == nil { cell.textField = field; field.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(field); NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4), field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4), field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)]) }
            field.stringValue = text
            if identifier.rawValue == "name" { cell.imageView = NSImageView(image: NSImage(systemSymbolName: entry.kind == .directory ? "folder" : "doc", accessibilityDescription: nil) ?? NSImage()) }
            return cell
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard entries.indices.contains(row) else { return nil }
            let selectedRows = tableView.selectedRowIndexes.isEmpty ? IndexSet(integer: row) : tableView.selectedRowIndexes
            let selectedEntries = selectedRows.compactMap { entries.indices.contains($0) ? entries[$0] : nil }
            let selectedIDs = Set(selectedEntries.map(\.id))
            if session == nil { session = model.makeDragExportSession(entryIDs: selectedIDs); promiseDelegates = [] }
            guard let session else { return nil }
            let entry = entries[row]
            if selectedEntries.contains(where: { $0.kind == .directory && $0.id != entry.id && entry.path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }) { return nil }
            let type = entry.kind == .directory ? UTType.folder.identifier : (UTType(filenameExtension: URL(fileURLWithPath: entry.path).pathExtension)?.identifier ?? UTType.data.identifier)
            let delegate = ArchiveFilePromiseDelegate(entry: entry, session: session); promiseDelegates.append(delegate)
            return NSFilePromiseProvider(fileType: type, delegate: delegate)
        }
        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            self.session?.end(); self.session = nil
            retainedPromiseDelegates.append(contentsOf: promiseDelegates); promiseDelegates = []
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T { lock(); defer { unlock() }; return try body() }
}
