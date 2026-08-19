import Compression
import Foundation

public struct XARInspector: Sendable {
    public static let maximumTOCBytes: UInt64 = 64 * 1024 * 1024
    public init() {}
    public func inspect(_ url: URL) throws -> XARInspectionResult {
        let handle=try FileHandle(forReadingFrom:url);defer{try?handle.close()}
        guard let header=try handle.read(upToCount:28),header.count==28,header.prefix(4)==Data("xar!".utf8) else{throw XIPStackError.notXAR}
        let headerSize=header.be16(4),version=header.be16(6),compressed=header.be64(8),uncompressed=header.be64(16),algorithm=header.be32(24)
        guard headerSize>=28,compressed>0,uncompressed>0,uncompressed<=Self.maximumTOCBytes,compressed<=Self.maximumTOCBytes else{throw XIPStackError.resourceLimitExceeded}
        try handle.seek(toOffset:UInt64(headerSize));guard let toc=try handle.read(upToCount:Int(compressed)),toc.count==compressed else{throw XIPStackError.malformedXAR("Truncated table of contents")}
        var decoded=Data(count:Int(uncompressed));let count=decoded.withUnsafeMutableBytes{dst in toc.withUnsafeBytes{src in compression_decode_buffer(dst.bindMemory(to:UInt8.self).baseAddress!,dst.count,src.bindMemory(to:UInt8.self).baseAddress!,src.count,nil,COMPRESSION_ZLIB)}}
        guard count==uncompressed else{throw XIPStackError.malformedXAR("Invalid compressed table of contents")};decoded.count=count
        let parser=XARTOCParser();guard XMLParser(data:decoded).parse(with:parser) else{throw XIPStackError.malformedXAR("Malformed table of contents XML")}
        return .init(headerSize:headerSize,version:version,tocCompressedSize:compressed,tocUncompressedSize:uncompressed,checksumAlgorithm:algorithm,entries:parser.entries)
    }
}

private final class XARTOCParser:NSObject,XMLParserDelegate {
    var entries:[XAREntry]=[];private var stack:[(name:String?,type:String?,size:UInt64?)]=[];private var field:String?,text=""
    func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName qName:String?,attributes attributeDict:[String:String]=[:]){if elementName=="file"{stack.append((nil,nil,nil))};field=elementName;text=""}
    func parser(_ parser:XMLParser,foundCharacters string:String){text+=string}
    func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName qName:String?){guard !stack.isEmpty else{return};let value=text.trimmingCharacters(in:.whitespacesAndNewlines);switch elementName{case"name":stack[stack.count-1].name=value;case"type":stack[stack.count-1].type=value;case"size":stack[stack.count-1].size=UInt64(value);case"file":let node=stack.removeLast();if let name=node.name{let prefix=stack.compactMap(\.name).joined(separator:"/");entries.append(.init(path:prefix.isEmpty ? name:prefix+"/"+name,kind:node.type,size:node.size))};default:break};text="";field=nil}
}
private extension XMLParser { func parse(with delegate:XMLParserDelegate)->Bool{self.delegate=delegate;return parse()} }
private extension Data { func be16(_ i:Int)->UInt16{self[i...i+1].reduce(0){($0<<8)|UInt16($1)}};func be32(_ i:Int)->UInt32{self[i...i+3].reduce(0){($0<<8)|UInt32($1)}};func be64(_ i:Int)->UInt64{self[i...i+7].reduce(0){($0<<8)|UInt64($1)}} }
