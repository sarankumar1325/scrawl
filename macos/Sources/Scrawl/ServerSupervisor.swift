import Foundation
import Combine
import AppKit

public enum ServerStatus: Equatable {
    case stopped
    case starting
    case running(port: Int)
    case error(String)
    
    public var description: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting Server..."
        case .running(let port): return "MCP Live on :\(port)"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

@MainActor
public final class ServerSupervisor: ObservableObject {
    public static let shared = ServerSupervisor()
    
    @Published public private(set) var status: ServerStatus = .stopped
    @Published public private(set) var logs: [String] = []
    @Published public var port: Int = 3779
    @Published public var dataDirectory: URL
    @Published public var nodeBinaryPath: String = ""
    /// A short confirmation the main window shows as a toast ("MCP URL copied").
    @Published public private(set) var toast: String?
    /// Bumped by File ▸ New Board; the canvas creates a board each time it changes.
    @Published public private(set) var newBoardRequests = 0
    private var toastTask: Task<Void, Never>?
    
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var healthCheckTask: Task<Void, Never>?
    private var isIntentionalShutdown = false
    private var retryCount = 0
    
    private let userDefaults = UserDefaults.standard
    private let portKey = "doodlebug.server.port"
    private let dataDirKey = "doodlebug.server.datadir"
    private let nodePathKey = "doodlebug.server.nodepath"

    private init() {
        // Settings saved by the app's former name (bundle id com.linework.mac) carry over.
        let legacyDefaults = UserDefaults(suiteName: "com.linework.mac")

        // Load saved preferences or defaults
        let savedPort = userDefaults.integer(forKey: portKey)
        let legacyPort = legacyDefaults?.integer(forKey: "linework.server.port") ?? 0
        self.port = savedPort > 0 ? savedPort : (legacyPort > 0 ? legacyPort : 3779)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let defaultDir = docs.appendingPathComponent("Scrawl")
        // Folders from the app's earlier names, newest first; boards stay where they are.
        let formerDirs = ["Doodlebug", "Linework", "Excalidraw Boards"].map { docs.appendingPathComponent($0) }

        if let savedDir = userDefaults.string(forKey: dataDirKey) ?? legacyDefaults?.string(forKey: "linework.server.datadir") {
            self.dataDirectory = URL(fileURLWithPath: savedDir)
        } else if FileManager.default.fileExists(atPath: defaultDir.path) {
            self.dataDirectory = defaultDir
        } else if let former = formerDirs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            self.dataDirectory = former
        } else {
            self.dataDirectory = defaultDir
        }

        let legacyNode = legacyDefaults?.string(forKey: "linework.server.nodepath")
        if let savedNode = userDefaults.string(forKey: nodePathKey) ?? legacyNode, !savedNode.isEmpty {
            self.nodeBinaryPath = savedNode
        } else {
            self.nodeBinaryPath = Self.discoverNodeBinary() ?? ""
        }
    }
    
    public var mcpEndpointURL: URL {
        URL(string: "http://localhost:\(port)/mcp")!
    }
    
    public var webAppURL: URL {
        URL(string: "http://localhost:\(port)")!
    }
    
    public func updatePort(_ newPort: Int) {
        guard newPort != port, newPort > 1024, newPort < 65535 else { return }
        port = newPort
        userDefaults.set(newPort, forKey: portKey)
        restart()
    }
    
    public func updateDataDirectory(_ url: URL) {
        dataDirectory = url
        userDefaults.set(url.path, forKey: dataDirKey)
        restart()
    }
    
    public func updateNodeBinaryPath(_ path: String) {
        nodeBinaryPath = path
        userDefaults.set(path, forKey: nodePathKey)
        restart()
    }
    
    public func freePort(targetPort: Int? = nil) {
        let p = targetPort ?? port
        appendLog("[Supervisor] Port \(p) will not be freed automatically; another application may own it.")
    }
    
