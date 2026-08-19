import AppKit
import ArchiveApplication
import BackendProtocol
import BackendRegistry
import Combine
import Domain
import SwiftUI

@MainActor
final class CreationSheetModel: ObservableObject {
    @Published var sources: [URL] = []
    @Published var destination: URL?
    @Published var formats: [CreationFormatOption] = []
    @Published var selectedFormat: ArchiveFormat?
    @Published var compressionLevel: CompressionLevel = .normal
    @Published var method: CompressionMethod?
    @Published var dictionarySize: UInt64?
    @Published var wordSize: Int?
    @Published var solidMode: SolidMode = .automatic
    @Published var automaticThreads = true
    @Published var threadCount = min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 64)
    @Published var encryptFileNames = false
    @Published var volumePreset: UInt64?
    @Published var customVolumeSize = ""
    @Published var password = ""
    @Published var advanced = false
    private let registry: ArchiveBackendRegistry

    init(registry: ArchiveBackendRegistry, initialSources: [URL] = [], initialFormat: ArchiveFormat? = nil) {
        self.registry = registry; sources = initialSources; selectedFormat = initialFormat
    }
    func load() async {
        formats = await AvailableCreationFormatsUseCase(registry: registry).execute()
        if selectedFormat == nil { selectedFormat = formats.first?.format }
    }
    var selectedOption: CreationFormatOption? { formats.first { $0.format == selectedFormat } }
    var optionCapabilities: CreationOptionCapabilities? { selectedOption?.capabilities.creationOptions }
    var canCreate: Bool { request() != nil }

    func normalizeOptionsForSelectedFormat() {
        guard let capabilities = optionCapabilities else { return }
        if let method, !capabilities.methods.contains(method) { self.method = nil }
        if let dictionarySize, !capabilities.dictionarySizes.contains(dictionarySize) { self.dictionarySize = nil }
        if let wordSize, !capabilities.wordSizes.contains(wordSize) { self.wordSize = nil }
        if !capabilities.supportsSolid { solidMode = .automatic }
        if !capabilities.supportsThreadCount { automaticThreads = true }
        if !capabilities.supportsHeaderEncryption { encryptFileNames = false }
        if !capabilities.supportsVolumes { volumePreset = nil; customVolumeSize = "" }
        if !capabilities.compressionLevels.contains(compressionLevel) {
            compressionLevel = capabilities.compressionLevels.contains(.normal)
                ? .normal : (CompressionLevel.allCases.first { capabilities.compressionLevels.contains($0) } ?? .normal)
        }
    }

    func chooseSources() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { sources = panel.urls }
    }
    func chooseDestination() {
        let panel = NSSavePanel(); panel.canCreateDirectories = true
        if let ext = selectedFormat?.canonicalExtension { panel.allowedContentTypes = []; panel.nameFieldStringValue = "Archive.\(ext)" }
        if panel.runModal() == .OK { destination = panel.url }
    }
    func request() -> CreationRequest? {
        guard let destination, let format = selectedFormat else { return nil }
        let credential = password.isEmpty ? nil : ArchiveCredential(password: password)
        guard !sources.isEmpty, let capabilities = optionCapabilities else { return nil }
        let volume: VolumeSize?
        if !customVolumeSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let parsed = try? VolumeSize(parsing: customVolumeSize) else { return nil }
            volume = parsed
        } else if let volumePreset {
            guard let preset = try? VolumeSize(bytes: volumePreset) else { return nil }
            volume = preset
        } else { volume = nil }
        let options = CreationOptions(format: format,
            compressionLevel: capabilities.compressionLevels.contains(compressionLevel) ? compressionLevel : nil,
            method: method, dictionarySize: dictionarySize, wordSize: wordSize,
            solidMode: solidMode, threads: automaticThreads ? .automatic : .explicit(threadCount),
            encryptFileNames: encryptFileNames, volumeSize: volume, credential: credential)
        guard (try? options.validate(against: capabilities)) != nil else { return nil }
        return .init(sourceURLs: sources, destinationURL: destination, options: options, overwritePolicy: .ask)
    }
}

