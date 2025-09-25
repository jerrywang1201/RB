//
//  SettingsApp_Tabbed.swift
//  ripplebeam
//

import SwiftUI
import Foundation
import FilePicker
import Zip

struct RadarAttachmentModel: Identifiable, Decodable {
    let id = UUID()
    var fileName: String
    var uploadDate: Date
    var author: String
    var radarID: String = ""
    var token: String = ""

    enum CodingKeys: String, CodingKey {
        case fileName
        case uploadDate = "createdAt"
        case addedBy
    }

    enum AddedByKeys: String, CodingKey {
        case firstName
        case lastName
    }

    init(fileName: String, radarID: String, uploadDate: Date, author: String, token: String) {
        self.fileName = fileName
        self.radarID = radarID
        self.uploadDate = uploadDate
        self.author = author
        self.token = token
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(String.self, forKey: .fileName)

        let dateStr = try container.decode(String.self, forKey: .uploadDate)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: dateStr) else {
            throw DecodingError.dataCorruptedError(forKey: .uploadDate, in: container, debugDescription: "Invalid date format")
        }
        uploadDate = date

        if let addedBy = try? container.nestedContainer(keyedBy: AddedByKeys.self, forKey: .addedBy) {
            let first = (try? addedBy.decode(String.self, forKey: .firstName)) ?? ""
            let last = (try? addedBy.decode(String.self, forKey: .lastName)) ?? ""
            author = "\(first) \(last)"
        } else {
            author = "Unknown"
        }

        token = ""
        radarID = ""
    }
}




class SettingsModel: ObservableObject {
    @Published var schema: Schema?
    @Published var jsonSchema: String = ""

    @AppStorage("ripplebeam.jsonSchema") private var jsonSchemaStorage = ""
    @AppStorage("ripplebeam.workingDir") var workingDir = ""
    @AppStorage("ripplebeam.pyExe") var pyExe = ""
    @AppStorage("ripplebeam.radarLink") var radarLink = "113934883"
    
    
    @Published var output: String = ""
    @Published var radarAccessToken: String = ""
    @Published var radarSearchKeyword: String = ""
    @Published var radarSearchResults: [String] = []
    @Published var isRadarSearchPresented: Bool = false
    @Published var radarDecodedResults: [RadarProblem] = []
    @Published var pythonSitePackagesPath: String = ""
    @Published var isSettingsPresented: Bool = false

    @Published var radarAttachments: [RadarAttachmentModel] = []
    @Published var ebAttachments: [RadarAttachmentModel] = []
    @Published var workingDirNeedsUpdate: Bool = false
    @Published var radarFetchError: String? = nil


    
    

    var baudRates: [Int] = [921600, 230400]
    @Published var addedBaudRates: [Int] = []

    let debug = false
    let defaults = UserDefaults.standard
    let embeddedDefaultSchemaPath = Bundle.main.resourcePath! + "/audiofactorydiagtools/schema.json"
    let userDefaultKey = "ripplebeam.defaultJsonSchema"


    init() {
        let userDefinedPath = UserDefaults.standard.string(forKey: userDefaultKey)
        if let userPath = userDefinedPath, FileManager.default.fileExists(atPath: userPath) {
            jsonSchema = userPath
        } else {
            jsonSchema = embeddedDefaultSchemaPath
        }

        jsonSchemaStorage = jsonSchema
        schema = readSchema(filePath: jsonSchema)
        addedBaudRates = (defaults.array(forKey: "rippleBeam.addedBaudRates") as? [Int]) ?? []

        if let embeddedBase = Bundle.main.resourcePath {
            let candidate = embeddedBase + "/audiofactorydiagtools"
            if FileManager.default.fileExists(atPath: candidate) {
                workingDir = candidate
                print("✅ Set workingDir to:", candidate)
            } else {
                print("❌ audiofactorydiagtools folder not found.")
            }
        }

        if pyExe.isEmpty,
           let resPath = Bundle.main.resourcePath {
        
            let bundledPython = resPath + "/audiofactorydiagtools/3.11/bin/python3.11"
            let defaultPythonPath = "/usr/local/bin/python3.11"

            pyExe = FileManager.default.fileExists(atPath: bundledPython) ? bundledPython : defaultPythonPath
            print("✅ Python path set to:", pyExe)

            let pyExeURL = URL(fileURLWithPath: pyExe)
            let envRoot = pyExeURL.deletingLastPathComponent().deletingLastPathComponent()
            let pythonVersion = "python3.11"
            let sitePackages = envRoot
                .appendingPathComponent("lib")
                .appendingPathComponent(pythonVersion)
                .appendingPathComponent("site-packages")
            pythonSitePackagesPath = sitePackages.path
            print("✅ PYTHONPATH set to:", pythonSitePackagesPath)
        }


    }

