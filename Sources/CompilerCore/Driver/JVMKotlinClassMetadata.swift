import Foundation

struct JVMKotlinClassMetadata {
    let kind: Int
    let classFlags: Int
    let companion: String?
    let typeParameters: [JVMTypeParameter]
    let constructors: [JVMKotlinConstructorInfo]
    let functions: [JVMKotlinFunctionInfo]
    let properties: [JVMKotlinPropertyInfo]

    private var classKind: Int { (classFlags >> 6) & 7 }
    var isObject: Bool { classKind == 5 || isCompanion }
    var isCompanion: Bool { classKind == 6 }
    var isFileFacade: Bool { kind == 2 || kind == 5 }
}

struct JVMKotlinConstructorInfo {
    let descriptor: String?
    let flags: Int
    let parameters: [JVMKotlinParameterInfo]

    var isPublic: Bool { (flags >> 1) & 7 == 3 }
    var isProtected: Bool { (flags >> 1) & 7 == 2 }
}

struct JVMKotlinFunctionInfo {
    let name: String
    let jvmName: String
    let descriptor: String?
    let flags: Int
    let typeParameters: [JVMTypeParameter]
    let receiver: JVMKotlinType?
    let parameters: [JVMKotlinParameterInfo]
    let result: JVMKotlinType

    var isPublic: Bool { (flags >> 1) & 7 == 3 }
    var isProtected: Bool { (flags >> 1) & 7 == 2 }
    var isAbstract: Bool { (flags >> 4) & 3 == 2 }
    var isOperator: Bool { flags & 256 != 0 }
    var isInfix: Bool { flags & 512 != 0 }
    var isSuspend: Bool { flags & 8192 != 0 }
}

struct JVMKotlinParameterInfo {
    let name: String
    let type: JVMKotlinType
    let varargType: JVMKotlinType?
    let hasDefault: Bool
}

struct JVMKotlinPropertyInfo {
    let name: String
    let type: JVMKotlinType
    let flags: Int
    let getter: String?
    let setter: String?

    var isPublic: Bool { (flags >> 1) & 7 == 3 }
    var isProtected: Bool { (flags >> 1) & 7 == 2 }
    var isAbstract: Bool { (flags >> 4) & 3 == 2 }
    var isMutable: Bool { flags & 256 != 0 && setter != nil }
}