    public func start() {
        guard process == nil else { return }
        status = .starting
        appendLog("[Supervisor] Initializing engine on port \(port)...")
        
        // 1. Ensure data directory exists
        do {
            try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            appendLog("[Supervisor] Storage directory ready: \(dataDirectory.path)")
        } catch {
            let msg = "Failed to create data directory at \(dataDirectory.path): \(error.localizedDescription)"
            appendLog("[Supervisor] \(msg)")
            status = .error(msg)
            return
        }
        
        // Find node executable. A port conflict is reported by the server;
        // never terminate an unrelated listener.
        let nodeExec: String
        if !nodeBinaryPath.isEmpty, FileManager.default.isExecutableFile(atPath: nodeBinaryPath) {
            nodeExec = nodeBinaryPath
        } else if let detected = Self.discoverNodeBinary() {
            nodeExec = detected
            self.nodeBinaryPath = detected
        } else {
            let msg = "Node.js executable could not be found. Please specify it in Settings."
            appendLog("[Supervisor] \(msg)")
            status = .error(msg)
            return
        }
        
        // 4. Find application bundle / server script
        guard let appRoot = Self.locateAppRoot() else {
            let msg = "Could not locate dist/server/index.js. Ensure project assets are built."
            appendLog("[Supervisor] \(msg)")
            status = .error(msg)
            return
        }
        
        let serverScript = appRoot.appendingPathComponent("dist/server/index.js").path
        guard FileManager.default.fileExists(atPath: serverScript) else {
            let msg = "Server script missing at \(serverScript)."
            appendLog("[Supervisor] \(msg)")
            status = .error(msg)
            return
        }
        
        appendLog("[Supervisor] Launching server with \(nodeExec) at \(serverScript)")
        isIntentionalShutdown = false
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: nodeExec)
        proc.arguments = [serverScript]
        proc.currentDirectoryURL = appRoot
        proc.standardInput = FileHandle.nullDevice
        