    func updateJsonSchema(_ newValue: String) {
        jsonSchema = newValue
        jsonSchemaStorage = newValue
        schema = readSchema(filePath: newValue)
    }

    func saveSettings() {
        defaults.set(addedBaudRates, forKey: "rippleBeam.addedBaudRates")
    }
}

extension SettingsModel {
    func pythonEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        // 设置 PYTHONPATH
        if !pythonSitePackagesPath.isEmpty {
            env["PYTHONPATH"] = pythonSitePackagesPath
        }

        // 设置 DYLD_LIBRARY_PATH 为 libusb 的所在文件夹
        if let resPath = Bundle.main.resourcePath {
            let embeddedLibusbDir = resPath + "/audiofactorydiagtools/libusb-1.0.26/libusb/.libs"
            env["DYLD_LIBRARY_PATH"] = embeddedLibusbDir
            print("✅ Hardcoded DYLD_LIBRARY_PATH:", embeddedLibusbDir)
        } else {
            print("❌ Failed to get Bundle.main.resourcePath")
        }

        return env
    }
}

struct SettingRow: View {
    var label: String
    var content: String
    var buttons: [AnyView]
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .frame(minWidth: 100, idealWidth: 120, maxWidth: 150, alignment: .leading)
            
            ScrollView(.horizontal, showsIndicators: false) {
                Text(content.isEmpty ? "Empty" : content)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
            }
            .frame(height: 24)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(maxWidth: .infinity, alignment: .leading)
            
            ForEach(0..<buttons.count, id: \..self) { index in
                buttons[index]
            }
        }
        .padding(.vertical, 6)
    }

}

extension SettingsModel {
    @MainActor
    func loadRadarAttachments(radarID: String) async {
        guard let token = await getRadarAccessToken() else {
            radarFetchError = "❌ Failed to get token"
            return
        }

        radarAccessToken = token

        await withCheckedContinuation { continuation in
            getProblemAttachments(radarID, accessToken: token) { data in
                guard let dictList = dataToDictList(data: data) else {
                    Task { @MainActor in
                        self.radarFetchError = "⚠️ Invalid Radar response."
                        continuation.resume()
                    }
                    return
                }

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                formatter.locale = Locale(identifier: "en_US_POSIX")

                let attachments = dictList.compactMap { dict -> RadarAttachmentModel? in
                    guard let file = dict["fileName"] as? String,
                          let createdAt = dict["createdAt"] as? String,
                          let date = formatter.date(from: createdAt) else { return nil }

                    let author = dict["userName"] as? String ?? "Unknown"
                    return RadarAttachmentModel(
                        fileName: file,
                        radarID: radarID,
                        uploadDate: date,
                        author: author,
                        token: token
                    )
                }.sorted { $0.uploadDate > $1.uploadDate }

                Task { @MainActor in
                    self.radarAttachments = attachments
                    continuation.resume()
                }
            }
        }
    }
}




