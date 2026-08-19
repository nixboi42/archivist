import Foundation
import Testing
@testable import Domain

@Test func compoundExtensionsPreferLongestMatch() {
    #expect(CompoundExtension.detect(in: "Backup.TAR.GZ") == .tarGzip)
    #expect(CompoundExtension.detect(in: "data.tbz2") == .tbz2)
    #expect(CompoundExtension.detect(in: "sdk.tar.zstd") == .tarZstandardLong)
    #expect(CompoundExtension.detect(in: "plain.gz") == nil)
}

@Test func extensionFallbackPreservesSemanticZIPKinds() {
    #expect(ArchiveFormat.extensionFallback(for: "app.apk") == .zip(.apk))
    #expect(ArchiveFormat.extensionFallback(for: "book.EPUB") == .zip(.epub))
    #expect(ArchiveFormat.extensionFallback(for: "classes.jar") == .zip(.jar))
    #expect(ArchiveFormat.extensionFallback(for: "no-extension") == .unknown)
}

@Test func capabilitiesAreOperationDriven() {
    let capabilities = ArchiveCapabilities(operations: [.read, .list, .extract], supportsRandomAccess: true)
    #expect(capabilities.supports(.extract))
    #expect(!capabilities.supports(.create))
    #expect(ArchiveCapabilities.unsupported.operations.isEmpty)
}

@Test func progressDoesNotFabricateUnknownFractions() {
    #expect(ProgressEvent(phase: .extracting, completedUnits: 1).fractionCompleted == nil)
    #expect(ProgressEvent(phase: .extracting, completedUnits: 5, totalUnits: 10).fractionCompleted == 0.5)
    #expect(ProgressEvent(phase: .extracting, completedUnits: 20, totalUnits: 10).fractionCompleted == 1)
}

@Test func resourceLimitsEnforceHardFloorsAndCeilings() {
    let limits = SecurityPolicy.ResourceLimits(maximumEntries: .max, maximumExpandedBytes: .max,
                                               maximumCompressionRatio: .greatestFiniteMagnitude)
    #expect(limits.maximumEntries == SecurityPolicy.ResourceLimits.hardMaximumEntries)
    #expect(limits.maximumExpandedBytes == SecurityPolicy.ResourceLimits.hardMaximumExpandedBytes)
    #expect(limits.maximumCompressionRatio == SecurityPolicy.ResourceLimits.hardMaximumCompressionRatio)
    #expect(SecurityPolicy.ResourceLimits(maximumEntries: 0).maximumEntries == 1)
}

@Test func domainModelsRoundTripThroughCodable() throws {
    let entry = ArchiveEntry(path: "bin/tool", kind: .regularFile, uncompressedSize: 42,
                             posixMode: 0o755, checksum: "abc", isEncrypted: true)
    let decoded = try JSONDecoder().decode(ArchiveEntry.self, from: JSONEncoder().encode(entry))
    #expect(decoded == entry)

    let job = JobDescriptor(kind: .extract, sourceURLs: [URL(fileURLWithPath: "/tmp/a.7z")],
                            destinationURL: URL(fileURLWithPath: "/tmp/out"), format: .sevenZip)
    #expect(try JSONDecoder().decode(JobDescriptor.self, from: JSONEncoder().encode(job)) == job)
}

@Test func structuredBackendErrorRetainsSafeContext() throws {
    let error = ArchiveBackendError(.incorrectPassword, backendIdentifier: "7zz", operation: .extract,
                                    message: "The password is incorrect", diagnosticCode: "E_PASSWORD")
    let decoded = try JSONDecoder().decode(ArchiveBackendError.self, from: JSONEncoder().encode(error))
    #expect(decoded == error)
    #expect(decoded.description == "The password is incorrect")
}

@Test func volumeSizesParseValidatedHumanUnits() throws {
    #expect(try VolumeSize(parsing: "10 MB").bytes == 10_000_000)
    #expect(try VolumeSize(parsing: "1GiB").bytes == 1 << 30)
    #expect(throws: VolumeSizeError.self) { try VolumeSize(parsing: "0 MB") }
    #expect(throws: VolumeSizeError.self) { try VolumeSize(parsing: "12 parsecs") }
}

@Test func multipartNamesRecognizeOnlySupportedNumberedVolumes() throws {
    let first = try #require(MultipartArchiveName.parse("Archive.7z.001"))
    #expect(first.format == .sevenZip); #expect(first.isFirstVolume)
    #expect(first.firstVolumeFilename == "Archive.7z.001")
    let later = try #require(MultipartArchiveName.parse("Archive.zip.002"))
    #expect(!later.isFirstVolume); #expect(later.volumeNumber == 2)
    #expect(MultipartArchiveName.parse("photo.001") == nil)
}