/// Kotlin's JVM annotation stores a length-prefixed string table followed by
/// a Class or Package protobuf. Keep the reader independent of the compiler
/// JAR so reading classpath declarations never runs dependency code.
extension JVMKotlinClassMetadata {
    static func read(_ annotation: JVMAnnotation) throws -> Self? {
        func value(_ key: String) -> JVMAnnotationValue? {
            annotation.values.first { $0.0 == key }?.1
        }
        func strings(_ key: String) -> [String] {
            guard case let .array(values) = value(key) else { return [] }
            return values.compactMap { if case let .constant(.string(text)) = $0 { text } else { nil } }
        }
        let kind: Int
        if case let .constant(.int(raw)) = value("k") { kind = Int(raw) } else { kind = 1 }
        guard [1, 2, 5].contains(kind), !strings("d1").isEmpty else { return nil }
        var stream = JVMMetadataWire(bytes: decode(strings("d1"))[...])
        let stringTable = try JVMMetadataMessage(stream.lengthDelimited())
        let names = try resolveStrings(strings("d2"), table: stringTable)
        let message = try JVMMetadataMessage(stream.remaining)
        let decoder = try JVMKotlinMetadataTypes(names: names, table: message.message(30))
        let isClass = kind == 1
        let parameters = isClass ? try message.messages(5).map(decoder.typeParameter) : []
        let constructors: [JVMKotlinConstructorInfo] = isClass ? try message.messages(8).map { constructor in
            let descriptor = try constructor.message(100)?.integer(2).map(decoder.name)
            return JVMKotlinConstructorInfo(descriptor: descriptor, flags: constructor.integer(1) ?? 6,
                parameters: try constructor.messages(2).map(decoder.parameter))
        } : []
        let functions = try message.messages(isClass ? 9 : 3).compactMap { function -> JVMKotlinFunctionInfo? in
            // Context receivers require an additional JVM argument per receiver.
            guard function.fields[10] == nil, function.fields[11] == nil else { return nil }
            let scope = try function.message(30).map { try JVMKotlinMetadataTypes(names: names, table: $0) } ?? decoder
            let name = try scope.name(function.integer(2))
            let signature = try function.message(100)
            let flags = function.integer(9) ?? function.integer(1).map { ($0 & 63) | (($0 >> 8) << 6) } ?? 6
            let result = try scope.requiredType(function, field: 3, indexField: 7)
            return JVMKotlinFunctionInfo(
                name: name, jvmName: try signature?.integer(1).map(scope.name) ?? name,
                descriptor: try signature?.integer(2).map(scope.name), flags: flags,
                typeParameters: try function.messages(4).map(scope.typeParameter),
                receiver: try scope.type(function, field: 5, indexField: 8),
                parameters: try function.messages(6).map(scope.parameter), result: result
            )
        }
        let properties = try message.messages(isClass ? 10 : 4).compactMap { property -> JVMKotlinPropertyInfo? in
            guard property.fields[5] == nil, property.fields[10] == nil,
                  property.fields[12] == nil, property.fields[13] == nil else { return nil }
            let signature = try property.message(100)
            let getter = try signature?.message(3)?.integer(1).map(decoder.name)
            let setter = try signature?.message(4)?.integer(1).map(decoder.name)
            let flags = property.integer(11) ?? property.integer(1).map { ($0 & 63) | (($0 >> 8) << 6) } ?? 518
            return JVMKotlinPropertyInfo(name: try decoder.name(property.integer(2)),
                type: try decoder.requiredType(property, field: 3, indexField: 9), flags: flags,
                getter: getter, setter: setter)
        }
        return Self(kind: kind, classFlags: isClass ? message.integer(1) ?? 6 : 0,
                    companion: isClass ? try message.integer(4).map(decoder.name) : nil,
                    typeParameters: parameters, constructors: constructors, functions: functions, properties: properties)
    }

    private static func decode(_ strings: [String]) -> [UInt8] {
        let units = strings.flatMap { $0.utf16 }
        guard let marker = units.first else { return [] }
        if marker == 0 { return units.dropFirst().map { UInt8(truncatingIfNeeded: $0) } }
        // The legacy encoding stores seven payload bits per code unit.
        var buffer: UInt16 = 0
        var bits = 0
        var result: [UInt8] = []
        for unit in units.dropFirst(marker == 0xFFFF ? 1 : 0) {
            buffer |= ((unit &- 1) & 0x7F) << bits
            bits += 7
            if bits >= 8 {
                result.append(UInt8(truncatingIfNeeded: buffer))
                buffer >>= 8
                bits -= 8
            }
        }
        return result
    }

    private static func resolveStrings(_ strings: [String], table: JVMMetadataMessage) throws -> [String] {
        // The predefined indices are part of Kotlin's JVM metadata format.
        let builtin = [
            "Any", "Nothing", "Unit", "Throwable", "Number", "Byte", "Double", "Float", "Int",
            "Long", "Short", "Boolean", "Char", "CharSequence", "String", "Comparable", "Enum",
            "Array", "ByteArray", "DoubleArray", "FloatArray", "IntArray", "LongArray", "ShortArray",
            "BooleanArray", "CharArray", "Cloneable", "Annotation", "collections/Iterable",
            "collections/MutableIterable", "collections/Collection", "collections/MutableCollection",
            "collections/List", "collections/MutableList", "collections/Set", "collections/MutableSet",
            "collections/Map", "collections/MutableMap", "collections/Map.Entry", "collections/MutableMap.MutableEntry",
            "collections/Iterator", "collections/MutableIterator", "collections/ListIterator", "collections/MutableListIterator",
        ]
        var names: [String] = []
        for record in try table.messages(1) {
            let count = record.integer(1) ?? 1
            guard count > 0, count <= strings.count - names.count else { throw JVMClassReader.Invalid() }
            let substring = try record.integers(4)
            let replacements = try record.integers(5)
            for _ in 0..<count {
                let source: String
                if let literal = record.bytes(6) { source = String(decoding: literal, as: UTF8.self) }
                else if let index = record.integer(2), builtin.indices.contains(index) { source = "kotlin/" + builtin[index] }
                else { source = strings[names.count] }
                var units = Array(source.utf16)
                if substring.count >= 2, substring[0] <= substring[1], substring[1] <= units.count {
                    units = Array(units[substring[0]..<substring[1]])
                }
                if replacements.count >= 2, let old = UInt16(exactly: replacements[0]),
                   let new = UInt16(exactly: replacements[1]) {
                    units = units.map { $0 == old ? new : $0 }
                }
                let operation = record.integer(3) ?? 0
                if operation == 2, units.count >= 2 { units = Array(units.dropFirst().dropLast()) }
                var resolved = String(decoding: units, as: UTF16.self)
                if operation == 1 || operation == 2 { resolved = resolved.replacingOccurrences(of: "$", with: ".") }
                names.append(resolved)
            }
        }
        names.append(contentsOf: strings.dropFirst(names.count))
        return names
    }
}

