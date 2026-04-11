import Foundation

struct ProcessResult {
    let success: Bool
    let output: String
    let error: String
    let exitCode: Int32
}

class ProcessRunner {
    func runCommand(_ command: String, args: [String] = []) async -> ProcessResult {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            var outputData = Data()
            var errorData = Data()
            
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                outputData.append(handle.availableData)
            }
            
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                errorData.append(handle.availableData)
            }
            
            process.terminationHandler = { _ in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let error = String(data: errorData, encoding: .utf8) ?? ""
                
                let result = ProcessResult(
                    success: process.terminationStatus == 0,
                    output: output,
                    error: error,
                    exitCode: process.terminationStatus
                )
                
                continuation.resume(returning: result)
            }
            
            do {
                try process.run()
            } catch {
                let result = ProcessResult(
                    success: false,
                    output: "",
                    error: error.localizedDescription,
                    exitCode: -1
                )
                continuation.resume(returning: result)
            }
        }
    }
    
    func runInteractiveCommand(_ command: String, args: [String] = []) async -> ProcessResult {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + args
            
            // For interactive commands, inherit stdin/stdout/stderr
            process.standardInput = FileHandle.standardInput
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            
            process.terminationHandler = { _ in
                let result = ProcessResult(
                    success: process.terminationStatus == 0,
                    output: "",
                    error: "",
                    exitCode: process.terminationStatus
                )
                continuation.resume(returning: result)
            }
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                let result = ProcessResult(
                    success: false,
                    output: "",
                    error: error.localizedDescription,
                    exitCode: -1
                )
                continuation.resume(returning: result)
            }
        }
    }
}