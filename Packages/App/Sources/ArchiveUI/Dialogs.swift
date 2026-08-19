import ArchiveApplication
import Domain
import SwiftUI

public struct ConflictSheet: View {
    let prompt: ConflictResolutionBroker.Prompt
    let answer: (ConflictResolution, Bool) -> Void
    public init(prompt: ConflictResolutionBroker.Prompt, answer: @escaping (ConflictResolution, Bool) -> Void) { self.prompt = prompt; self.answer = answer }
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("An Item Already Exists", systemImage: "exclamationmark.triangle").font(.title2)
            Text(prompt.context.destinationURL.path(percentEncoded: false)).textSelection(.enabled).foregroundStyle(.secondary)
            Text("Choose how Archivist should handle this conflict.")
            HStack {
                Button("Skip") { answer(.skip, false) }
                Button("Skip All") { answer(.skip, true) }
                Spacer()
                Button("Keep Both") { answer(.keepBoth, false) }
                Button("Replace") { answer(.replace, false) }
                Button("Replace All") { answer(.replace, true) }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520)
    }
}

public struct ErrorSheet: View {
    let presentation: ErrorPresentation
    let dismiss: () -> Void
    @State private var details = false
    public init(presentation: ErrorPresentation, dismiss: @escaping () -> Void = {}) { self.presentation = presentation; self.dismiss = dismiss }
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(presentation.title, systemImage: "exclamationmark.triangle").font(.title2)
            Text(presentation.message)
            if let value = presentation.details { DisclosureGroup("Details", isExpanded: $details) { Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled) } }
            HStack { Spacer(); Button("OK") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 460)
    }
}

struct VerificationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let result: TestArchiveResult
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Archive Verification", systemImage: "checkmark.shield").font(.title2)
            LabeledContent("Backend", value: result.backendIdentifier.rawValue)
            if case .xip(let details) = result.details {
                GroupBox("XIP Verification") {
                    VStack(alignment: .leading) {
                        LabeledContent("Container", value: details.containerStructure.rawValue)
                        LabeledContent("Checksum", value: details.containerChecksum.rawValue)
                        LabeledContent("Signature", value: details.cryptographicSignature.rawValue)
                        LabeledContent("Signer Trust", value: details.signerTrust.rawValue)
                        if let payload = details.payloadIntegrity { LabeledContent("Payload", value: payload.rawValue) }
                    }.padding(6)
                }
            } else { Text("The archive passed the backend verification checks.") }
            ForEach(result.warnings, id: \.self) { warning in Label(warning.message, systemImage: "exclamationmark.triangle") }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 480)
    }
}