struct FilePathsSettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var cachedJsonSchema = ""
    @State private var isRadarPickerPresented = false

    var body: some View {
        Form(content: {
            Section(header: Text("File Paths")) {
                
                // ─── JSON schema row ─────────────────────────────────────────────────
                SettingRow(
                    label: "JSON schema",
                    content: cachedJsonSchema,
                    buttons: [
                        AnyView(
                            FilePicker(
                                types: [.json],
                                allowMultiple: false,
                                title: "Select"
                            ) { urls in
                                let selected = urls[0].path()
                                cachedJsonSchema = selected
                                settings.updateJsonSchema(selected)
                            }
                        ),
                        AnyView(
                            Button("Default") {
                                UserDefaults.standard.set(
                                    cachedJsonSchema,
                                    forKey: "ripplebeam.defaultJsonSchema"
                                )
                                settings.updateJsonSchema(cachedJsonSchema)
                            }
                        )
                    ]
                )
                
                // ─── Working directory row + popover ────────────────────────────────
                // ─── Working directory row + always Refresh ────────────────
                SettingRow(
                    label: "Working directory",
                    content: settings.workingDir,
                    buttons: [
                        AnyView(
                            Button("Refresh") {
                                isRadarPickerPresented = true
                            }
                        )
                    ]
                )
                .popover(isPresented: $isRadarPickerPresented, arrowEdge: .trailing) {
                    RadarDownloadFallbackView(
                        radarID: "113934883",
                        onSuccess: { unzipDir in
                            settings.workingDir = unzipDir.path()
                            settings.workingDirNeedsUpdate = false
                        },
                        onFailure: { err in
                            settings.radarFetchError = err
                        }
                    )
                    .frame(width: 500)
                }
                
                // ─── Python executable row ──────────────────────────────────────────
                SettingRow(
                    label: "Python executable",
                    content: settings.pyExe,
                    buttons: [
                        AnyView(
                            FilePickerNoAlias(
                                types: [.data],
                                allowMultiple: false,
                                title: "Select"
                            ) { urls in
                                if let selected = urls.first {
                                    settings.pyExe = selected.path()
                                }
                            }
                        ),
                        AnyView(
                            Button("Default") {
                                if let embeddedBase = Bundle.main.resourcePath {
                                    let defaultPath = embeddedBase + "/audiofactorydiagtools/3.11/bin/python3.11"
                                    settings.pyExe = defaultPath
                                    print("🔁 Reset Python path to default:", defaultPath)
                                } else {
                                    print("❌ resourcePath not found in app bundle.")
                                }
                            }
                        )
                    ]
                )            }
        })
        .formStyle(.grouped)
        .padding()
        .onAppear {
            cachedJsonSchema = settings.jsonSchema
        }
        .onChange(of: settings.jsonSchema) { newValue in
            cachedJsonSchema = newValue
        }
    }
}

struct RadarDownloadFallbackView: View {
    let radarID: String
    var onSuccess: (URL) -> Void
    var onFailure: (String) -> Void

    @EnvironmentObject var settings: SettingsModel
    @State private var attachments: [RadarAttachmentModel] = []
    @State private var loading: Bool = true
    @State private var error: String? = nil

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading Radar attachments...")
                    .onAppear {
                        Task {
                            guard let token = await getRadarAccessToken() else {
                                error = "⚠️ Unable to fetch Radar token."
                                loading = false
                                onFailure("No token")
                                return
                            }

                            getProblemAttachments(radarID, accessToken: token) { data in
                                guard let dictList = dataToDictList(data: data) else {
                                    error = "⚠️ Invalid Radar response."
                                    loading = false
                                    onFailure("Bad data")
                                    return
                                }

                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                                formatter.locale = Locale(identifier: "en_US_POSIX")

                                let models = dictList.compactMap { dict -> RadarAttachmentModel? in
                                    guard let file = dict["fileName"] as? String,
                                          let createdAt = dict["createdAt"] as? String,
                                          let date = formatter.date(from: createdAt) else { return nil }

                                    let author = dict["userName"] as? String ?? "Unknown"
                                    return RadarAttachmentModel(fileName: file, radarID: radarID, uploadDate: date, author: author, token: token)
                                }.sorted(by: { $0.uploadDate > $1.uploadDate })

                                Task { @MainActor in
                                    attachments = models
                                    loading = false
                                }
                            }
                        }
                    }
            } else if let error = error {
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundColor(.red)
                    Text("Please contact Apple DRI Jerry Wang")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding()
            } else {
                List {
                    ForEach(attachments) { attachment in
                        RadarAttachment(attachment: attachment) { unzipDir in
                            onSuccess(unzipDir)
                        }
                        .environmentObject(settings)
                    }
                }
            }
        }
        .frame(width: 500)
    }
}

