// TerminalModel.swift
import Foundation
import Combine
import SwiftUI
import AppKit
import ORSSerial



struct TerminalLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isCommand: Bool
    let rawData: Data?
}


class TerminalModel: ObservableObject {
    
    
    private var line: String = ""
    private var subSet = Set<AnyCancellable>()
    
    
    // MARK: — Published State

    /// All lines displayed in the terminal.
    @Published var output: [TerminalLine] = []

    /// The currently highlighted command ID, if any.
    @Published var highlightedCommandID: UUID?

    /// Whether to display highlighted command output in hex.
    @Published var hexMode: Bool = false

    /// Regex pattern for consoleControls features.
    @Published var pattern: String = ""

    /// Whether we have an open serial connection.
    @Published var isConnected: Bool = false

    // MARK: — Underlying Serial Port

    /// The active SerialPort wrapper, if connected.
    //var consoleSerial: SerialPort?
    @Published var availablePorts: [String] = []


    /// Used to cancel Combine subscriptions when disconnecting.
    var cancellables = Set<AnyCancellable>()

    // MARK: — Line‐Buffering

    /// Temporary buffer for assembling command lines.
    private var cmdLineBuffer = ""

    /// Temporary buffer for assembling serial output lines.
    private var serialLineBuffer = ""

    // MARK: — Init

    /// Initialize without opening any port; user must call `connect(...)`.
    init() {
        // 处理 cmd echo
        cmdOutputSub
            .receive(on: RunLoop.main)
            .sink { [weak self] data in
                guard let self = self,
                      let chunk = String(data: data, encoding: .utf8)
                else { return }

                self.cmdLineBuffer += chunk

                if chunk.contains("\n") || chunk.contains("\r") {
                    let isCmd = self.isLikelyCommand(self.cmdLineBuffer)
                    self.output.append(
                        TerminalLine(text: self.cmdLineBuffer,
                                     isCommand: isCmd,
                                     rawData: data)
                    )
                    self.cmdLineBuffer = ""
                }
            }
            .store(in: &cancellables)

        // 处理 serial output
        serialOutputSub
            .receive(on: RunLoop.main)
            .sink { [weak self] data in
                guard let self = self,
                      let chunk = String(data: data, encoding: .utf8)
                else { return }

                self.serialLineBuffer += chunk
                var lines = self.serialLineBuffer.components(separatedBy: .newlines)
                self.serialLineBuffer = lines.removeLast()

                for line in lines where !line.isEmpty {
                    // ✅ 忽略掉你自己 echo 的命令（避免死循环）
                    if self.isLikelyCommand(line) { continue }

                    self.appendLine(
                        TerminalLine(text: line, isCommand: false, rawData: data)
                    )
                }
            }
            .store(in: &cancellables)
    }

    // MARK: — Connection Management

    /// Open the serial port at the given path and baud rate.
    /// - Parameters:
    ///   - path: The `/dev/cu.*` device path.
    ///   - baudRate: The baud rate to use (default 115200).

    // MARK: — Subscription Plumbing

    

    // MARK: — Helpers
    
    private func appendLine(_ line: TerminalLine) {
        let maxLines = 500
        DispatchQueue.main.async {
            if self.output.count >= maxLines {
                self.output.removeFirst(self.output.count - maxLines + 1)
            }
            self.output.append(line)
            TerminalModel.sharedOutput = self.output
        }
    }

    /// Determine if the given text appears to be a user-typed command.
    func isLikelyCommand(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("./") || t.hasPrefix("make") || t.hasPrefix("git")
    }

    /// Return all lines of output under the command with the given ID.
    func outputUnderCommand(_ id: UUID) -> [TerminalLine] {
        guard let idx = output.firstIndex(where: { $0.id == id }) else {
            return []
        }
        var result: [TerminalLine] = []
        for line in output[(idx + 1)...] {
            if line.isCommand { break }
            result.append(line)
        }
        return result
    }

    /// The full terminal text, used for exporting or TextEditor.
    var fullTextOutput: String {
        output.map(\.text).joined(separator: "\n")
    }

    /// Write the full output to a temp file and open in TextEdit.
    func openInTextEdit() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TerminalOutput.txt")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.fullTextOutput.write(to: tempURL,
                                              atomically: true,
                                              encoding: .utf8)
                DispatchQueue.global(qos: .userInitiated).async {
                    NSWorkspace.shared.open(tempURL)
                }
            } catch {
                print("Failed to write log: \(error)")
            }
        }
    }

    /// Clear all buffered terminal output.
    func clear() {
        output.removeAll()
        cmdLineBuffer = ""
        serialLineBuffer = ""
    }
    
    var ecidCancellable: AnyCancellable?
    let ecidPublisher = PassthroughSubject<String, Never>()

    func sendECIDCommand(port: SerialPort) {
        serialOutputSub.send(Data("🛫 Sending 'ft ecid\\r'...\n".utf8))
        port.send(value: "ft ecid")

            
            ecidCancellable?.cancel()

           
            ecidCancellable = serialOutputSub
                .map { data in String(data: data, encoding: .utf8) ?? "" }
                .compactMap { line in
                    
                    let regex = try? NSRegularExpression(pattern: #"ECID\s*=\s*(0x[0-9a-fA-F]+)"#)
                    let range = NSRange(location: 0, length: line.utf16.count)
                    if let match = regex?.firstMatch(in: line, options: [], range: range),
                       let ecidRange = Range(match.range(at: 1), in: line) {
                        return String(line[ecidRange])
                    }
                    return nil
                }
                .first()
                .sink { [weak self] ecid in
                    self?.ecidPublisher.send(ecid)
                }
        }

    // MARK: — Data Subjects

    /// Emits user-entered command data.
    var cmdOutputSub = PassthroughSubject<Data, Never>()

    /// Emits raw serial port data.
    var serialOutputSub = PassthroughSubject<Data, Never>()
    
    
    
}

