//
//  ConsoleView.swift
//  ripplebeam
//
//  Created by Shaoxuan Yuan on 2024/8/20.
//

import Foundation
import SwiftUI
import Combine
import SplitView
import CodeEditorView
import LanguageSupport




enum Mode: CaseIterable {
    case raw
    case upy

    var value: String {
        switch self {
        case .raw:
            "Raw"
        case .upy:
            "uPy"
        }
    }
}


enum sendingStatus {
    case sending
    case stopped
    case done
}


struct SafeCodeEditor: View {
    @Binding var text: String
    @Binding var position: CodeEditor.Position
    @Binding var messages: Set<TextLocated<Message>>
    let colorScheme: ColorScheme

    var body: some View {
        CodeEditor(
            text: $text,
            position: Binding(
                get: { position },
                set: { newValue in
                    DispatchQueue.main.async {
                        position = newValue
                    }
                }
            ),
            messages: $messages,
            language: .diags(),
            layout: .init(showMinimap: false, wrapText: true)
        )
        .environment(\.codeEditorTheme,
                     colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
    }
}

class ConsoleModel: ObservableObject {
        @Published var hasSentCommand = false
        //@Published var terminal: TerminalModel
        @Published var command: String = ""
        @Published var mode: Mode = .raw
        @Published var loops: String = "1"
        @Published var status: sendingStatus = .done
        @ObservedObject var terminal = consoleTerm



        init(terminal: TerminalModel) {
            print("ConsoleView init - current port: \(consoleSerial.selectedPath)")
            self.terminal = terminal
        }

    func upyUpload(_ serialP: SerialPort, command cmd: String) {
        serialP.send(value: "upy upload", suffix: "\n")
        serialP.send(value: cmd, suffix: "\n")
        // send Ctrl-C to end upload
        serialP.send(value: String(UnicodeScalar(3)!), suffix: "")
    }

    func upyRun(_ serialP: SerialPort, script: String) {
        serialP.send(value: "upy run \(script)", suffix: "\n")
    }

    struct BIFARGS {
        let pattern: String
        let timeout: Int
    }

    /// Validate if this line represents a correct ##BIF command
    /// - Parameter cmd: input cmd line, i.e. ##BIF "pattern" timeout
    /// - Returns: if correct, return an array of command args; else, return nil
    func validateBIF(cmd: String) -> BIFARGS? {
        let parts = parseArguments(cmd)
        guard parts.count == 3 else { return nil }
        let pattern = parts[1]

        /// check timeout is an int
        guard let timeout = Int(parts[2]) else { return nil }

        return BIFARGS(pattern: pattern, timeout: timeout)
    }

    /// Validate if this line represents a correct ##DELAY command
    /// - Parameter cmd: input cmd line, i.e. ##DELAY timeout
    /// - Returns: if correct, returns an Int representing the ms to delay; else, return nil
    func validateDELAY(cmd: String) -> Int? {
        let parts = parseArguments(cmd)
        guard parts.count == 2 else { return nil }

        /// check timeout is an int
        guard let timeout = Int(parts[1]) else { return nil }

        return timeout
    }

