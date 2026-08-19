import Domain
import FinderIntegration
import Foundation
import Testing

@Test func requestRoundTripAndOpaqueActivation() throws {
    try withStore { store in
        let request=ArchiveFinderRequest(action:.openArchive,urls:[URL(fileURLWithPath:"/tmp/a.zip")])
        try store.write(request);let activation=store.activationURL(for:request.id)
        #expect(!activation.absoluteString.contains("a.zip"));#expect(try store.requestIdentifier(from:activation)==request.id)
        #expect(try store.consume(id:request.id)==request)
    }
}

@Test func atomicStorageLeavesOnlyPermissionRestrictedFinalFile() throws {
    try withStore { store in
        let request = ArchiveFinderRequest(action: .extractHere, urls: [URL(fileURLWithPath: "/tmp/a.zip")])
        let finalURL = try store.write(request)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.rootURL.path)
        #expect(names == [finalURL.lastPathComponent])
        let attributes = try FileManager.default.attributesOfItem(atPath: finalURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}

@Test func expiredAndInvalidRequestsAreRejectedAndConsumed() throws {
    try withStore { store in
        let request=ArchiveFinderRequest(action:.extractHere,urls:[URL(fileURLWithPath:"/tmp/a.zip")],createdAt:Date(timeIntervalSinceNow:-600))
        let permissive=FinderRequestStore(rootURL:store.rootURL,maximumAge:1000);try permissive.write(request)
        #expect(throws:FinderRequestError.self){try store.consume(id:request.id)}
        #expect(throws:FinderRequestError.self){try store.consume(id:request.id)}
    }
}

@Test func consumptionPreventsReplay() throws {
    try withStore { store in
        let request=ArchiveFinderRequest(action:.createZIP,urls:[URL(fileURLWithPath:"/tmp/a")]);try store.write(request)
        _=try store.consume(id:request.id);#expect(throws:FinderRequestError.self){try store.consume(id:request.id)}
    }
}

@Test func requestRejectsNonFileURLsAndExcessiveCounts() throws {
    try withStore { store in
        #expect(throws:FinderRequestError.self){try store.write(.init(action:.openArchive,urls:[URL(string:"https://example.com")!]))}
        #expect(throws:FinderRequestError.self){try FinderRequestStore(rootURL:store.rootURL,maximumURLCount:1).write(.init(action:.createArchive,urls:[URL(fileURLWithPath:"/a"),URL(fileURLWithPath:"/b")]))}
        #expect(throws:FinderRequestError.self){try store.write(.init(action:.openArchive,urls:[URL(fileURLWithPath:"/a.zip"),URL(fileURLWithPath:"/b.zip")]))}
    }
}

@Test func extractionDestinationsHandleCompoundExtensions() {
    let zip=URL(fileURLWithPath:"/tmp/foo.zip"),tar=URL(fileURLWithPath:"/tmp/foo.tar.gz")
    #expect(FinderDestinationPolicy.extractHere(for:zip).path=="/tmp")
    #expect(FinderDestinationPolicy.extractToNamedDirectory(for:zip).path=="/tmp/foo")
    #expect(FinderDestinationPolicy.extractToNamedDirectory(for:tar).path=="/tmp/foo")
}

@Test func archiveSelectionGetsCoherentActions() {
    let policy=FinderSelectionPolicy(),snapshot=FinderCapabilitySnapshot(readableFormats:[.zip(.zip),.tarGzip],canCreateSevenZip:true,canCreateZIP:true)
    #expect(policy.actions(for:[URL(fileURLWithPath:"/a.zip")],snapshot:snapshot)==[.openArchive,.extractHere,.extractTo,.extractToNamed])
    #expect(policy.actions(for:[URL(fileURLWithPath:"/a.zip"),URL(fileURLWithPath:"/b.tar.gz")],snapshot:snapshot)==[.extractHere,.extractToNamed])
}

@Test func ordinaryAndMixedSelectionsAreDeliberate() {
    let policy=FinderSelectionPolicy(),snapshot=FinderCapabilitySnapshot(readableFormats:[.zip(.zip)],canCreateSevenZip:true,canCreateZIP:false)
    #expect(policy.actions(for:[URL(fileURLWithPath:"/a.txt"),URL(fileURLWithPath:"/folder")],snapshot:snapshot)==[.createSevenZip,.createArchive])
    #expect(policy.actions(for:[URL(fileURLWithPath:"/a.zip"),URL(fileURLWithPath:"/b.txt")],snapshot:snapshot).isEmpty)
}

@Test func missingSnapshotIsConservativeForCreation() {
    let policy=FinderSelectionPolicy()
    #expect(policy.actions(for:[URL(fileURLWithPath:"/a.txt")],snapshot:nil)==[.createArchive])
}

@Test func personalTeamTransportRoundTripsAndPreventsReplay() async throws {
    let transport = PersonalTeamDevelopmentTransport()
    let request = ArchiveFinderRequest(action: .extractHere, urls: [URL(fileURLWithPath: "/tmp/personal.zip")])
    let activation = try await transport.submit(request)
    #expect(activation.host == PersonalTeamDevelopmentTransport.activationHost)
    #expect(try await transport.receive(from: activation, now: request.createdAt) == request)
    await #expect(throws: FinderRequestError.self) {
        _ = try await transport.receive(from: activation, now: request.createdAt)
    }
}

