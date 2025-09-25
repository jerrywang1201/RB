//
//  DashboardView.swift
//  ripplebeam
//
//  Created by Shaoxuan Yuan on 2024/7/16.
//

import Foundation
import SwiftUI
import ORSSerial
import Combine

var dashTerm = TerminalModel()
var dashboardModelGlobal = DashboardModel()

struct DashboardRow: Identifiable {
    let key: String
    let value: String
    let id = UUID()

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

class DashboardModel: ObservableObject {
    @Published var rows: [DashboardRow] = []

    var dataSub = PassthroughSubject<Data, Never>()
    private var subSet = Set<AnyCancellable>()
    private var line: String = ""

    /// return the Script linked to the current setup, if schema and setup could be found
    func getRetrieveScript(schema: Schema?, setupName: String) -> Script? {
        if let schema, let setup = schema.setups.first(where: { $0.name == setupName }) {
            return setup.dashboard
        } else {
            return nil
        }
    }

    private var buffer = Data()

    init() {
        dataSub
            .receive(on: RunLoop.main)
            .sink { [weak self] newValue in
                guard let self = self else { return }

                // Append to buffer
                self.buffer.append(newValue)

                // Try decode entire buffer
                if let text = String(data: self.buffer, encoding: .utf8) {
                    Log.general.info("Dashboard: ⬇️ Received full string:\n\(text)")

                    var lines: [String] = []
                    self.line += text
                    self.line = processAccumulatedString(currLine: self.line, lineArray: &lines)

                    Log.general.info("Dashboard: 🧩 Extracted lines:")
                    for line in lines {
                        Log.general.info("- \(line)")
                    }

                    for l in lines {
                        let lower = l.lowercased()
                        if lower.contains("exception occurred") || lower.contains("traceback") {
                            Log.general.warning("Dashboard: ⚠️ Skipping error line: \(l)")
                            continue
                        }

                        if let pos = l.firstIndex(of: ":") {
                            let key = String(l.prefix(upTo: pos)).trimmingCharacters(in: .whitespaces)
                            let value = String(l.suffix(from: l.index(after: pos))).trimmingCharacters(in: .whitespaces)

                            if !key.isEmpty && !value.isEmpty {
                                Log.general.info("Dashboard: ✅ Adding row \(key): \(value)")
                                self.rows.append(DashboardRow(key: key, value: value))
                            }
                        }
                    }

                    // Clear buffer after successful decode
                    self.buffer.removeAll()
                } else {
                    Log.general.warning("Dashboard: partial buffer, waiting for more bytes...")
                }
            }
            .store(in: &subSet)
    }
    
}

struct DashboardView: View {
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject var controlModel = controlModelGlobal
    @ObservedObject var consoleSerial: SerialPort
    @ObservedObject var updateModel: UpdateModel

    var body: some View {
        VStack {
            Text("📋 Current setup in DashboardView: '\(controlModel.setup)'")

            if controlModel.setup.isEmpty {
                Text("⚠️ No setup selected yet.")
            } else {
                DashboardContentView(
                    setupName: controlModel.setup,
                    schema: settings.schema,
                    dashboardModel: dashboardModelGlobal,
                    consoleSerial: consoleSerial,
                    controlSerial: controlModel.serialPort,
                    updateModel: updateModel
                )
            }
        }
        .onChange(of: controlModel.setup) { newSetup in
            print("🔄 DashboardView detected new setup: \(newSetup)")
        }
    }
}
extension Script {
    func replacingVars(_ vars: [String: String]) -> Script {
        let replacedDefaults = defaults.map { str in
            var s = str
            for (key, value) in vars {
                s = s.replacingOccurrences(of: key, with: value)
            }
            return s
        }
        return Script(name: name, script: script, defaults: replacedDefaults, options: options)
    }
}

struct DashboardContentView: View {
    let setupName: String
    let schema: Schema?
    let dashboardModel: DashboardModel
    let consoleSerial: SerialPort
    let controlSerial: SerialPort
    let updateModel: UpdateModel

    var body: some View {
        VStack {
            if let setup = schema?.setups.first(where: { $0.name == setupName }) {
                
                let script = setup.dashboard
                ScriptButton(
                    script: script,
                    dataSub: dashboardModel.dataSub,
                    preAction: {
                        print("📌 Dashboard button clicked with consoleSerial = \(consoleSerial.serialPath)")
                        dashboardModel.rows.removeAll()
                    },
                    consoleSerial: consoleSerial,
                    controlSerial: controlSerial,
                    bundle: "Default"
                )
                

                Table(dashboardModel.rows) {
                    TableColumn("Key", value: \.key)
                    TableColumn("Value", value: \.value)
                }
                .onAppear {
                    print("📋 Table appeared with rows = \(dashboardModel.rows.count)")
                }
            } else {
                Text("⚠️ No dashboard script found for “\(setupName)”")
                    .foregroundColor(.secondary)
            }
        }
    }
}
