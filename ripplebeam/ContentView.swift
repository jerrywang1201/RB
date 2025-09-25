//
//  ContentView.swift
//
//  Created by Shaoxuan Yuan.
//  Adapted from:
//  Jan Anstipp https://github.com/janhendry/ORSSerialPort/commit/24ec6a166178d0f4484ebcfc292588f5beca25fe
//

import SwiftUI
import FilePicker


// HACK to work-around the smart quote issue
extension NSTextView {
    open override var frame: CGRect {
        didSet {
            self.isAutomaticQuoteSubstitutionEnabled = false
        }
    }
}

let offlineWarning: String = "Device not connected or port not opened."



struct ContentView: View {
    
    @StateObject var consoleTermModel = TerminalModel()
    @StateObject var consoleSerial: SerialPort
    @StateObject var consoleModel: ConsoleModel
    @StateObject var updateModel = UpdateModel()

    init() {
        let termModel = TerminalModel()
        _consoleTermModel = StateObject(wrappedValue: termModel)
        _consoleSerial = StateObject(wrappedValue: SerialPort(dataSub: termModel.serialOutputSub))
        _consoleModel = StateObject(wrappedValue: ConsoleModel(terminal: termModel))
    }
    
    @StateObject var sharedTerminalModel = TerminalModel()
    @StateObject var controlSerial = SerialPort()
    @StateObject var controlModelGlobal = ControlModel()
    @State var isSettingsPresented = false
    @State private var currentTab: Tab = .control
    @State private var isLogSummaryPresented = false
    @State private var isTestChatBotPresented = false
    @State private var launcherReady = false
    @EnvironmentObject var settings: SettingsModel
    
    var body: some View {
        if let schema = settings.schema {
            TabView(selection: $currentTab) {
                ControlView(
                    updateModel: updateModel,
                    terminal: sharedTerminalModel,
                    serialPort: controlSerial,
                    controlModel: controlModelGlobal,
                    consoleSerial: consoleSerial,
                    schema: schema,
                    
                    
                )
                .tabItem {
                    Text("Control")
                }
                .tag(Tab.control)
                .asRBFrame()

                ConsoleView(
                    terminal: consoleTermModel,
                    serialP: consoleSerial,
                    model: consoleModel
                )
                .tabItem {
                    Text("Console")
                }
                .tag(Tab.console)
                .asRBFrame()
                
                
                DashboardView(
                    controlModel: controlModelGlobal,
                    consoleSerial: consoleSerial,
                    updateModel: updateModel
                )
                .tabItem { Text("Dashboard") }
                .tag(Tab.dashboard)
                .asRBFrame()
                
                DebugView(
                    controlModel: controlModelGlobal,
                    terminalModel: sharedTerminalModel,
                    consoleSerial: consoleSerial,
                    updateModel: updateModel
                )
                .tabItem {
                    Text("Debug")
                }
                .tag(Tab.debug)
                .asRBFrame()
                
                EBUpdateView(
                    terminal: sharedTerminalModel
                )
                .tabItem {
                    Text("EB Update")
                }
                .tag(Tab.EBupdate)
                .asRBFrame()
                
                
            }
            .padding()
            .task {
                    launcherReady = true
                }
        } else {
            Text("Cannot read schema JSON")
            Text("Check Settings for JSON path and the JSON is compatible")
        }
        
        // ====== fooder ======
        Divider()
        
        
        
        HStack {
            Button("Settings") {
                print("Settings clicked")
                settings.isSettingsPresented = true
                
            }
            .sheet(isPresented: $settings.isSettingsPresented) {
                SettingsTabView(isPresented: $settings.isSettingsPresented)
                    .environmentObject(settings)
            }
            Divider().frame(height: 20)
            
            Button("Search Radar") {
                settings.isRadarSearchPresented = true
            }
            .sheet(isPresented: $settings.isRadarSearchPresented) {
                RadarSearchView(isPresented: $settings.isRadarSearchPresented)
                    .environmentObject(settings)
            }
            .padding(.leading)

            Spacer()

           
            if launcherReady {
                UnifiedAssistantLauncher(
                    pyExe: settings.pyExe,
                    chatScriptPath: settings.workingDir + "/ai/test_chat_ai.py",
                    logScriptPath: settings.workingDir + "/ai/log_summary_ai.py",
                    controlTerminal: sharedTerminalModel,
                    consoleTerminal: consoleTermModel,
                    currentTab: $currentTab
                )
            }
           
        }
        .padding([.horizontal, .bottom])

    }
}

enum Tab {
    case control
    case console
    case dashboard
    case debug
    case EBupdate
}
