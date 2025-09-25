//
//  Debug.swift
//  ripplebeam
//
//  Created by Shaoxuan Yuan on 2024/8/30.
//

import SwiftUI
import Combine

var debugTerminalModelGlobal = TerminalModel()


struct DebugView: View {
    @ObservedObject var controlModel = controlModelGlobal
    @ObservedObject var terminalModel = debugTerminalModelGlobal
    @ObservedObject var consoleSerial: SerialPort
    @ObservedObject var updateModel: UpdateModel

    var body: some View {
        VStack {
            DebugShortcutsView(
                setupName: controlModel.setup,
                dataSub: terminalModel.cmdOutputSub,
                consoleSerial: consoleSerial,
                controlSerial: controlModel.serialPort,
                bundle: updateModel.fwVer
            )
            Divider()
            TerminalView(terminal: terminalModel)
        }
    }
}


struct DebugShortcut: View {
    private let script: Script
    private let dataSub: PassthroughSubject<Data, Never>
    private let consoleSerial: SerialPort
    private let controlSerial: SerialPort
    @State private var options = ""
    private let bundle: String

    var body: some View {
        HStack {
            ScriptButton(
                script: script,
                dataSub: dataSub,
                extraArgs: options.split(separator: " ").map { String($0) },
                consoleSerial: consoleSerial,
                controlSerial: controlSerial,
                bundle: bundle
            )
            TextField("options", text: $options)
        }
    }

    init(
        script: Script,
        dataSub: PassthroughSubject<Data, Never>,
        options: String = "",
        consoleSerial: SerialPort,
        controlSerial: SerialPort,
        bundle: String
    ) {
        self.script = script
        self.dataSub = dataSub
        self.consoleSerial = consoleSerial
        self.controlSerial = controlSerial
        self.options = options
        self.bundle = bundle
    }
}


struct DebugShortcutsView: View {
    @EnvironmentObject var settings: SettingsModel
    private let consoleSerial: SerialPort
    private let controlSerial: SerialPort
    private let setupName: String
    private let dataSub: PassthroughSubject<Data, Never>
    private let shortcutColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let bundle: String

    var body: some View {
        VStack (alignment: .leading) {
            Text("Debug shortcuts").bold()

            LazyVGrid(columns: shortcutColumns) {
                /// unwrap the setup with name equals to the current setupName and extract all the shortcuts inside
                if let schema = settings.schema,
                   let setup = schema.setups.filter({$0.name == setupName}).first {
                    ForEach(setup.debug, id: \.name) { script in
                        DebugShortcut(
                            script: script,
                            dataSub: dataSub,
                            consoleSerial: consoleSerial,
                            controlSerial: controlSerial,
                            bundle: bundle
                        )
                    }
                }
            }
        }
    }

    init(setupName: String,
         dataSub: PassthroughSubject<Data, Never>,
         consoleSerial: SerialPort,
         controlSerial: SerialPort,
         bundle: String) {
        self.setupName = setupName
        self.dataSub = dataSub
        self.consoleSerial = consoleSerial
        self.controlSerial = controlSerial
        self.bundle = bundle
    }
}
