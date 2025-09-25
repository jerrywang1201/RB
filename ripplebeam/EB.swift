// === RadarUploader.swift ===
import Foundation
import Combine
import FilePicker
import SwiftUI
import Zip
import UniformTypeIdentifiers



struct FolderPicker: NSViewControllerRepresentable {
    var title: String
    var onSelect: (URL?) -> Void

    func makeNSViewController(context: Context) -> NSViewController {
        let viewController = NSViewController()
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.title = title
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.begin { response in
                onSelect(response == .OK ? panel.url : nil)
            }
        }
        return viewController
    }

    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}

class RadarUploader {
    static func upload(ftab: URL, comment: String, radarId: String, token: String, settings: SettingsModel, terminal: TerminalModel) async throws {
        //
        let encodedFileName = ftab.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "upload.bin"
        
        //
        let uploadURL = URL(string: "https://radar-webservices.apple.com/problems/\(radarId)/attachments/\(encodedFileName)")!
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(token, forHTTPHeaderField: "Radar-Authentication")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "X-Override-File") // 可选
        
        //
        let fileData = try Data(contentsOf: ftab)
        request.httpBody = fileData
        
        //
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let respBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"

        terminal.cmdOutputSub.send(Data("HTTP Status \(status)\n".utf8))
        terminal.cmdOutputSub.send(Data("Server response \(respBody)\n".utf8))

        guard (200...299).contains(status) else {
            throw NSError(domain: "UploadFailed", code: 1, userInfo: [NSLocalizedDescriptionKey: "Upload failed with status \(status)"])
        }

        //
//        var diagRequest = URLRequest(url: URL(string: "https://radar-webservices.apple.com/problems/\(radarId)/diagnosis")!)
//        diagRequest.httpMethod = "POST"
//        diagRequest.setValue(token, forHTTPHeaderField: "Radar-Authentication")
//        diagRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        let commentBody = ["text": comment]
//        diagRequest.httpBody = try JSONSerialization.data(withJSONObject: commentBody)
//
//        let (_, diagResponse) = try await URLSession.shared.data(for: diagRequest)
//        guard let diagResp = diagResponse as? HTTPURLResponse, diagResp.statusCode == 201 else {
//            throw NSError(domain: "DiagnosisPostFailed", code: 2)
//        }
        var diagRequest = URLRequest(url: URL(string: "https://radar-webservices.apple.com/problems/\(radarId)/diagnosis")!)
        diagRequest.httpMethod = "POST"
        diagRequest.setValue(token, forHTTPHeaderField: "Radar-Authentication")
        diagRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let commentBody = ["text": comment]
        let jsonData = try JSONSerialization.data(withJSONObject: commentBody)
        diagRequest.httpBody = jsonData

        let (diagData, diagResponse) = try await URLSession.shared.data(for: diagRequest)
        let diagStatus = (diagResponse as? HTTPURLResponse)?.statusCode ?? -1
        let diagRespBody = String(data: diagData, encoding: .utf8) ?? "<non-utf8>"

        terminal.cmdOutputSub.send(Data("📡 Diagnosis HTTP Status: \(diagStatus)\n".utf8))
        terminal.cmdOutputSub.send(Data("📨 Diagnosis Server response: \(diagRespBody)\n".utf8))

        guard diagStatus == 201 else {
            throw NSError(domain: "DiagnosisPostFailed", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Diagnosis failed with status \(diagStatus): \(diagRespBody)"
            ])
        }

        await settings.refreshEBAttachments()
    }
}

// === RadarWatcher.swift ===
struct RadarWatcher {
    static func findLatestTGZ(in attachments: [RadarAttachmentModel], after referenceTime: Date, by authorName: String) -> RadarAttachmentModel? {
        return attachments
            .filter { attachment in
                attachment.fileName.hasSuffix(".tgz") &&
                attachment.uploadDate > referenceTime &&
                attachment.author.contains(authorName)
            }
            .sorted(by: { $0.uploadDate > $1.uploadDate })
            .first
    }

    static func downloadTGZ(attachment: RadarAttachmentModel) async throws -> URL {
        let url = URL(string: "https://radar-webservices.apple.com/problems/\(attachment.radarID)/attachments/\(attachment.fileName)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(attachment.token, forHTTPHeaderField: "Radar-Authentication")

        let (data, _) = try await URLSession.shared.data(for: request)
        let saveURL = FileManager.default.temporaryDirectory.appendingPathComponent(attachment.fileName)
        try data.write(to: saveURL)
        return saveURL
    }
}


enum Shell {
    @discardableResult
    static func run(_ command: String, arguments: [String] = []) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)