@Test func personalTeamTransportRejectsMalformedExpiredAndMismatchedRequests() async throws {
    let transport = PersonalTeamDevelopmentTransport(maximumAge: 60)
    await #expect(throws: FinderRequestError.self) {
        _ = try await transport.receive(from: URL(string: "archivist://finder-dev-request/not-a-uuid?payload=nope")!)
    }
    let expired = ArchiveFinderRequest(
        action: .openArchive,
        urls: [URL(fileURLWithPath: "/tmp/old.zip")],
        createdAt: Date(timeIntervalSinceNow: -120)
    )
    await #expect(throws: FinderRequestError.self) { _ = try await transport.submit(expired) }
}

@Test func productionTransportUsesOpaqueAppGroupActivationSemantics() {
    let request = ArchiveFinderRequest(action: .openArchive, urls: [URL(fileURLWithPath: "/tmp/secret.zip")])
    let activation = FinderRequestStore(rootURL: URL(fileURLWithPath: "/tmp/unused")).activationURL(for: request.id)
    #expect(activation.host == "finder-request")
    #expect(!activation.absoluteString.contains("secret.zip"))
}

@Test func releaseGuardForbidsPersonalTeamFallback() throws {
    #expect(throws: FinderRequestError.self) {
        try FinderRequestBuildGuard.validate(mode: .personalTeamDevelopment, configuration: "Release")
    }
    try FinderRequestBuildGuard.validate(mode: .appGroup, configuration: "Release")
    try FinderRequestBuildGuard.validate(mode: .personalTeamDevelopment, configuration: "Debug")
}

@Test func personalTeamCreationShortcutsAreExplicitlyDevelopmentOnly() {
    let policy = FinderSelectionPolicy()
    let input = [URL(fileURLWithPath: "/tmp/source.txt")]
    #expect(policy.actions(for: input, snapshot: nil) == [.createArchive])
    #expect(policy.actions(for: input, snapshot: nil, developmentCreationShortcuts: true) == [.createSevenZip, .createZIP, .createArchive])
}

@Test func monitoredRootsRoundTrip() throws {
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?FileManager.default.removeItem(at:root)}
    let store=MonitoredRootStore(containerURL:root),configuration=MonitoredRootConfiguration(enabled:true,roots:[URL(fileURLWithPath:"/custom")],allowExternalVolumes:true)
    try store.save(configuration);#expect(store.load()==configuration)
}

