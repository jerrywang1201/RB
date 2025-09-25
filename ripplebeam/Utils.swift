//
//  Utils.swift
//  ripplebeam
//
//  Created by Shaoxuan Yuan on 2024/7/18.
//

import Foundation
import Combine
import AppKit

// read a file URL and return its content in a string
func uRLToString(_ url: URL) -> String {
    var res: String
    do {
        res = try String(contentsOf: url, encoding: .utf8)
        return res
    } catch {
        return "Error when reading file URL"
    }
}

/// Get the first capture of a regex pattern within an input string.
///
/// - Parameters:
///   - of: The regex pattern string.
///   - input: The input string to search in.
/// - Returns: nil if nothing is found or there is an error parsing the regex, else returns the matched string.
func regexGetFirstMatch(of pattern: String, in input: String) -> String? {
    if let regex = try? NSRegularExpression(pattern: pattern) {
        // Create a range that covers the entire input string
        let nsrange = NSRange(input.startIndex..<input.endIndex, in: input)
        // Search for the first match
        if let match = regex.firstMatch(in: input, options: [], range: nsrange) {
            // Get the range of the first capture group
            if match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: input) {
                // Extract the substring
                return String(input[range])
            }
        }
    } else {
        return nil
    }
    return nil
}


/// Get a list of matches from a chunk of input text. Only include the first matched group in
/// a regex, e.g. if pattern is "a = (\d+) (\s)", this function only extracts the "(\d+)", and it will
/// move on to find next match, starting after currently matched substring. For every match
/// it finds, it appends to a final result array.
///
/// - Parameters:
///   - pattern: string that represents a valid regex
///   - input: the input string to search in
/// - Returns: a list of first capture groups, e.g. if pattern is "a = (\d+)", and the input is
/// "a = 1 a = 2 a = 3", then the return value is ["1", "2", "3"]; if anything goes wrong, return nil.
func regexGetList(of pattern: String, in input: String) -> [String]? {
    var startIndex = input.startIndex
    var res: [String] = []
    do {
        let regex = try Regex(pattern)

        while true {
            if let match = try regex.firstMatch(in: input[startIndex..<input.endIndex]) {
                /// match[1] is the first captured group value, match[0] is the whole matched string
                if match.count > 1 {
                    res.append(String(match[1].substring ?? "0"))
                } else {
                    break
                }

                /// update startIndex to point at the index immediately after the already matched range,
                if match.range.upperBound < input.endIndex {
                    startIndex = match.range.upperBound
                } else {
                    break
                }
            } else {
                break
            }
        }
    } catch {
        Log.general.error("regex error: \(error)")
        return nil
    }
    return res
}

func runShellCommandAsync(
    _ command: String,
    arguments: [String],
    environment: [String: String]? = nil,
    dataSub: PassthroughSubject<Data, Never>? = nil
) async -> Data? {
    Log.general.info("running shell command: \(command) \(arguments)")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = arguments

    if let env = environment {
        Log.general.info("✅ Setting environment: \(env)")
        process.environment = env
    }

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    var output = Data()

    do {
        try process.run()

        for try await chunk in pipe.fileHandleForReading.bytes {
            output.append(chunk)
            if let dataSub {
                dataSub.send(Data([chunk]))
            }
        }

        process.waitUntilExit()
        Log.general.info("shell command successfully exiting...")
        return output
    } catch {
        Log.general.error("shell command failed...")
        Log.general.error("error: \(error)")
        return nil
    }
}

func dataToDictList(data: Data) -> [[String: Any]]? {
    do {
        // Use JSONSerialization to convert Data to a dictionary
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])

        // Ensure the resulting object is a dictionary
        if let dictionary = jsonObject as? [[String: Any]] {
            return dictionary
        } else {
            Log.general.error("The JSON object is not a dictionary")
            return nil
        }
    } catch {
        // Handle any errors
        Log.general.error("Failed to convert Data to dictionary: \(error.localizedDescription)")
        return nil
    }
}

func dataToDict(data: Data) -> [String: Any]? {
    do {
        // Use JSONSerialization to convert Data to a dictionary
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])

        // Ensure the resulting object is a dictionary
        if let dictionary = jsonObject as? [String: Any] {
            return dictionary
        } else {
            Log.general.error("The JSON object is not a dictionary")
            return nil
        }
    } catch {
        // Handle any errors
        Log.general.error("Failed to convert Data to dictionary: \(error.localizedDescription)")
        return nil
    }
}

func updatePointers(train: String, imageName: String) async -> [String] {
    var pointers: [String] = []
    Log.general.info("updating pointers with train: \(train), imageName: \(imageName)")

    let knox = "/usr/local/bin/knox"
    let arguments = ["list", "pointers", "support-image", "train=\(train)", "image-name=\(imageName)", "--quiet", "--disable-version-check"]

    guard let output = await runShellCommandAsync(knox, arguments: arguments) else {
        return ["Loading error"]
    }

    guard let dictList = dataToDictList(data: output) else {
        Log.general.error("cannot convert knox output to dict")
        let knoxOutput = String(data: output, encoding: .utf8)!
        Log.general.error("knox output: \(knoxOutput)")
        return ["Loading error"]
    }

    for dict in dictList {
        if let fields = dict["fields"] as? [String: String] {
            pointers.append(fields["update"] ?? "Invalid update")
        } else {
            Log.general.info("no 'fields' key in dict")
        }
    }
    Log.general.info("pointers updated")
    return pointers
}


func setupKeyCommands(_ key: String, action: @escaping () -> Void) -> Any? {
    // Add a local monitor for keyDown events
    return NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        // Check if Command + O is pressed
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == key {
            action()  // Trigger the passed-in action
            return nil  // Swallow the event
        }
        return event
    }
}