        var env = ProcessInfo.processInfo.environment
        env["PORT"] = String(port)
        env["DATA_DIR"] = dataDirectory.path
        env["PUBLIC_URL"] = "http://localhost:\(port)"
        env["ALLOWED_HOSTS"] = "*"
        env["NODE_ENV"] = "production"
        proc.environment = env
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        
        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let data = outHandle.availableData
                guard !data.isEmpty else { break }
                if let text = String(data: data, encoding: .utf8) {
                    Task { @MainActor in
                        self?.appendLog(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        }
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            while true {
                let data = errHandle.availableData
                guard !data.isEmpty else { break }
                if let text = String(data: data, encoding: .utf8) {
                    Task { @MainActor in
                        self?.appendLog("[stderr] " + text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        }
        
        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                self?.handleTermination(process: p, exitCode: p.terminationStatus)
            }
        }
        
        do {
            try proc.run()
            self.process = proc
            self.outputPipe = outPipe
            self.errorPipe = errPipe
            
            pollHealthCheck(targetPort: port)
        } catch {
            let msg = "Failed to launch Node process: \(error.localizedDescription)"
            appendLog("[Supervisor] \(msg)")
            status = .error(msg)
        }
    }
    
    private func pollHealthCheck(targetPort: Int) {
        healthCheckTask?.cancel()
        healthCheckTask = Task { [weak self] in
            let healthUrl = URL(string: "http://localhost:\(targetPort)/healthz")!
            var attempts = 0
            
            while attempts < 40 {
                if Task.isCancelled { return }
                guard let self = self, let proc = self.process, proc.isRunning else {
                    return
                }
                
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                
                do {
                    var req = URLRequest(url: healthUrl)
                    req.timeoutInterval = 1.0
                    let (data, response) = try await URLSession.shared.data(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200,
                       String(data: data, encoding: .utf8)?.contains("ok") == true {
                        self.retryCount = 0
                        self.status = .running(port: targetPort)
                        self.appendLog("[Supervisor] Healthcheck passed. MCP Server online at \(self.mcpEndpointURL.absoluteString)")
                        return
                    }
                } catch {
                    // Waiting for server to finish starting
                }
                attempts += 1
            }
            
            if case .starting = self?.status {
                self?.status = .error("Server started on port \(targetPort) but health check timed out.")
            }
        }
    }
    
    public func stop() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
        isIntentionalShutdown = true
        
        guard let proc = process else {
            status = .stopped
            return
        }
        
        appendLog("[Supervisor] Stopping server...")
        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()
        
        proc.terminate()
        
        DispatchQueue.global().async {
            let deadline = DispatchTime.now() + 1.2
            while proc.isRunning && DispatchTime.now() < deadline {
                usleep(50_000)
            }
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
        
        self.process = nil
        self.outputPipe = nil
        self.errorPipe = nil
        self.status = .stopped
    }
    
    public func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isIntentionalShutdown = false
            self?.start()
        }
    }
    
    public func forceResetAndRestart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.retryCount = 0
            self?.isIntentionalShutdown = false
            self?.start()
        }
    }
    
    private func handleTermination(process terminated: Process, exitCode: Int32) {
        // A delayed callback from an old process must not stop a newer one.
        guard process === terminated else { return }
        process = nil
        healthCheckTask?.cancel()
        healthCheckTask = nil
        
        appendLog("[Supervisor] Process exited with status code \(exitCode)")
        
        if isIntentionalShutdown {
            status = .stopped
            return
        }
        
        if exitCode == 98 {
            status = .error("Port \(port) is already in use by another application. Free the port or change it in Settings.")
            return
        }
        
        if retryCount < 1 {
            retryCount += 1
            appendLog("[Supervisor] Unexpected exit. Attempting automatic recovery (attempt \(retryCount))...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.start()
            }
            return
        }
        
        retryCount = 0
        status = .error("Server terminated (exit code \(exitCode)). Restart Scrawl or check Settings.")
    }
    
    public func clearLogs() {
        logs.removeAll()
    }
    
    private func appendLog(_ message: String) {
        guard !message.isEmpty else { return }
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }
    
    public func copyMcpUrlToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mcpEndpointURL.absoluteString, forType: .string)
        showToast("MCP URL copied")
    }

    public func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            if !Task.isCancelled { toast = nil }
        }
    }

    public func requestNewBoard() {
        newBoardRequests += 1
    }
    
    public func revealDataDirectory() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dataDirectory.path)
    }
    
    // MARK: - Auto Discovery
    
    public static func discoverNodeBinary() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        
        var candidates: [String] = []
        
        // Check nvm versions
        let nvmVersionsDir = "\(home)/.nvm/versions/node"
        if let contents = try? fm.contentsOfDirectory(atPath: nvmVersionsDir) {
            for ver in contents.sorted().reversed() {
                candidates.append("\(nvmVersionsDir)/\(ver)/bin/node")
            }
        }
        
        // Homebrew (Apple Silicon & Intel)
        candidates.append("/opt/homebrew/bin/node")
        candidates.append("/usr/local/bin/node")
        
        // fnm
        candidates.append("\(home)/.local/share/fnm/current/bin/node")
        candidates.append("\(home)/.fnm/current/bin/node")
        
        // volta
        candidates.append("\(home)/.volta/bin/node")
        
        // asdf
        candidates.append("\(home)/.asdf/shims/node")
        
        // System
        candidates.append("/usr/bin/node")
        
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        let pipe = Pipe()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-ilc", "which node"]
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !out.isEmpty, fm.isExecutableFile(atPath: out) {
            return out
        }
        
        return nil
    }
    
    public static func locateAppRoot() -> URL? {
        let fm = FileManager.default
        
        // 1. Check if bundled inside .app/Contents/Resources/app
        if let resourceURL = Bundle.main.resourceURL {
            let bundledApp = resourceURL.appendingPathComponent("app")
            if fm.fileExists(atPath: bundledApp.appendingPathComponent("dist/server/index.js").path) {
                return bundledApp
            }
        }
        
        // 2. Check current working directory or relative to executable
        let currentDir = URL(fileURLWithPath: fm.currentDirectoryPath)
        let candidates = [
            currentDir,
            currentDir.appendingPathComponent("excalidraw-boards"),
            currentDir.deletingLastPathComponent(),
            currentDir.deletingLastPathComponent().deletingLastPathComponent()
        ]
        
        for candidate in candidates {
            let serverFile = candidate.appendingPathComponent("dist/server/index.js").path
            if fm.fileExists(atPath: serverFile) {
                return candidate
            }
        }
        
        return nil
    }
}
