import Foundation

struct ToolResult:Sendable{let status:Int32;let stdout:String;let stderr:String}
struct SystemToolRunner:Sendable{
    func run(_ executable:String,_ arguments:[String],workingDirectory:URL?=nil)throws->ToolResult{let process=Process(),out=Pipe(),err=Pipe();process.executableURL=URL(fileURLWithPath:executable);process.arguments=arguments;process.currentDirectoryURL=workingDirectory;process.standardOutput=out;process.standardError=err;try process.run();process.waitUntilExit();return .init(status:process.terminationStatus,stdout:String(decoding:out.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self),stderr:String(decoding:err.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self))}
}
