import Foundation

/// One MCP tool: its contract for the model and the code that runs it.
struct Tool: Sendable {
    /// What the tool does to the device. Sets both the MCP annotations and the access level it needs.
    enum Effect: Sendable {
        /// Only looks.
        case read
        /// Changes state the user can easily change back (a tap, a setting).
        case control
        /// Can lose data or replace an app.
        case destructive

        var requiredAccess: AgentAccess { self == .read ? .readOnly : .full }
    }

    let name: String
    let title: String
    let description: String
    let effect: Effect
    /// Same call twice has no extra effect (setting a value, not toggling it).
    var idempotent = false
    /// Adds the shared optional `device` parameter.
    var targetsDevice = true
    var parameters: [ToolParameter] = []
    let run: @Sendable (ToolCall) async throws -> ToolResult

    var definition: JSONValue {
        var properties: [String: JSONValue] = [:]
        for parameter in allParameters { properties[parameter.name] = parameter.schema }
        var schema: [String: JSONValue] = ["type": "object", "properties": .object(properties), "additionalProperties": false]
        let required = allParameters.filter(\.required).map { JSONValue.string($0.name) }
        if !required.isEmpty { schema["required"] = .array(required) }
        return [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": .object(schema),
            "annotations": [
                "readOnlyHint": .bool(effect == .read),
                "destructiveHint": .bool(effect == .destructive),
                "idempotentHint": .bool(effect == .read || idempotent),
                "openWorldHint": false,
            ],
        ]
    }

    private var allParameters: [ToolParameter] {
        targetsDevice ? parameters + [.string("device", "Device serial (list_devices). Only needed with several devices.")] : parameters
    }
}

/// One property of a tool's input schema.
struct ToolParameter: Sendable {
    let name: String
    let schema: JSONValue
    let required: Bool

    static func string(_ name: String, _ description: String, required: Bool = false, oneOf values: [String]? = nil) -> ToolParameter {
        var schema: [String: JSONValue] = ["type": "string", "description": .string(description)]
        if let values { schema["enum"] = .array(values.map(JSONValue.string)) }
        return ToolParameter(name: name, schema: .object(schema), required: required)
    }

    static func number(_ name: String, _ description: String, required: Bool = false, range: ClosedRange<Double>? = nil) -> ToolParameter {
        ToolParameter(name: name, schema: .object(bounded(["type": "number", "description": .string(description)], range)), required: required)
    }

    static func integer(_ name: String, _ description: String, required: Bool = false, range: ClosedRange<Double>? = nil) -> ToolParameter {
        ToolParameter(name: name, schema: .object(bounded(["type": "integer", "description": .string(description)], range)), required: required)
    }

    static func boolean(_ name: String, _ description: String, required: Bool = false) -> ToolParameter {
        ToolParameter(name: name, schema: ["type": "boolean", "description": .string(description)], required: required)
    }

    private static func bounded(_ schema: [String: JSONValue], _ range: ClosedRange<Double>?) -> [String: JSONValue] {
        guard let range else { return schema }
        var schema = schema
        schema["minimum"] = .double(range.lowerBound)
        schema["maximum"] = .double(range.upperBound)
        return schema
    }
}

/// What a tool returns: text for the model, optionally an image.
struct ToolResult: Sendable {
    enum Content: Sendable {
        case text(String)
        case image(Data, mimeType: String)
    }

    var content: [Content]
    var isError = false

    static func text(_ text: String) -> ToolResult { ToolResult(content: [.text(text)]) }
    static func error(_ text: String) -> ToolResult { ToolResult(content: [.text(text)], isError: true) }

    var json: JSONValue {
        let blocks: [JSONValue] = content.map { block in
            switch block {
            case .text(let text): ["type": "text", "text": .string(text)]
            case .image(let data, let mimeType): ["type": "image", "data": .string(data.base64EncodedString()), "mimeType": .string(mimeType)]
            }
        }
        var result: [String: JSONValue] = ["content": .array(blocks)]
        if isError { result["isError"] = true }
        return .object(result)
    }
}

/// Wrong or missing argument. Returned to the model as a tool error so it can correct the call.
struct ToolInputError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Arguments of one call, read with type checks. Models sometimes send numbers and booleans as strings;
/// those are accepted when they parse cleanly.
struct Arguments: Sendable {
    let values: [String: JSONValue]

    func has(_ key: String) -> Bool { values[key].map { $0 != .null } ?? false }

    func string(_ key: String) throws -> String? {
        guard let value = values[key], value != .null else { return nil }
        guard let string = value.string else { throw ToolInputError("\(key) must be a string.") }
        return string
    }

    func requiredString(_ key: String) throws -> String {
        guard let value = try string(key), !value.isEmpty else { throw ToolInputError("\(key) is required.") }
        return value
    }

    func double(_ key: String, in range: ClosedRange<Double>? = nil) throws -> Double? {
        guard let value = values[key], value != .null else { return nil }
        guard let number = value.double ?? value.string.flatMap({ Double($0.trimmed) }) else { throw ToolInputError("\(key) must be a number.") }
        if let range, !range.contains(number) { throw ToolInputError("\(key) must be from \(range.lowerBound) to \(range.upperBound).") }
        return number
    }

    func int(_ key: String, in range: ClosedRange<Int>? = nil) throws -> Int? {
        guard let number = try double(key) else { return nil }
        guard number.rounded() == number, let value = Int(exactly: number) else { throw ToolInputError("\(key) must be a whole number.") }
        if let range, !range.contains(value) { throw ToolInputError("\(key) must be from \(range.lowerBound) to \(range.upperBound).") }
        return value
    }

    func bool(_ key: String) throws -> Bool? {
        guard let value = values[key], value != .null else { return nil }
        if let bool = value.bool { return bool }
        switch value.string?.lowercased() {
        case "true"?: return true
        case "false"?: return false
        default: throw ToolInputError("\(key) must be true or false.")
        }
    }

    func choice(_ key: String, _ allowed: [String]) throws -> String? {
        guard let value = try string(key) else { return nil }
        guard allowed.contains(value) else { throw ToolInputError("\(key) must be one of: \(allowed.joined(separator: ", ")).") }
        return value
    }
}

/// Everything a running tool gets.
struct ToolCall: Sendable {
    let arguments: Arguments
    let environment: ToolEnvironment

    /// Device named by the `device` argument, or the only (or last used) ready device.
    func device() async throws -> DeviceContext {
        try await environment.context(serial: try arguments.string("device"))
    }
}
