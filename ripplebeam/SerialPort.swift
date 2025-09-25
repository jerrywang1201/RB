//
//  SerialPort.swift
//  ripplebeam
//
//  Created by Shaoxuan Yuan on 2024/8/27.
//

import Foundation
import ORSSerial
@preconcurrency import Combine


class SerialPort: NSObject, ObservableObject {
    
    @Published var selectedPath: String = ""
    @Published var ports: [ORSSerialPort] = []

    var port: ORSSerialPort?
    private var subSet = Set<AnyCancellable>()
    private var manager = ORSSerialPortManager.shared()

    /// current sending task
    var task: Task<(), Never>?
    @Published var taskFinished: Bool = true

    @Published var serialPath: String
    @Published var baudRate: Int
    @Published var isConnect: Bool
    @Published var isOpen: Bool
    @Published var availablePorts: [String] = []
    /// Downstream subject that receives serial output data,
    /// e.g. a terminal view that displays the data from this port
    var dataSub: PassthroughSubject<Data, Never>?

    var name: String { port?.name ?? "null" }
    var path: String { port?.path ?? "null" }

    func open(){
        port?.open()
    }
    func close(){
        port?.close()
    }

    func send(value:String, suffix: String = "\r\n"){
        let data = value + suffix
        for char in data {
            if let char = String(char).data(using: .utf8) {
                usleep(50)
                port?.send(char)
            }
        }
    }

    private func newPort(_ path: String) {
        guard !path.isEmpty else {
            Log.general.error("❌ Attempted to create serial port with empty path.")
            return
        }

        port?.close()

        
        port = ORSSerialPort(path: path)
        Log.general.info("✅ creating new port with path: \(path)")
        port?.allowsNonStandardBaudRates = true
        port?.baudRate = NSNumber(value: baudRate)
        self.port?.delegate = self
        
        
        self.dataSub = self.dataSub ?? PassthroughSubject<Data, Never>()

        if dataSub == nil {
            Log.general.warning("⚠️ Warning: dataSub is nil after port init!")
        }
    }

    func initPublisherSub() {
        manager.publisher(for: \.availablePorts).map{ $0.map{$0.path} }.assign(to: \.availablePorts, on: self).store(in: &subSet)

        $serialPath
            .removeDuplicates()
            .handleEvents(receiveOutput: { val in
                Log.general.info("📌 serialPath updated to: '\(val)'")
            })
            .sink { path in
                guard !path.isEmpty, path != "NO_PORT_SELECTED" else {
                    Log.general.warning("⛔️ Skipping newPort due to empty or placeholder serialPath")
                    return
                }
                self.newPort(path)
            }
            .store(in: &subSet)

        $baudRate.removeDuplicates()
            .sink { value in
                self.port?.baudRate = NSNumber(value: value)
            }.store(in: &subSet)
    }

    init(dataSub: PassthroughSubject<Data, Never>? = nil){
        self.baudRate = 921600
        self.isConnect = false
        self.isOpen = false
        self.serialPath = ""
        

        super.init()
        self.dataSub = dataSub
        initPublisherSub()
        print("SerialPort init - reset selectedPath to empty string")
    }

    deinit {
        port?.delegate = nil
    }
}

extension SerialPort {
    func getECIDFromDevice() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            var output = ""
            var didResume = false

            var cancellable: AnyCancellable?
            cancellable = self.dataSub?.sink { data in
                if let str = String(data: data, encoding: .utf8) {
                    output += str
                    if let match = output.range(of: #"0x[0-9a-fA-F]{14,}"#, options: .regularExpression) {
                        let ecid = String(output[match])
                        if !didResume {
                            didResume = true
                            continuation.resume(returning: ecid)
                            cancellable?.cancel()
                        }
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: NSError(
                        domain: "ECIDTimeout",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Timeout: ECID not found\n\(output)"]
                    ))
                }
            }