        if process.terminationStatus != 0 {
            throw NSError(domain: "Shell", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Shell command failed: \(output)"
            ])
        }

        return output
    }
}

// === RadarFileProcessor.swift ===
struct RadarFileProcessor {
    static func extractAndRenameUARP(tgzURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let extractDir = fileManager.temporaryDirectory
            .appendingPathComponent(tgzURL.deletingPathExtension().lastPathComponent)

        try? fileManager.removeItem(at: extractDir)
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // 解压 .tgz
        try Shell.run("/usr/bin/tar", arguments: ["-xzf", tgzURL.path, "-C", extractDir.path])

        // 查找 .uarp 文件（递归）
        let allPaths = try fileManager.subpathsOfDirectory(atPath: extractDir.path)
        guard let relativePath = allPaths.first(where: { $0.hasSuffix(".uarp") }) else {
            throw NSError(domain: "RadarFileProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "NoUARPFound error 4."])
        }

        let originalURL = extractDir.appendingPathComponent(relativePath)

        // 重命名：把前缀替换成 t2016
        let originalName = originalURL.lastPathComponent
        let renamed = originalName.replacingOccurrences(of: #"^[^-]+"#, with: "t2016", options: .regularExpression)
        let renamedURL = originalURL.deletingLastPathComponent().appendingPathComponent(renamed)

        try fileManager.moveItem(at: originalURL, to: renamedURL)
        
        print("📂 Extracted UARP path = \(renamedURL.path)")
        return renamedURL
    }
}


// === RestoreRunner.swift ===
// RestoreRunner.swift
func runShellCommandAsyncEB(
    _ command: String,
    arguments: [String],
    environment: [String: String]? = nil,
    dataSub: PassthroughSubject<Data, Never>? = nil
) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = arguments
    process.environment = environment

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    let handle = pipe.fileHandleForReading
    handle.readabilityHandler = { fileHandle in
        let data = fileHandle.availableData
        if !data.isEmpty {
            dataSub?.send(data)
        }
    }

    do {
        try process.run()
        process.waitUntilExit()
        handle.readabilityHandler = nil
    } catch let error {
        let errorMsg = "[ERROR] \(error.localizedDescription)\n"
        dataSub?.send(Data(errorMsg.utf8))
        throw error
    }
}

func runShellCommandAsyncEBTest(
    _ command: String,
    arguments: [String],
    dataSub: PassthroughSubject<Data, Never>? = nil
) async {
    do {
        try await runShellCommandAsyncEB(command, arguments: arguments, dataSub: dataSub)
    } catch {
        let errMsg = "[ERROR] \(error.localizedDescription)\n"
        dataSub?.send(Data(errMsg.utf8))
    }
}




// === UploadFTABView.swift ===


struct EBUpdateView: View {
    
    
    @ObservedObject var terminal: TerminalModel
    @EnvironmentObject var settings: SettingsModel
    @State private var selectedDevice: EBDeviceType = .buds
    @State private var isPickingFolder = false
    
    enum EBDeviceType: String, CaseIterable, Identifiable {
        case buds = "Buds"
        case caseDevice = "Case"
        case airpodsMax = "..."
        
        var id: String { rawValue }
    }

    var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Device Type", selection: $selectedDevice) {
                    ForEach(EBDeviceType.allCases) { device in
                        Text(device.rawValue).tag(device)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.bottom)

                GroupBox(label: Text("Upload & Restore").bold()) {
                    switch selectedDevice {
                    case .buds:
                        UploadFTABView(terminal: terminal)
                    case .caseDevice:
                        CaseEBUploadView(terminal: terminal)
                    case .airpodsMax:
                        MaxEBUploadView(terminal: terminal)
                    }
                }

                TerminalView(terminal: terminal, viewParent: .debug)
            }
            .padding()
        }
}


struct CaseEBUploadView: View {
    @ObservedObject var terminal: TerminalModel
    @EnvironmentObject var settings: SettingsModel

