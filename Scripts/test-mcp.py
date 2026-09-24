#!/usr/bin/env python3
"""Protocol test of the Oh My Android MCP server. Needs no device, so it runs in CI.

Usage: Scripts/test-mcp.py <path to ohmyandroid-mcp>
Checks both protocol eras (initialize handshake and per-request _meta), tool schemas, prompts,
errors, and that stdout carries nothing but JSON-RPC.
"""
import json
import subprocess
import sys

MODERN = {"io.modelcontextprotocol/protocolVersion": "2026-07-28", "io.modelcontextprotocol/clientCapabilities": {}}
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL", message)


def session(server, messages):
    """Sends all messages, closes stdin, returns responses by id. The server must answer before exiting."""
    lines = "".join(json.dumps(m) + "\n" for m in messages)
    out = subprocess.run([server], input=lines, capture_output=True, text=True, timeout=30).stdout
    responses = {}
    for line in out.splitlines():
        message = json.loads(line)  # every stdout line must be JSON
        check(message.get("jsonrpc") == "2.0", f"not JSON-RPC 2.0: {line[:80]}")
        responses[message.get("id")] = message
    return responses


def main(server):
    legacy = session(server, [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
        {"jsonrpc": "2.0", "id": 3, "method": "prompts/list"},
        {"jsonrpc": "2.0", "id": 4, "method": "prompts/get", "params": {"name": "debug_crash", "arguments": {"package": "com.example"}}},
        {"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "no_such_tool", "arguments": {}}},
        {"jsonrpc": "2.0", "id": 6, "method": "ping"},
        {"jsonrpc": "2.0", "id": 7, "method": "no/such/method"},
        {"jsonrpc": "2.0", "id": 8, "method": "initialize", "params": {"protocolVersion": "2099-01-01", "capabilities": {}}},
    ])
    init = legacy[1]["result"]
    check(init["protocolVersion"] == "2025-06-18", "initialize echoes a supported version")
    check(legacy[8]["result"]["protocolVersion"] == "2025-11-25", "initialize falls back to the latest legacy version")
    check(init["serverInfo"]["name"] == "oh-my-android", "serverInfo name")
    check("resultType" not in init, "legacy results carry no modern fields")

    tools = legacy[2]["result"]["tools"]
    names = [t["name"] for t in tools]
    check(len(names) == len(set(names)), "tool names are unique")
    check(len(tools) == 18, f"18 tools, got {len(tools)}")
    for tool in tools:
        schema = tool["inputSchema"]
        check(schema.get("type") == "object", f"{tool['name']}: schema type object")
        props = schema.get("properties", {})
        check(set(schema.get("required", [])) <= set(props), f"{tool['name']}: required names exist")
        for name, prop in props.items():
            check("type" in prop and prop.get("description"), f"{tool['name']}.{name}: type and description")
        annotations = tool["annotations"]
        check(isinstance(annotations.get("readOnlyHint"), bool), f"{tool['name']}: readOnlyHint")
        check(tool["description"] and len(tool["description"]) < 400, f"{tool['name']}: short description")
    size = sum(len(json.dumps({k: t[k] for k in ("name", "description", "inputSchema")}, separators=(",", ":"))) for t in tools)
    check(size < 14000, f"tool definitions stay small for the model ({size} chars)")

    check(len(legacy[3]["result"]["prompts"]) == 3, "3 prompts")
    check("com.example" in legacy[4]["result"]["messages"][0]["content"]["text"], "prompt argument is filled in")
    check(legacy[5]["error"]["code"] == -32602, "unknown tool is invalid params")
    check(legacy[6]["result"] == {}, "ping")
    check(legacy[7]["error"]["code"] == -32601, "unknown method")

    modern = session(server, [
        {"jsonrpc": "2.0", "id": "d", "method": "server/discover", "params": {"_meta": MODERN}},
        {"jsonrpc": "2.0", "id": "t", "method": "tools/list", "params": {"_meta": MODERN}},
        {"jsonrpc": "2.0", "id": "v", "method": "tools/list",
         "params": {"_meta": {**MODERN, "io.modelcontextprotocol/protocolVersion": "1999-01-01"}}},
        {"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": "unknown"}},
        "not json",
    ])
    discover = modern["d"]["result"]
    check(discover["supportedVersions"] == ["2026-07-28"], "discover lists modern versions")
    check(discover["resultType"] == "complete", "modern results carry resultType")
    check(discover["_meta"]["io.modelcontextprotocol/serverInfo"]["name"] == "oh-my-android", "modern serverInfo in _meta")
    listed = modern["t"]["result"]
    check(listed["ttlMs"] > 0 and listed["cacheScope"] == "public", "modern lists are cacheable")
    check([t["name"] for t in listed["tools"]] == names, "tool order is stable across eras")
    check(modern["v"]["error"]["code"] == -32022, "unsupported version error")
    check(modern["v"]["error"]["data"]["requested"] == "1999-01-01", "unsupported version names the request")
    check(modern[None]["error"]["code"] == -32700, "parse error")

    help_text = subprocess.run([server, "--help"], capture_output=True, text=True, timeout=10).stdout
    check("claude mcp add" in help_text, "--help shows setup")

    print(f"{len(tools)} tools, {size} chars of definitions. " + ("FAILED" if failures else "All checks passed."))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main(sys.argv[1])
