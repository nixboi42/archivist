import Compression
import Foundation
import Testing
import XIPStack
import BackendProtocol
import Domain

@Test func rejectsNonXARAndOversizedTOC()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?FileManager.default.removeItem(at:root)};try Data("nope".utf8).write(to:root)
    #expect(throws:XIPStackError.self){try XARInspector().inspect(root)}
}

@Test func nativeXARInspectionRecognizesXIPShape()throws{
    let xml="<?xml version=\"1.0\"?><xar><toc><file><name>Content</name><type>file</type><data><size>4</size></data></file><file><name>Metadata</name><type>file</type></file></toc></xar>"
    let fixture=try makeXAR(xml),url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?FileManager.default.removeItem(at:url)};try fixture.write(to:url)
    let result=try XARInspector().inspect(url);#expect(result.hasXIPShape);#expect(result.entries.map(\.path)==["Content","Metadata"])
}

@Test func verificationDimensionsCannotConflateTrustAndSignature(){let value=XIPVerificationResult(containerStructure:.valid,containerChecksum:.notChecked,cryptographicSignature:.notChecked,signerTrust:.trustedBySystemXIPPolicy,payloadIntegrity:nil);#expect(value.cryptographicSignature != .validBySystemXIP)}
@Test func legacyPayloadHasExplicitUnsupportedResult(){let inspection=XIPInspection(container:.init(headerSize:28,version:1,tocCompressedSize:1,tocUncompressedSize:1,checksumAlgorithm:1,entries:[]),payloadKind:.legacyPBZX,payloadEntries:[],verification:.init(containerStructure:.valid,containerChecksum:.valid,cryptographicSignature:.notChecked,signerTrust:.notIndependentlyEvaluated,payloadIntegrity:nil));#expect(throws:XIPStackError.self){try XIPCoordinator().requireSupportedPayload(inspection)}}

@Test func frameworkReadsRealAppleArchivePayload()throws{
    let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?fm.removeItem(at:root)};let source=root.appendingPathComponent("source");try fm.createDirectory(at:source,withIntermediateDirectories:true);try Data("payload".utf8).write(to:source.appendingPathComponent("hello.txt"));let archive=root.appendingPathComponent("Content")
    let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/aa");process.arguments=["archive","-d",source.path,"-o",archive.path];try process.run();process.waitUntilExit();#expect(process.terminationStatus==0)
    let entries=try AppleArchivePayloadReader().list(archive);#expect(entries.contains{$0.path=="hello.txt"})
}

@Test func adapterListsXARThroughArchiveBackend()async throws{
    let xml="<?xml version=\"1.0\"?><xar><toc><file><name>folder</name><type>directory</type><file><name>hello.txt</name><type>file</type><data><size>7</size></data></file></file></toc></xar>"
    let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("xar")
    defer{try?FileManager.default.removeItem(at:url)};try makeXAR(xml).write(to:url)
    let backend=XIPArchiveBackend();#expect(backend.capabilities(for:.xar).supports(.list))
    let handle=try await backend.open(url,format:.xar,credential:nil);var entries:[ArchiveEntry]=[]
    for try await entry in backend.list(handle){entries.append(entry)};await backend.close(handle)
    #expect(entries.map(\.path)==["folder/hello.txt","folder"] || entries.map(\.path)==["folder","folder/hello.txt"])
    #expect(entries.contains{$0.path=="folder/hello.txt" && $0.uncompressedSize==7})
}

@Test func adapterListsRawAppleArchive()async throws{
    let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try?fm.removeItem(at:root)}
    let source=root.appendingPathComponent("source"),archive=root.appendingPathComponent("payload.aar");try fm.createDirectory(at:source,withIntermediateDirectories:true);try Data("payload".utf8).write(to:source.appendingPathComponent("hello.txt"))
    let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/aa");process.arguments=["archive","-d",source.path,"-o",archive.path];try process.run();process.waitUntilExit();#expect(process.terminationStatus==0)
    let backend=XIPArchiveBackend(),handle=try await backend.open(archive,format:.appleArchive,credential:nil);var paths:[String]=[]
    for try await entry in backend.list(handle){paths.append(entry.path)};#expect(paths.contains("hello.txt"))
    let output=root.appendingPathComponent("output");try fm.createDirectory(at:output,withIntermediateDirectories:true)
    for try await _ in backend.extract(handle,entries:nil,to:output,options:.init(conflictResolution:.replace)){}
    #expect(try Data(contentsOf:output.appendingPathComponent("hello.txt")) == Data("payload".utf8));await backend.close(handle)
}

@Test func richVerificationConversionPreservesIndependentDimensions(){
    let source=XIPVerificationResult(containerStructure:.valid,containerChecksum:.invalid,cryptographicSignature:.validBySystemXIP,signerTrust:.notIndependentlyEvaluated,payloadIntegrity:.notChecked)
    guard case .xip(let details)=source.domainDetails else{Issue.record("Expected XIP details");return}
    #expect(details.containerStructure == .valid);#expect(details.containerChecksum == .invalid)
    #expect(details.cryptographicSignature == .validBySystemXIP);#expect(details.signerTrust == .notIndependentlyEvaluated);#expect(details.payloadIntegrity == .notChecked)
}

private func makeXAR(_ xml:String)throws->Data{let input=Data(xml.utf8);var compressed=Data(count:input.count+128);let count=compressed.withUnsafeMutableBytes{dst in input.withUnsafeBytes{src in compression_encode_buffer(dst.bindMemory(to:UInt8.self).baseAddress!,dst.count,src.bindMemory(to:UInt8.self).baseAddress!,src.count,nil,COMPRESSION_ZLIB)}};compressed.count=count;var out=Data("xar!".utf8);out.appendBE(UInt16(28));out.appendBE(UInt16(1));out.appendBE(UInt64(count));out.appendBE(UInt64(input.count));out.appendBE(UInt32(1));out.append(compressed);return out}
private extension Data{mutating func appendBE<T:FixedWidthInteger>(_ value:T){var v=value.bigEndian;Swift.withUnsafeBytes(of:&v){append(contentsOf:$0)}}}
