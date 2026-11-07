import SwiftUI
import AppKit

// MARK: - The Scrawl mark

/// One stroke of the logo's S, traced from the app icon's 512×512 artwork so the two match exactly.
struct ScrawlStroke: Shape {
    enum Part { case body, tail }
    let part: Part

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 512
        let ox = rect.midX - 256 * s, oy = rect.midY - 256 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()
        switch part {
        case .body: // your stroke
            path.move(to: p(374, 148))
            path.addCurve(to: p(174, 154), control1: p(332, 92), control2: p(212, 92))
            path.addCurve(to: p(264, 264), control1: p(140, 212), control2: p(200, 248))
            path.addCurve(to: p(342, 374), control1: p(334, 282), control2: p(374, 318))
        case .tail: // the tail your agent adds
            path.move(to: p(342, 374))
            path.addCurve(to: p(138, 366), control1: p(306, 432), control2: p(190, 428))
        }
        return path
    }
}

/// The app icon as a view: the ink tile with the S. `animated` draws the S on a loop, like a pen.
struct ScrawlAppTile: View {
    var size: CGFloat
    var animated = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bodyProgress: CGFloat = 1
    @State private var tailProgress: CGFloat = 1

    var body: some View {
        let line = StrokeStyle(lineWidth: size * 44 / 512, lineCap: .round, lineJoin: .round)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2227, style: .continuous)
                .fill(Color(red: 0x1c / 255, green: 0x1c / 255, blue: 0x22 / 255))
            ScrawlStroke(part: .body).trim(from: 0, to: bodyProgress).stroke(.white, style: line)
            ScrawlStroke(part: .tail).trim(from: 0, to: tailProgress).stroke(Color(red: 1, green: 0x5a / 255, blue: 0x5f / 255), style: line)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: size * 0.08, y: size * 0.04)
        .accessibilityHidden(true)
        .task {
            guard animated, !reduceMotion else { return }
            while !Task.isCancelled {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { bodyProgress = 0; tailProgress = 0 }
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(.easeInOut(duration: 0.75)) { bodyProgress = 1 }
                try? await Task.sleep(for: .milliseconds(750))
                withAnimation(.easeOut(duration: 0.35)) { tailProgress = 1 }
                try? await Task.sleep(for: .seconds(1.6))
            }
        }
    }
}

// MARK: - Copyable snippet

/// A line or block of setup text with a copy button that confirms in place.
struct CodeSnippetCard: View {
    let snippet: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(snippet)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(snippet, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(copied ? Color.scrawlCoral : .secondary)
                    .frame(width: 18, height: 18)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help(copied ? "Copied" : "Copy")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }
}

/// Setup text for the common MCP clients, built from the live server URL.
enum AgentSetup {
    static func claudeCode(_ url: URL) -> String {
        "claude mcp add --transport http scrawl \(url.absoluteString)"
    }

    static func cursor(_ url: URL) -> String {
        """
        {
          "mcpServers": {
            "scrawl": { "url": "\(url.absoluteString)" }
          }
        }
        """
    }
}

// MARK: - Toolbar status and the connect popover

struct StatusBadgeView: View {
    let status: ServerStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)
                .shadow(color: indicatorColor.opacity(0.5), radius: isLive ? 3 : 0)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .contentShape(Capsule())
    }

    private var isLive: Bool { if case .running = status { return true } else { return false } }

    private var indicatorColor: Color {
        switch status {
        case .running: return .green
        case .starting: return .orange
        case .error: return .red
        case .stopped: return .gray
        }
    }

    private var statusText: String {
        switch status {
        case .running(let port): return "MCP Live :\(port)"
        case .starting: return "Starting…"
        case .error: return "Offline"
        case .stopped: return "Stopped"
        }
    }
}

/// Everything needed to point an agent at Scrawl, one click from the toolbar.
struct ConnectAgentView: View {
    @ObservedObject var supervisor: ServerSupervisor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ScrawlAppTile(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let an agent draw").font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }

            group("Server URL") { CodeSnippetCard(snippet: supervisor.mcpEndpointURL.absoluteString) }
            group("Claude Code · run once in Terminal") { CodeSnippetCard(snippet: AgentSetup.claudeCode(supervisor.mcpEndpointURL)) }
            group("Cursor · add to ~/.cursor/mcp.json") { CodeSnippetCard(snippet: AgentSetup.cursor(supervisor.mcpEndpointURL)) }

            Divider()
            HStack {
                Text("Works with any MCP client on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                SettingsLink { Text("Agent settings…") }
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 480)
    }

    private var subtitle: String {
        if case .running(let port) = supervisor.status { return "The drawing server is live on port \(port)." }
        return "The drawing server isn't running right now."
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Toast

/// A small confirmation that floats up from the bottom of the window, like a macOS HUD.
struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.scrawlCoral)
            Text(text)
        }
        .font(.system(size: 12.5, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

// MARK: - About

enum AboutPanel {
    @MainActor static func show() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let credits = NSAttributedString(
            string: "Sketch it on your Mac. Pay for it once.\nA whiteboard your AI agent can draw on.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Scrawl", .credits: credits])
        NSApp.activate()
    }
}
