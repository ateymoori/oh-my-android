import Foundation

// ohmyandroid-mcp: the Oh My Android MCP server. An AI agent starts it and talks JSON-RPC over stdin/stdout.

let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
let help = """
ohmyandroid-mcp \(version): MCP server of Oh My Android (https://github.com/ateymoori/oh-my-android)

AI agents start this program themselves; you do not run it by hand. Add it to your agent:
  Claude Code:  claude mcp add oh-my-android -- \(executable.shellQuoted)
  Codex CLI:    codex mcp add oh-my-android -- \(executable.shellQuoted)
  JSON config:  { "mcpServers": { "oh-my-android": { "command": "\(executable)" } } }

Needs adb: ANDROID_HOME, ~/Library/Android/sdk, Homebrew, or the SDK chosen in Oh My Android → Settings.
Access (Off, Read only, Full control): Oh My Android menu bar icon → AI Agents.
"""

let options = Set(CommandLine.arguments.dropFirst())
if options.contains("--version") {
    print(version)
    exit(0)
}
if options.contains("--help") || options.contains("-h") || isatty(STDIN_FILENO) == 1 {
    print(help)
    exit(0)
}

signal(SIGPIPE, SIG_IGN)  // a closed client pipe becomes a write error, handled by exiting
let sdk = AndroidSDK.locate(defaults: UserDefaults(suiteName: AgentSettings.domainName) ?? .standard)
let server = MCPServer(environment: ToolEnvironment(sdk: sdk), output: MessageWriter())

// One message per line. Split on LF only: JSON strings may hold other line separators such as U+2028.
var line = Data()
for try await byte in FileHandle.standardInput.bytes {
    if byte == 0x0A {
        if !line.isEmpty { await server.receive(line) }
        line.removeAll(keepingCapacity: true)
    } else {
        line.append(byte)
    }
}
if !line.isEmpty { await server.receive(line) }
await server.finish()
exit(0)
