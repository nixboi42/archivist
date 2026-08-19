import Domain
import SwiftUI

struct ArchiveInspectorView: View {
    let entries: [ArchiveEntry]
    var body: some View {
        Form {
            if entries.count == 1, let entry = entries.first {
                Section("Entry") {
                    LabeledContent("Path", value: entry.path)
                    LabeledContent("Type", value: kindName(entry.kind))
                    optional("Original Size", formatBytes(entry.uncompressedSize), available: entry.uncompressedSize != nil)
                    optional("Packed Size", formatBytes(entry.compressedSize), available: entry.compressedSize != nil)
                    if let original = entry.uncompressedSize, let packed = entry.compressedSize, original > 0 {
                        LabeledContent("Ratio", value: ((Double(packed) / Double(original)).formatted(.percent.precision(.fractionLength(1)))))
                    }
                    if let date = entry.modificationDate { LabeledContent("Modified", value: date.formatted()) }
                    if let mode = entry.posixMode { LabeledContent("Permissions", value: String(format: "%04o", mode)) }
                    if let checksum = entry.checksum { LabeledContent("Checksum", value: checksum) }
                    LabeledContent("Encrypted", value: entry.isEncrypted ? "Yes" : "No")
                    if let target = entry.linkTarget { LabeledContent("Link Target", value: target) }
                }
            } else if entries.isEmpty {
                ContentUnavailableView("No Selection", systemImage: "info.circle", description: Text("Select an entry to inspect it."))
            } else { Text("\(entries.count) entries selected").foregroundStyle(.secondary) }
        }.formStyle(.grouped).frame(minWidth: 260, idealWidth: 300).accessibilityLabel("Archive entry inspector")
    }

    @ViewBuilder private func optional(_ label: String, _ value: String, available: Bool) -> some View {
        if available { LabeledContent(label, value: value) }
    }
}