            self.send(value: "ft ecid")

            
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                cancellable?.cancel()
            }
        }
    }
    
    func getProjectNameFromDevice() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            var didResume = false

         
            guard let dataSub = self.dataSub else {
                continuation.resume(throwing: NSError(domain: "NoDataSub", code: 1))
                return
            }

            
            cancellable = dataSub.sink { data in
                guard let str = String(data: data, encoding: .utf8) else { return }
                if str.contains("Diags Image") {
                    let lines = str.components(separatedBy: .newlines)
                    for line in lines {
                        if let match = line.range(of: #"b\d{3}"#, options: .regularExpression) {
                            let name = String(line[match]).replacingOccurrences(of: "b", with: "B")
                            if !didResume {
                                didResume = true
                                continuation.resume(returning: name)
                                cancellable?.cancel()
                            }
                            cancellable?.cancel()
                            return
                        }
                    }
                }
            }

          
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if !didResume {
                    didResume = true
                    cancellable?.cancel()
                    continuation.resume(throwing: NSError(domain: "ProjectNameTimeout", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Timeout: Project name not found"
                    ]))
                    cancellable?.cancel()
                }
            }

          
            self.send(value: "ft whoami")
        }
    }
    
    func sendResetSequence() async {
        guard isOpen else {
            print("❌ Serial port not open")
            return
        }

        send(value: "ble system set enable")
        try? await Task.sleep(nanoseconds: 500_000_000)
        send(value: "ft reset")
        print("✅ Reset sequence sent")
    }
    
    func getTargetFromDevice() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var buffer = ""
            var didResume = false

            guard let dataSub = self.dataSub else {
                continuation.resume(throwing: NSError(domain: "NoDataSub", code: 1))
                return
            }

            var cancellable: AnyCancellable?
            cancellable = dataSub.sink { data in
                if let str = String(data: data, encoding: .utf8) {
                    buffer += str
                    print("🪵 Buffer so far:\n\(buffer)")

                    // ✅ Only parse target when both 'target:' and 'ft:ok' exist
                    if buffer.contains("target:") && buffer.contains("ft:ok") {
                        if let regex = try? NSRegularExpression(pattern: #"target:\s*([a-zA-Z0-9_]+)"#),
                           let match = regex.firstMatch(in: buffer, range: NSRange(buffer.startIndex..., in: buffer)),
                           let range = Range(match.range(at: 1), in: buffer) {
                            
                            let target = String(buffer[range])
                            if !didResume {
                                didResume = true
                                continuation.resume(returning: target)
                                cancellable?.cancel()
                            }
                        }
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if !didResume {
                    didResume = true
                    continuation.resume(throwing: NSError(
                        domain: "TargetTimeout",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Timeout: target not found\n\(buffer)"]
                    ))
                    cancellable?.cancel()
                }
            }

            self.send(value: "ft version case")
        }
    }

        /// Run shell script with terminal output capture
        @discardableResult
        func runShellCommandAsyncEB(
            _ executable: String,
            arguments: [String],
            dataSub: PassthroughSubject<Data, Never>?
        ) async throws -> Int32 {
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            let fileHandle = pipe.fileHandleForReading

            try process.run()

            for try await line in fileHandle.bytes.lines {
                if let data = (line + "\n").data(using: .utf8) {
                    dataSub?.send(data)
                }
            }

            process.waitUntilExit()
            return process.terminationStatus
        }
    
    func refreshAvailablePorts() {
        let ports = ORSSerialPortManager.shared().availablePorts.map { $0.path }
        DispatchQueue.main.async {
            self.availablePorts = ports
        }
    }
    
}

extension SerialPort: ORSSerialPortDelegate{

    func serialPortWasRemovedFromSystem(_ serialPort: ORSSerialPort){
        isConnect = false
        isOpen = false
    }

    func serialPort(_ serialPort: ORSSerialPort, didReceive data: Data){
        if let str = String(data: data, encoding: .utf8) {
            print("[🔁 serial received]: \(str)")
        } else {
            print("[🔁 serial received non-utf8]: \(data as NSData)")
        }

        dataSub?.send(data)
    }

    func serialPortWasOpened(_ serialPort: ORSSerialPort){
        isOpen = true
        Log.general.info("port \(self.port?.name ?? "") was opened")
    }

    func serialPortWasClosed(_ serialPort: ORSSerialPort){
        isOpen = false
        Log.general.info("port \(self.port?.name ?? "") was closed")
    }

}
