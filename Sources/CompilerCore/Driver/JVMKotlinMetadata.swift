import Foundation

/// The source signature of a suspend declaration linked to a classfile method.
struct JVMKotlinSuspendFunction {
    struct Parameter {
        let name: String?
        let isNullable: Bool
    }

    let name: String
    let result: JVMValueType
    let parameters: [Parameter]
    let receiverIsNullable: Bool?
}

/// The Kotlin source signature of a classpath function whose erased JVM
/// parameters include function types. The physical descriptor stays on
/// `JVMForeignMethod`; this carries only the declaration shape Sema needs.
struct JVMKotlinFunction {
    struct Parameter {
        let name: String?
        let sourceType: String
        let isVararg: Bool
    }

    let name: String
    let jvmName: String?
    let descriptor: String?
    let result: String
    let parameters: [Parameter]
    let receiver: String?
    let isSuspend: Bool
}

/// Reads the class and file-facade subset of Kotlin's JVM metadata. Field
/// numbers follow metadata.proto and jvm_metadata.proto.
struct JVMKotlinMetadata {
    var kind: Int32 = 1
    var version: [Int32] = []
    var data1: [String] = []
    var data2: [String] = []

    var isFileFacade: Bool? {
        switch kind {
        case 1: false
        case 2: true
        default: nil
        }
    }

    struct FunctionTable {
        fileprivate let names: JVMMetadataNames
        fileprivate let types: TypeTable
        fileprivate let functions: [ProtoFields]
    }

    func functionTable(byteLimit: Int) throws -> FunctionTable? {
        guard let isFileFacade, let major = version.first, (1...2).contains(major) else { return nil }
        let bytes = try decodedData(limit: byteLimit)
        var cursor = ProtoCursor(bytes[...])
        guard let tableLength = Int(exactly: try cursor.readVarint()) else { throw JVMClassReader.Invalid() }
        let names = try JVMMetadataNames(ProtoFields(cursor.readBytes(tableLength)), strings: data2)
        let declaration = try ProtoFields(bytes[cursor.position...])
        let classTypes = try TypeTable(declaration.message(30))
        return FunctionTable(names: names, types: classTypes, functions: try declaration.messages(isFileFacade ? 3 : 9))
    }

    func suspendFunctions(in table: FunctionTable) throws -> [String: JVMKotlinSuspendFunction] {
        let names = table.names
        let classTypes = table.types
        var result: [String: JVMKotlinSuspendFunction] = [:]
        for function in table.functions {
            guard (function.int32(9) ?? 0) & (1 << 13) != 0,
                  let name = try names.resolve(function.int32(2)),
                  let signature = try function.message(100),
                  let descriptor = try names.resolve(signature.int32(2)) else { continue }
            let jvmName = try names.resolve(signature.int32(1)) ?? name
            let types = try function.message(30).map(TypeTable.init) ?? classTypes
            guard let returnType = try types.resolve(function, inline: 3, indexed: 7),
                  let carrier = try Self.resultType(returnType, types: types, names: names) else { continue }
            let receiver = try types.resolve(function, inline: 5, indexed: 8)
            let parameters = try function.messages(6).map { parameter in
                JVMKotlinSuspendFunction.Parameter(
                    name: try names.resolve(parameter.int32(2)),
                    isNullable: try types.resolve(parameter, inline: 3, indexed: 5)?.nullable ?? false
                )
            }
            let info = JVMKotlinSuspendFunction(
                name: name, result: carrier, parameters: parameters, receiverIsNullable: receiver?.nullable
            )
            guard result.updateValue(info, forKey: jvmName + descriptor) == nil else { throw JVMClassReader.Invalid() }
        }
        return result
    }

    /// Names of primary-constructor parameters declared `vararg`. Annotation
    /// classes expose those parameters as element methods, so classfile flags
    /// alone cannot recover the Kotlin source shape.
    func annotationVarargElements(byteLimit: Int) throws -> Set<String> {
        guard kind == 1, let major = version.first, (1...2).contains(major) else { return [] }
        let bytes = try decodedData(limit: byteLimit)
        var cursor = ProtoCursor(bytes[...])
        guard let tableLength = Int(exactly: try cursor.readVarint()) else { throw JVMClassReader.Invalid() }
        let names = try JVMMetadataNames(ProtoFields(cursor.readBytes(tableLength)), strings: data2)
        let declaration = try ProtoFields(bytes[cursor.position...])
        var result = Set<String>()
        for constructor in try declaration.messages(8) {
            for parameter in try constructor.messages(2) where parameter.has(4) || parameter.has(6) {
                if let name = try names.resolve(parameter.int32(2)) { result.insert(name) }
            }
        }
        return result
    }