private struct JVMKotlinMetadataTypes {
    let names: [String]
    let entries: [JVMMetadataMessage]
    let firstNullable: Int

    init(names: [String], table: JVMMetadataMessage?) throws {
        self.names = names
        entries = try table?.messages(1) ?? []
        firstNullable = table?.integer(2) ?? Int.max
    }

    func name(_ index: Int?) throws -> String {
        guard let index, names.indices.contains(index) else { throw JVMClassReader.Invalid() }
        return names[index]
    }

    func requiredType(_ node: JVMMetadataMessage, field: Int, indexField: Int) throws -> JVMKotlinType {
        guard let type = try type(node, field: field, indexField: indexField) else { throw JVMClassReader.Invalid() }
        return type
    }

    func types(_ node: JVMMetadataMessage, field: Int, indexField: Int) throws -> [JVMKotlinType] {
        try node.messages(field).map { try parseType($0, nullable: false, depth: 0) }
            + node.integers(indexField).map { try indexedType($0, depth: 0) }
    }

    func type(_ node: JVMMetadataMessage, field: Int, indexField: Int, depth: Int = 0) throws -> JVMKotlinType? {
        if let message = try node.message(field) { return try parseType(message, nullable: false, depth: depth) }
        if let index = node.integer(indexField) { return try indexedType(index, depth: depth) }
        return nil
    }

    private func indexedType(_ index: Int, depth: Int) throws -> JVMKotlinType {
        guard entries.indices.contains(index) else { throw JVMClassReader.Invalid() }
        return try parseType(entries[index], nullable: index >= firstNullable, depth: depth)
    }

    private func parseType(_ message: JVMMetadataMessage, nullable: Bool, depth: Int) throws -> JVMKotlinType {
        guard depth < 64 else { throw JVMClassReader.Invalid() }
        let isNullable = nullable || message.integer(3) == 1
        let type: JVMKotlinType
        if let index = message.integer(7) {
            type = .parameter(index, nullable: isNullable, definitelyNotNull: false)
        } else if let index = message.integer(9) {
            // Some compiler versions encode local parameter references by name.
            type = .named(try name(index), [], nullable: isNullable)
        } else {
            let qualified = try name(message.integer(6) ?? message.integer(12))
            let args = try message.messages(2).map {
                JVMKotlinTypeArgument(type: try self.type($0, field: 2, indexField: 3, depth: depth + 1),
                                      variance: $0.integer(1) ?? 2)
            }
            let binary = qualified.replacingOccurrences(of: ".", with: "$")
            let functionPrefix = "kotlin/Function"
            if qualified.hasPrefix(functionPrefix), Int(qualified.dropFirst(functionPrefix.count)) != nil,
               args.allSatisfy({ $0.type != nil }), let result = args.last?.type {
                let extensionType = try message.messages(100).contains { try name($0.integer(1)) == "kotlin/ExtensionFunctionType" }
                var parameters = args.dropLast().compactMap(\.type)
                let receiver = extensionType && !parameters.isEmpty ? parameters.removeFirst() : nil
                let isSuspend = (message.integer(1) ?? 0) & 1 != 0
                if isSuspend, case .named("kotlin/coroutines/Continuation", let arguments, _) = parameters.last,
                   let suspendResult = arguments.first?.type {
                    parameters.removeLast()
                    type = .function(parameters, suspendResult, receiver: receiver, nullable: isNullable, isSuspend: true)
                } else {
                    type = .function(parameters, result, receiver: receiver, nullable: isNullable)
                }
            } else {
                type = .named(binary, args, nullable: isNullable)
            }
        }
        if message.integer(4) != nil, let upper = try self.type(message, field: 5, indexField: 8, depth: depth + 1) {
            return .flexible(type, upper)
        }
        return type
    }

