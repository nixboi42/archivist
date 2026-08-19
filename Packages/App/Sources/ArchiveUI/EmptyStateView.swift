import SwiftUI

struct EmptyStateView: View {
    let open: () -> Void
    let create: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Open an Archive", systemImage: "archivebox")
        } description: {
            Text("Browse, verify, create, and safely extract archives.")
        } actions: {
            HStack {
                Button("Open Archive…", action: open).keyboardShortcut("o")
                Button("Create Archive…", action: create)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
