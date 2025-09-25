//
//  bot.swift
//  ripplebeam
//
//  Created by Jialong Wang's MacBook Pro 16'
//


import SwiftUI

/// A button that launches the Test Chat Bot view as a sheet.
struct TestChatBotLauncher: View {
    // MARK: - Properties

    /// The path to the Python executable (e.g., "/usr/bin/python3").
    var pyExe: String
    
    /// The path to the Python script to be executed.
    var scriptPath: String
    
    /// A binding to control the presentation of the chat sheet.
    @Binding var isPresented: Bool
    
    /// A local state to track the button's press-down animation.
    @State private var isPressed = false

    // MARK: - Body

    var body: some View {
        Button(action: {
            // Set the binding to true to present the sheet.
            isPresented = true
        }) {
            Text("Virtual Firmware Engineer")
                .font(.system(size: 14, weight: .semibold))
                // The styling for this button is defined inline.
                // For a more reusable approach, see the `AIStyleButton` modifier below.
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.purple.opacity(0.85), Color.blue.opacity(0.85)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: Color.purple.opacity(0.3), radius: 5, x: 0, y: 3)
                // Provides visual feedback when the button is pressed.
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        // Use PlainButtonStyle to remove the default button visuals and allow our custom styling to show.
        .buttonStyle(PlainButtonStyle())
        // A long press gesture is used to detect the start and end of a press for the animation.
        .onLongPressGesture(minimumDuration: 0.01, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        // The sheet modifier presents the TestChatBotView when `isPresented` is true.
        .sheet(isPresented: $isPresented) {
            TestChatBotView(
                pyExe: pyExe,
                scriptPath: scriptPath,
                isPresented: $isPresented
            )
        }
    }
}

/// A `ViewModifier` to apply a consistent, reusable AI-themed style to any view.
/// Using a ViewModifier promotes code reuse and a single source of truth for styling.
struct AIStyleButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.purple.opacity(0.85), Color.blue.opacity(0.85)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
            .shadow(color: Color.purple.opacity(0.3), radius: 5, x: 0, y: 3)
    }
}

// An extension on View to provide a convenient, chainable method for applying the style.
extension View {
    /// Applies the reusable AI-themed button style.
    func aiButtonStyle() -> some View {
        self.modifier(AIStyleButton())
    }
}


/// A data model representing a single message in the chat history.
/// It's `Identifiable` so it can be used easily in SwiftUI's `ForEach`.
struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool // True if the message is from the user, false if from the AI.
}

/// A view that displays a response from the AI.
/// It includes special handling for copying command-line snippets from the response.
struct AIResponseView: View {
    let text: String
    
    /// A state to show a "Copied!" confirmation message briefly.
    @State private var showCopyConfirmation = false

