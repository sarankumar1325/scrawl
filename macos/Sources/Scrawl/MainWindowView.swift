import SwiftUI
import AppKit

public struct MainWindowView: View {
    @ObservedObject var supervisor = ServerSupervisor.shared
    @State private var isLoadingWeb = true
    @State private var showConnect = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        ZStack {
            switch supervisor.status {
            case .running:
                ZStack {
                    CanvasWebView(
                        url: supervisor.webAppURL,
                        supervisor: supervisor,
                        onLoadingChanged: { loading in
                            isLoadingWeb = loading
                        }
                    )
                    // The board stays below the title bar, in full screen too: under it, the
                    // toolbar would cover the board's own controls whenever it slides in.

                    // Until the board has loaded, the window shows the mark on the canvas colour
                    // instead of a blank page.
                    if isLoadingWeb {
                        ScrawlAppTile(size: 56)
                            .opacity(0.9)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.35), value: isLoadingWeb)

            case .starting:
                StartingView(port: supervisor.port, onForceRestart: supervisor.forceResetAndRestart)

            case .error(let message):
                ErrorStateView(
                    message: message,
                    onRetry: supervisor.restart,
                    onFreePortAndRetry: supervisor.forceResetAndRestart,
                    onOpenSettings: { openSettings() },
                    onOpenLogs: { openWindow(id: "logs") }
                )

            case .stopped:
                StoppedView(onStart: supervisor.start)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = supervisor.toast {
                ToastView(text: toast)
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: supervisor.toast)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // The status pill opens everything needed to connect an agent
                Button {
                    showConnect.toggle()
                } label: {
                    StatusBadgeView(status: supervisor.status)
                }
                .buttonStyle(.plain)
                .help("Connect an AI agent")
                .popover(isPresented: $showConnect, arrowEdge: .bottom) {
                    ConnectAgentView(supervisor: supervisor)
                }

                Button {
                    supervisor.revealDataDirectory()
                } label: {
                    Label("Open Boards Folder", systemImage: "folder")
                }
                .help("Show your board files in Finder")

                // Less frequent actions live in one menu, so the toolbar stays quiet
                Menu {
                    Button {
                        supervisor.restart()
                    } label: {
                        Label("Restart Server", systemImage: "arrow.clockwise")
                    }
                    Button {
                        openWindow(id: "logs")
                    } label: {
                        Label("Server Logs", systemImage: "terminal")
                    }
                    Divider()
                    SettingsLink {
                        Label("Settings…", systemImage: "gearshape")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("Restart the server, view logs, or open Settings")
            }
        }
        .background(WindowChrome())
        .onAppear {
            if supervisor.status == .stopped {
                supervisor.start()
            }
        }
    }
}

// MARK: - Launch and server states

/// While the drawing server starts: the mark draws itself, like a pen.
struct StartingView: View {
    let port: Int
    let onForceRestart: () -> Void
    @State private var showEscapeHatch = false

    var body: some View {
        VStack(spacing: 0) {
            ScrawlAppTile(size: 88, animated: true)
                .padding(.bottom, 26)
            Text("Starting Scrawl")
                .font(.system(size: 20, weight: .semibold))
            Text("Getting the drawing server ready on port \(String(port))…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            Button("Taking a while? Free the port and try again", action: onForceRestart)
                .buttonStyle(.link)
                .font(.callout)
                .padding(.top, 22)
                .opacity(showEscapeHatch ? 1 : 0)
                .animation(.easeOut(duration: 0.4), value: showEscapeHatch)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: .seconds(4))
            showEscapeHatch = true
        }
    }
}

/// The server couldn't start: say what happened and offer the next step first.
struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void
    let onFreePortAndRetry: () -> Void
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrawlAppTile(size: 76)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 26))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.scrawlCoral)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(2))
                        .offset(x: 9, y: 9)
                }
                .padding(.bottom, 26)

            Text("Scrawl couldn't start its drawing server")
                .font(.system(size: 20, weight: .semibold))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .padding(.top, 8)

            HStack(spacing: 10) {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .tint(.scrawlCoral)
                    .keyboardShortcut(.defaultAction)
                Button("Restart & Retry", action: onFreePortAndRetry)
            }
            .controlSize(.large)
            .padding(.top, 24)

            HStack(spacing: 18) {
                Button("Open Settings", action: onOpenSettings)
                Button("Show Server Logs", action: onOpenLogs)
            }
            .buttonStyle(.link)
            .font(.callout)
            .padding(.top, 16)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The server was stopped from the menu.
struct StoppedView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrawlAppTile(size: 76)
                .opacity(0.85)
                .padding(.bottom, 26)
            Text("The drawing server is stopped")
                .font(.system(size: 20, weight: .semibold))
            Text("Start it to open your boards. Agents can't draw while it's stopped.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Button("Start Server", action: onStart)
                .buttonStyle(.borderedProminent)
                .tint(.scrawlCoral)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
