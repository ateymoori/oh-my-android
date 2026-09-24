import Foundation

/// MCP server over stdio, dual-era:
/// - modern clients (2026-07-28) send the protocol version in every request's `_meta`; no handshake;
/// - legacy clients (2024-11-05 … 2025-11-25) open with `initialize`.
/// Requests run concurrently; `notifications/cancelled` stops one and suppresses its response.
actor MCPServer {
    static let modernVersions = ["2026-07-28"]
    static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    private let tools: [String: Tool]
    private let toolList: JSONValue
    private let environment: ToolEnvironment
    private let output: MessageWriter
    private var clientName: String?
    private var running: [JSONValue: Task<Void, Never>] = [:]

    init(environment: ToolEnvironment, output: MessageWriter) {
        self.environment = environment
        self.output = output
        tools = Dictionary(uniqueKeysWithValues: Catalog.tools.map { ($0.name, $0) })
        toolList = .array(Catalog.tools.map(\.definition))
    }

    static var serverInfo: JSONValue {
        [
            "name": "oh-my-android",
            "title": "Oh My Android",
            "version": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"),
            "websiteUrl": "https://github.com/ateymoori/oh-my-android",
        ]
    }

    private static let capabilities: JSONValue = ["tools": [:], "prompts": [:]]

    // MARK: - Messages

    func receive(_ line: Data) async {
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: line), let object = message.object else {
            await output.send(Self.errorResponse(id: .null, RPCError(code: -32700, message: "Parse error")))
            return
        }
        guard let method = object["method"]?.string else { return }  // a response; this server sends no requests
        let params = object["params"] ?? [:]
        guard let id = object["id"], id != .null else { return notification(method, params) }
        guard id.string != nil || id.double != nil else {
            await output.send(Self.errorResponse(id: .null, RPCError(code: -32600, message: "Invalid request id")))
            return
        }
        running[id] = Task { await self.respond(id: id, method: method, params: params) }
    }

    /// Waits for every request in flight: stdin closing is no reason to drop answers already owed.
    func finish() async {
        while let task = running.values.first { await task.value }
    }

    private func notification(_ method: String, _ params: JSONValue) {
        if method == "notifications/cancelled", let id = params["requestId"] {
            running.removeValue(forKey: id)?.cancel()
        }
    }

    private func respond(id: JSONValue, method: String, params: JSONValue) async {
        let response: JSONValue
        do {
            let modern = try Self.modernVersion(params)
            var result = try await handle(method, params, modern: modern != nil)
            if modern != nil, case .object(var fields) = result {
                fields["resultType"] = "complete"
                fields["_meta"] = ["io.modelcontextprotocol/serverInfo": Self.serverInfo]
                result = .object(fields)
            }
            response = ["jsonrpc": "2.0", "id": id, "result": result]
        } catch let error as RPCError {
            response = Self.errorResponse(id: id, error)
        } catch {
            response = Self.errorResponse(id: id, RPCError(code: -32603, message: error.localizedDescription))
        }
        guard running[id] != nil, !Task.isCancelled else { return }  // cancelled: send nothing
        await output.send(response)
        running[id] = nil  // only now: `finish` must not let the process exit before the answer is out
    }

    /// Protocol version from `_meta`, or nil for a legacy request. Unknown versions are refused.
    private static func modernVersion(_ params: JSONValue) throws -> String? {
        guard let version = params["_meta"]?["io.modelcontextprotocol/protocolVersion"]?.string else { return nil }
        guard modernVersions.contains(version) else {
            throw RPCError(code: -32022, message: "Unsupported protocol version",
                           data: ["supported": .array(modernVersions.map(JSONValue.string)), "requested": .string(version)])
        }
        return version
    }

    private func handle(_ method: String, _ params: JSONValue, modern: Bool) async throws -> JSONValue {
        if let name = params["_meta"]?["io.modelcontextprotocol/clientInfo"]?["name"]?.string { clientName = name }
        let cache: [String: JSONValue] = modern ? ["ttlMs": 3_600_000, "cacheScope": "public"] : [:]
        switch method {
        case "initialize":
            clientName = params["clientInfo"]?["name"]?.string ?? clientName
            let requested = params["protocolVersion"]?.string ?? ""
            return [
                "protocolVersion": .string(Self.legacyVersions.contains(requested) ? requested : Self.legacyVersions[0]),
                "capabilities": Self.capabilities,
                "serverInfo": Self.serverInfo,
                "instructions": .string(Catalog.instructions),
            ]
        case "server/discover":
            return .object([
                "supportedVersions": .array(Self.modernVersions.map(JSONValue.string)),
                "capabilities": Self.capabilities,
                "instructions": .string(Catalog.instructions),
            ].merging(cache) { value, _ in value })
        case "ping":
            return [:]
        case "tools/list":
            return .object(["tools": toolList].merging(cache) { value, _ in value })
        case "tools/call":
            return try await callTool(params)
        case "prompts/list":
            return .object(["prompts": .array(Catalog.prompts.map(\.definition))].merging(cache) { value, _ in value })
        case "prompts/get":
            guard let name = params["name"]?.string, let prompt = Catalog.prompts.first(where: { $0.name == name }) else {
                throw RPCError(code: -32602, message: "Unknown prompt: \(params["name"]?.string ?? "")")
            }
            let values = (params["arguments"]?.object ?? [:]).compactMapValues(\.string)
            return ["description": .string(prompt.description), "messages": prompt.messages(values)]
        default:
            throw RPCError(code: -32601, message: "Method not found: \(method)")
        }
    }

    private func callTool(_ params: JSONValue) async throws -> JSONValue {
        guard let name = params["name"]?.string, let tool = tools[name] else {
            throw RPCError(code: -32602, message: "Unknown tool: \(params["name"]?.string ?? "")")
        }
        let access = AgentSettings.access
        guard access >= tool.effect.requiredAccess else {
            return ToolResult.error(access == .off
                ? "Oh My Android: AI agent access is off. Ask the user to turn it on: Oh My Android menu bar icon → AI Agents."
                : "Oh My Android: \(name) changes the device, and agent access is Read only. Ask the user to choose Full control: Oh My Android menu bar icon → AI Agents."
            ).json
        }
        AgentSettings.recordUse(client: clientName)
        let call = ToolCall(arguments: Arguments(values: params["arguments"]?.object ?? [:]), environment: environment)
        do {
            return try await tool.run(call).json
        } catch {
            // Tool failures go back as results, so the model sees them and can correct itself.
            return ToolResult.error(error.localizedDescription).json
        }
    }

    private static func errorResponse(id: JSONValue, _ error: RPCError) -> JSONValue {
        var body: [String: JSONValue] = ["code": .int(error.code), "message": .string(error.message)]
        if let data = error.data { body["data"] = data }
        return ["jsonrpc": "2.0", "id": id, "error": .object(body)]
    }
}

struct RPCError: Error {
    let code: Int
    let message: String
    var data: JSONValue?
}

/// Writes one JSON message per line to stdout. Nothing else may ever go to stdout.
actor MessageWriter {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    func send(_ message: JSONValue) {
        guard var data = try? encoder.encode(message) else { return }
        data.append(0x0A)  // the encoder escapes newlines inside strings, so this is the only one
        do { try FileHandle.standardOutput.write(contentsOf: data) } catch { exit(0) }  // client is gone
    }
}