struct RadarSettingsView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        Form {
            Section(header: Text("Radar Downloads")) {
                RadarDownloadSection(
                    title: "Update EB",
                    radarID: "133428147",
                    attachments: $settings.ebAttachments
                )

                RadarDownloadSection(
                    title: "Update toolkit",
                    radarID: "113934883",
                    attachments: $settings.radarAttachments
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
struct RadarAttachment: View {
    @EnvironmentObject var settings: SettingsModel
    let attachment: RadarAttachmentModel
    let onDownloadComplete: (URL) -> Void
    @StateObject private var downloadDelegate = DownloadDelegate()

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.fileName)
                    .font(.body)
                Text(attachment.uploadDate.formatted(.dateTime.year().month().day().hour().minute()))
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(spacing: 8) {
                if downloadDelegate.inProgress {
                    ProgressView(value: downloadDelegate.progress)
                } else if !downloadDelegate.downloaded {
                    Button("Download") {
                        var request = URLRequest(
                            url: URL(string: "https://radar-webservices.apple.com/problems/\(attachment.radarID)/attachments/\(attachment.fileName)")!
                        )
                        request.addValue(attachment.token, forHTTPHeaderField: "Radar-Authentication")
                        request.httpMethod = "GET"
                        _ = downloadDelegate.startDownload(url: request)
                    }
                } else {
                    Button("Use") {
                        if let savedURL = downloadDelegate.savedURL {
                            do {
                                let unzipDir = attachment.fileName.hasSuffix(".zip")
                                    ? try Zip.quickUnzipFile(savedURL)
                                    : savedURL.deletingLastPathComponent()
                                onDownloadComplete(unzipDir)
                            } catch {
                                print("Unzip error: \(error)")
                            }
                        }
                    }
                    Button("Reset") {
                        downloadDelegate.downloaded = false
                    }
                }
            }
            .frame(width: 100)
        }
        .padding(.vertical, 4)
    }
}



struct RadarAttachmentListView: View {
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var downloadModel = DownloadProgressModel()
    @State private var downloadingAttachment: RadarAttachmentModel?
    
    let radarID: String
    let onComplete: (URL) -> Void

    @State private var isLoading = true
    @State private var errorMsg: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .task {
                        await settings.loadRadarAttachments(radarID: radarID)
                        isLoading = false
                    }
            } else if let err = errorMsg {
                VStack(spacing: 8) {
                    Text("⚠️ \(err)").foregroundColor(.red)
                    Text("Please contact Apple DRI Jerry Wang").font(.caption)
                }.padding()
            } else {
                List(settings.radarAttachments) { att in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(att.fileName)
                                .font(.body)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(att.uploadDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Button {
                            downloadingAttachment = att
                            let url = URL(string: "https://radar-webservices.apple.com/problems/\(att.radarID)/attachments/\(att.fileName)")!

                            downloadModel.completionHandler = { tmpURL in
                                guard let tmpURL = tmpURL else {
                                    downloadingAttachment = nil
                                    return
                                }
                                do {
                                    let dest = try Zip.quickUnzipFile(tmpURL)
                                    DispatchQueue.main.async {
                                        settings.workingDir = dest.path()
                                        settings.workingDirNeedsUpdate = false
                                        downloadingAttachment = nil
                                        onComplete(dest)
                                    }
                                } catch {
                                    downloadingAttachment = nil
                                }
                            }

                            downloadModel.startDownload(from: url, token: att.token)
                        } label: {
                            if downloadingAttachment?.fileName == att.fileName {
                                VStack {
                                    ProgressView(value: downloadModel.progress)
                                        .frame(width: 80)
                                    Text("\(Int(downloadModel.progress * 100))%")
                                        .font(.caption)
                                }
                            } else {
                                Text("Download")
                            }
                        }
                        .buttonStyle(.bordered)
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                .listStyle(.plain)
                .frame(minWidth: 880)
            }
        }
    }

    private func downloadAndUnzip(att: RadarAttachmentModel) {

        var req = URLRequest(
            url: URL(string: "https://radar-webservices.apple.com/problems/\(att.radarID)/attachments/\(att.fileName)")!
        )
        req.addValue(att.token, forHTTPHeaderField: "Radar-Authentication")
        req.httpMethod = "GET"
        let task = URLSession.shared.downloadTask(with: req) { tmpURL, resp, err in
            guard let tmpURL = tmpURL else {
                errorMsg = err?.localizedDescription ?? "Download failed"
                return
            }
            do {
                // 2) 解压到临时目录
                let dest = try Zip.quickUnzipFile(tmpURL)
                DispatchQueue.main.async {
                    // 3) 切换工作目录
                    settings.workingDir = dest.path()
                    settings.workingDirNeedsUpdate = false
                    onComplete(dest)
                }
            } catch {
                errorMsg = error.localizedDescription
            }
        }
        task.resume()
    }
}

