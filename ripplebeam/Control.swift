//
//  DemoView.swift
//
//  Created by Shaoxuan Yuan.
//  Adapted from:
//  Jan Anstipp https://github.com/janhendry/ORSSerialPort/commit/24ec6a166178d0f4484ebcfc292588f5beca25fe
//

import SwiftUI
import ORSSerial
import FilePicker

var controlSerial = SerialPort(dataSub: nil)
var updateModelGlobal = UpdateModel()
var controlModelGlobal = ControlModel()

class ControlModel: ObservableObject {
    let serialPort: SerialPort
    @Published var setup: String = ""

    init(serialPort: SerialPort = SerialPort(dataSub: nil)) {
        self.serialPort = serialPort
    }
}

struct ControlView: View {
    @ObservedObject var updateModel: UpdateModel
        @ObservedObject var terminal: TerminalModel
        @ObservedObject var serialPort: SerialPort
        @ObservedObject var controlModel: ControlModel
        let consoleSerial: SerialPort
    
    
        var schema: Schema
        var debug: Bool = false
    
    var body: some View {
        VStack {
            HStack {
                Picker("Port", selection: $serialPort.serialPath) {
                    ForEach(serialPort.availablePorts, id: \.self) {
                        Text($0)
                    }
                }
                .frame(maxWidth: 200)
                .onAppear {
                    if serialPort.serialPath.isEmpty, let first = serialPort.availablePorts.first {
                        serialPort.serialPath = first
                    }
                }
                .onChange(of: serialPort.availablePorts) { newPorts in
                    if !newPorts.contains(serialPort.serialPath) {
                        Log.general.warning("Port '\(serialPort.serialPath)' no longer available. Resetting to first available.")
                        if let first = newPorts.first {
                            serialPort.serialPath = first
                        } else {
                            Log.general.warning("No available ports to select.")
                        }
                    }
                }

                Picker("Setup", selection: $controlModel.setup) {
                    ForEach(schema.setups.map { $0.name }, id: \.self) {
                        Text($0)
                    }
                }.frame(maxWidth: 200)
                .onAppear {
                    if controlModel.setup == "" {
                        controlModel.setup = schema.setups.first?.name ?? ""
                    }
                }
            }

            Divider()
            ShortcutsView(
                schema: schema,
                setupName: controlModel.setup,
                terminal: terminal,
                consoleSerial: consoleSerial,
                controlSerial: serialPort,
                updateModel: updateModel
            )

            Divider()
            UpdateView(schema: schema, setupName: controlModel.setup, terminal: terminal, controlSerial: serialPort)

            Divider()
            TerminalView(
              terminal: terminal,
              viewParent: .control
            )

        }
    }
}

// MARK: - Shortcuts

struct ShortcutsView: View {
    let shortcutColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    let schema: Schema
    let setupName: String
    let terminal: TerminalModel
    let consoleSerial: SerialPort
    let controlSerial: SerialPort
    let updateModel: UpdateModel

