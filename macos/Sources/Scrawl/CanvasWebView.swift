import SwiftUI
import WebKit
import AppKit

public struct CanvasWebView: NSViewRepresentable {
    public let url: URL
    @ObservedObject public var supervisor: ServerSupervisor
    public let onLoadingChanged: (Bool) -> Void
    
    public init(
        url: URL,
        supervisor: ServerSupervisor,
        onLoadingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.url = url
        self.supervisor = supervisor
        self.onLoadingChanged = onLoadingChanged
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // The canvas posts its theme here (App.tsx), and the window chrome follows it.
        config.userContentController.add(context.coordinator, name: "scrawl")

        let webView = CustomWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        // Enable Safari Web Inspector
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        
        // Translucent background until loaded
        webView.setValue(false, forKey: "drawsBackground")
        
        context.coordinator.webView = webView
        
        if case .running = supervisor.status {
            webView.load(URLRequest(url: url))
        }
        
        return webView
    }
    
    public func updateNSView(_ nsView: WKWebView, context: Context) {
        // If server just transitioned to running and webView hasn't loaded target url
        if case .running = supervisor.status {
            if nsView.url == nil || nsView.url?.host != url.host || nsView.url?.port != url.port {
                nsView.load(URLRequest(url: url))
            }
        }
        // File ▸ New Board: the web app creates and opens an "Untitled" board (App.tsx)
        if supervisor.newBoardRequests != context.coordinator.handledNewBoardRequests {
            context.coordinator.handledNewBoardRequests = supervisor.newBoardRequests
            nsView.evaluateJavaScript("window.scrawl && window.scrawl.newBoard && window.scrawl.newBoard()", completionHandler: nil)
        }
    }
    
    public class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: CanvasWebView
        weak var webView: WKWebView?
        var handledNewBoardRequests = 0

        init(_ parent: CanvasWebView) {
            self.parent = parent
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let raw = body["theme"] as? String,
                  let theme = CanvasTheme(rawValue: raw) else { return }
            webView?.window?.applyScrawlChrome(theme)
        }

        // WKWebView answers window.alert / confirm / prompt with "cancel" unless the app shows them,
        // which is what made "Move to trash" do nothing.
        private func present(_ alert: NSAlert, in webView: WKWebView, completion: @escaping (NSApplication.ModalResponse) -> Void) {
            if let window = webView.window {
                alert.beginSheetModal(for: window, completionHandler: completion)
            } else {
                completion(alert.runModal())
            }
        }

        public func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable () -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            present(alert, in: webView) { _ in completionHandler() }
        }

        public func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            present(alert, in: webView) { response in completionHandler(response == .alertFirstButtonReturn) }
        }

        public func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable (String?) -> Void
        ) {
            let alert = NSAlert()
            alert.messageText = prompt
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.stringValue = defaultText ?? ""
            alert.accessoryView = field
            present(alert, in: webView) { response in
                completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
            }
        }

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoadingChanged(true)
        }
        
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onLoadingChanged(false)
        }
        
        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onLoadingChanged(false)
        }
        
        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onLoadingChanged(false)
            // If failed because server was still starting, retry in 500ms
            if case .running = parent.supervisor.status {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, let wv = self.webView else { return }
                    if wv.url == nil {
                        wv.load(URLRequest(url: self.parent.url))
                    }
                }
            }
        }
    }
}

// Subclass to handle native Mac keyboard shortcuts and trackpad gestures seamlessly
final class CustomWKWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Allow standard Mac editing shortcuts (Cmd+C, Cmd+V, Cmd+Z, Cmd+Shift+Z, Cmd+A)
        // to pass through to the canvas web editor without being consumed by AppKit
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "z", "Z", "c", "v", "x", "a":
                return super.performKeyEquivalent(with: event)
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

