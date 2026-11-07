import SwiftUI
import AppKit

extension Color {
    /// Scrawl's coral accent, the same red as the logo and the web UI (#e5484d).
    static let scrawlCoral = Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255)
}

/// The canvas theme the web app reports, which the window chrome follows.
enum CanvasTheme: String {
    case light, dark

    /// Excalidraw's canvas colour in each theme.
    var background: NSColor {
        self == .dark ? NSColor(srgbRed: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, alpha: 1) : .white
    }

    @MainActor static var system: CanvasTheme {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }
}

extension NSWindow {
    /// No title and no separator, with the title bar in the canvas colour,
    /// so the toolbar sits on the board instead of on a grey strip above it.
    func applyScrawlChrome(_ theme: CanvasTheme) {
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        titlebarSeparatorStyle = .none
        appearance = NSAppearance(named: theme == .dark ? .darkAqua : .aqua)
        backgroundColor = theme.background
    }
}

/// Applies the chrome as soon as the SwiftUI window exists, before the canvas reports its theme.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.applyScrawlChrome(.system)
        }
    }
}