    var body: some View {
        VStack (alignment: .leading) {
            Text("Shortcuts").bold()
            LazyVGrid(columns: shortcutColumns) {
                if let setup = schema.setups.first(where: { $0.name == setupName }) {
                    ForEach(setup.shortcuts, id: \.name) { script in
                        ScriptButton(
                            script: script,
                            dataSub: terminal.cmdOutputSub,
                            extraArgs: updateModel.args.split(separator: " ").map(String.init),
                            consoleSerial: consoleSerial,
                            controlSerial: controlSerial,
                            bundle: updateModel.fwVer
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Firmware updates

class UpdateModel: ObservableObject {
    @Published var fwVerList: [String] = []
    @Published var fwVer: String = ""
    @Published var target: String = ""
    @Published var fwBundlePath: String = ""
    @Published var args: String = ""
    @Published var history: [String] = []
    @Published var useLocalFiles: Bool = false
}


struct UpdateView: View {
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject var updateModel = updateModelGlobal
    @State private var isShowingOptions = false
    @State private var isShowingHistory = false
    @State private var isShowingVersions = false
    @State private var isPickingFiles = false
    private let fwSources = ["Fetch", "Local"]
    @State private var fwSrc = ""
    /// "bundles" in the schema, e.g. "ToT", "Factory"
    @State private var bundleType = ""
    @State private var isImporting = false
    @State private var selectedFiles: [URL] = []
    @State private var showFileHint = false
    @State private var showFileHintAlert = false
    let schema: Schema
    let setupName: String
    let terminal: TerminalModel
    let controlSerial: SerialPort
    

    var body: some View {
        VStack (alignment: .leading) {
            HStack {
                Text("Firmware Update").bold()
            }

            if let setup = schema.setups.filter({$0.name == setupName}).first {
                let targets = setup.fwUpdate.targets.map{ $0.name }

                /// Target
                Picker("Target", selection: $updateModel.target) {
                    ForEach(targets, id: \.self) {
                        Text($0)
                    }
                }.frame(maxWidth: 130)
                    .onAppear {
                        if updateModel.target == "" {
                            updateModel.target = targets[0]
                        }
                    }

                Spacer().frame(height: 20)

                /// Firmware source
                HStack {
                    Text("Firmware")

                    TextField("Bundle", text: $updateModel.fwVer)
                        .frame(maxWidth: 300)

                    FilePicker(types: [.plainText], allowMultiple: false,
                               title: "Local") { urls in
                        let fileURL = urls[0]
                        updateModel.fwVer = fileURL.path()
                    }

                    Button(action: {
                        isShowingVersions = true

                        updateModel.fwVerList = ["Loading..."]

                        guard let project = schema.projects.filter( {$0["name"] == updateModel.target} ).first,
                              let projectName = project["name"],
                              let trainName = project[bundleType.lowercased()] else {
                            Log.general.error("cannot load project/projectName/trainName")
                            return
                        }

                        Task {
                            updateModel.fwVerList = await updatePointers(train: trainName, imageName: projectName + "DFUDeviceFirmware")
                            if let latestPoiter = updateModel.fwVerList.first {
                                updateModel.fwVer = latestPoiter
                            }
                        }
                    }) {
                        Text("Download")
                    }.popover(isPresented: $isShowingVersions, arrowEdge: .bottom) {
                        List {
                            ForEach(updateModel.fwVerList, id: \.self) { version in
                                Text(version).onTapGesture {
                                    updateModel.fwVer = version
                                }
                            }
                        }.frame(width: 200)
                    }

                    Picker("Type", selection: $bundleType) {
                        ForEach(Array(schema.bundles), id: \.self) {
                            Text($0)
                        }
                    }.frame(maxWidth: 120)
                        .onAppear{
                            bundleType = schema.bundles.first ?? ""
                        }
                }

                Spacer().frame(height: 20)
                
    
                Button("CM Flash Released FW") {
                    showFileHintAlert = true
                }
                .alert("Required Files", isPresented: $showFileHintAlert) {
                    Button("Continue", role: .none) { isImporting = true }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("""
                    Please select exactly these 4 files:
                    • ftab.bin
                    • t2016diagdfuap.bin
                    • t2016fwupdaterap.bin
                    • upyf.bin
                    """)
                }
                .fileImporter(
                    isPresented: $isImporting,
                    allowedContentTypes: [.data],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        guard urls.count == 4 else {
                            terminal.cmdOutputSub.send("❌ Please select exactly 4 files.\n".utf8Data)
                            return
                        }
                        let expected = ["ftab.bin", "t2016diagdfuap.bin", "t2016fwupdaterap.bin", "upyf.bin"]
                        let fileNames = urls.map { $0.lastPathComponent }
                        let missing = expected.filter { !fileNames.contains($0) }
                        guard missing.isEmpty else {
                            terminal.cmdOutputSub.send("❌ Missing required files: \(missing.joined(separator: ", "))\n".utf8Data)
                            return
                        }
                        Task {
                            let destPath = settings.workingDir + "/goldrestore_durant/RestorePackage/t2016"
                            let destURL = URL(fileURLWithPath: destPath)
                            try? FileManager.default.createDirectory(at: destURL, withIntermediateDirectories: true)
                            for src in urls {
                                let fileName = src.lastPathComponent
                                let dst = destURL.appendingPathComponent(fileName)
                                do {
                                    if FileManager.default.fileExists(atPath: dst.path) {
                                        try FileManager.default.removeItem(at: dst)
                                    }
                                    try FileManager.default.copyItem(at: src, to: dst)
                                    terminal.cmdOutputSub.send("✅ Copied \(fileName) to \(dst.path)\n".utf8Data)
                                } catch {
                                    terminal.cmdOutputSub.send("❌ Failed to copy \(fileName): \(error.localizedDescription)\n".utf8Data)
                                }
                            }
                            terminal.cmdOutputSub.send("📦 Files ready. Running golden restore for t2016...\n".utf8Data)
                            updateModel.useLocalFiles = true
                            await runLocalRestore()
                        }
                    case .failure(let error):
                        terminal.cmdOutputSub.send("❌ File import failed: \(error.localizedDescription)\n".utf8Data)
                    }
                }
                

                /// Options
                HStack {
                    Button("Options") {
                        isShowingOptions = true
                    }.popover(isPresented: $isShowingOptions, arrowEdge: .bottom) {
                        if let target = setup.fwUpdate.targets.filter({$0.name == updateModel.target}).first {
                            List {
                                ForEach(target.options, id: \.self) { option in
                                    Text(option).onTapGesture {
                                        updateModel.args += "\(option) "
                                    }
                                }
                            }.frame(width: 200)
                        }
                    }

                    TextField("", text: $updateModel.args)

                    Button("Clear") {
                        updateModel.args = ""
                    }

                    Button(action: {
                        isShowingHistory = true
                    }) {
                        Image(systemName: "triangle.fill")
                            .frame(width: 15, height: 15)
                            .foregroundColor(.blue)
                    }.popover(isPresented: $isShowingHistory) {
                        List {
                            ForEach(updateModel.history, id: \.self) { historyArg in
                                Text(historyArg).onTapGesture {
                                    updateModel.args = historyArg
                                }
                            }
                        }
                    }
                }

                Spacer().frame(height: 20)

                /// Start
                Button("Start") {
                    if let target = setup.fwUpdate.targets.first(where: { $0.name == updateModel.target }) {
                        // Append to history if args is not empty
                        if !updateModel.args.isEmpty {
                            updateModel.history.append(updateModel.args)
                        }

                        // Build the full script path using URL-safe logic
                        let scriptURL = URL(fileURLWithPath: settings.workingDir)
                            .appendingPathComponent(target.script)  // Make sure this is a relative path like "goldrestore_durant/goldrestore_durant.sh"
                        let scriptPath = scriptURL.path

                        // Prepare full arguments list
                        let userArgs = updateModel.args
                            .split(separator: " ")
                            .map(String.init)
                            .filter { !$0.isEmpty }

                        var resolvedDefaults = target.defaults

                        if updateModel.useLocalFiles {
                            resolvedDefaults = resolvedDefaults.filter { $0 != "-b" && $0 != "$BUNDLE" }
                        } else {
                            resolvedDefaults = resolvedDefaults.map { arg in
                                arg == "$CONTROLPORT" ? controlSerial.serialPath : arg
                            }
                        }

                        // 构造最终 arguments
                        var arguments = [scriptPath] + resolvedDefaults + userArgs

                        macroReplace(&arguments, consoleSerial: consoleSerial, controlSerial: controlSerial, bundle: updateModel.fwVer)
                        

                        // Debug print to verify the script path
                        print("Running script at path: \(scriptPath)")

                        // Execute if it's a .sh script
                        if target.script.hasSuffix(".sh") {
                            Task {
                            
                                guard let resPath = Bundle.main.resourcePath else {
                                    terminal.cmdOutputSub.send("❌ resourcePath not found.\n".utf8Data)
                                    return
                                }

                                let pythonBinPath = resPath + "/audiofactorydiagtools/3.11/bin/python3.11"
                                let pythonDir = (pythonBinPath as NSString).deletingLastPathComponent

                                var env = ProcessInfo.processInfo.environment
                                env["PYTHON_BIN"] = pythonBinPath
                                env["PATH"] = "\(pythonDir):\(env["PATH"] ?? "")"
                                
                                let embeddedLibusbDir = resPath + "/audiofactorydiagtools/libusb-1.0.26/libusb/.libs"
                                if FileManager.default.fileExists(atPath: embeddedLibusbDir) {
                                    env["DYLD_LIBRARY_PATH"] = embeddedLibusbDir
                                    terminal.cmdOutputSub.send("✅ DYLD_LIBRARY_PATH -> \(embeddedLibusbDir)\n".utf8Data)
                                } else {
                                    terminal.cmdOutputSub.send("⚠️ Embedded libusb dir not found: \(embeddedLibusbDir)\n".utf8Data)
                                 
                                    let brewLib = "/opt/homebrew/lib"
                                    if FileManager.default.fileExists(atPath: brewLib) {
                                        env["DYLD_LIBRARY_PATH"] = brewLib
                                        terminal.cmdOutputSub.send("↪︎ Fallback DYLD_LIBRARY_PATH -> \(brewLib)\n".utf8Data)
                                    }
                                }

                               
                                let pythonSitePackages = resPath + "/audiofactorydiagtools/3.11/lib/python3.11/site-packages"
                                if FileManager.default.fileExists(atPath: pythonSitePackages) {
                                    env["PYTHONPATH"] = pythonSitePackages
                                }

                                await runShellCommandAsync(
                                    "/bin/sh",
                                    arguments: arguments,
                                    environment: env,
                                    dataSub: terminal.cmdOutputSub
                                )
                            }
                        }
                    }
                }

            } else {
                Text("Cannot load target")
                    .onAppear{ Log.general.error("cannot find setup when populating Target picker") }
            }
        }
    }
    private func runLocalRestore() async {
        let scriptURL = URL(fileURLWithPath: settings.workingDir)
            .appendingPathComponent("goldrestore_durant/goldrestore_durant.sh")
        let scriptPath = scriptURL.path

        var arguments: [String] = [
            scriptPath,
            "-t", "t2016",
            "-g", controlSerial.serialPath,
            "-u", "--factory"
        ]
        let userArgs = updateModel.args.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        arguments.append(contentsOf: userArgs)

        guard let resPath = Bundle.main.resourcePath else {
            terminal.cmdOutputSub.send("❌ resourcePath not found.\n".utf8Data)
            return
        }

        // Embedded Python
        let pythonBinPath = resPath + "/audiofactorydiagtools/3.11/bin/python3.11"
        let pythonDir = (pythonBinPath as NSString).deletingLastPathComponent
        let sitePkgs = resPath + "/audiofactorydiagtools/3.11/lib/python3.11/site-packages"

        // 👉 关键：内嵌 libusb 目录（不是文件）
        let embeddedLibusbDir = resPath + "/audiofactorydiagtools/libusb-1.0.26/libusb/.libs"

        var env = ProcessInfo.processInfo.environment
        env["PYTHON_BIN"] = pythonBinPath
        env["PATH"] = "\(pythonDir):\(env["PATH"] ?? "")"
        if FileManager.default.fileExists(atPath: sitePkgs) {
            env["PYTHONPATH"] = sitePkgs
        }

        // 强制让 pyusb/pyftdi 用到内嵌的 libusb
        if FileManager.default.fileExists(atPath: embeddedLibusbDir) {
            env["DYLD_LIBRARY_PATH"] = embeddedLibusbDir
            terminal.cmdOutputSub.send("✅ DYLD_LIBRARY_PATH -> \(embeddedLibusbDir)\n".utf8Data)
        } else {
            terminal.cmdOutputSub.send("⚠️ Embedded libusb dir not found: \(embeddedLibusbDir)\n".utf8Data)
        }

        // 可选：打开 libusb 调试
        // env["LIBUSB_DEBUG"] = "3"

        await runShellCommandAsync(
            "/bin/sh",
            arguments: arguments,
            environment: env,
            dataSub: terminal.cmdOutputSub
        )
    }
}

enum Suffix: CaseIterable {
    case cr
    case lf
    case crls
    case none

    var description: String {
        switch self {
            case .cr: return "CR (\\r}"
            case .lf: return "LF (\\n)"
            case .crls: return "CRLF (\\r\\n)"
            case .none: return "none"
        }
    }
    var value: String {
        switch self {
            case .cr: return "\r"
            case .lf: return "\n"
            case .crls: return "\r\n)"
            case .none: return ""
        }
    }
}

enum BaudRate: CaseIterable {
    case _921600
    case _230400

    var value: Int {
        switch self {
            case ._921600: return 921600
            case ._230400: return 230400
        }
    }
}
