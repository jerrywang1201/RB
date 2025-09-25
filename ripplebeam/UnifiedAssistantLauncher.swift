import SwiftUI

// Main launcher button for AI Assistant features
struct UnifiedAssistantLauncher: View {
    var pyExe: String                  // Path to Python executable
    var chatScriptPath: String         // Path to chatbot script
    var logScriptPath: String          // Path to log summary script
    var controlTerminal: TerminalModel // Terminal model for Control tab
    var consoleTerminal: TerminalModel // Terminal model for Console tab
    @Binding var currentTab: Tab       // Current active tab (decides which terminal to use)

    // UI state variables
    @State private var isSelectionSheetPresented = false  // Controls if the option sheet is visible
    @State private var isChatBotPresented = false         // Controls if the chatbot sheet is open
    @State private var isLogSummaryPresented = false      // Controls if the log summary sheet is open

    var body: some View {
        // Main button that opens the assistant option sheet
        Button(action: {
            isSelectionSheetPresented = true
        }) {
            Text("Assistant")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
                .background(
                    // Gradient background
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
        .buttonStyle(PlainButtonStyle())
        // Popover for assistant option sheet
        .popover(isPresented: $isSelectionSheetPresented, arrowEdge: .bottom) {
            AssistantOptionSheetView(
                isPresented: $isSelectionSheetPresented,
                isChatBotPresented: $isChatBotPresented,
                isLogSummaryPresented: $isLogSummaryPresented
            )
            .frame(width: 320)
        }
        // Sheet for chatbot
        .sheet(isPresented: $isChatBotPresented) {
            TestChatBotView(
                pyExe: pyExe,
                scriptPath: chatScriptPath,
                isPresented: $isChatBotPresented
            )
        }
        // Sheet for log summary
        .sheet(isPresented: $isLogSummaryPresented) {
            // Decide which terminal to use based on current tab
            let terminalToUse = currentTab == .control ? controlTerminal : consoleTerminal
            LogSummaryView(
                terminal: terminalToUse,
                pyExe: pyExe,
                scriptPath: logScriptPath,
                isPresented: $isLogSummaryPresented
            )
        }
    }
}

// Popover option sheet with Assistant choices
struct AssistantOptionSheetView: View {
    @Binding var isPresented: Bool
    @Binding var isChatBotPresented: Bool
    @Binding var isLogSummaryPresented: Bool

    var body: some View {
        VStack(spacing: 20) {
            // ✅ Logo with circular background & shadow
            Image("ai")
                .resizable()
                .frame(width: 96, height: 96)
                .background(
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                )
                .clipShape(Circle())
                .shadow(color: .purple.opacity(0.4), radius: 10, x: 0, y: 4)

            // ✅ Title text
            Text("Welcome to AI FW Assistant")
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)

            // ✅ Virtual Firmware Engineer Button
            Button(action: {
                isPresented = false
                // Delay to ensure smooth sheet transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isChatBotPresented = true
                }
            }) {
                HStack {
                    Image(systemName: "brain.head.profile")
                    Text("Virtual Firmware Engineer")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(LinearGradient(
                    colors: [Color.purple, Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: Color.purple.opacity(0.3), radius: 6, x: 0, y: 3)
            }

            // ✅ Log Diagnostics Button
            Button(action: {
                isPresented = false
                // Delay to ensure smooth sheet transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isLogSummaryPresented = true
                }
            }) {
                HStack {
                    Image(systemName: "chart.bar.xaxis")
                    Text("Run Log Diagnostics")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(LinearGradient(
                    colors: [Color.green, Color.blue],
                    startPoint: .leading,
                    endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: Color.purple.opacity(0.3), radius: 6, x: 0, y: 3)
            }

            // Cancel button
            Button("Cancel") {
                isPresented = false
            }
            .padding(.top, 10)
        }
        .padding(30)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(radius: 10)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(radius: 10)
        )
        .padding()
    }
}
