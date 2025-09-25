import SwiftUI
import FilePicker
import UniformTypeIdentifiers
import Combine

struct AutoScrollingTextEditor: View {
    @Binding var text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                TextEditor(text: $text)
                    .background(Color.clear)
                    .frame(minHeight: 300)
                    .id("TextEditor")
                    .onChange(of: text) { _ in
                        withAnimation {
                            proxy.scrollTo("TextEditor", anchor: .bottom)
                        }
                    }
            }
        }
    }
}

public struct FilePickerNoAlias<LabelView: View>: View {
    public typealias PickedURLsCompletionHandler = (_ urls: [URL]) -> Void
    public typealias LabelViewContent = () -> LabelView

    @State private var isPresented: Bool = false

    public let types: [UTType]
    public let allowMultiple: Bool
    public let pickedCompletionHandler: PickedURLsCompletionHandler
    public let labelViewContent: LabelViewContent

    public init(types: [UTType], allowMultiple: Bool, onPicked completionHandler: @escaping PickedURLsCompletionHandler, @ViewBuilder label labelViewContent: @escaping LabelViewContent) {
        self.types = types
        self.allowMultiple = allowMultiple
        self.pickedCompletionHandler = completionHandler
        self.labelViewContent = labelViewContent
    }

    public init(types: [UTType], allowMultiple: Bool, title: String, onPicked completionHandler: @escaping PickedURLsCompletionHandler) where LabelView == Text {
        self.init(types: types, allowMultiple: allowMultiple, onPicked: completionHandler) { Text(title) }
    }

    public var body: some View {
        Button(action: {
            if !isPresented { isPresented = true }
        }) {
            labelViewContent()
        }
        .disabled(isPresented)
        .onChange(of: isPresented) { presented in
            if presented {
                let panel = NSOpenPanel()
                panel.resolvesAliases = false
                panel.allowsMultipleSelection = allowMultiple
                panel.canChooseDirectories = true
                panel.canChooseFiles = true

                if #available(macOS 12.0, *) {
                    
                    panel.allowedContentTypes = types
                } else {
                    
                    panel.allowedFileTypes = types.map { $0.identifier }
                }

                panel.begin { response in
                    if response == .OK {
                        pickedCompletionHandler(panel.urls)
                    }
                    isPresented = false
                }
            }
        }
    }
}

public struct DirPicker<LabelView: View>: View {
    public typealias PickedURLsCompletionHandler = (_ urls: [URL]) -> Void
    public typealias LabelViewContent = () -> LabelView

    @State private var isPresented: Bool = false

    public let types: [UTType]
    public let allowMultiple: Bool
    public let pickedCompletionHandler: PickedURLsCompletionHandler
    public let labelViewContent: LabelViewContent

    public init(types: [UTType], allowMultiple: Bool, onPicked completionHandler: @escaping PickedURLsCompletionHandler, @ViewBuilder label labelViewContent: @escaping LabelViewContent) {
        self.types = types
        self.allowMultiple = allowMultiple
        self.pickedCompletionHandler = completionHandler
        self.labelViewContent = labelViewContent
    }

    public init(types: [UTType], allowMultiple: Bool, title: String, onPicked completionHandler: @escaping PickedURLsCompletionHandler) where LabelView == Text {
        self.init(types: types, allowMultiple: allowMultiple, onPicked: completionHandler) { Text(title) }
    }

    public var body: some View {
        Button(action: {
            if !isPresented { isPresented = true }
        }) {
            labelViewContent()
        }
        .disabled(isPresented)
        .onChange(of: isPresented) { presented in
            if presented {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = allowMultiple
                panel.canChooseDirectories = true
                panel.canChooseFiles = true

                if #available(macOS 12.0, *) {
                    panel.allowedContentTypes = types
                } else {
                    panel.allowedFileTypes = types.map { $0.identifier }
                }

                panel.begin { response in
                    if response == .OK {
                        pickedCompletionHandler(panel.urls)
                    }
                    isPresented = false
                }
            }
        }
    }
}

struct RBFrameModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
    }
}

extension View {
    func asRBFrame() -> some View {
        self.modifier(RBFrameModifier())
    }
}

struct TerminalTextOnlyView: View {
    @ObservedObject var terminal: TerminalModel

    var body: some View {
        ScrollViewReader { scrollViewProxy in
            VStack(alignment: .leading) {
                ScrollView {
                    VStack(alignment: .leading) {
                        Text(terminal.output.map(\.text).joined(separator: "\n"))
                            .id(0)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("").id("Bottom")
                    }
                }
                .onChange(of: terminal.output) { _ in
                    withAnimation {
                        scrollViewProxy.scrollTo("Bottom", anchor: .bottom)
                    }
                }

                HStack {
                    Button("Go to top") {
                        withAnimation {
                            scrollViewProxy.scrollTo(0, anchor: .top)
                        }
                    }
                    Button("Go to bottom") {
                        withAnimation {
                            scrollViewProxy.scrollTo("Bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(Color.gray.opacity(0.1))
    }
}