    /// A computed property that extracts command lines from the AI's response text.
    /// This enhances usability for our technical teams who might need to run these commands.
    private var commandLines: [String] {
        text
            .components(separatedBy: "\n")
            // A computer emoji (💻) is used as a clear, accessible indicator for a command.
            .filter { $0.hasPrefix("\u{1F4BB} Command:") }
            .map { line in
                // Clean up the string to get just the command.
                line.replacingOccurrences(of: "\u{1F4BB} Command:", with: "").trimmingCharacters(in: .whitespaces)
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The main text bubble for the AI's response.
            Text(text)
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(16)
                .frame(maxWidth: 280, alignment: .leading)

            // The "Copy Commands" button only appears if commands are detected in the response.
            if !commandLines.isEmpty {
                Button(action: {
                    // Join multiple commands with newlines and copy them to the system pasteboard.
                    let joined = commandLines.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(joined, forType: .string)
                    
                    // Provide immediate visual feedback that the copy action was successful.
                    showCopyConfirmation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopyConfirmation = false
                    }
                }) {
                    Text(showCopyConfirmation ? "✅ Copied!" : "Copy Commands")
                        .font(.caption)
                        .padding(6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
        }
    }
}

/// The main view for the chat bot interface.
struct TestChatBotView: View {
    // MARK: - Properties

    var pyExe: String
    var scriptPath: String
    @Binding var isPresented: Bool

    /// The text currently being typed by the user.
    @State private var userInput: String = ""
    
    /// An array holding the entire chat history. The view automatically updates when this changes.
    @State private var messages: [ChatMessage] = [
        ChatMessage(text: "Hello! How may I assist you today?", isUser: false)
    ]
    
    /// A boolean to indicate when the app is waiting for a response from the Python script.
    @State private var isThinking = false
    
    /// A focus state to manage the keyboard for the text input field.
    @FocusState private var isInputFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Text("Welcome to Virtual FW Engineer")
                    .font(.title2.bold())
                    .padding()

                // ScrollViewReader allows us to programmatically scroll to the newest message.
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { msg in
                                HStack {
                                    if msg.isUser {
                                        Spacer() // Pushes user messages to the right.
                                        Text(msg.text)
                                            .padding()
                                            .foregroundColor(.white)
                                            .background(Color.blue)
                                            .cornerRadius(16)
                                            .frame(maxWidth: 280, alignment: .trailing)
                                    } else {
                                        // Use the dedicated view for AI responses.
                                        AIResponseView(text: msg.text)
                                        Spacer() // Keeps AI messages aligned to the left.
                                    }
                                }
                                .id(msg.id)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    // Whenever a new message is added, scroll to the bottom.
                    .onChange(of: messages.count) { _ in
                        DispatchQueue.main.async {
                            if let last = messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // The input area at the bottom of the view.
                HStack {
                    TextField("Type a message...", text: $userInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isInputFocused)

                    // Show a progress indicator while waiting for the AI response.
                    if isThinking {
                        ProgressView()
                            .padding(.horizontal, 4)
                    }

                    Button("Send") {
                        submitMessage()
                    }
                    // The send button is disabled if there's no text or if the AI is "thinking".
                    .disabled(userInput.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
                }
                .padding()
            }
            .frame(minWidth: 500, minHeight: 500)
            // The toolbar provides a standard way to dismiss the view.
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }

    // MARK: - Private Methods
    
    /// Handles the logic for submitting a user's message.
    private func submitMessage() {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        print("🟢 User Input:", trimmed)
        messages.append(ChatMessage(text: trimmed, isUser: true))
        userInput = ""
        isThinking = true

        // Run the Python script in a background task to avoid blocking the UI.
        Task {
            let response = await runShellCapture(pyExe, arguments: [scriptPath, trimmed])
            // Ensure we always have some text to display, even on error.
            let reply = response.isEmpty ? "❌ No response from Python." : response
            
            // Appending the response will automatically update the UI.
            messages.append(ChatMessage(text: reply, isUser: false))
            isThinking = false
        }
    }

    /// Asynchronously runs an external shell command and captures its output.
    /// - Parameters:
    ///   - exe: The path to the executable.
    ///   - arguments: An array of command-line arguments.
    /// - Returns: The captured output (from stdout and stderr) as a String.
    private func runShellCapture(_ exe: String, arguments: [String]) async -> String {
        print("🚀 Running:", exe, arguments.joined(separator: " "))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = arguments

        // Use a Pipe to capture the output of the process.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe // Capture errors as well.

        do {
            try process.run()
            print("✅ Process started.")
        } catch {
            print("❌ Process failed to start:", error.localizedDescription)
            return "❌ Failed to run script: \(error.localizedDescription)"
        }

        // Bridge the callback-based `terminationHandler` with async/await.
        // This makes the asynchronous code much cleaner to work with.
        await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                print("🏁 Process ended. Exit code:", proc.terminationStatus)
                continuation.resume()
            }
        }

        // Read the data from the pipe and convert it to a string.
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let result = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        print("📤 Raw Output:", result)
        return result
    }
}
