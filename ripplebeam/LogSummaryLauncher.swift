//
//  LogSummaryLauncher.swift
//  ripplebeam
//
//  Created by Jialong Wang's MacBook Pro 16' on 2025/6/12.
//

import SwiftUI

struct LogSummaryLauncher: View {
    var controlTerminal: TerminalModel
    var consoleTerminal: TerminalModel
    @Binding var currentTab: Tab
    var pyExe: String
    var scriptPath: String
    @Binding var isPresented: Bool

    @State private var showSummary = false

    var body: some View {
        Button("Log Diagnostics") {
            showSummary = true
        }
        .sheet(isPresented: $showSummary) {
            let terminalToUse = currentTab == .control ? controlTerminal : consoleTerminal

            LogSummaryView(
                terminal: terminalToUse,
                pyExe: pyExe,
                scriptPath: scriptPath,
                isPresented: $showSummary
            )
        }
    }
}

struct LogSummaryView: View {
    @ObservedObject var terminal: TerminalModel
    var pyExe: String
    var scriptPath: String
    @Binding var isPresented: Bool
    @State private var logSummary = "⏳ Waiting for summary..."

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Log Summary")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    summarizeLog()
                }
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 4)

            ScrollView {
                Text(logSummary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color.gray.opacity(0.05))
            .frame(minHeight: 300)

            Spacer()
        }
        .padding()
        .onAppear {
            summarizeLog()
        }
    }

    private func summarizeLog() {
        Task {
            let logPath = "/tmp/terminal_log.txt"
            print("📄 [1] Writing terminal log to: \(logPath)")

            let logContent = terminal.output.map(\.text).joined(separator: "\n")
            try? logContent.write(toFile: logPath, atomically: true, encoding: .utf8)
            print("✅ [2] Wrote \(logContent.count) bytes to log")

            await MainActor.run {
                logSummary = """
                🛠️ Starting Log Diagnostics...

                📄 Writing terminal log to: \(logPath)
                ✅ Log content written: \(logContent.count) characters

                🚀 Running analysis script...
                """
            }

            let result = await runShellCapture(pyExe, arguments: [scriptPath, logPath])

            await MainActor.run {
                logSummary += "\n✅ Script finished.\n\n"
                logSummary += result.isEmpty ? "⚠️ No summary generated." : result
            }
        }
    }

    private func runShellCapture(_ exe: String, arguments: [String]) async -> String {
        print("⚙️ [3] Preparing process for: \(exe) with arguments: \(arguments)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let handle = pipe.fileHandleForReading
        var collected = Data()

        do {
            try process.run()
            print("✅ [4] Python script started successfully")
        } catch {
            print("❌ [4] Failed to run process: \(error.localizedDescription)")
            return "❌ Failed to run script: \(error.localizedDescription)"
        }

        do {
            for try await byte in handle.bytes {
                collected.append(byte)
            }
        } catch {
            print("❌ [5] Failed to read output: \(error.localizedDescription)")
            return "❌ Failed to read output: \(error.localizedDescription)"
        }

        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                print("🛑 [6] Python process terminated")
                continuation.resume()
            }
        }

        let decoded = String(data: collected, encoding: .utf8) ?? ""
        print("📦 [7] Final output length: \(decoded.count) characters")
        return decoded
    }
}
