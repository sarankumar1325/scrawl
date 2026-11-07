import SwiftUI
import AppKit

/// Window ▸ Server Logs (⌥⌘L): the drawing server's output, in its own window so it never blocks the board.
struct ServerLogsView: View {
    @ObservedObject var supervisor: ServerSupervisor
    @State private var follow = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(supervisor.logs.enumerated()), id: \.offset) { index, line in
                        LogLine(line: line).id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                if supervisor.logs.isEmpty {
                    ContentUnavailableView(
                        "No server output yet",
                        systemImage: "terminal",
                        description: Text("Messages from the drawing server appear here as it runs.")
                    )
                }
            }
            .onChange(of: supervisor.logs.count) {
                guard follow, let last = supervisor.logs.indices.last else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
        .navigationTitle("Server Logs")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $follow) {
                    Label("Follow", systemImage: "arrow.down.to.line")
                }
                .help("Keep the newest line in view")

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(supervisor.logs.joined(separator: "\n"), forType: .string)
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .help("Copy all log lines")
                .disabled(supervisor.logs.isEmpty)

                Button {
                    supervisor.clearLogs()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .help("Clear the log")
                .disabled(supervisor.logs.isEmpty)
            }
        }
        .frame(minWidth: 560, minHeight: 320)
    }

    private var subtitle: String {
        switch supervisor.status {
        case .running(let port): return "Live on port \(port)"
        case .starting: return "Starting…"
        case .error: return "Not running"
        case .stopped: return "Stopped"
        }
    }
}

/// "[time] message": the time quiet, errors in the pen colour.
private struct LogLine: View {
    let line: String

    var body: some View {
        let (time, message) = split(line)
        let isError = message.contains("[stderr]") || message.localizedCaseInsensitiveContains("error")
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let time {
                Text(time).foregroundStyle(.tertiary)
            }
            Text(message).foregroundStyle(isError ? Color.scrawlCoral : .primary)
        }
        .font(.system(size: 11.5, design: .monospaced))
    }

    private func split(_ line: String) -> (String?, String) {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return (nil, line) }
        let time = String(line[line.index(after: line.startIndex)..<close])
        let rest = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return (time, rest)
    }
}