    @State private var selectedPort: String = ""
    @State private var selectedChip: String = "All"
    @State private var folderURL: URL?
    @State private var isRunning = false
    @State private var isPickingFolder = false
    @State private var cachedTarget: String? = nil

    @StateObject private var portModel = SerialPort()
    @State private var updateTask: Task<Void, Never>? = nil

    let chipOptions = ["BLE", "STM32", "Rose", "All"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Port")
                            .frame(width: 50, alignment: .leading)

                        Picker("", selection: $selectedPort) {
                            ForEach(portModel.availablePorts, id: \.self) { port in
                                Text(port).tag(port)
                            }
                        }
                        .frame(width: 160)

                   

                        Text("BaudRate: 230400")
                            .frame(width: 140, alignment: .leading)
                }

                HStack {
                    Text("Core")
                        .frame(width: 50, alignment: .leading)

                    Picker("", selection: $selectedChip) {
                        ForEach(chipOptions, id: \.self) { Text($0) }
                    }
                    .frame(width: 160)

                    Spacer()
                }
            }
      
            Button("Select EB Folder") {
                isPickingFolder = true
            }
            .sheet(isPresented: $isPickingFolder) {
                FolderPicker(title: "Select EB Folder") { url in
                    defer { isPickingFolder = false }
                    if let selected = url {
                        folderURL = selected
                    }
                }
            }

            if let folder = folderURL {
                Text("📁 Selected folder: \(folder.lastPathComponent)")
                    .foregroundColor(.green)
            } else {
                Text("❌ No folder selected")
                    .foregroundColor(.red)
            }
            Button("Send Reset Commands") {
                guard updateTask == nil else { return }
                updateTask = Task {
                    portModel.baudRate = 230400
                    portModel.serialPath = selectedPort
                    portModel.open()

                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard portModel.port?.isOpen == true else {
                        terminal.cmdOutputSub.send("❌ Port not open\n".utf8Data)
                        return
                    }

                    portModel.send(value: "ble system set enable")
                    
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    portModel.send(value: "ft reset")
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    portModel.send(value: "ft version case")
                

                    do {
                        let target = try await portModel.getTargetFromDevice()
                        cachedTarget = target
                        terminal.cmdOutputSub.send("✅ Detected target: \(target)\n".utf8Data)
                    } catch {
                        terminal.cmdOutputSub.send("❌ Failed to get target: \(error.localizedDescription)\n".utf8Data)
                    }

                    terminal.cmdOutputSub.send("✅ Sent reset commands\n".utf8Data)
                }
            }
            .disabled(selectedPort.isEmpty)

            Button("Start EB Update") {
                runCaseUpdate()
            }
            .disabled(folderURL == nil || selectedPort.isEmpty || isRunning)

            if isRunning {
                ProgressView("Running...")
            }
            if isRunning {
                Button("Stop") {
                    updateTask?.cancel()
                    updateTask = nil
                    isRunning = false
                    terminal.cmdOutputSub.send("🛑 Update cancelled by user\n".utf8Data)
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .onAppear {
            portModel.refreshAvailablePorts()
        }
    }

    func runCaseUpdate() {
        
        guard let target = cachedTarget else {
            terminal.cmdOutputSub.send("❌ No cached target found. Please run Reset first.\n".utf8Data)
            isRunning = false
            return
        }
        guard folderURL != nil else { return }

        Task {
            
            isRunning = true
            portModel.baudRate = 230400
            portModel.serialPath = selectedPort
            portModel.open()
            portModel.close()

            try? await Task.sleep(nanoseconds: 300_000_000)
            
            

            guard let folderURL else {
                terminal.cmdOutputSub.send("❌ No folder selected.\n".utf8Data)
                return
            }

            let caseEBPath = settings.workingDir + "/CaseEB"
            let destBaseURL = URL(fileURLWithPath: caseEBPath)

            if !FileManager.default.fileExists(atPath: destBaseURL.path) {
                try? FileManager.default.createDirectory(at: destBaseURL, withIntermediateDirectories: true)
            }

            try? FileManager.default.contentsOfDirectory(at: destBaseURL, includingPropertiesForKeys: nil).forEach {
                try? FileManager.default.removeItem(at: $0)
            }

            let uploadFolderName = folderURL.lastPathComponent
            let destination = destBaseURL.appendingPathComponent(uploadFolderName)

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: folderURL, to: destination)
                terminal.cmdOutputSub.send("✅ Copied folder to CaseEB/\(uploadFolderName)\n".utf8Data)
            } catch {
                terminal.cmdOutputSub.send("❌ Failed to copy folder: \(error.localizedDescription)\n".utf8Data)
                isRunning = false
                return
            }

            let scriptPath = settings.workingDir + "/goldrestore_b747_EVT/goldrestore2_case.py"

            let chipCore: String
            switch selectedChip.lowercased() {
            case "r2", "rose":
                chipCore = "r1"
            case "stm32":
                chipCore = "st"
            case "ble":
                chipCore = "nrf"
            case "all":
                chipCore = "all"
            default:
                chipCore = "r1"
            }

            var args: [String] = []

            if selectedChip.lowercased() == "rose" {
                let targetDir = String(target.prefix(4))
                args = [
                    scriptPath,
                    "--core=r1",
                    "--target=\(target)",
                    "--no_knox",
                    "--ftab=\(settings.workingDir)/CaseEB/Rose/\(targetDir)/ftab.bin",
                    "--diag",
                    //"--tatsu", "http://17.238.121.69:8080",
                    "--serialPort=\(selectedPort)"
                ]
            } else {
                let generatedPath = "\(caseEBPath)/audio_assets/juicebox/generated/\(target)"
                args = [
                    scriptPath,
                    "--core=\(chipCore)",
                    "--target=\(target)",
                    "--no_knox",
                    "--diag",
                    "--serialPort=\(selectedPort)"
                ]

                if chipCore == "st" {
                    args.append("--st_files_path=\(caseEBPath)/b747")
                } else if chipCore == "nrf" {
                    args.append("--nrf_file_path=\(caseEBPath)/nerfthis")
                } else if chipCore == "r1" || chipCore == "all" {
                    let targetDir = String(target.prefix(4))
                    let ftabPath = "\(caseEBPath)/Rose/\(targetDir)/ftab.bin"
                    let norFlashPath = "\(caseEBPath)/Rose/\(targetDir)/nor_flash.bin"
                    args.append("--ftab=\(ftabPath)")
                    args.append("--nor_flash=\(norFlashPath)")
                    args.append("--nrf_file_path=\(caseEBPath)/nerfthis")
                    args.append("--st_files_path=\(caseEBPath)/b747")
                    args.append("--tatsu")
                    args.append("http://17.238.121.69:8080")

                    if chipCore == "all" {
                        let audioFiles = [
                            "auch_jb", "auer_jb", "aufm_jb", "aufr_jb", "aulb_jb", "aupc_jb", "aups_jb", "auut_jb", "auuf_jb",
                            "ftfm_jb", "fts1_jb", "fts2_jb", "ftss_jb", "ftt3_jb", "fta1_jb", "fta2_jb", "audt_jb"
                        ]
                        for audio in audioFiles {
                            let key = audio.replacingOccurrences(of: "_jb", with: "")
                            let path = "\(generatedPath)/\(audio).bin"
                            args.append("--audio_\(key)=\(path)")
                        }
                    }
                }
            }

            args.forEach { terminal.cmdOutputSub.send("🧾 \($0)\n".utf8Data) }

            terminal.cmdOutputSub.send("🚀 Launching restore...\n".utf8Data)

            let timeoutSeconds: UInt64 = 300

            do {
                if portModel.port?.isOpen == true {
                    terminal.cmdOutputSub.send("⚠️ Swift port open. Closing before Python...\n".utf8Data)
                    portModel.close()
                }

                let restoreTask: Task<String, Error> = Task {
                    terminal.cmdOutputSub.send("🔴 Starting Python restore task...\n".utf8Data)
                    terminal.cmdOutputSub.send("🟣 Running Python with args:\n\(args.joined(separator: " "))\n".utf8Data)
                    return try await PythonScriptRunner.run(
                        executable: settings.pyExe.isEmpty ? "/usr/bin/python3.13" : settings.pyExe,
                        arguments: args,
                        pythonPath: settings.pythonSitePackagesPath,
                        dataSub: terminal.cmdOutputSub
                    )
                }

                let result = try await withTimeout(seconds: timeoutSeconds, operation: restoreTask)
                terminal.cmdOutputSub.send("✅ Python output:\n\(result)".utf8Data)

            } catch {
                terminal.cmdOutputSub.send("❌ Python script timeout or failed: \(error.localizedDescription)\n".utf8Data)
                if FileManager.default.fileExists(atPath: selectedPort) == false {
                    terminal.cmdOutputSub.send("⚠️ Serial port \(selectedPort) not found. Device may be disconnected.\n".utf8Data)
                }
            }

            try? FileManager.default.contentsOfDirectory(at: destBaseURL, includingPropertiesForKeys: nil).forEach {
                try? FileManager.default.removeItem(at: $0)
            }

            terminal.cmdOutputSub.send("🧹 Cleaned up CaseEB folder\n".utf8Data)
            isRunning = false
        }
    }
    func withTimeout<T>(
        seconds: UInt64,
        operation: Task<T, Error>
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                return try await operation.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw CancellationError()
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

struct MaxEBUploadView: View {
    @ObservedObject var terminal: TerminalModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🎧 New function will update soon.")
                .foregroundColor(.purple)
                .padding()
        }
    }
}