@Test func personalTeamRootsResolveWithoutAppGroupConfiguration() {
    let roots = PersonalTeamMonitoredRoots.resolve()
    let home = PersonalTeamMonitoredRoots.currentUserHomeURL()
    let desktop = home?.appendingPathComponent("Desktop", isDirectory: true).standardizedFileURL
    let downloads = home?.appendingPathComponent("Downloads", isDirectory: true).standardizedFileURL
    #expect(!roots.isEmpty)
    #expect(roots.allSatisfy { $0.isFileURL })
    #expect(desktop.map(roots.contains) == true)
    #expect(downloads.map(roots.contains) == true)
}

@Test func personalTeamProjectionUsesAuthoritativeCapabilityPolicy() {
    let snapshot = PersonalTeamFinderCapabilityProjection.makeSnapshot()
    #expect(snapshot.readableFormats.contains(.sevenZip))
    #expect(snapshot.readableFormats.contains(.rar))
    #expect(snapshot.canCreateSevenZip)
    #expect(snapshot.canCreateZIP)
    #expect(!PersonalTeamFinderCapabilityProjection.supportsCreation(of: .rar))
    #expect(!PersonalTeamFinderCapabilityProjection.supportsCreation(of: .cab))
    #expect(!PersonalTeamFinderCapabilityProjection.supportsCreation(of: .arj))
}

@Test func personalTeamProjectionDrivesArchiveAndOrdinarySelectionActions() {
    let policy = FinderSelectionPolicy()
    let snapshot = PersonalTeamFinderCapabilityProjection.makeSnapshot()
    #expect(policy.actions(for: [URL(fileURLWithPath: "/tmp/Archive.7z")], snapshot: snapshot) ==
        [.openArchive, .extractHere, .extractTo, .extractToNamed])
    #expect(policy.actions(for: [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")], snapshot: snapshot) ==
        [.createSevenZip, .createZIP, .createArchive])
    #expect(policy.actions(for: [URL(fileURLWithPath: "/tmp/unknown.thing")], snapshot: snapshot) == [.createSevenZip, .createZIP, .createArchive])
}

@Test func finderActionSelectorContractIsExplicitAndNeverGeneric() {
    let names = FinderArchiveAction.allCases.map(FinderActionSelectorContract.selectorName)
    #expect(Set(names).count == FinderArchiveAction.allCases.count)
    #expect(names.allSatisfy { $0.hasSuffix("Action:") })
    #expect(!names.contains("performAction:"))
}

@Test func finderInvocationPrefersControllerSelectionAndFallsBackToMenuSnapshot() throws {
    let controllerURL = URL(fileURLWithPath: "/tmp/controller.7z")
    let snapshotURL = URL(fileURLWithPath: "/tmp/snapshot.7z")
    let live = try FinderActionInvocation.prepare(
        action: .extractHere,
        controllerSelection: [controllerURL],
        menuSelection: [snapshotURL]
    )
    #expect(live.selectionSource == .controller)
    #expect(live.request.urls == [controllerURL])
    let fallback = try FinderActionInvocation.prepare(
        action: .extractHere,
        controllerSelection: [],
        menuSelection: [snapshotURL]
    )
    #expect(fallback.selectionSource == .menuSnapshot)
    #expect(fallback.request.urls == [snapshotURL])
}

private func withStore(_ body:(FinderRequestStore)throws->Void)throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?FileManager.default.removeItem(at:root)}
    try body(.init(rootURL:root))
}

@Test func finderOffersExtractionOnlyForFirstMultipartVolume() {
    let snapshot = FinderCapabilitySnapshot(readableFormats: [.sevenZip], canCreateSevenZip: true, canCreateZIP: true)
    let policy = FinderSelectionPolicy()
    #expect(policy.actions(for: [URL(fileURLWithPath: "/tmp/Archive.7z.001")], snapshot: snapshot)
        == [.openArchive, .extractHere, .extractTo, .extractToNamed])
    #expect(policy.actions(for: [URL(fileURLWithPath: "/tmp/Archive.7z.002")], snapshot: snapshot).isEmpty)
    #expect(FinderDestinationPolicy.extractToNamedDirectory(for: URL(fileURLWithPath: "/tmp/Archive.7z.001")).path == "/tmp/Archive")
}
