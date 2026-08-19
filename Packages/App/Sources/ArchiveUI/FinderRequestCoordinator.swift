import ArchiveApplication
import BackendRegistry
import Domain
import FinderIntegration
import Foundation
import OSLog

@MainActor
public final class FinderRequestCoordinator {
    private static let logger = Logger(subsystem: "com.keremgurevin.Archivist", category: "finder-conflict-policy")
    private unowned let model: ArchiveAppModel
    private let transport: (any FinderRequestTransport)?
    private weak var presentation: (any ApplicationPresenting)?
    private let presentationPolicy: FinderPresentationPolicy
    public init(model: ArchiveAppModel, transport: (any FinderRequestTransport)? = nil,
                presentation: (any ApplicationPresenting)? = nil,
                presentationPolicy: FinderPresentationPolicy = .init()) {
        self.model = model; self.transport = transport; self.presentation = presentation
        self.presentationPolicy = presentationPolicy
    }

    public func handle(_ activationURL: URL) {
        Task {
            do {
                let selectedTransport: any FinderRequestTransport
                if let transport {
                    selectedTransport = transport
                } else {
                    selectedTransport = try FinderRequestTransportConfiguration.make(bundle: .main)
                }
                try route(try await selectedTransport.receive(from: activationURL))
                if (try? FinderRequestTransportConfiguration.mode(bundle: .main)) == .appGroup {
                    await publishCapabilitySnapshot()
                }
            } catch {
                model.errorPresentation = .init(ApplicationError(.filesystemFailure,
                    message: "The Finder request could not be validated or has expired.",
                    diagnosticCode: "FINDER_REQUEST_REJECTED"))
            }
        }
    }

    public func route(_ request: ArchiveFinderRequest) throws {
        let requestedPresentation = presentationPolicy.presentation(for: request.action)
        if requestedPresentation == .mainWindow { presentation?.presentMainWindow() }
        switch request.action {
        case .openArchive:
            guard let url = request.urls.first else { throw FinderRequestError.invalidURLCount }
            model.open(url)
        case .extractHere:
            for archive in request.urls {
                let destination = FinderDestinationPolicy.extractHere(for: archive)
                Self.logger.notice("Finder Extract Here routed through application extraction policy; destination=\(destination.path, privacy: .private(mask: .hash))")
                model.startExtractionForFinder(archive: archive, destination: destination)
            }
        case .extractToNamed:
            for archive in request.urls {
                let destination = FinderDestinationPolicy.extractToNamedDirectory(for: archive)
                Self.logger.notice("Finder Extract to Named routed through application extraction policy; destination=\(destination.path, privacy: .private(mask: .hash))")
                model.startExtractionForFinder(archive: archive, destination: destination)
            }
        case .extractTo:
            guard let archive = request.urls.first else { throw FinderRequestError.invalidURLCount }
            presentation?.presentExtractionDestination(for: archive) { [weak model] destination in
                Self.logger.notice("Finder Extract To destination accepted; routing through application extraction policy; destination=\(destination.path, privacy: .private(mask: .hash))")
                model?.startExtractionForFinder(archive: archive, destination: destination)
            }
        case .createSevenZip:
            model.startFinderCreation(sources: request.urls, format: .sevenZip,
                                      destination: try FinderCreationDestinationPolicy.destination(for: request.urls, format: .sevenZip))
        case .createZIP:
            let format = ArchiveFormat.zip(.zip)
            model.startFinderCreation(sources: request.urls, format: format,
                                      destination: try FinderCreationDestinationPolicy.destination(for: request.urls, format: format))
        case .createArchive: model.beginCreation(sources: request.urls)
        }
    }

    public func publishCapabilitySnapshot() async {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: FinderRequestStore.appGroupIdentifier
        ) else { return }
        let candidates: [ArchiveFormat] = [.sevenZip,.zip(.zip),.zip(.jar),.zip(.apk),.zip(.epub),.rar,.tar,.tarGzip,
            .tarBzip2,.tarXZ,.gzip,.bzip2,.xz,.cpio,.cab,.arj,.xar,.xip,.appleArchive]
        var readable = Set<ArchiveFormat>()
        for format in candidates where (try? await model.registry.select(format: format, operation: .read)) != nil { readable.insert(format) }
        let snapshot = FinderCapabilitySnapshot(readableFormats: readable,
            canCreateSevenZip: (try? await model.registry.select(format: .sevenZip, operation: .create)) != nil,
            canCreateZIP: (try? await model.registry.select(format: .zip(.zip), operation: .create)) != nil)
        try? FinderCapabilityStore(containerURL: container).save(snapshot)
    }
}