func removeKeyCommands(monitor: Any?) {
    // Remove the event monitor when the view disappears
    if let monitor {
        NSEvent.removeMonitor(monitor)
    }
}


/// Split currLine by newline chars, and append everything except for the last string to lineArray.
/// Return the last element or an empty string if nil.
func processAccumulatedString(currLine: String, lineArray: inout [String]) -> String {
    // Split the string by newline character
    let parts = currLine.components(separatedBy: "\n")
    // Append all the parts except for the last one to the array
    lineArray.append(contentsOf: parts.dropLast())
    // return last part (after the last newline)
    return parts.last ?? ""
}

func taskSleepMillisecondsNoThrow(_ ms: Int) async {
    do {
        try await Task.sleep(for: .milliseconds(ms))
    } catch {
        Log.general.error("could not sleep for \(ms) milliseconds")
    }
}

/// Parses command line arguments where the arguments are separated by whitespaces,
/// except for double-quoted strings (which may contain spaces and should be treated as a single argument)
/// 
/// - Parameter input: input command line
/// - Returns: parsed array of arguments
func parseArguments(_ input: String) -> [String] {
    var arguments: [String] = []
    var currentArgument = ""
    var insideQuotes = false
    var iterator = input.makeIterator()

    while let char = iterator.next() {
        if char == "\"" {
            // Toggle the insideQuotes flag when encountering a double quote
            insideQuotes.toggle()
            if !insideQuotes {
                // Closing quote, add the current argument to the list
                arguments.append(currentArgument)
                currentArgument = ""
            }
        } else if char.isWhitespace && !insideQuotes {
            // Outside quotes, use whitespace to split arguments
            if !currentArgument.isEmpty {
                arguments.append(currentArgument)
                currentArgument = ""
            }
        } else {
            // Append character to current argument
            currentArgument.append(char)
        }
    }

    // Add the last argument if any
    if !currentArgument.isEmpty {
        arguments.append(currentArgument)
    }

    return arguments
}


/// Get accessToken for Radar PROD environment, using SPNego authentication method
///
/// - Returns: accessToken string if everything works out, nil otherwise
/// - [Radar API reference](https://radar.apple.com/developer/api/documentation/latest/authentication)
func getRadarAccessToken() async -> String? {
    let arguments = ["--no-progress-meter", "-X", "GET", "-H", "Accept: application/json",
    "--negotiate", "-u", ":", "https://radar-webservices.apple.com/signon"]

    guard let data = await runShellCommandAsync("/usr/bin/curl", arguments: arguments) else {
        return nil
    }

    Log.general.info("getRadarAccessToken: got data \(String(data: data, encoding: .utf8) ?? "failed")")

    guard let dict = dataToDict(data: data) else {
        Log.general.error("cannot convert curl output to dict")
        let curlOutput = String(data: data, encoding: .utf8)!
        Log.general.error("curl output: \(curlOutput)")
        return nil
    }

    return dict["accessToken"] as? String
}


/// Get a list of attachments for a Radar problem, the retrieved data are handled inside a handler
/// - Parameters:
///   - problem: Radar problem ID
///   - accessToken: Radar-Authentication accessToken
func getProblemAttachments(_ problem: String, accessToken: String, handler: @escaping (Data) -> Void) {
    var request = URLRequest(url: URL(string: "https://radar-webservices.apple.com/problems/\(problem)/attachments")!,timeoutInterval: Double.infinity)
    request.addValue(accessToken, forHTTPHeaderField: "Radar-Authentication")
    request.httpMethod = "GET"

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        guard let data else {
            Log.network.error("\(error)")
            return
        }
        Log.network.info("Problem attachnents retrieved")
        handler(data)
    }
    Log.network.info("Retrieving problem attachnents")
    task.resume()
}


class DownloadDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, ObservableObject {

    private lazy var urlSession = URLSession(configuration: .default,
                                             delegate: self,
                                             delegateQueue: nil)
    var downloadTask: URLSessionDownloadTask?
    @Published var savedURL: URL?

    /// init to -1, if download started, change to 0
    @Published var progress: Float = -1
    @Published var inProgress = false
    @Published var downloaded = false
    private var downloadFileName = ""

    func startDownload(url: URLRequest) -> URLSessionDownloadTask {
        let downloadTask = urlSession.downloadTask(with: url)
        downloadFileName = url.url?.lastPathComponent ?? ""
        downloadTask.resume()
        inProgress = true
        downloaded = false
        self.downloadTask = downloadTask
        return downloadTask
    }

    /// After downloading the file, move it to ~/Downloads directory
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let downloadsURL = try
                FileManager.default.url(for: .downloadsDirectory,
                                        in: .userDomainMask,
                                        appropriateFor: nil,
                                        create: false)
            let savedURL = downloadsURL.appendingPathComponent(
                downloadFileName)

            DispatchQueue.main.async {
                self.savedURL = savedURL
            }

            try FileManager.default.moveItem(at: location, to: savedURL)
            Log.general.info("file downloaded and saved to: \(savedURL.absoluteString)")

            DispatchQueue.main.async {
                self.inProgress = false
                self.downloaded = true
            }

        } catch {
            if error.localizedDescription.contains("name already exists") {
                DispatchQueue.main.async {
                    self.inProgress = false
                    self.downloaded = true
                }
            } else {
                Log.general.error("filesystem error: \(error)")
            }
        }
    }

    /// Periodically reports download progress
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        /// publish updates on the main queue
        DispatchQueue.main.async {
            self.progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        }
    }
}