    fileprivate struct TypeTable {
        let entries: [ProtoFields]
        let firstNullable: Int

        init(_ message: ProtoFields?) throws {
            entries = try message?.messages(1) ?? []
            firstNullable = Int(message?.int32(2) ?? -1)
        }

        func resolve(_ message: ProtoFields, inline: Int, indexed: Int) throws -> (type: ProtoFields, nullable: Bool)? {
            if let type = try message.message(inline) { return (type, type.bool(3) == true) }
            guard let index = message.int32(indexed), entries.indices.contains(Int(index)) else { return nil }
            let type = entries[Int(index)]
            return (type, type.bool(3) == true || (firstNullable >= 0 && index >= firstNullable))
        }
    }

    private static func resultType(
        _ resolved: (type: ProtoFields, nullable: Bool), types: TypeTable, names: JVMMetadataNames, depth: Int = 0
    ) throws -> JVMValueType? {
        let (type, nullable) = resolved
        guard let name = try names.resolve(type.int32(6)) else {
            // The classpath importer exposes erased method type parameters.
            return type.has(7) || type.has(9) ? .reference("java/lang/Object", nullable: true) : nil
        }
        switch name {
        case "kotlin/Any": return .reference("java/lang/Object", nullable: nullable)
        case "kotlin/String": return nullable ? .reference("java/lang/String", nullable: true) : .string
        case "kotlin/Unit": return nullable ? .reference(name, nullable: true) : .unit
        case "kotlin/Nothing": return .reference(name, nullable: nullable)
        case "kotlin/Array":
            guard depth < 255 else { return nil }
            let object = JVMValueType.reference("java/lang/Object", nullable: true)
            let element: JVMValueType
            if let argument = try type.message(2), argument.int32(1) != 0,
               let component = try types.resolve(argument, inline: 2, indexed: 3) {
                guard let carrier = try resultType(component, types: types, names: names, depth: depth + 1) else { return nil }
                element = carrier == .unit ? .reference("kotlin/Unit", nullable: false) : JVMClasspathIndex.boxed(carrier)
            } else {
                element = object
            }
            return .reference("[" + element.descriptor, nullable: nullable)
        default:
            if name.hasPrefix("kotlin/") {
                let short = String(name.dropFirst("kotlin/".count))
                if let primitive = PrimitiveType(rawValue: short.lowercased()), primitive.kotlinName == short {
                    let carrier = JVMValueType.primitive(primitive)
                    return nullable ? .reference(carrier.boxName!, nullable: true) : carrier
                }
                if let element = JVMClasspathIndex.primitiveArrays[short] {
                    return .reference("[" + element.descriptor, nullable: nullable)
                }
            }
            let binaryName = name.replacingOccurrences(of: ".", with: "$")
            let carrier = JVMClasspathIndex.builtinName(binaryName) ?? binaryName
            guard (try? JVMDescriptor.parse("()L" + carrier + ";")) != nil else { return nil }
            return .reference(carrier, nullable: nullable)
        }
    }