    /// Send the commands in input textbox line-by-line asynchronously.
    /// Handles built-in macro commands.
    /// - Returns: 0 if exited normally;
    ///   positive number indicating which line, if stopped by macros (e.g. BIF/WAIT)
    func sendCommand(_ serialP: SerialPort) async -> Int {
        
        print("📤 [sendCommand] \(self.command)")
        Thread.callStackSymbols.forEach { print($0) }
        let commands = self.command.components(separatedBy: "\n")

        for i in 0..<(Int(self.loops) ?? 0) {
            if mode == .upy {
                if i == 0 {
                    // do the initial upload
                    upyUpload(serialP, command: command)
                }
                upyRun(serialP, script: "temp")
                await taskSleepMillisecondsNoThrow(100)
                continue
            }
            for (lineNo, cmd) in commands.enumerated() {

                // MARK: - ##BIF "<pattern>" <timeout>
                if cmd.hasPrefix("##BIF") {
                    guard let args = validateBIF(cmd: cmd) else { continue }
                    Log.general.info("Console: ##BIF \(args.pattern) \(args.timeout)")
                    var timeout = args.timeout

                    /// let the output settle a bit
                    await Task.yield()

                    /// check output every 100ms while waiting for timeout
                    while timeout > 0 {
                        /// if found pattern, break; else wait another 100ms
                        if terminal.output.map(\.text).joined().contains(args.pattern) {
                            self.status = .stopped
                            return lineNo + 1
                        } else {
                            await taskSleepMillisecondsNoThrow(100)
                            timeout -= 100
                        }
                    }
                // MARK: - ##CIF "<pattern>" <timeout>
                } else if cmd.hasPrefix("##CIF") {
                    guard let args = validateBIF(cmd: cmd) else { continue }
                    Log.general.info("Console: ##CIF \(args.pattern) \(args.timeout)")
                    var timeout = args.timeout

                    /// let the output settle a bit
                    await Task.yield()

                    /// check output every 100ms while waiting for timeout
                    while timeout > 0 {
                        /// if cannot find pattern, wait another 100ms then recheck
                        if terminal.output.map(\.text).joined().contains(args.pattern) {
                            break
                        } else {
                            await taskSleepMillisecondsNoThrow(100)
                            timeout -= 100
                        }
                    }
                    if timeout <= 0 {
                        return lineNo + 1
                    }
                // MARK: - ##DELAY <timeout>
                } else if cmd.hasPrefix("##DELAY") {
                    guard let delay = validateDELAY(cmd: cmd) else { continue }
                    Log.general.info("Console: ##DELAY \(delay)")
                    await taskSleepMillisecondsNoThrow(delay)
                // MARK: - ##CLEAR
                } else if cmd.hasPrefix("##CLEAR") {
                    /// let the output settle a bit
                    await Task.yield()
                    Log.general.info("Console: ##CLEAR")
                    terminal.output.removeAll()
                } else if cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Log.general.info("Console: skipped empty command line")
                    continue
                } else {
                    Log.general.info("Console: sending cmd '\(cmd)'")
                    serialP.send(value: cmd)
                }
            }
        }
        return 0
    }
}


struct ConsoleView: View {
        @ObservedObject var terminal: TerminalModel
        @ObservedObject var serialP:  SerialPort
        @ObservedObject var model:    ConsoleModel
        @State private var position: CodeEditor.Position  = CodeEditor.Position()
        @State private var messages: Set<TextLocated<Message>> = Set()
        @Environment(\.colorScheme) private var colorScheme: ColorScheme
        @State private var isAdvancedExpanded = false
        @State private var stoppedLine = 0
        @State private var addBaudRateIsPresented = false
        @EnvironmentObject private var settings: SettingsModel
        @State private var addedBaudRate = ""
        @State private var disposables = Set<AnyCancellable>()

    func insertAtCursor(text: String) {
        if let range = position.selections.first {
            let offset = range.location
            let commandLength = model.command.count

            if offset <= commandLength {
                let insertIndex = model.command.index(model.command.startIndex, offsetBy: offset)
                model.command.insert(contentsOf: text, at: insertIndex)
            } else {
                // fallback: append to the end if index is out of bounds
                model.command.append(contentsOf: text)
            }
        } else {
            model.command.insert(contentsOf: text, at: model.command.startIndex)
        }
    }