struct CreationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form: CreationSheetModel
    let create: (CreationRequest) -> Void
    init(registry: ArchiveBackendRegistry, initialSources: [URL] = [], initialFormat: ArchiveFormat? = nil,
         create: @escaping (CreationRequest) -> Void) {
        _form = StateObject(wrappedValue: CreationSheetModel(registry: registry, initialSources: initialSources,
                                                              initialFormat: initialFormat)); self.create = create
    }
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Sources") {
                    HStack { Text(form.sources.isEmpty ? "No files selected" : "\(form.sources.count) item(s)"); Spacer(); Button("Choose…") { form.chooseSources() } }
                }
                Section("Archive") {
                    Picker("Format", selection: $form.selectedFormat) {
                        ForEach(form.formats) { option in Text(option.displayName).tag(Optional(option.format)) }
                    }
                    HStack { Text("Destination"); Spacer(); Text(form.destination?.path(percentEncoded: false) ?? "Not selected").lineLimit(1).foregroundStyle(.secondary); Button("Choose…") { form.chooseDestination() } }
                    if let capabilities = form.optionCapabilities, !capabilities.compressionLevels.isEmpty {
                        Picker("Compression", selection: $form.compressionLevel) {
                            ForEach(CompressionLevel.allCases.filter(capabilities.compressionLevels.contains), id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                    }
                    if form.selectedOption?.capabilities.encryptionCreate != nil {
                        SecureField("Password (optional)", text: $form.password).privacySensitive().textContentType(.password)
                    }
                }
                DisclosureGroup("Advanced", isExpanded: $form.advanced) {
                    if let capabilities = form.optionCapabilities {
                        if !capabilities.methods.isEmpty {
                            Picker("Method", selection: $form.method) {
                                Text("Automatic").tag(Optional<CompressionMethod>.none)
                                ForEach(CompressionMethod.allCases.filter(capabilities.methods.contains), id: \.self) {
                                    Text($0.displayName).tag(Optional($0))
                                }
                            }
                        }
                        if !capabilities.dictionarySizes.isEmpty {
                            Picker("Dictionary", selection: $form.dictionarySize) {
                                Text("Automatic").tag(Optional<UInt64>.none)
                                ForEach(capabilities.dictionarySizes.sorted(), id: \.self) { size in
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .memory)).tag(Optional(size))
                                }
                            }
                            Text("Larger dictionaries can improve compression but require more memory.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !capabilities.wordSizes.isEmpty {
                            Picker("Word size", selection: $form.wordSize) {
                                Text("Automatic").tag(Optional<Int>.none)
                                ForEach(capabilities.wordSizes.sorted(), id: \.self) { Text("\($0)").tag(Optional($0)) }
                            }
                        }
                        if capabilities.supportsSolid {
                            Picker("Solid archive", selection: $form.solidMode) {
                                Text("Automatic").tag(SolidMode.automatic); Text("Off").tag(SolidMode.off); Text("On").tag(SolidMode.on)
                            }
                        }
                        if capabilities.supportsThreadCount {
                            Toggle("Automatic threads", isOn: $form.automaticThreads)
                            if !form.automaticThreads { Stepper("Threads: \(form.threadCount)", value: $form.threadCount, in: 1...min(max(ProcessInfo.processInfo.activeProcessorCount, 1), 64)) }
                        }
                        if capabilities.supportsHeaderEncryption && !form.password.isEmpty {
                            Toggle("Encrypt file names", isOn: $form.encryptFileNames)
                        }
                        if capabilities.supportsVolumes {
                            Picker("Split into volumes", selection: $form.volumePreset) {
                                Text("None").tag(Optional<UInt64>.none)
                                Text("10 MB").tag(Optional(UInt64(10_000_000)))
                                Text("100 MB").tag(Optional(UInt64(100_000_000)))
                                Text("700 MB").tag(Optional(UInt64(700_000_000)))
                                Text("1 GB").tag(Optional(UInt64(1_000_000_000)))
                                Text("4 GB").tag(Optional(UInt64(4_000_000_000)))
                            }
                            TextField("Custom size (for example, 250 MiB)", text: $form.customVolumeSize)
                        }
                    } else { Text("No additional verified options for this format.").foregroundStyle(.secondary) }
                }
            }.formStyle(.grouped)
            Divider()
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Create") { if let request = form.request() { create(request) } }.keyboardShortcut(.defaultAction).disabled(!form.canCreate) }.padding()
        }.frame(width: 520, height: 540).task { await form.load(); form.normalizeOptionsForSelectedFormat() }
            .onChange(of: form.selectedFormat) { _, _ in form.normalizeOptionsForSelectedFormat() }
    }
}

private extension CompressionLevel {
    var displayName: String { switch self { case .store: "Store / None"; case .fastest: "Fastest"; case .fast: "Fast"; case .normal: "Normal"; case .maximum: "Maximum"; case .ultra: "Ultra" } }
}
private extension CompressionMethod {
    var displayName: String { switch self { case .copy: "Copy"; case .lzma2: "LZMA2"; case .lzma: "LZMA"; case .ppmd: "PPMd"; case .deflate: "Deflate"; case .deflate64: "Deflate64"; case .bzip2: "BZip2" } }
}