    func typeParameter(_ node: JVMMetadataMessage) throws -> JVMTypeParameter {
        guard let id = node.integer(1) else { throw JVMClassReader.Invalid() }
        let name = try name(node.integer(2))
        return JVMTypeParameter(id: id, name: name, variance: node.integer(4) ?? 2,
                                bounds: try types(node, field: 5, indexField: 6), signature: "", isReified: node.integer(3) == 1)
    }

    func parameter(_ node: JVMMetadataMessage) throws -> JVMKotlinParameterInfo {
        JVMKotlinParameterInfo(name: try name(node.integer(2)),
            type: try requiredType(node, field: 3, indexField: 5),
            varargType: try type(node, field: 4, indexField: 6),
            hasDefault: (node.integer(1) ?? 0) & 2 != 0)
    }
}

private struct JVMMetadataWire {
    var bytes: ArraySlice<UInt8>

    var remaining: ArraySlice<UInt8> { bytes }

    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard let byte = bytes.popFirst(), shift != 63 || byte <= 1 else { throw JVMClassReader.Invalid() }
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
        }
        throw JVMClassReader.Invalid()
    }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count <= bytes.count else { throw JVMClassReader.Invalid() }
        let result = bytes.prefix(count)
        bytes = bytes.dropFirst(count)
        return result
    }

    mutating func lengthDelimited() throws -> ArraySlice<UInt8> {
        guard let length = Int(exactly: try varint()) else { throw JVMClassReader.Invalid() }
        return try take(length)
    }
}

private struct JVMMetadataMessage {
    enum Field {
        case integer(UInt64)
        case bytes(ArraySlice<UInt8>)
    }

    let fields: [Int: [Field]]

    init(_ bytes: ArraySlice<UInt8>) throws {
        var stream = JVMMetadataWire(bytes: bytes)
        var fields: [Int: [Field]] = [:]
        while !stream.remaining.isEmpty {
            let key = try stream.varint()
            guard let number = Int(exactly: key >> 3), number > 0 else { throw JVMClassReader.Invalid() }
            switch key & 7 {
            case 0: fields[number, default: []].append(.integer(try stream.varint()))
            case 2: fields[number, default: []].append(.bytes(try stream.lengthDelimited()))
            case 1: _ = try stream.take(8)
            case 5: _ = try stream.take(4)
            default: throw JVMClassReader.Invalid()
            }
        }
        self.fields = fields
    }

    func integer(_ field: Int) -> Int? {
        guard case let .integer(value) = fields[field]?.last else { return nil }
        return Int(exactly: value)
    }

    func integers(_ field: Int) throws -> [Int] {
        var result: [Int] = []
        for item in fields[field] ?? [] {
            switch item {
            case .integer(let value):
                if let value = Int(exactly: value) { result.append(value) }
            case .bytes(let bytes):
                var stream = JVMMetadataWire(bytes: bytes)
                while !stream.remaining.isEmpty {
                    if let value = Int(exactly: try stream.varint()) { result.append(value) }
                }
            }
        }
        return result
    }

    func bytes(_ field: Int) -> ArraySlice<UInt8>? {
        guard case let .bytes(bytes) = fields[field]?.last else { return nil }
        return bytes
    }

    func message(_ field: Int) throws -> Self? { try bytes(field).map(Self.init) }

    func messages(_ field: Int) throws -> [Self] {
        try (fields[field] ?? []).compactMap { if case let .bytes(bytes) = $0 { try Self(bytes) } else { nil } }
    }
}