    var body: some View {
        VStack (alignment: .center) {
            HStack {
                Picker("Port", selection: $serialP.serialPath) {
                    ForEach(serialP.availablePorts, id: \.self) { port in
                        Text(port).tag(port)
                    }
                    Text("No Port").tag("NO_PORT_SELECTED")
                }
                .frame(maxWidth: 200)
                .onAppear {
                    DispatchQueue.main.async {
                        if serialP.serialPath.isEmpty || !serialP.availablePorts.contains(serialP.serialPath) || serialP.serialPath == "NO_PORT_SELECTED" {
                            Log.general.warning("⚠️ serialPath invalid on appear: \(serialP.serialPath)")
                            serialP.serialPath = serialP.availablePorts.first ?? "NO_PORT_SELECTED"
                        }
                    }
                }
                .onChange(of: serialP.availablePorts) { _ in
                    if serialP.serialPath.isEmpty || !serialP.availablePorts.contains(serialP.serialPath) || serialP.serialPath == "NO_PORT_SELECTED" {
                        Log.general.warning("⚠️ serialPath invalid on port list change: \(serialP.serialPath)")
                        serialP.serialPath = serialP.availablePorts.first ?? "NO_PORT_SELECTED"
                    }
                }
                Picker("BaudRate", selection: $serialP.baudRate) {
                    ForEach(settings.baudRates + settings.addedBaudRates, id: \.self) {
                        Text(String($0))
                    }
                    Divider()
                    Text("Add baud rate...").tag(-1)
                    Divider()
                    Text("Reset").tag(-2)
                }.frame(maxWidth: 200)
    
                    .onChange(of: serialP.baudRate) { _ in
                        if serialP.baudRate == -1 {
                            addBaudRateIsPresented = true
                            serialP.baudRate = settings.baudRates[0]
                        } else if serialP.baudRate == -2 {
                            serialP.baudRate = settings.baudRates[0]
                            settings.addedBaudRates.removeAll()
                            settings.saveSettings()
                        }
                    }.sheet(isPresented: $addBaudRateIsPresented) {
                        VStack {
                            TextField("Baud rate", text: $addedBaudRate).frame(width: 100)
                            Button("Done") {
                                if let rate = Int(addedBaudRate) {
                                    settings.addedBaudRates.append(rate)
                                    serialP.baudRate = rate
                                    settings.saveSettings()
                                }
                                addBaudRateIsPresented = false
                            }
                        }.frame(minWidth: 130, minHeight: 100)
                    }
                Button(serialP.isOpen ? "Disconnect" : "Connect") {
                    serialP.isOpen ? serialP.close() : serialP.open()
                }
            }
            
            
            Text("Output lines: \(terminal.output.count)")
                    .padding()

            if serialP.isOpen {
                let fraction = FractionHolder.usingUserDefaults(0.9, key: "consoleTermFraction")

                VSplit() {
                    // terminal
                    TerminalView(terminal: terminal, viewParent: .console)
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, 5)


                } bottom: {
                    // input textbox
                    VStack(alignment: .leading) {

                        SafeCodeEditor(
                            text: $model.command,
                            position: $position,
                            messages: $messages,
                            colorScheme: colorScheme
                        )

                        HStack {
                            Button("Send (⌘ ⏎)") {
                                guard serialP.taskFinished else {
                                    Log.general.error("Console: there is an ongoing sending task, wait til it's done")
                                    return
                                }
                                serialP.task = Task {
                                    model.status = .sending
                                    serialP.taskFinished = false
                                    let ret = await model.sendCommand(serialP)
                                    serialP.taskFinished = true
                                    model.status = ret == 0 ? .done : .stopped
                                    stoppedLine = ret
                                }
                            }.keyboardShortcut(.init(.return, modifiers: .command))

                            Divider().frame(height: 15)

                            Picker("Mode", selection: $model.mode) {
                                ForEach(Mode.allCases, id: \.self) {
                                    Text($0.value)
                                }
                            }.frame(maxWidth: 100)

                            Divider().frame(height: 15)

                            TextField("Number", text: Binding(
                                get: { model.loops },
                                set: { newVal in
                                    if newVal.allSatisfy({ $0.isNumber }) {
                                        model.loops = newVal
                                    } else {
                                        Log.general.warning("🚫 Invalid loop input: \(newVal)")
                                    }
                                }
                            )).frame(maxWidth: 50)
                            Text("loops")

                            Divider().frame(height: 15)
                            Button("Advanced...") {
                                isAdvancedExpanded.toggle()
                            }

                            Spacer().frame(height: 20)
                            /// status
                            switch model.status {
                            case .sending:
                                Text("Status: sending").bold().foregroundStyle(.blue)
                            case .stopped:
                                Text("Status: stopped at \(stoppedLine)").bold().foregroundStyle(.red)
                            case .done:
                                Text("Status: done").bold().foregroundStyle(.green)
                            }
                        }

                        if isAdvancedExpanded {
                            Section("Macros") {
                                HStack {
                                    Button("##DELAY") {
                                        let text = "##DELAY 0"
                                        insertAtCursor(text: text)
                                        /// move the cursor to the end of inserted macro
                                        position.selections[0].location += text.count
                                    }

                                    Button("##BIF") {
                                        let text = "##BIF \"\" 0"
                                        insertAtCursor(text: text)
                                        /// move the cursor to the end of inserted macro
                                        position.selections[0].location += text.count
                                    }

                                    Button("##CIF") {
                                        let text = "##CIF \"\" 0"
                                        insertAtCursor(text: text)
                                        /// move the cursor to the end of inserted macro
                                        position.selections[0].location += text.count
                                    }

                                    Button("##CLEAR") {
                                        let text = "##CLEAR"
                                        insertAtCursor(text: text)
                                        /// move the cursor to the end of inserted macro
                                        position.selections[0].location += text.count
                                    }
                                }
                            }
                        }


                    }
                    .frame(maxHeight: .infinity)
                    .padding(.top, 5)
                }
                .fraction(fraction)
                .constraints(minPFraction: 0.1, minSFraction: 0.1)
                .styling(invisibleThickness: 5)
                .frame(minHeight: 300)
            } else {
                Text(offlineWarning)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        
    }
}
