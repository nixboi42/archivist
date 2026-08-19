import Domain
import FinderIntegration
import Foundation

public enum FinderPresentation: Equatable, Sendable {
    case mainWindow
    case destinationChooser
    case background
}

public struct FinderPresentationPolicy: Sendable {
    public init() {}

    public func presentation(for action: FinderArchiveAction) -> FinderPresentation {
        switch action {
        case .openArchive, .createArchive: .mainWindow
        case .extractTo: .destinationChooser
        case .extractHere, .extractToNamed, .createSevenZip, .createZIP: .background
        }
    }
}

public enum FinderCreationDestinationPolicy {
    public static func destination(for sources: [URL], format: ArchiveFormat) throws -> URL {
        guard let first = sources.first, let fileExtension = format.canonicalExtension else {
            throw FinderRequestError.invalidURLCount
        }
        let baseName: String
        if sources.count == 1 {
            baseName = first.hasDirectoryPath ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent
        } else {
            baseName = "Archive"
        }
        return first.deletingLastPathComponent().appendingPathComponent(baseName).appendingPathExtension(fileExtension)
    }
}

@MainActor
public protocol ApplicationPresenting: AnyObject {
    func presentMainWindow()
    func presentJobs()
    func presentExtractionDestination(for archive: URL, completion: @escaping @MainActor (URL) -> Void)
}
