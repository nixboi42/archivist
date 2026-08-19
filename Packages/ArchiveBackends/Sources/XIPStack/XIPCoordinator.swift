import Foundation
import ArchiveSecurity
import Domain

public struct XIPCoordinator:Sendable{
    private let xar=XARInspector(),apple=AppleArchivePayloadReader(),tools=SystemToolRunner()
    public init(){}
    public func inspect(_ url:URL)throws->XIPInspection{
        let container=try xar.inspect(url);guard container.hasXIPShape else{throw XIPStackError.unsupportedPayload}
        let temporary=FileManager.default.temporaryDirectory.appendingPathComponent("archivist-xip-\(UUID())");try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true);defer{try?FileManager.default.removeItem(at:temporary)}
        let extraction=try tools.run("/usr/bin/xar",["-xf",url.path,"-C",temporary.path,"Content","Metadata"])
        guard extraction.status==0 else{throw XIPStackError.systemToolFailure(tool:"xar",status:extraction.status,message:extraction.stderr)}
        let content=temporary.appendingPathComponent("Content"),prefix=(try?Data(contentsOf:content,options:.mappedIfSafe).prefix(4)) ?? Data()
        let kind:XIPPayloadKind,entries:[AppleArchiveEntry],payloadIntegrity:IntegrityStatus
        if prefix==Data("pbzx".utf8){kind = .legacyPBZX;entries=[];payloadIntegrity = .notChecked}
        else if let listed=try?apple.list(content){kind = .appleArchive;entries=listed;payloadIntegrity = .valid}
        else{kind = .unknown;entries=[];payloadIntegrity = .invalid}
        let verification=try verify(url,containerValid:true,payloadIntegrity:payloadIntegrity)
        return .init(container:container,payloadKind:kind,payloadEntries:entries,verification:verification)
    }
    public func requireSupportedPayload(_ inspection:XIPInspection)throws{switch inspection.payloadKind{case .appleArchive:return;case .legacyPBZX:throw XIPStackError.unsupportedLegacyPayload;case .unknown:throw XIPStackError.unsupportedPayload}}
    public func expand(_ url:URL,to destination:URL,securityPolicy:SecurityPolicy = .secureDefault)throws{
        let inspection=try inspect(url);try requireSupportedPayload(inspection)
        let staging=FileManager.default.temporaryDirectory.appendingPathComponent("archivist-xip-expand-\(UUID())");try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true);defer{try?FileManager.default.removeItem(at:staging)}
        let expanded=try tools.run("/usr/bin/xip",["--expand",url.path],workingDirectory:staging);guard expanded.status==0 else{throw XIPStackError.systemToolFailure(tool:"xip",status:expanded.status,message:expanded.stderr)}
        let staged=try stagedEntries(staging),plans=try SecureExtractionPlanner(policy:securityPolicy).plan(destinationRoot:destination,entries:staged.map(\.entry));try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        let sourceByID=Dictionary(uniqueKeysWithValues:staged.map{($0.entry.id,$0.url)})
        for plan in plans where plan.entry.kind == .directory{try FileManager.default.createDirectory(at:plan.destinationURL,withIntermediateDirectories:true)}
        for plan in plans where plan.entry.kind == .regularFile{guard let source=sourceByID[plan.entry.id]else{continue};try FileManager.default.createDirectory(at:plan.destinationURL.deletingLastPathComponent(),withIntermediateDirectories:true);let partial=plan.destinationURL.appendingPathExtension("archiveutil-partial");try?FileManager.default.removeItem(at:partial);try FileManager.default.copyItem(at:source,to:partial);try FileManager.default.moveItem(at:partial,to:plan.destinationURL)}
        for plan in plans where plan.entry.kind == .symbolicLink{guard plan.symlinkTarget != nil,let target=plan.entry.linkTarget else{continue};try FileManager.default.createDirectory(at:plan.destinationURL.deletingLastPathComponent(),withIntermediateDirectories:true);try FileManager.default.createSymbolicLink(atPath:plan.destinationURL.path,withDestinationPath:target)}
    }
    public func verify(_ url:URL)throws->XIPVerificationResult{_ = try xar.inspect(url);return try verify(url,containerValid:true,payloadIntegrity:nil)}
    private func verify(_ url:URL,containerValid:Bool,payloadIntegrity:IntegrityStatus?)throws->XIPVerificationResult{
        let result=try tools.run("/usr/bin/xip",["--verify",url.path])
        if result.status==0{return .init(containerStructure:containerValid ? .valid:.invalid,containerChecksum:.valid,cryptographicSignature:.validBySystemXIP,signerTrust:.trustedBySystemXIPPolicy,payloadIntegrity:payloadIntegrity)}
        return .init(containerStructure:containerValid ? .valid:.invalid,containerChecksum:.notChecked,cryptographicSignature:.invalid,signerTrust:.notIndependentlyEvaluated,payloadIntegrity:payloadIntegrity)
    }
}

private func stagedEntries(_ root:URL)throws->[(entry:ArchiveEntry,url:URL)]{let fm=FileManager.default,keys:Set<URLResourceKey>=[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey];guard let iterator=fm.enumerator(at:root,includingPropertiesForKeys:Array(keys),options:[.skipsPackageDescendants])else{return[]};var result:[(ArchiveEntry,URL)]=[];for case let url as URL in iterator{let value=try url.resourceValues(forKeys:keys),relative=url.pathComponents.dropFirst(root.pathComponents.count).joined(separator:"/");if value.isSymbolicLink==true{iterator.skipDescendants();result.append((.init(path:relative,kind:.symbolicLink,linkTarget:try fm.destinationOfSymbolicLink(atPath:url.path)),url))}else if value.isDirectory==true{result.append((.init(path:relative,kind:.directory,modificationDate:value.contentModificationDate),url))}else if value.isRegularFile==true{result.append((.init(path:relative,kind:.regularFile,uncompressedSize:value.fileSize.map(UInt64.init),modificationDate:value.contentModificationDate),url))}};return result}
