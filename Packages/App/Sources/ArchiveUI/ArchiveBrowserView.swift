import Domain
import SwiftUI

public struct ArchiveBrowserView: View {
    @ObservedObject private var model: ArchiveAppModel
    public init(model: ArchiveAppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            BreadcrumbView(components: model.browser.currentPath) { model.browser.navigate(to: $0) }
            Divider()
            ArchiveEntryTable(model: model)
            .searchable(text: $model.browser.searchText, placement: .toolbar, prompt: "Search Archive")
            .overlay {
                if model.browser.visibleEntries.isEmpty && !model.isScanning {
                    ContentUnavailableView("No Entries", systemImage: "doc.text.magnifyingglass",
                                           description: Text(model.browser.searchText.isEmpty ? "This folder is empty." : "No entries match your search."))
                }
            }
            if model.isScanning {
                HStack { ProgressView().controlSize(.small); Text("Scanning… \(model.scanCount) entries").foregroundStyle(.secondary); Spacer() }
                    .padding(.horizontal).padding(.vertical, 7).background(.bar)
                    .accessibilityLabel("Scanning archive, \(model.scanCount) entries discovered")
            }
        }
    }
}

private struct BreadcrumbView: View {
    let components: [String]
    let navigate: (Int) -> Void
    var body: some View {
        HStack(spacing: 4) {
            Button { navigate(0) } label: { Label("Archive Root", systemImage: "archivebox") }.buttonStyle(.plain)
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                Button(component) { navigate(index + 1) }.buttonStyle(.plain)
            }
            Spacer()
        }.padding(.horizontal, 12).frame(height: 34)
    }
}

func formatBytes(_ value: UInt64?) -> String {
    guard let value else { return "—" }
    return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
}

func kindName(_ kind: ArchiveEntryKind) -> String {
    switch kind { case .regularFile: "File"; case .directory: "Folder"; case .symbolicLink: "Symbolic Link"; case .hardLink: "Hard Link"; default: kind.rawValue }
}
