//
//  ripplebeamApp.swift
//  ripplebeam
//
//  Created by Shaoxuan Yuan on 2024/7/15.
//

import SwiftUI

@main
struct ripplebeamApp: App {
    @ObservedObject var settings = SettingsModel()
    @StateObject var consoleTerm = TerminalModel()

    init() {
        Log.general.info("RippleBeam started")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(consoleTerm)
        }

        WindowGroup(id: "plot", for: [String].self) { strArray in
            if let array = strArray.wrappedValue {
                let floatValues = array.compactMap { Float($0) }
                FloatChartView(title: "Regex Plot", floatValues: floatValues)
            } else {
                Text("No data to display")
            }
        }

        Window("Console CSV export", id: "console_csv") {
            CSVPanelView()
        }

        Window("Regex XY Plot", id: "regex_xy_plot") {
            RegexXYPlotView()
        }
        
        Window("Regex Multi-Plot", id: "regex_multi_plot") {
            RegexPlotPanelView()
        }

        Window("Regex XY Plot", id: "regex_xy_plot") {
            RegexXYPlotView()
        }
        WindowGroup(id: "regex_plot") {
            RegexXYPlotView()
        }
    }
}
