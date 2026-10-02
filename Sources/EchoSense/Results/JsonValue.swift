import Foundation

public enum JsonParsingError: LocalizedError {
    case invalidEncoding
    case invalidStructure

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "The selected value is not valid UTF-8 encoded JSON."
        case .invalidStructure:
            return "The selected value is not a valid JSON object."
        }
    }
}

public enum JsonValue: Equatable, Sendable {
    public struct ObjectEntry: Equatable, Sendable {
        public let key: String
        public let value: JsonValue

        public init(key: String, value: JsonValue) {
            self.key = key
            self.value = value
        }
    }

    case object([ObjectEntry])
    case array([JsonValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    public enum Kind: String, Sendable {
        case object
        case array
        case string
        case number
        case boolean
        case null

        public var displayName: String {
            switch self {
            case .object: return "Object"
            case .array: return "Array"
            case .string: return "String"
            case .number: return "Number"
            case .boolean: return "Boolean"
            case .null: return "Null"
            }
        }
    }

    public var kind: Kind {
        switch self {
        case .object: return .object
        case .array: return .array
        case .string: return .string
        case .number: return .number
        case .bool: return .boolean
        case .null: return .null
        }
    }

    public var isContainer: Bool {
        switch self {
        case .object, .array: return true
        default: return false
        }
    }

    public var childCount: Int {
        switch self {
        case .object(let entries): return entries.count
        case .array(let values): return values.count
        default: return 0
        }
    }

    public var summary: String {
        switch self {
        case .object(let entries):
            let count = entries.count
            return count == 1 ? "1 key" : "\(count) keys"
        case .array(let values):
            let count = values.count
            return count == 1 ? "1 item" : "\(count) items"
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }

    public func makeDetailRows() -> [JsonDetailRow] {
        switch self {
        case .object(let entries):
            return entries.enumerated().map { index, entry in
                JsonDetailRow(
                    id: UUID(),
                    key: .property(entry.key, index: index),
                    value: entry.value
                )
            }
        case .array(let values):
            return values.enumerated().map { index, value in
                JsonDetailRow(
                    id: UUID(),
                    key: .index(index),
                    value: value
                )
            }
        case .string, .number, .bool, .null:
            return []
        }
    }

    public func toOutlineNode(key: JsonOutlineNode.Key = .root) -> JsonOutlineNode {
        JsonOutlineNode(
            id: UUID(),
            key: key,
            value: self,
            children: childOutlineNodes(for: key)
        )
    }

    private func childOutlineNodes(for parent: JsonOutlineNode.Key) -> [JsonOutlineNode] {
        switch self {
        case .object(let entries):
            return entries.enumerated().map { index, entry in
                entry.value.toOutlineNode(
                    key: .property(entry.key, index: index)
                )
            }
        case .array(let values):
            return values.enumerated().map { offset, value in
                value.toOutlineNode(key: .index(offset))
            }
        case .string, .number, .bool, .null:
            return []
        }
    }

    public static func parse(from string: String) throws -> JsonValue {
        guard let data = string.data(using: .utf8) else {
            throw JsonParsingError.invalidEncoding
        }
        let options: JSONSerialization.ReadingOptions = [.fragmentsAllowed]
        let raw = try JSONSerialization.jsonObject(with: data, options: options)
        return try JsonValue.make(from: raw)
    }

    private static func make(from raw: Any) throws -> JsonValue {
        if raw is NSNull {
            return .null
        }

        if let dict = raw as? [String: Any] {
            let orderedKeys = dict.keys.sorted()
            let entries: [ObjectEntry] = orderedKeys.compactMap { key in
                guard let value = dict[key] else { return nil }
                guard let jsonValue = try? make(from: value) else { return nil }
                return ObjectEntry(key: key, value: jsonValue)
            }
            return .object(entries)
        }

        if let array = raw as? [Any] {
            let values = try array.map { try make(from: $0) }
            return .array(values)
        }

        if let string = raw as? String {
            return .string(string)
        }

        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            } else {
                return .number(number.stringValue)
            }
        }

        if let data = raw as? Data, let decoded = String(data: data, encoding: .utf8) {
            return .string(decoded)
        }

        throw JsonParsingError.invalidStructure
    }
}

public struct JsonDetailRow: Identifiable, Equatable, Sendable {
    public enum Key: Equatable, Sendable {
        case property(String, index: Int)
        case index(Int)

        public var breadcrumbTitle: String {
            switch self {
            case .property(let key, _): return key
            case .index(let value): return "[\(value)]"
            }
        }

        public var displayTitle: String {
            switch self {
            case .property(let key, _): return key
            case .index(let value): return "#\(value)"
            }
        }
    }

    public let id: UUID
    public let key: Key
    public let value: JsonValue

    public init(id: UUID, key: Key, value: JsonValue) {
        self.id = id
        self.key = key
        self.value = value
    }

    public var typeDescription: String { value.kind.displayName }

    public var preview: String { value.summary }
}

public struct JsonOutlineNode: Identifiable, Equatable, Sendable {
    public enum Key: Equatable, Sendable {
        case root
        case property(String, index: Int)
        case index(Int)

        public var displayTitle: String? {
            switch self {
            case .root: return nil
            case .property(let key, _): return key
            case .index(let value): return "[\(value)]"
            }
        }
    }

    public let id: UUID
    public let key: Key
    public let value: JsonValue
    public let children: [JsonOutlineNode]

    public init(id: UUID, key: Key, value: JsonValue, children: [JsonOutlineNode]) {
        self.id = id
        self.key = key
        self.value = value
        self.children = children
    }

    public var title: String {
        key.displayTitle ?? value.kind.displayName
    }

    public var subtitle: String {
        switch value.kind {
        case .object, .array:
            return value.summary
        default:
            return value.summary
        }
    }

    public var hasChildren: Bool { !children.isEmpty }

    /// A name that can follow a dot in a path: letters, digits and underscores, not starting with a digit.
    private static func isPlainName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, !("0"..."9").contains(first) else { return false }
        return name.unicodeScalars.allSatisfy { $0 == "_" || CharacterSet.alphanumerics.contains($0) }
    }

    public func jsonPath(parentPath: String = "$") -> String {
        switch key {
        case .root:
            return parentPath
        case .property(let name, _):
            if Self.isPlainName(name) { return "\(parentPath).\(name)" }
            let escaped = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            return "\(parentPath)['\(escaped)']"
        case .index(let idx):
            return "\(parentPath)[\(idx)]"
        }
    }
}

