//
//  Logging.swift
//  ripplebeam
//
//  Created by Shaoxuan Yuan on 2024/8/7.
//

import os
import Foundation

let subsystem = "com.apple.ripplebeam"
struct Log {
    static let general = Logger(subsystem: subsystem, category: "general")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
