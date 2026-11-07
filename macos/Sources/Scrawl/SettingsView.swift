import SwiftUI
import AppKit

/// Scrawl ▸ Settings… (⌘,): a standard Mac settings window in the System Settings style.
/// Changes apply as you make them; the ones that restart the server say so.
public struct SettingsView: View {
    @ObservedObject var supervisor: ServerSupervisor

    public init(supervisor: ServerSupervisor) {
        self.supervisor = supervisor
    }

    public var body: some View {
        TabView {
            GeneralSettings(supervisor: supervisor)
                .tabItem { Label("General", systemImage: "gearshape") }
            AgentSettings(supervisor: supervisor)
                .tabItem { Label("Agents", systemImage: "sparkles") }
            AdvancedSettings(supervisor: supervisor)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var supervisor: ServerSupervisor

    var body: some View {
        Form {
            Section {
                LabeledContent("Boards folder") {
                    Text(displayPath(supervisor.dataDirectory))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(supervisor.dataDirectory.path)
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") { supervisor.revealDataDirectory() }
                    Button("Change…") { pickFolder() }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Each board is saved as an .excalidraw file in this folder. Changing the folder restarts the drawing server.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                shortcut("New board", "⌘N")
                shortcut("Reveal boards in Finder", "⇧⌘O")
                shortcut("Copy MCP URL", "⇧⌘C")
                shortcut("Server logs", "⌥⌘L")
                shortcut("Restart server", "⌘R")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) {
            Text(keys)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = supervisor.dataDirectory
        panel.prompt = "Use This Folder"
        panel.message = "Choose where Scrawl keeps your boards."
        if panel.runModal() == .OK, let url = panel.url, url != supervisor.dataDirectory {
            supervisor.updateDataDirectory(url)
        }
    }
}

// MARK: - Agents

private struct AgentSettings: View {
    @ObservedObject var supervisor: ServerSupervisor

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") { StatusBadgeLabel(status: supervisor.status) }
                LabeledContent("Server URL") {
                    HStack(spacing: 8) {
                        Text(supervisor.mcpEndpointURL.absoluteString)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            supervisor.copyMcpUrlToClipboard()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy MCP URL")
                    }
                }
            } header: {
                Text("MCP server")
            } footer: {
                Text("Any MCP client on this Mac or your private network can draw on your boards through this URL. It runs while Scrawl is open.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                CodeSnippetCard(snippet: AgentSetup.claudeCode(supervisor.mcpEndpointURL))
            } header: {
                Text("Claude Code")
            } footer: {
                Text("Run this once in Terminal.").font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                CodeSnippetCard(snippet: AgentSetup.cursor(supervisor.mcpEndpointURL))
            } header: {
                Text("Cursor")
            } footer: {
                Text("Add this to ~/.cursor/mcp.json.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The status dot and words, without the toolbar pill's chevron.
private struct StatusBadgeLabel: View {
    let status: ServerStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch status {
        case .running: return .green
        case .starting: return .orange
        case .error: return .red
        case .stopped: return .gray
        }
    }

    private var text: String {
        switch status {
        case .running(let port): return "Live on port \(port)"
        case .starting: return "Starting…"
        case .error: return "Not running"
        case .stopped: return "Stopped"
        }
    }
}

// MARK: - Advanced

private struct AdvancedSettings: View {
    @ObservedObject var supervisor: ServerSupervisor
    @Environment(\.openWindow) private var openWindow

    @State private var portText = ""
    @State private var nodePath = ""

    private var newPort: Int? {
        guard let p = Int(portText), p > 1024, p < 65535, p != supervisor.port else { return nil }
        return p
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Port") {
                    HStack(spacing: 8) {
                        TextField("Port", text: $portText, prompt: Text("3779"))
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                            .onSubmit(applyPort)
                        Button("Apply", action: applyPort)
                            .disabled(newPort == nil)
                    }
                }
            } header: {
                Text("Server")
            } footer: {
                Text("The default is 3779. Changing the port restarts the server, so reconnect your agents with the new URL.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Node.js") {
                    TextField("Node.js", text: $nodePath, prompt: Text("/usr/local/bin/node"))
                        .labelsHidden()
                        .font(.system(.callout, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .onSubmit(applyNode)
                }
                HStack {
                    Button("Detect") {
                        if let found = ServerSupervisor.discoverNodeBinary() { nodePath = found; applyNode() }
                    }
                    Button("Choose…", action: pickNode)
                    Spacer()
                    Button("Apply", action: applyNode)
                        .disabled(nodePath.isEmpty || nodePath == supervisor.nodeBinaryPath)
                }
            } header: {
                Text("Node.js runtime")
            } footer: {
                Text("Scrawl's drawing server needs Node.js 22 or newer.").font(.footnote).foregroundStyle(.secondary)
            }

            Section("Troubleshooting") {
                HStack {
                    Button("Restart Server") { supervisor.restart() }
                    Button("Restart Server") { supervisor.forceResetAndRestart() }
                    Spacer()
                    Button("Show Logs") { openWindow(id: "logs") }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            portText = String(supervisor.port)
            nodePath = supervisor.nodeBinaryPath
        }
    }

    private func applyPort() {
        guard let p = newPort else { return }
        supervisor.updatePort(p)
    }

    private func applyNode() {
        guard !nodePath.isEmpty, nodePath != supervisor.nodeBinaryPath else { return }
        supervisor.updateNodeBinaryPath(nodePath)
    }

    private func pickNode() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Node"
        panel.message = "Choose the node executable Scrawl should run."
        if panel.runModal() == .OK, let url = panel.url {
            nodePath = url.path
            applyNode()
        }
    }
}

/// "~/Documents/Scrawl" rather than the full home path.
private func displayPath(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
}
