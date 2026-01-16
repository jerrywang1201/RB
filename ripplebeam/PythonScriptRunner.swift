//
//  PythonScriptRunner.swift
//  ripplebeam
//
//  Created by Jialong Wang's MacBook Pro 16' on 2025/7/7.
//

import Foundation
import Combine

class PythonScriptRunner {
    static func run(
        executable: String,
        arguments: [String],
        pythonPath: String = "",
        dataSub: PassthroughSubject<Data, Never>? = nil
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        if !pythonPath.isEmpty {
            env["PYTHONPATH"] = pythonPath
        }
        process.environment = env

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        if let dataSub, !outputData.isEmpty {
            dataSub.send(outputData)
        }

        let output = outputData
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "PythonScriptRunner",
                          code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Python script failed"])
        }

        return String(data: output, encoding: .utf8) ?? ""
    }
}
