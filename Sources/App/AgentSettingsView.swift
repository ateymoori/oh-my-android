import SwiftUI

/// Settings tab for the MCP server: access level, setup for each agent, and proof that it works.
struct AgentSettingsView: View {
    @AppStorage(AgentSettings.accessKey) private var access = AgentSettings.defaultAccess
    @AppStorage("agents.client") private var clientID = AgentClient.all[0].id
    @State private var copied = false

    private var client: AgentClient { AgentClient.all.first { $0.id == clientID } ?? AgentClient.all[0] }

    var body: some View {
        Form {
            Section {
                Picker("Agent access", selection: $access) {
                    ForEach(AgentAccess.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(access.detail).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Agent", selection: $clientID) {
                    ForEach(AgentClient.all) { Text($0.name).tag($0.id) }
                }
                Text(client.snippet)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
                HStack {
                    Text(client.hint).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let url = client.installURL, NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
                        Button("Add to \(client.name)") { NSWorkspace.shared.open(url) }
                    }
                    Button(copied ? "Copied" : "Copy", action: copy)
                }
            } header: {
                Text("Connect an agent")
            } footer: {
                Text("The agent starts the server when it needs it. Oh My Android does not have to be open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: clientID) { copied = false }

            Section {
                TimelineView(.periodic(from: .now, by: 15)) { _ in
                    LabeledContent("Last used", value: Self.lastUse)
                }
                LabeledContent("Tools") {
                    Link("What agents can do", destination: URL(string: "https://github.com/ateymoori/oh-my-android#ai-agents-mcp")!)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(client.snippet, forType: .string)
        copied = true
    }

    private static var lastUse: String {
        guard let use = AgentSettings.lastUse else { return "Not yet" }
        let when = use.date.formatted(.relative(presentation: .named))
        return use.client.map { "\(when) by \($0)" } ?? when
    }
}

/// How one AI agent adds an MCP server. All use the absolute path of the server inside this app.
struct AgentClient: Identifiable {
    let id: String
    let name: String
    let snippet: String
    let hint: String
    var installURL: URL?

    static let name = "oh-my-android"
    static let server = Bundle.main.bundleURL.appending(path: "Contents/MacOS/ohmyandroid-mcp").path

    static let all: [AgentClient] = [
        AgentClient(id: "claude-code", name: "Claude Code", snippet: "claude mcp add --scope user \(name) -- \(server.shellQuoted)",
                    hint: "Run in Terminal once. Works in every project."),
        AgentClient(id: "codex", name: "Codex CLI", snippet: "codex mcp add \(name) -- \(server.shellQuoted)",
                    hint: "Run in Terminal once."),
        AgentClient(id: "cursor", name: "Cursor", snippet: json(["mcpServers": [name: ["command": server]]]),
                    hint: "Or paste into ~/.cursor/mcp.json.",
                    installURL: URL(string: "cursor://anysphere.cursor-deeplink/mcp/install?name=\(name)&config=\(Data(json(["command": server]).utf8).base64EncodedString())")),
        AgentClient(id: "vscode", name: "VS Code", snippet: json(["servers": [name: ["type": "stdio", "command": server]]]),
                    hint: "Or paste into .vscode/mcp.json (Copilot agent mode).",
                    installURL: vscodeURL),
        AgentClient(id: "claude-desktop", name: "Claude Desktop", snippet: json(["mcpServers": [name: ["command": server]]]),
                    hint: "Settings → Developer → Edit Config, merge, restart Claude."),
        AgentClient(id: "other", name: "Other", snippet: json(["mcpServers": [name: ["command": server]]]),
                    hint: "Standard stdio config: Windsurf, Gemini CLI, JetBrains AI, Zed and more."),
    ]

    private static var vscodeURL: URL? {
        let config = json(["name": name, "command": server])
        return config.addingPercentEncoding(withAllowedCharacters: .alphanumerics).flatMap { URL(string: "vscode:mcp/install?\($0)") }
    }

    private static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
