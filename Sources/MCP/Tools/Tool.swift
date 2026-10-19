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

    var allParameters: [ToolParameter] {
        targetsDevice ? parameters + [.string("device", "Device serial (list_devices). Only needed with several devices.")] : parameters
    }
}

/// One property of a tool's input schema. Its allowed values and bounds are also what `Arguments`
/// checks, so each limit is written once.
struct ToolParameter: Sendable {
    enum Kind: String, Sendable { case string, number, integer, boolean }

    let name: String
    let kind: Kind
    let description: String
    var required = false
    /// Allowed values of a string.
    var values: [String]?
    /// Bounds of a number or integer.
    var range: ClosedRange<Double>?

    static func string(_ name: String, _ description: String, required: Bool = false, oneOf values: [String]? = nil) -> ToolParameter {
        ToolParameter(name: name, kind: .string, description: description, required: required, values: values)
    }

    static func number(_ name: String, _ description: String, required: Bool = false, range: ClosedRange<Double>? = nil) -> ToolParameter {
        ToolParameter(name: name, kind: .number, description: description, required: required, range: range)
    }

    static func integer(_ name: String, _ description: String, required: Bool = false, range: ClosedRange<Double>? = nil) -> ToolParameter {
        ToolParameter(name: name, kind: .integer, description: description, required: required, range: range)
    }

    static func boolean(_ name: String, _ description: String, required: Bool = false) -> ToolParameter {
        ToolParameter(name: name, kind: .boolean, description: description, required: required)
    }

    var schema: JSONValue {
        var schema: [String: JSONValue] = ["type": .string(kind.rawValue), "description": .string(description)]
        if let values { schema["enum"] = .array(values.map(JSONValue.string)) }
        if let range {
            schema["minimum"] = .double(range.lowerBound)
            schema["maximum"] = .double(range.upperBound)
        }
        return .object(schema)
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

/// Arguments of one call, read with type checks and the limits the tool declares. Models sometimes send
/// numbers and booleans as strings; those are accepted when they parse cleanly.
struct Arguments: Sendable {
    let values: [String: JSONValue]
    let parameters: [String: ToolParameter]

    init(values: [String: JSONValue], parameters: [ToolParameter] = []) {
        self.values = values
        self.parameters = Dictionary(parameters.map { ($0.name, $0) }) { first, _ in first }
    }

    func has(_ key: String) -> Bool { values[key].map { $0 != .null } ?? false }

    /// A string; for a parameter with allowed values, one of them.
    func string(_ key: String) throws -> String? {
        guard let value = values[key], value != .null else { return nil }
        guard let string = value.string else { throw ToolInputError("\(key) must be a string.") }
        if let allowed = parameters[key]?.values, !allowed.contains(string) {
            throw ToolInputError("\(key) must be one of: \(allowed.joined(separator: ", ")).")
        }
        return string
    }

    func double(_ key: String) throws -> Double? {
        guard let value = values[key], value != .null else { return nil }
        guard let number = value.double ?? value.string.flatMap({ Double($0.trimmed) }) else { throw ToolInputError("\(key) must be a number.") }
        if let range = parameters[key]?.range, !range.contains(number) {
            throw ToolInputError("\(key) must be from \(Self.format(range.lowerBound)) to \(Self.format(range.upperBound)).")
        }
        return number
    }

    func int(_ key: String) throws -> Int? {
        guard let number = try double(key) else { return nil }
        guard let value = Int(exactly: number) else { throw ToolInputError("\(key) must be a whole number.") }
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

    func requiredString(_ key: String) throws -> String { try require(string(key).flatMap { $0.isEmpty ? nil : $0 }, key) }
    func requiredDouble(_ key: String) throws -> Double { try require(double(key), key) }
    func requiredInt(_ key: String) throws -> Int { try require(int(key), key) }
    func requiredBool(_ key: String) throws -> Bool { try require(bool(key), key) }

    private func require<Value>(_ value: Value?, _ key: String) throws -> Value {
        guard let value else { throw ToolInputError("\(key) is required.") }
        return value
    }

    /// "1" rather than "1.0" for whole bounds.
    private static func format(_ bound: Double) -> String {
        Int(exactly: bound).map(String.init) ?? String(bound)
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