struct RadarDownloadSection: View {
    @EnvironmentObject var settings: SettingsModel
    var title: String
    var radarID: String
    @Binding var attachments: [RadarAttachmentModel]

    @State private var isPresented = false
    @State private var attachmentsLoaded = false
    @State private var loadingMessage = "Loading Radar attachments..."

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 140, alignment: .leading)
            Spacer()
            Button("Download from Radar") {
                isPresented = true
                if attachmentsLoaded { return }

                attachmentsLoaded = false
                loadingMessage = "Loading attachments..."

                Task {
                    guard let token = await getRadarAccessToken() else {
                        loadingMessage = "Need AppleConnect signed in"
                        return
                    }
                    settings.radarAccessToken = token

                    getProblemAttachments(radarID, accessToken: token) { data in
                        guard let dictList = dataToDictList(data: data) else { return }

                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                        formatter.locale = Locale(identifier: "en_US_POSIX")

                        let sorted = dictList.compactMap { dict -> RadarAttachmentModel? in
                            guard let file = dict["fileName"] as? String,
                                  let createdAt = dict["createdAt"] as? String,
                                  let date = formatter.date(from: createdAt) else { return nil }

                            let author = dict["userName"] as? String ?? "Unknown"

                            return RadarAttachmentModel(
                                fileName: file,
                                radarID: radarID,
                                uploadDate: date,
                                author: author,
                                token: token
                            )
                        }.sorted(by: { $0.uploadDate > $1.uploadDate })

                        Task { @MainActor in
                            attachments = sorted
                            attachmentsLoaded = true
                        }
                    }
                }
            }
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                if attachmentsLoaded {
                    List {
                        ForEach(attachments) { attachment in
                            RadarAttachment(attachment: attachment) { unzipDir in
                                settings.workingDir = unzipDir.path()
                            }
                            .environmentObject(settings)
                        }
                    }.frame(width: 500)
                } else {
                    Text(loadingMessage).frame(width: 500)
                }
            }
        }.padding(.vertical, 4)
    }
}


// ripplebeam SettingsTabView with optimized layout and bottom padding

struct SettingsTabView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                FilePathsSettingsView()
                    .tabItem { Label("Paths", systemImage: "folder") }
                
                RadarSettingsView()
                    .tabItem { Label("Radar", systemImage: "wifi") }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
                    
            Spacer(minLength: 0)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
                    .padding()
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        
        .frame(minWidth: 800, maxWidth: 1000, minHeight: 620, maxHeight: .infinity)
    }
}

class DownloadProgressModel: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0.0
    var completionHandler: ((URL?) -> Void)?

    func startDownload(from url: URL, token: String) {
        progress = 0.0

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        var req = URLRequest(url: url)
        req.addValue(token, forHTTPHeaderField: "Radar-Authentication")
        req.httpMethod = "GET"

        let task = session.downloadTask(with: req)
        task.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        completionHandler?(location)
    }
}
