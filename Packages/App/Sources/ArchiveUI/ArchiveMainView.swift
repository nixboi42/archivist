import BackendProtocol
import Domain
import SwiftUI
import UniformTypeIdentifiers

public struct ArchiveMainView: View {
    @ObservedObject private var model: ArchiveAppModel
    private weak var presentation: (any ApplicationPresenting)?
    @State private var droppedSources: [URL] = []
    public init(model: ArchiveAppModel, presentation: (any ApplicationPresenting)? = nil) { self.model = model; self.presentation = presentation }

    public var body: some View {
        Group {
            if model.archiveURL == nil { EmptyStateView(open: model.presentOpenPanel, create: { model.beginCreation() }) }
            else { ArchiveBrowserView(model: model) }
        }
        .navigationTitle(model.archiveURL?.lastPathComponent ?? "Archivist")
        .frame(minWidth: 820, minHeight: 520)
        .toolbar { toolbar }
        .inspector(isPresented: $model.showingInspector) { ArchiveInspectorView(entries: model.selectedEntries) }
        .sheet(isPresented: $model.showingCreation) {
            CreationView(registry: model.registry,
                         initialSources: model.pendingCreationSources.isEmpty ? droppedSources : model.pendingCreationSources,
                         initialFormat: model.pendingCreationFormat) { model.startCreation($0) }
        }
        .sheet(isPresented: verificationPresented) { if let result = model.verificationResult { VerificationSheet(result: result) } }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil, perform: handleDrop)
        .safeAreaInset(edge: .bottom) {
            if let warning = model.previewWarning {
                HStack { Image(systemName: "info.circle"); Text(warning.message).font(.caption); Spacer(); Button("Dismiss") { model.previewWarning = nil }.buttonStyle(.plain) }
                    .padding(.horizontal).padding(.vertical, 7).background(.bar)
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { model.browser.goBack() } label: { Label("Back", systemImage: "chevron.left") }.disabled(model.browser.currentPath.isEmpty)
            Button { model.presentExtractionPanel(selectedOnly: false) } label: { Label("Extract", systemImage: "square.and.arrow.down") }.disabled(model.archiveURL == nil)
            Button { model.testArchive() } label: { Label("Test Archive", systemImage: "checkmark.shield") }.disabled(model.archiveURL == nil)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { presentation?.presentJobs() } label: { Label("Show Jobs", systemImage: "clock") }
            Button { model.showingInspector.toggle() } label: { Label("Toggle Inspector", systemImage: "sidebar.right") }
        }
    }

    private var verificationPresented: Binding<Bool> {
        .init(get: { model.verificationResult != nil }, set: { if !$0 { model.verificationResult = nil } })
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                if likelyArchive(url) { model.open(url) }
                else { droppedSources = [url]; model.beginCreation(sources: [url]) }
            }
        }
        return true
    }

    private func likelyArchive(_ url: URL) -> Bool {
        let extensions = ["7z","zip","jar","apk","epub","rar","tar","gz","tgz","bz2","xz","cpio","cab","arj","xar","xip","aar"]
        return extensions.contains(url.pathExtension.lowercased())
    }
}

public struct ArchiveCommands: Commands {
    @ObservedObject private var model: ArchiveAppModel
    private weak var presentation: (any ApplicationPresenting)?
    public init(model: ArchiveAppModel, presentation: (any ApplicationPresenting)? = nil) { self.model = model; self.presentation = presentation }
    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Archive…") { presentation?.presentMainWindow(); model.presentOpenPanel() }.keyboardShortcut("o")
            Button("Create Archive…") { presentation?.presentMainWindow(); model.beginCreation() }.keyboardShortcut("n")
            Divider()
            Button("Close Archive") { model.closeArchive() }.keyboardShortcut("w").disabled(model.archiveURL == nil)
        }
        CommandMenu("Archive") {
            Button("Test Archive") { model.testArchive() }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(model.archiveURL == nil)
            Divider()
            Button("Extract Selected…") { model.presentExtractionPanel(selectedOnly: true) }.disabled(model.selection.isEmpty)
            Button("Extract All…") { model.presentExtractionPanel(selectedOnly: false) }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.archiveURL == nil)
        }
        CommandGroup(after: .windowArrangement) {
            Button("Show Jobs") { presentation?.presentJobs() }.keyboardShortcut("j", modifiers: [.command, .shift])
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Inspector") { model.showingInspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
