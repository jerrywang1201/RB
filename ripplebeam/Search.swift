import Foundation
import SwiftUI

struct RadarProblem: Identifiable, Decodable {
    let id: Int
    let title: String
    let state: String
    let classification: String
    let priority: Int
}

//@MainActor
//func searchRadarByTitle(_ keyword: String, accessToken: String) async throws -> [RadarProblem] {
//    guard let url = URL(string: "https://radar-webservices.apple.com/problems/find") else {
//        throw URLError(.badURL)
//    }
//
//    var request = URLRequest(url: url)
//    request.httpMethod = "POST"
//    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
//    request.addValue(accessToken, forHTTPHeaderField: "Radar-Authentication")
//
//    let keywords = keyword.split(separator: " ").map { String($0) }
//        let likeConditions = keywords.map { word in
//            return ["title": ["like": "%\(word)%"]]
//        }
//        let requestBody: [String: Any] = [
//            "all": likeConditions
//        ]
//
//    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
//
//    let (data, response) = try await URLSession.shared.data(for: request)
//
//    guard let httpResponse = response as? HTTPURLResponse else {
//        throw URLError(.badServerResponse)
//    }
//
//    if httpResponse.statusCode != 200 {
//        let raw = String(data: data, encoding: .utf8) ?? "<unreadable>"
//        print("Error \(httpResponse.statusCode): \(raw)")
//        throw URLError(.cannotParseResponse)
//    }
//
//    do {
//        let decoded = try JSONDecoder().decode([RadarProblem].self, from: data)
//        return decoded
//    } catch {
//        let jsonString = String(data: data, encoding: .utf8) ?? "N/A"
//        print("JSON Decode Error. Raw data:\n\(jsonString)")
//        throw error
//    }
//}

@MainActor
func searchRadarByTitle(_ keyword: String, accessToken: String) async throws -> [RadarProblem] {
    let urls = [
        "https://radar-webservices.apple.com/problems/find",
    ]

    var lastError: Error?

    for urlString in urls {
        guard let url = URL(string: urlString) else { continue }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(accessToken, forHTTPHeaderField: "Radar-Authentication")

        let keywords = keyword.split(separator: " ").map { String($0) }
        let likeConditions = keywords.map { word in
            return ["title": ["like": "%\(word)%"]]
        }
        let requestBody: [String: Any] = [
            "all": likeConditions
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if httpResponse.statusCode != 200 {
                let raw = String(data: data, encoding: .utf8) ?? "<unreadable>"
                print("Radar API (\(url.host ?? "")) error \(httpResponse.statusCode): \(raw)")
                continue
            }

            let decoded = try JSONDecoder().decode([RadarProblem].self, from: data)
            return decoded

        } catch {
            print("Radar API (\(urlString)) failed: \(error)")
            lastError = error
        }
    }

    throw lastError ?? URLError(.unknown)
}


struct RadarSearchView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var isSearching = false
    @State private var searchError: String?
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(header: Text("Radar Search")) {
                    TextField("Enter title keyword...", text: $settings.radarSearchKeyword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .multilineTextAlignment(.leading)
                    
                    HStack {
                        Button("Search") {
                            Task {
                                await performSearch()
                            }
                        }

                        if isSearching {
                            ProgressView()
                                .padding(.leading, 8)
                        }

                        if let error = searchError {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.subheadline)
                                .padding(.leading, 12)
                        }
                    }
                }

                Section(header: Text("Results")) {
                    if settings.radarDecodedResults.isEmpty && !isSearching && searchError == nil {
                        Text("No results yet.").foregroundColor(.secondary)
                    }

                    List(settings.radarDecodedResults) { problem in
                        Button(action: {
                            if let url = URL(string: "radar://problem/\(problem.id)") {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(problem.title).bold()
                                Text("ID: \(problem.id) • State: \(problem.state) • Priority: \(problem.priority)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Text(problem.classification)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Clear") {
                    settings.radarSearchKeyword = ""
                    settings.radarDecodedResults = []
                    searchError = nil
                }

                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 700, height: 540)
        .onAppear {
            Task {
                if settings.radarAccessToken.isEmpty {
                    if let token = await getRadarAccessToken() {
                        settings.radarAccessToken = token
                    }
                }
            }
        }
    }

    private func performSearch() async {
        isSearching = true
        searchError = nil
        settings.radarDecodedResults = []

        do {
            let results = try await searchRadarByTitle(settings.radarSearchKeyword, accessToken: settings.radarAccessToken)
            settings.radarDecodedResults = results
            if results.isEmpty {
                searchError = "No results found."
            }
        } catch {
            searchError = error.localizedDescription
            settings.output += "\nRadar search failed: \(error.localizedDescription)"
        }

        isSearching = false
    }
}
