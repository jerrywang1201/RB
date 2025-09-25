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

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        if let dataSub = dataSub {
            if !stdoutData.isEmpty { dataSub.send(stdoutData) }
            if !stderrData.isEmpty { dataSub.send(stderrData) }
        }

        let output = stdoutData + stderrData
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "PythonScriptRunner",
                          code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "Python script failed"])
        }

        return String(data: output, encoding: .utf8) ?? ""
    }
}
