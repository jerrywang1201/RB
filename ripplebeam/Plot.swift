
import SwiftUI
import Charts
import AppKit
import Foundation
import UniformTypeIdentifiers


struct FloatChartView: View {
    let title: String
    
    
    let floatValues: [Float]

    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
                .padding(.top, 8)

            Chart {
                ForEach(floatValues.indices, id: \.self) { index in
                    LineMark(
                        x: .value("Index", index),
                        y: .value("Value", floatValues[index])
                    )
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 200)
        }
        .padding()
    }
}

struct RegexPlotCol: Identifiable {
    var id = UUID()
    var label: String
    var pattern: String
}

struct RegexPlotPanelView: View {
    @State private var columns: [RegexPlotCol] = []
    @State private var selected: RegexPlotCol.ID?

    var body: some View {
        VStack {
            HStack {
                Button("Add Plot Column") {
                    columns.append(RegexPlotCol(label: "", pattern: ""))
                }
                .padding(.horizontal)

                Button("Remove All") {
                    columns.removeAll()
                }

                Spacer()
            }

            HStack(alignment: .top) {
                List(selection: $selected) {
                    ForEach(columns) { col in
                        VStack(alignment: .leading) {
                            TextField("Label", text: Binding(
                                get: { col.label },
                                set: { newVal in
                                    if let idx = columns.firstIndex(where: { $0.id == col.id }) {
                                        columns[idx].label = newVal
                                    }
                                }
                            ))
                            TextField("Regex (e.g. Vbat=(\\d+))", text: Binding(
                                get: { col.pattern },
                                set: { newVal in
                                    if let idx = columns.firstIndex(where: { $0.id == col.id }) {
                                        columns[idx].pattern = newVal
                                    }
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        }
                    }
                }
                .frame(width: 320)

                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(columns) { col in
                            let values = extractFloatList(
                                from: TerminalModel.sharedOutput.map(\.text).joined(separator: "\n"),
                                pattern: col.pattern
                            )

                            if values.isEmpty {
                                Text("⚠️ \(col.label): No match or invalid pattern")
                                    .foregroundColor(.red)
                                    .padding(.top, 4)
                            } else {
                                Text("📊 \(col.label) (\(values.count) pts)")
                                    .font(.subheadline)
                                FloatChartView(title: col.label, floatValues: values)
                                    .frame(height: 200)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }
}



struct RegexXYPlotView: View {
    @State private var xPattern: String = ""
    @State private var yPattern: String = ""
    @State private var xLabel: String = "X Axis"
    @State private var yLabel: String = "Y Axis"
    @State private var isPlotReady: Bool = false
    @State private var extractedXs: [Float] = []
    @State private var extractedYs: [Float] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 输入区域
            HStack {
                TextField("X Label", text: $xLabel)
                TextField("Regex for X (e.g. Rtc=(\\d+))", text: $xPattern)
            }
            HStack {
                TextField("Y Label", text: $yLabel)
                TextField("Regex for Y (e.g. Vbat=(\\d+))", text: $yPattern)
            }

            // 按钮
            HStack {
                Button("Extract & Show Plot") {
                    let joined = TerminalModel.sharedOutput.map(\.text).joined(separator: "\n")
                    print("📄 Raw log preview:\n\(joined.prefix(500))")

                    do {
                        let xRegex = try NSRegularExpression(pattern: xPattern)
                        let yRegex = try NSRegularExpression(pattern: yPattern)

                        let xMatches = xRegex.matches(in: joined, range: NSRange(location: 0, length: joined.utf16.count))
                        let yMatches = yRegex.matches(in: joined, range: NSRange(location: 0, length: joined.utf16.count))

                        print("🔢 Found \(xMatches.count) X matches")
                        print("🔢 Found \(yMatches.count) Y matches")

                        let xs: [Float] = xMatches.compactMap {
                            guard let range = Range($0.range(at: 1), in: joined) else { return nil }
                            return Float(joined[range])
                        }

                        let ys: [Float] = yMatches.compactMap {
                            guard let range = Range($0.range(at: 1), in: joined) else { return nil }
                            return Float(joined[range])
                        }

                        extractedXs = xs
                        extractedYs = ys

                        print("📈 X values: \(xs)")
                        print("📉 Y values: \(ys)")
                        isPlotReady = true
                    } catch {
                        print("❌ Regex error: \(error)")
                    }
                }
                .buttonStyle(.borderedProminent)

                if isPlotReady {
                    Button("Export CSV") {
                        exportCSV(xs: extractedXs, ys: extractedYs, xLabel: xLabel, yLabel: yLabel)
                    }
                }
            }

            Divider().padding(.vertical, 8)

            // 展示图表
            if isPlotReady {
                if extractedXs.count == extractedYs.count && extractedXs.count > 0 {
                    Text("📈 Plotting \(extractedXs.count) points").padding(.top)

                    Chart {
                        ForEach(0..<extractedXs.count, id: \.self) { i in
                            LineMark(
                                x: .value(xLabel, extractedXs[i]),
                                y: .value(yLabel, extractedYs[i])
                            )
                        }
                    }
                    .frame(height: 240)
                    .chartYScale(domain: .automatic(includesZero: false))
                } else {
                    Text("⚠️ Mismatched or empty data").foregroundColor(.red).padding(.top)
                }
            }

            Spacer()
        }
        .padding()
    }

    // 正则匹配 float
    func extractFloatList(from input: String, pattern: String) -> [Float] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        return matches.compactMap {
            let range: Range<String.Index>?
            if $0.numberOfRanges > 1 {
                range = Range($0.range(at: 1), in: input)
            } else {
                range = Range($0.range(at: 0), in: input)
            }
            guard let r = range, let val = Float(input[r]) else { return nil }
            return val
        }
    }

    // 导出为 CSV 文件
    func exportCSV(xs: [Float], ys: [Float], xLabel: String, yLabel: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "regex_plot.csv"

        if panel.runModal() == .OK, let url = panel.url {
            var csv = "\(xLabel),\(yLabel)\n"
            for i in 0..<min(xs.count, ys.count) {
                csv += "\(xs[i]),\(ys[i])\n"
            }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}



func extractFloatList(from input: String, pattern: String) -> [Float] {
    print("📥 Regex pattern: \(pattern)")
    print("📄 Input preview:\n" + input.prefix(300))

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        print("❌ Invalid regex")
        return []
    }

    let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
    print("🔍 Total matches found: \(matches.count)")

    var results: [Float] = []

    for match in matches {
        let range: Range<String.Index>?
        if match.numberOfRanges > 1 {
            range = Range(match.range(at: 1), in: input)
        } else {
            range = Range(match.range(at: 0), in: input)
        }

        if let r = range {
            let valStr = String(input[r])
            if let val = Float(valStr) {
                print("✅ Extracted value: \(val)")
                results.append(val)
            } else {
                print("⚠️ Value not convertible to Float: \(valStr)")
            }
        }
    }

    if results.isEmpty {
        print("⚠️ No valid float values extracted.")
    }

    return results
}