extension TerminalModel {
  var highlightedBlockIDs: Set<UUID> {
    guard let cmdID = highlightedCommandID else { return [] }
    let outputIDs = outputUnderCommand(cmdID).map(\.id)
    return Set(outputIDs + [cmdID])
  }
}


struct TerminalView: View {
    @ObservedObject var terminal: TerminalModel
    @Environment(\.openWindow) private var openWindow
    private let viewParent: Tab?
    
    init(terminal: TerminalModel, viewParent: Tab? = nil) {
        self.terminal    = terminal
        self.viewParent  = viewParent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
          
            HStack(spacing: 12) {
                Text("Output").bold()
                
                Button("Clear") {
                    terminal.clear()
                }

                Button("Open log in TextEdit ↗") {
                    terminal.openInTextEdit()
                }
                
            
                if viewParent == .console {
                    Divider().frame(height: 20)
                    
                    Button("Open Plot") {
                        openWindow(id: "regex_plot")
                    }
                    
                    TextField("regex pattern", text: $terminal.pattern)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    
                    Divider().frame(height: 20)
                    
                    Button("Export to CSV ↗") {
                        openWindow(id: "console_csv")
                    }
                }
            }
            .padding(.horizontal)
            
           
            TerminalOutputView(terminal: terminal)
                .frame(maxHeight: .infinity)
        }
        .textSelection(.enabled)
    }
}

struct TerminalLineView: View {
    let line: TerminalLine
    @ObservedObject var terminal: TerminalModel

    
    private var isHighlighted: Bool {
        terminal.highlightedCommandID == line.id
    }
    private var isDimmed: Bool {
        terminal.highlightedCommandID != nil &&
        !terminal.highlightedBlockIDs.contains(line.id)
    }

    var body: some View {
        Text(line.text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(
                isHighlighted
                  ? .accentColor
                  : (isDimmed ? .secondary : .primary)
            )
            .opacity(isDimmed ? 0.5 : 1.0)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isHighlighted
                          ? Color.accentColor.opacity(0.25)
                          : Color.clear
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
               
                if line.isCommand {
                    terminal.highlightedCommandID = line.id
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

struct TerminalOutputView: View {
    @ObservedObject var terminal: TerminalModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                       
                        ForEach(terminal.output) { line in
                            TerminalLineView(line: line, terminal: terminal)
                                .id(line.id)
                        }
                        
                        GeometryReader { geo in
                                        Color.clear
                                            .frame(height: 1)
                                            .id("bottomAnchor")
                        }

                       
                        if let cmdID = terminal.highlightedCommandID {
                            Divider()
                                .padding(.top, 8)

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(terminal.outputUnderCommand(cmdID)) { line in
                                    if terminal.hexMode, let data = line.rawData {
                                        Text(data
                                            .map { String(format: "%02X", $0) }
                                            .joined(separator: " ")
                                        )
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.blue)
                                    } else {
                                        Text(line.text)
                                            .font(.system(size: 12, design: .monospaced))
                                    }
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        colorScheme == .light
                                            ? Color.gray.opacity(0.1)
                                            : Color.white.opacity(0.1)
                                    )
                            )
                        }
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, minHeight: 300, alignment: .leading)
                    .textSelection(.enabled)

                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .scrollToTopOrBottom)
                ) { notif in
                
                    if let id = notif.object as? UUID {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                }
                
                .onChange(of: terminal.output) { newOutput in
                    if let lastID = newOutput.last?.id {
                        DispatchQueue.main.async {
                            withAnimation {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

           
            HStack(spacing: 12) {
                Button("Go to top") {
                    if let firstID = terminal.output.first?.id {
                        NotificationCenter.default.post(
                            name: .scrollToTopOrBottom,
                            object: firstID
                        )
                    }
                }
                Button("Go to bottom") {
                    if let lastID = terminal.output.last?.id {
                        NotificationCenter.default.post(
                            name: .scrollToTopOrBottom,
                            object: lastID
                        )
                    }
                }
                Spacer()
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    colorScheme == .light
                        ? Color.white
                        : Color.black.opacity(0.8)
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .light ? 0.05 : 0.3),
                    radius: 4, x: 0, y: 2
                )
        )
        .padding(.horizontal)
    }
}

extension Notification.Name {
    static let scrollToTopOrBottom = Notification.Name("scrollToTopOrBottom")
}


extension TerminalModel {
    static var sharedOutput: [TerminalLine] = []
}
