//
//  global.swift
//  ripplebeam
//
//  Created by Jialong Wang's MacBook Pro 16' on 2025/7/16.
//

import Foundation

// Terminal output and input model
let consoleTerm = TerminalModel()


// Singleton SerialPort, keeps connection alive
let consoleSerial = SerialPort(dataSub: consoleTerm.serialOutputSub)

// Singleton ConsoleModel, binds to UI state
let modelGlob = ConsoleModel(terminal: consoleTerm)
