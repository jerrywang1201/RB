//
//  Schema.swift
//  ripplebeam
//
//  Created by Shaoxuan Yuan on 2024/8/21.
//

import Foundation
import SwiftUI
import Combine


struct Script: Codable {
    let name: String
    let script: String
    let defaults: [String]
    let options: [String]
}

struct Setup: Codable {
    struct FwUpdate: Codable {
        let targets: [Script]
    }

    let name: String
    let shortcuts: [Script]
    let fwUpdate: FwUpdate
    let dashboard: Script
    let debug: [Script]
}

struct Schema: Codable {
    let audioFactoryDiagTools: String
    /// "bundles" in the schema, e.g. "ToT", "Factory"
    let bundles: [String]
    /// "projects" in the schema
    let projects: [[String: String]]
    let setups: [Setup]
}

/// Replace each arg in args according to rules
///  
/// - Parameter args: the argument array for macro replacing
/// - Rules:\
/// **$CONSOLEPORT**: current selected serial device in console view
/// **$CONTROLPORT**: current selected serial device in control view
func macroReplace(
    _ args: inout [String],
    consoleSerial: SerialPort,
    controlSerial: SerialPort,
    bundle: String
) {
    for (i, arg) in args.enumerated() {
        switch arg {
        case "$CONSOLEPORT":
            args[i] = consoleSerial.serialPath
        case "$CONTROLPORT":
            args[i] = controlSerial.serialPath
        case "$BUNDLE":
            args[i] = bundle
        default:
            continue
        }
    }
}

struct ScriptButton: View {
    let script: Script
    let dataSub: PassthroughSubject<Data, Never>
    let preAction: (() -> Void)?
    let extraArgs: [String]?
    let consoleSerial: SerialPort
    let controlSerial: SerialPort
    let bundle: String

    @EnvironmentObject private var settings: SettingsModel

    var body: some View {
        Button(script.name) {
            if let preAction {
                preAction()
            }
            var arguments = ["\(settings.workingDir)\(script.script)"] + script.defaults + (extraArgs ?? [])

            macroReplace(
                &arguments,
                consoleSerial: consoleSerial,
                controlSerial: controlSerial,
                bundle: bundle
            )

            if script.script.suffix(3) == ".py" {
                Task {
                    await runShellCommandAsync(
                        settings.pyExe,
                        arguments: arguments,
                        environment: settings.pythonEnvironment(),
                        dataSub: dataSub
                    )
                }
            } else if script.script.suffix(3) == ".sh" {
                Task {
                    await runShellCommandAsync(
                        "/bin/sh",
                        arguments: arguments,
                        dataSub: dataSub
                    )
                }
            }
        }
    }

    init(script: Script,
         dataSub: PassthroughSubject<Data, Never>,
         extraArgs: [String]? = nil,
         preAction: (() -> Void)? = nil,
         consoleSerial: SerialPort,
         controlSerial: SerialPort,
         bundle: String) {
        self.script = script
        self.dataSub = dataSub
        self.extraArgs = extraArgs
        self.preAction = preAction
        self.consoleSerial = consoleSerial
        self.controlSerial = controlSerial
        self.bundle = bundle
    }
}

func readSchema(filePath: String) -> Schema? {
    Log.general.info("reading schema from path \(filePath)...")
    do {
        // Load the data from the file
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))

        // Decode the JSON data into the ResponseData struct
        let decoder = JSONDecoder()
        let responseData = try decoder.decode(Schema.self, from: data)
        Log.general.info("read schema successfully")

        return responseData

    } catch {
        // Handle any errors
        Log.general.error("Error reading or parsing the JSON file: \(error)")
    }
    return nil
}