struct UploadFTABView: View {
    @ObservedObject var terminal: TerminalModel
    @EnvironmentObject var settings: SettingsModel
    @State private var ftabURL: URL?
    @State private var comment: String = ""
    @State private var selectedPort: String = ""
    @State private var isRunning = false
    @State private var uploadStartTime = Date()
    @StateObject private var portModel = SerialPort()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upload FTAB and Run EB Restore").font(.headline)

            FilePicker(
                types: [.data],
                allowMultiple: false,
                title: "Select ftab.bin"
            ) { urls in
                if let selected = urls.first {
                    ftabURL = selected
                }
            }
            if let ftab = ftabURL {
                Text("✅ Selected: \(ftab.lastPathComponent)")
                    .font(.subheadline)
                    .foregroundColor(.green)
            } else {
                Text("❌ No ftab.bin selected.")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }

            TextEditor(text: $comment)
                .frame(maxWidth: .infinity, minHeight: 80)
                .font(.system(size: 13, design: .default))
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())

            

            HStack {
                Button("One-click Upload & Fetch") {
                    Task {
                        defer {
                                portModel.close()
                        }
                        // Step 1: Open serial and get ECID
                        portModel.serialPath = selectedPort
                        try? await Task.sleep(nanoseconds: 300_000_000)

                        guard portModel.port != nil else {
                            terminal.cmdOutputSub.send("❌ No serial port connected.\n".utf8Data)
                            return
                        }

                        if portModel.port?.isOpen == false {
                            portModel.open()
                        }

                        do {
                            let project = try await portModel.getProjectNameFromDevice()
                            let ecid = try await portModel.getECIDFromDevice()

                            await MainActor.run {
                                comment = "Personalize for \(project)\n\(ecid)"
                                terminal.cmdOutputSub.send("✅ Got ECID: \(ecid) for \(project)\n".utf8Data)
                            }
                        } catch {
                            terminal.cmdOutputSub.send("❌ Failed to get ECID/project info: \(error.localizedDescription)\n".utf8Data)
                            return
                        }

                        // Step 2: Upload ftab to Radar
                        guard let ftab = ftabURL else {
                            terminal.cmdOutputSub.send("⚠️ Please select a valid ftab.bin before uploading.\n".utf8Data)
                            return
                        }

                        guard !comment.isEmpty else {
                            terminal.cmdOutputSub.send("⚠️ Please enter a comment before uploading.\n".utf8Data)
                            return
                        }

                        guard let token = await getRadarAccessToken() else {
                            terminal.cmdOutputSub.send("❌ Could not get Radar token.\n".utf8Data)
                            return
                        }

                        settings.radarAccessToken = token
                        uploadStartTime = Date()

                        do {
                            try await RadarUploader.upload(
                                ftab: ftab,
                                comment: comment,
                                radarId: "133428147",
                                token: token,
                                settings: settings,
                                terminal: terminal
                            )
                            terminal.cmdOutputSub.send("✅ Uploaded to Radar.\n".utf8Data)
                        } catch {
                            terminal.cmdOutputSub.send("❌ Upload failed: \(error.localizedDescription)\n".utf8Data)
                            return
                        }

                        // Step 3: Poll and download .tgz
                        let maxAttempts = 10
                        let interval: TimeInterval = 30
                        var attempts = 0
                        var tgzFound: RadarAttachmentModel? = nil

                        while attempts < maxAttempts {
                            await settings.refreshEBAttachments()
                            tgzFound = RadarWatcher.findLatestTGZ(
                                in: settings.ebAttachments,
                                after: uploadStartTime,
                                by: "Jason (Jingqian) Wang"
                            )

                            if let found = tgzFound {
                                terminal.cmdOutputSub.send("📦 Found .tgz from Radar: \(found.fileName)\n".utf8Data)
                                break
                            } else {
                                terminal.cmdOutputSub.send("⏳ Waiting for .tgz... attempt \(attempts + 1)/\(maxAttempts)\n".utf8Data)
                                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                                attempts += 1
                            }
                        }

                        guard let latest = tgzFound else {
                            terminal.cmdOutputSub.send("❌ Timeout: No recent .tgz found from Radar after \(maxAttempts) attempts.\n".utf8Data)
                            return
                        }

                        // Step 4: Extract + rename + copy uarp
                        do {
                            let tgz = try await RadarWatcher.downloadTGZ(attachment: latest)
                            let uarp = try RadarFileProcessor.extractAndRenameUARP(tgzURL: tgz)

                            terminal.cmdOutputSub.send("📄 Extracted and renamed uarp: \(uarp.lastPathComponent)\n".utf8Data)
                            terminal.cmdOutputSub.send("📂 Source path: \(uarp.path)\n".utf8Data)

                            let destDir = settings.workingDir + "/goldrestore_durant/RestorePackage/EB_UARP"
                            var destURL = URL(fileURLWithPath: destDir)

                            if FileManager.default.fileExists(atPath: destDir) {
                                do {
                                    let contents = try FileManager.default.contentsOfDirectory(at: destURL, includingPropertiesForKeys: nil)
                                    for file in contents {
                                        try FileManager.default.removeItem(at: file)
                                    }
                                    terminal.cmdOutputSub.send("🧹 Cleared EB_UARP folder due to failure.\n".utf8Data)
                                } catch {
                                    terminal.cmdOutputSub.send("⚠️ Failed to clean EB_UARP folder: \(error.localizedDescription)\n".utf8Data)
                                }
                            }

                            // 追加 .uarp 文件名到 destURL
                            destURL = destURL.appendingPathComponent(uarp.lastPathComponent)

                            try? FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
                            try FileManager.default.copyItem(at: uarp, to: destURL)
                            terminal.cmdOutputSub.send("✅ Copied uarp to: \(destURL.path)\n".utf8Data)
                        } catch {
                            terminal.cmdOutputSub.send("❌ Error in processing Radar files: \(error.localizedDescription)\n".utf8Data)
                        }
                    }
                }
                
            }
            SerialPortPicker(selectedPath: $selectedPort, serialPort: portModel) .frame(width: 200)
            
            

            Button(action: runWorkflow) {
                Text(isRunning ? "Processing..." : "Start EB Update")
            }
            .disabled(ftabURL == nil || comment.isEmpty || selectedPort.isEmpty || isRunning)
        }
        .padding()
    }
    func runWorkflow() {
        isRunning = true
        terminal.cmdOutputSub.send(Data("\n🔄 Starting EB Restore script...\n".utf8))

        Task {
            do {
                let project = try await portModel.getProjectNameFromDevice()

                let script = settings.workingDir + "/goldrestore_durant/goldrestore_eb.sh"
                let env: [String: String] = [
                    "PYTHONPATH": settings.pythonSitePackagesPath,
                    "PYTHON_BIN": settings.pyExe,
                    "DYLD_LIBRARY_PATH": "/opt/homebrew/lib"
                ]

                terminal.cmdOutputSub.send(Data("🐍 PYTHONPATH = \(settings.pythonSitePackagesPath)\n".utf8))
                terminal.cmdOutputSub.send(Data("🔌 Using port: \(selectedPort)\n".utf8))
                terminal.cmdOutputSub.send(Data("📦 Target project: \(project)\n".utf8))

                let fullCommand = "/bin/sh \(script) -p \(selectedPort) -t t2016"
                terminal.cmdOutputSub.send(Data("🚀 Command: \(fullCommand)\n".utf8))

                try await runShellCommandAsyncEB(
                    "/bin/sh",
                    arguments: [script, "-p", selectedPort, "-t", "t2016"],
                    environment: env,
                    dataSub: terminal.cmdOutputSub
                )
            } catch {
                terminal.cmdOutputSub.send(Data("❌ Buds restore failed: \(error.localizedDescription)\n".utf8))

                // 清空 EB_UARP 目录
                let destDir = settings.workingDir + "/goldrestore_durant/RestorePackage/EB_UARP"
                let destURL = URL(fileURLWithPath: destDir)

                if FileManager.default.fileExists(atPath: destDir) {
                    do {
                        let contents = try FileManager.default.contentsOfDirectory(at: destURL, includingPropertiesForKeys: nil)
                        for file in contents {
                            try FileManager.default.removeItem(at: file)
                        }
                        terminal.cmdOutputSub.send("🧹 Cleared EB_UARP folder due to failure.\n".utf8Data)
                    } catch {
                        terminal.cmdOutputSub.send("⚠️ Failed to clean EB_UARP folder: \(error.localizedDescription)\n".utf8Data)
                    }
                }
            }
            isRunning = false
            portModel.close()
        }
    }
}