    /// Functions whose Kotlin signature cannot be recovered from the erased JVM
    /// descriptor, plus every top-level file-facade function so lazy classpath
    /// roots can be found by callable name.
    func functions(in table: FunctionTable) throws -> [JVMKotlinFunction] {
        let names = table.names
        let classTypes = table.types
        var result: [JVMKotlinFunction] = []
        for function in table.functions {
            guard let name = try names.resolve(function.int32(2)) else { continue }
            let signature = try function.message(100)
            let jvmName: String?
            var descriptor: String?
            if let signature {
                jvmName = try names.resolve(signature.int32(1))
                descriptor = try names.resolve(signature.int32(2))
            } else {
                jvmName = nil
                descriptor = nil
            }
            let types = try function.message(30).map(TypeTable.init) ?? classTypes
            guard let returnResolved = try types.resolve(function, inline: 3, indexed: 7),
                  let resultType = try Self.sourceType(returnResolved, types: types, names: names) else { continue }
            let receiver = try types.resolve(function, inline: 5, indexed: 8)
            let receiverType = try receiver.flatMap { try Self.sourceType($0, types: types, names: names) }
            guard receiver == nil || receiverType != nil else { continue }
            let parameterMessages = try function.messages(6)
            var parameters: [JVMKotlinFunction.Parameter] = []
            var hasFunctionTypes = resultType.contains("->") || (receiverType?.contains("->") ?? false)
            var valid = true
            for parameter in parameterMessages {
                let parameterName = try names.resolve(parameter.int32(2))
                if let vararg = try types.resolve(parameter, inline: 4, indexed: 6) {
                    guard let element = try Self.sourceType(vararg, types: types, names: names) else {
                        valid = false
                        break
                    }
                    parameters.append(JVMKotlinFunction.Parameter(name: parameterName, sourceType: element, isVararg: true))
                    hasFunctionTypes = hasFunctionTypes || element.contains("->")
                    continue
                }
                guard let resolved = try types.resolve(parameter, inline: 3, indexed: 5),
                      let type = try Self.sourceType(resolved, types: types, names: names) else {
                    valid = false
                    break
                }
                parameters.append(JVMKotlinFunction.Parameter(name: parameterName, sourceType: type, isVararg: false))
                hasFunctionTypes = hasFunctionTypes || type.contains("->")
            }
            guard valid, hasFunctionTypes || (isFileFacade == true) else { continue }
            let isSuspend = ((function.int32(9) ?? 0) & (1 << 13)) != 0
            if !hasFunctionTypes, descriptor == nil {
                // The signature extension can omit descriptors that the JVM
                // backend derives from Kotlin types. Recover them so overloads
                // with the same arity are matched by their actual carriers.
                var inputs = [receiver].compactMap { $0 }
                for parameter in parameterMessages {
                    if let type = try types.resolve(parameter, inline: 3, indexed: 5) {
                        inputs.append(type)
                    }
                }
                let carriers = try inputs.compactMap {
                    try Self.resultType($0, types: types, names: names)
                }
                guard carriers.count == parameters.count + (receiver == nil ? 0 : 1),
                      let resultCarrier = try Self.resultType(returnResolved, types: types, names: names)
                else { continue }
                descriptor = "(" + carriers.map { $0 == .unit ? "Lkotlin/Unit;" : $0.descriptor }.joined() + ")" + resultCarrier.descriptor
            }
            result.append(JVMKotlinFunction(
                name: name,
                jvmName: jvmName,
                descriptor: descriptor,
                result: resultType,
                parameters: parameters,
                receiver: receiverType,
                isSuspend: isSuspend
            ))
        }
        return result
    }

    private static func sourceType(
        _ resolved: (type: ProtoFields, nullable: Bool),
        types: TypeTable,
        names: JVMMetadataNames,
        depth: Int = 0
    ) throws -> String? {
        guard depth < 64 else { return nil }
        let (type, nullable) = resolved
        let suffix = nullable ? "?" : ""
        switch try names.resolve(type.int32(6)) {
        case "kotlin/Any": return "kotlin.Any" + suffix
        case "kotlin/String": return "kotlin.String" + suffix
        case "kotlin/Unit": return "kotlin.Unit" + suffix
        case "kotlin/Nothing": return "kotlin.Nothing" + suffix
        default: break
        }
        guard let name = try names.resolve(type.int32(6)) else { return nil }
        if let arity = functionArity(name) {
            let arguments = try type.messages(2)
            guard arguments.count == arity + 1 else { return nil }
            var rendered: [String] = []
            for argument in arguments {
                guard let argumentType = try argumentSource(argument, types: types, names: names, depth: depth + 1) else { return nil }
                rendered.append(argumentType)
            }
            let isSuspendFunction = name.hasPrefix("kotlin/SuspendFunction")
            let isExtension = try isExtensionFunctionType(type, names: names)
            let returnType = rendered[arity]
            let inputs = Array(rendered.dropLast())
            let receiver: String?
            let parameters: [String]
            if isExtension {
                guard !inputs.isEmpty else { return nil }
                receiver = inputs[0]
                parameters = Array(inputs.dropFirst())
            } else {
                receiver = nil
                parameters = inputs
            }
            guard parameters.count + (receiver == nil ? 0 : 1) == arity else { return nil }
            let parameterList = parameters.joined(separator: ", ")
            let body: String
            if let receiver {
                body = receiver + ".(" + parameterList + ") -> " + returnType
            } else {
                body = "(" + parameterList + ") -> " + returnType
            }
            let functionType = (isSuspendFunction ? "suspend " : "") + body
            return nullable ? "(" + functionType + ")?" : functionType
        }
        var base = sourceClassName(name)
        let arguments = try type.messages(2)
        if !arguments.isEmpty {
            var rendered: [String] = []
            for argument in arguments {
                guard let argumentType = try argumentSource(argument, types: types, names: names, depth: depth + 1) else { return nil }
                rendered.append(argumentType)
            }
            base += "<" + rendered.joined(separator: ", ") + ">"
        }
        return base + suffix
    }

    private static func argumentSource(
        _ argument: ProtoFields,
        types: TypeTable,
        names: JVMMetadataNames,
        depth: Int
    ) throws -> String? {
        let projection = argument.int32(1) ?? 2
        if projection == 3 { return "*" }
        guard let resolved = try types.resolve(argument, inline: 2, indexed: 3),
              var type = try sourceType(resolved, types: types, names: names, depth: depth + 1) else { return nil }
        switch projection {
        case 0: type = "in " + type
        case 1: type = "out " + type
        default: break
        }
        return type
    }

