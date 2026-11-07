import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationWillTerminate(_ notification: Notification) {
        ServerSupervisor.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct ScrawlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var supervisor = ServerSupervisor.shared

    var body: some Scene {
        // Every window is tinted coral, so controls never pick up the system accent
        // (purple, if that's the Mac's accent colour).
        WindowGroup {
            MainWindowView()
                .frame(minWidth: 960, minHeight: 640)
                .tint(.scrawlCoral)
        }
        .defaultSize(width: 1320, height: 860)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            ScrawlCommands(supervisor: supervisor)
        }

        // Window ▸ Server Logs (⌥⌘L)
        Window("Server Logs", id: "logs") {
            ServerLogsView(supervisor: supervisor)
                .tint(.scrawlCoral)
        }
        .defaultSize(width: 760, height: 480)

        // Scrawl ▸ Settings… (⌘,)
        Settings {
            SettingsView(supervisor: supervisor)
                .tint(.scrawlCoral)
        }
    }
}

struct ScrawlCommands: Commands {
    @ObservedObject var supervisor: ServerSupervisor
    @Environment(\.openWindow) private var openWindow

    private var isRunning: Bool {
        if case .running = supervisor.status { return true } else { return false }
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Scrawl") { AboutPanel.show() }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Board") { supervisor.requestNewBoard() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!isRunning)

            Button("Reveal Boards in Finder") { supervisor.revealDataDirectory() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandMenu("Server") {
            Button("Copy MCP URL") { supervisor.copyMcpUrlToClipboard() }
                .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Show Server Logs") { openWindow(id: "logs") }
                .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button("Restart Server") { supervisor.restart() }
                .keyboardShortcut("r", modifiers: .command)

            Divider()

            if isRunning || supervisor.status == .starting {
                Button("Stop Server") { supervisor.stop() }
            } else {
                Button("Start Server") { supervisor.start() }
            }
        }
    }
}