extension SerialPort {
    func reset() {
        self.close()
        self.serialPath = ""
    }
}
func runShellGetECID(
    port: String,
    terminal: TerminalModel,
    serialPort: SerialPort
) async throws -> String {
    
    terminal.cmdOutputSub.send(Data("🔧 Running ECID fetch task for: \(port)\n".utf8))

    
    serialPort.close()
    try await Task.sleep(nanoseconds: 300_000_000)

    let command = "echo 'ft ecid' > \(port); sleep 1; cat \(port)"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outputData, encoding: .utf8) ?? ""
    
    terminal.cmdOutputSub.send(Data("📥 Raw ECID shell output:\n\(output)\n".utf8))

    
    serialPort.open()

    if let match = output.range(of: #"0x[0-9a-fA-F]{14,}"#, options: .regularExpression) {
        return String(output[match])
    } else {
        throw NSError(domain: "ECIDParsing", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "ECID not found in output:\n\(output)"
        ])
    }
}

// === SettingsModel+RadarRefresh.swift ===
extension SettingsModel {
    @MainActor
    func refreshEBAttachments() async {
        guard !radarAccessToken.isEmpty else { return }

        await withCheckedContinuation { continuation in
            getProblemAttachments("133428147", accessToken: radarAccessToken) { data in
                guard let dictList = dataToDictList(data: data) else {
                    continuation.resume()
                    return
                }

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                formatter.locale = Locale(identifier: "en_US_POSIX")

                let enriched = dictList.compactMap { dict -> RadarAttachmentModel? in
                    guard let file = dict["fileName"] as? String,
                          let createdAt = dict["createdAt"] as? String,
                          let date = formatter.date(from: createdAt) else { return nil }

                    let addedBy = dict["addedBy"] as? [String: Any]
                    let firstName = addedBy?["firstName"] as? String ?? ""
                    let lastName = addedBy?["lastName"] as? String ?? ""

                    return RadarAttachmentModel(
                        fileName: file,
                        radarID: "133428147",
                        uploadDate: date,
                        author: "\(firstName) \(lastName)",
                        token: self.radarAccessToken
                    )
                }.sorted(by: { $0.uploadDate > $1.uploadDate })

                Task { @MainActor in
                    self.ebAttachments = enriched
                    continuation.resume()
                }
            }
        }
    }

    func getRadarAccessToken() async -> String? {
        return radarAccessToken.isEmpty ? nil : radarAccessToken
    }
}



struct SerialPortPicker: View {
    @Binding var selectedPath: String
    @ObservedObject var serialPort: SerialPort
    
    

    var body: some View {
        Picker("Port", selection: $selectedPath) {
            ForEach(serialPort.availablePorts, id: \.self) { port in
                Text(port).tag(port)
            }
        }
        .onAppear {
            if selectedPath.isEmpty, let first = serialPort.availablePorts.first {
                selectedPath = first
            }
        }
        .onChange(of: serialPort.availablePorts) { newPorts in
            if !newPorts.contains(selectedPath) {
                if let first = newPorts.first {
                    selectedPath = first
                }
            }
        }
        .pickerStyle(MenuPickerStyle())
    }
}

extension String {
    var utf8Data: Data {
        return Data(self.utf8)
    }
}