    private static func isExtensionFunctionType(_ type: ProtoFields, names: JVMMetadataNames) throws -> Bool {
        for annotation in try type.messages(100) {
            if try names.resolve(annotation.int32(1)) == "kotlin/ExtensionFunctionType" { return true }
        }
        return false
    }

    private static func functionArity(_ name: String) -> Int? {
        for prefix in ["kotlin/SuspendFunction", "kotlin/Function"] {
            if name.hasPrefix(prefix), let arity = Int(name.dropFirst(prefix.count)) { return arity }
        }
        return nil
    }

    private static func sourceClassName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: ".")
    }

    private func decodedData(limit: Int) throws -> [UInt8] {
        let marker = data1.first?.utf16.first
        let rawBytes = marker == 0
        let hasMarker = rawBytes || marker == 0xFFFF
        var bytes: [UInt8] = []
        var buffer: UInt16 = 0
        var bits = 0
        var unitCount = 0
        for (index, chunk) in data1.enumerated() {
            let units = chunk.utf16
            for unit in units.dropFirst(index == 0 && hasMarker ? 1 : 0) {
                // The annotation can reference the same pool string repeatedly.
                guard unitCount < limit else { throw JVMClassReader.Invalid() }
                unitCount += 1
                if rawBytes {
                    guard let byte = UInt8(exactly: unit) else { throw JVMClassReader.Invalid() }
                    bytes.append(byte)
                } else {
                    guard unit <= 0x7F else { throw JVMClassReader.Invalid() }
                    buffer |= ((unit + 0x7F) & 0x7F) << bits
                    bits += 7
                    if bits >= 8 {
                        bytes.append(UInt8(truncatingIfNeeded: buffer))
                        buffer >>= 8
                        bits -= 8
                    }
                }
            }
        }
        return bytes
    }
}

private struct JVMMetadataNames {
    let strings: [String]
    let records: [ProtoFields]

    init(_ table: ProtoFields, strings: [String]) throws {
        self.strings = strings
        var records: [ProtoFields] = []
        for record in try table.messages(1) {
            let count = Int(record.int32(1) ?? 1)
            guard count > 0, count <= strings.count - records.count else { throw JVMClassReader.Invalid() }
            records.append(contentsOf: repeatElement(record, count: count))
        }
        self.records = records
    }

    func resolve(_ rawIndex: Int32?) throws -> String? {
        guard let rawIndex else { return nil }
        let index = Int(rawIndex)
        guard records.indices.contains(index) else { return nil }
        let record = records[index]
        let predefined = Int(record.int32(2) ?? -1)
        var name = record.string(6) ?? (Self.predefined.indices.contains(predefined) ? Self.predefined[predefined] : strings[index])
        let substring = try record.int32List(4)
        let replacement = try record.int32List(5)
        if substring.count >= 2 || replacement.count >= 2 {
            var units = Array(name.utf16)
            if substring.count >= 2 {
                let start = Int(substring[0]), end = Int(substring[1])
                if 0 <= start, start <= end, end <= units.count { units = Array(units[start..<end]) }
            }
            if replacement.count >= 2 {
                let from = UInt16(truncatingIfNeeded: replacement[0]), to = UInt16(truncatingIfNeeded: replacement[1])
                units = units.map { $0 == from ? to : $0 }
            }
            name = String(decoding: units, as: UTF16.self)
        }
        switch record.int32(3) {
        case 1: return name.replacingOccurrences(of: "$", with: ".")
        case 2: return String(name.dropFirst().dropLast()).replacingOccurrences(of: "$", with: ".")
        default: return name
        }
    }

    // Predefined StringTableTypes entries use the order in JvmNameResolverBase.
    private static let predefined = [
        "Any", "Nothing", "Unit", "Throwable", "Number", "Byte", "Double", "Float", "Int", "Long", "Short", "Boolean", "Char",
        "CharSequence", "String", "Comparable", "Enum", "Array",
        "ByteArray", "DoubleArray", "FloatArray", "IntArray", "LongArray", "ShortArray", "BooleanArray", "CharArray",
        "Cloneable", "Annotation",
        "collections/Iterable", "collections/MutableIterable", "collections/Collection", "collections/MutableCollection",
        "collections/List", "collections/MutableList", "collections/Set", "collections/MutableSet", "collections/Map",
        "collections/MutableMap", "collections/Map.Entry", "collections/MutableMap.MutableEntry",
        "collections/Iterator", "collections/MutableIterator", "collections/ListIterator", "collections/MutableListIterator",
    ].map { "kotlin/" + $0 }
}
