import SwiftUI
import OSLog

struct CSVCol {
    var columnName: String = ""
    var regexStr: String = ""
}


struct CSVPanelView: View {
    @State private var CSVCols: [CSVCol] = []
    @State private var writtenFile: String? = nil
    @State private var isAlertPresented: Bool = false

    // ✅ 你不需要 EnvironmentObject 也不需要 init 了
    // ✅ 所有数据改为读取 TerminalModel.sharedOutput 即可

    var body: some View {
        VStack {
            HStack {
                Button("Add column") {
                    CSVCols.append(CSVCol())
                }
                .padding(.horizontal)

                Button("Remove all") {
                    CSVCols.removeAll()
                }

                Spacer()

                Button("Generate CSV") {
                    if let file = generateCSV() {
                        writtenFile = file
                        isAlertPresented = true
                    }
                }
                .disabled(CSVCols.isEmpty)
                .alert(isPresented: $isAlertPresented) {
                    Alert(title: Text("CSV Exported"),
                          message: Text("Saved to \(writtenFile ?? "unknown")"),
                          dismissButton: .default(Text("OK")))
                }
            }

            HStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(CSVCols.indices, id: \.self) { idx in
                            HStack(spacing: 8) {
                                TextField("Column name", text: $CSVCols[idx].columnName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 120)

                                TextField("Regex", text: $CSVCols[idx].regexStr)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(minWidth: 250)

                                Button("Remove") {
                                    CSVCols.remove(at: idx)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 500, maxHeight: 300)

                Spacer()

                VStack {
                    Spacer()
                    Button("Go to top") {
                        // Optional
                    }
                    Button("Go to bottom") {
                        // Optional
                    }
                }
            }

            Text("Generated file will be under ~/Downloads")
                .font(.footnote)
                .foregroundColor(.gray)
                .padding(.top, 4)
        }
        .padding()
    }

    private func generateCSV() -> String? {
        let terminalOutput = TerminalModel.sharedOutput.map(\.text).joined(separator: "\n")
        

        print("🧾 Terminal Output Preview:\n\(terminalOutput.prefix(500))")
        Log.general.info("📄 Terminal output line count: \(TerminalModel.sharedOutput.count)")
        print("📄 Terminal output line count: \(TerminalModel.sharedOutput.count)")

        var dict: [String: [String]] = [:]
        var fileName = "RippleBeam"

        for CSVCol in CSVCols {
            Log.general.info("🔍 Parsing column '\(CSVCol.columnName)' with regex: '\(CSVCol.regexStr)'")
            print("🔍 Parsing column '\(CSVCol.columnName)' with regex: '\(CSVCol.regexStr)'")

            guard let columnValues = regexGetList(of: CSVCol.regexStr, in: terminalOutput) else {
                Log.general.error("❌ Regex failed to match for column '\(CSVCol.columnName)'")
                print("❌ Regex failed to match for column '\(CSVCol.columnName)'")
                continue
            }

            Log.general.info("✅ Column '\(CSVCol.columnName)' matched \(columnValues.count) values.")
            print("✅ Column '\(CSVCol.columnName)' matched \(columnValues.count) values.")

            dict[CSVCol.columnName] = columnValues
            fileName += "_\(CSVCol.columnName)"
        }

        let maxCount = dict.values.map(\.count).max() ?? 0
        var rows: [String] = []

        let header = dict.keys.joined(separator: ",")
        rows.append(header)

        for i in 0..<maxCount {
            let row = dict.keys.map { dict[$0]?[safe: i] ?? "" }.joined(separator: ",")
            rows.append(row)
        }

        let csvString = rows.joined(separator: "\n")
        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
            .appendingPathComponent("\(fileName).csv")

        do {
            try csvString.write(to: fileURL, atomically: true, encoding: .utf8)
            Log.general.info("✅ CSV file written to: \(fileURL.path)")
            print("✅ CSV file written to: \(fileURL.path)")
            return fileURL.path
        } catch {
            Log.general.error("❌ Error writing to file: \(error)")
            return nil
        }
    }

    private func regexGetList(of pattern: String, in input: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        return matches.compactMap {
            guard let range = Range($0.range(at: 1), in: input) else { return nil }
            return String(input[range])
        }
    }
}

// Safe array access
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
