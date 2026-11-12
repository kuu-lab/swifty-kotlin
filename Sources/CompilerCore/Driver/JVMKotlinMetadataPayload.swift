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
    struct TypeParameter {
        let name: String
        let bounds: [String]
    }

    struct Parameter {
        let name: String?
        let sourceType: String
        let isVararg: Bool
        let hasDefaultValue: Bool
        var isCrossinline = false
        var isNoinline = false
    }

    let name: String
    let jvmName: String?
    let descriptor: String?
    let result: String
    let parameters: [Parameter]
    let typeParameters: [TypeParameter]
    let contextParameters: [Parameter]
    let receiver: String?
    let isSuspend: Bool
    var isInline = false
    var isOperator = false
    var isInfix = false

    var leadingParameterCount: Int { contextParameters.count + (receiver == nil ? 0 : 1) }
    var composableParameters: Set<Int> {
        Set(parameters.indices.filter {
            parameters[$0].sourceType.hasPrefix("@androidx.compose.runtime.Composable ")
        })
    }
    var hasInlineContextCallback: Bool {
        isInline && parameters.contains { $0.sourceType.hasPrefix("context(") && !$0.isCrossinline && !$0.isNoinline }
    }
}

struct JVMKotlinClassProperty {
    let name: String
    let getterName: String
    let getterDescriptor: String
    let isNullable: Bool
    let isVar: Bool
    let sourceType: String?
}

struct JVMKotlinTopLevelProperty {
    let name: String
    let receiver: String?
    let result: String
    let getterName: String
    let getterDescriptor: String
}

/// Reads the class and file-facade subset of Kotlin's JVM metadata. Field
/// numbers follow metadata.proto and jvm_metadata.proto.
struct JVMKotlinMetadataPayload {
    var kind: Int32 = 1
    var version: [Int32] = []
    var data1: [String] = []
    var data2: [String] = []

    var isFileFacade: Bool? {
        switch kind {
        case 1: false
        case 2, 4, 5: true
        default: nil
        }
    }

    struct FunctionTable {
        fileprivate let names: JVMMetadataNames
        fileprivate let types: TypeTable
        fileprivate let functions: [ProtoFields]
        fileprivate let ownerTypeParameters: [Int32: String]
    }

    var multifileParts: [String] { kind == 4 ? data1 : [] }
    var isMultifilePart: Bool { kind == 5 }

    func functionTable(byteLimit: Int) throws -> FunctionTable? {
        guard kind != 4, let isFileFacade, let major = version.first, (1...2).contains(major) else { return nil }
        let bytes = try decodedData(limit: byteLimit)
        var cursor = ProtoCursor(bytes[...])
        guard let tableLength = Int(exactly: try cursor.readVarint()) else { throw JVMClassReader.Invalid() }
        let names = try JVMMetadataNames(ProtoFields(cursor.readBytes(tableLength)), strings: data2)
        let declaration = try ProtoFields(bytes[cursor.position...])
        let classTypes = try TypeTable(declaration.message(30))
        var ownerTypeParameters: [Int32: String] = [:]
        if !isFileFacade {
            for parameter in try declaration.messages(5) {
                guard let id = parameter.int32(1), let name = try names.resolve(parameter.int32(2)),
                      JVMProgramBuilder.isIdentifier(name) else { continue }
                ownerTypeParameters[id] = name
            }
        }
        return FunctionTable(names: names, types: classTypes,
                             functions: try declaration.messages(isFileFacade ? 3 : 9),
                             ownerTypeParameters: ownerTypeParameters)
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
            guard let returnType = try types.resolve(function, inline: 3, indexed: 7) else { continue }
            let carrier: JVMValueType
            if let concrete = try Self.resultType(returnType, types: types, names: names) {
                carrier = concrete
            } else if try function.messages(4).contains(where: { parameter in
                returnType.type.int32(7).map { $0 == parameter.int32(1) } == true
                    || returnType.type.int32(9).map { $0 == parameter.int32(2) } == true
            }) {
                // Type-parameter results travel as boxed objects across the continuation boundary.
                carrier = .reference("java/lang/Object", nullable: true)
            } else {
                continue
            }
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

    /// Static properties exposed by Kotlin objects through @JvmStatic accessors.
    func classPropertyCandidates(byteLimit: Int) throws -> [JVMKotlinClassProperty] {
        guard kind == 1, let major = version.first, (1...2).contains(major) else { return [] }
        let bytes = try decodedData(limit: byteLimit)
        var cursor = ProtoCursor(bytes[...])
        guard let tableLength = Int(exactly: try cursor.readVarint()) else { throw JVMClassReader.Invalid() }
        let names = try JVMMetadataNames(ProtoFields(cursor.readBytes(tableLength)), strings: data2)
        let declaration = try ProtoFields(bytes[cursor.position...])
        let types = try TypeTable(declaration.message(30))
        return try declaration.messages(10).compactMap { property in
            guard let name = try names.resolve(property.int32(2)), JVMProgramBuilder.isIdentifier(name),
                  let type = try types.resolve(property, inline: 3, indexed: 9),
                  let signature = try property.message(100),
                  let getter = try signature.message(3),
                  let getterName = try names.resolve(getter.int32(1)),
                  let descriptor = try names.resolve(getter.int32(2))
            else { return nil }
            let hasSetter = try signature.message(4) != nil
            return JVMKotlinClassProperty(name: name, getterName: getterName, getterDescriptor: descriptor,
                                           isNullable: type.nullable, isVar: (property.int32(11) ?? 0) & (1 << 8) != 0 || hasSetter,
                                           sourceType: try Self.sourceType(type, types: types, names: names))
        }
    }

    private func declarationData(byteLimit: Int) throws -> (ProtoFields, JVMMetadataNames) {
        let bytes = try decodedData(limit: byteLimit)
        var cursor = ProtoCursor(bytes[...])
        guard let tableLength = Int(exactly: try cursor.readVarint()) else { throw JVMClassReader.Invalid() }
        let names = try JVMMetadataNames(ProtoFields(cursor.readBytes(tableLength)), strings: data2)
        return (try ProtoFields(bytes[cursor.position...]), names)
    }

    func topLevelProperties(byteLimit: Int) throws -> [JVMKotlinTopLevelProperty] {
        guard kind == 2 || kind == 5, let major = version.first, (1...2).contains(major) else { return [] }
        let (declaration, names) = try declarationData(byteLimit: byteLimit)
        let types = try TypeTable(declaration.message(30))
        return try declaration.messages(4).compactMap { property in
            let receiver = try types.resolve(property, inline: 5, indexed: 10)
            let receiverType = try receiver.flatMap { try Self.sourceType($0, types: types, names: names) }
            guard let name = try names.resolve(property.int32(2)), JVMProgramBuilder.isIdentifier(name),
                  receiver == nil || receiverType != nil, receiverType?.contains("->") != true,
                  let result = try types.resolve(property, inline: 3, indexed: 9),
                  let resultType = try Self.sourceType(result, types: types, names: names),
                  let signature = try property.message(100),
                  let getter = try signature.message(3),
                  let getterName = try names.resolve(getter.int32(1)),
                  let descriptor = try names.resolve(getter.int32(2))
            else { return nil }
            return JVMKotlinTopLevelProperty(name: name, receiver: receiverType, result: resultType,
                                              getterName: getterName, getterDescriptor: descriptor)
        }
    }

    fileprivate struct TypeTable {
        let entries: [ProtoFields]
        let firstNullable: Int
        var parameterNames: [Int32: String] = [:]

        init(_ message: ProtoFields?) throws {
            entries = try message?.messages(1) ?? []
            firstNullable = Int(message?.int32(2) ?? -1)
        }

        func resolve(_ message: ProtoFields, inline: Int, indexed: Int) throws -> (type: ProtoFields, nullable: Bool)? {
            if let type = try message.message(inline) { return (type, type.bool(3) == true) }
            return message.int32(indexed).flatMap { resolve(index: $0) }
        }

        func resolve(index: Int32) -> (type: ProtoFields, nullable: Bool)? {
            guard entries.indices.contains(Int(index)) else { return nil }
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
        let ownerTypeParameters = table.ownerTypeParameters
        var result: [JVMKotlinFunction] = []
        for function in table.functions {
            guard let name = try names.resolve(function.int32(2)) else { continue }
            let flags = function.int32(9) ?? 0
            let isInfix = flags & (1 << 9) != 0
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
            var types = try function.message(30).map(TypeTable.init) ?? classTypes
            if isInfix { types.parameterNames = ownerTypeParameters }
            let typeParameterMessages = try function.messages(4)
            guard typeParameterMessages.isEmpty || isFileFacade == true else { continue }
            let parameterIDs = try typeParameterMessages.compactMap { parameter -> Int32? in
                guard parameter.bool(3) != true, let id = parameter.int32(1),
                      let name = try names.resolve(parameter.int32(2)), JVMProgramBuilder.isIdentifier(name)
                else { return nil }
                types.parameterNames[id] = name
                return id
            }
            guard parameterIDs.count == typeParameterMessages.count else { continue }
            var typeParameters: [JVMKotlinFunction.TypeParameter] = []
            for (id, parameter) in zip(parameterIDs, typeParameterMessages) {
                let inlineBounds = try parameter.messages(5).map { (type: $0, nullable: $0.bool(3) == true) }
                let boundIDs = try parameter.int32List(6)
                let indexedBounds = boundIDs.compactMap { types.resolve(index: $0) }
                let allBounds = inlineBounds + indexedBounds
                let bounds = try allBounds.compactMap { try Self.sourceType($0, types: types, names: names) }
                guard indexedBounds.count == boundIDs.count, bounds.count == allBounds.count,
                      let parameterName = types.parameterNames[id] else { break }
                typeParameters.append(.init(name: parameterName, bounds: bounds))
            }
            guard typeParameters.count == parameterIDs.count else { continue }
            guard let returnResolved = try types.resolve(function, inline: 3, indexed: 7),
                  let resultType = try Self.sourceType(returnResolved, types: types, names: names) else { continue }
            let receiver = try types.resolve(function, inline: 5, indexed: 8)
            let receiverType = try receiver.flatMap { try Self.sourceType($0, types: types, names: names) }
            guard receiver == nil || receiverType != nil else { continue }
            let contextMessages = try function.messages(13)
            let contextTypes = try contextMessages.compactMap { try types.resolve($0, inline: 3, indexed: 5) }
            let contextParameters = try zip(contextMessages, contextTypes).compactMap { parameter, resolved -> JVMKotlinFunction.Parameter? in
                guard let type = try Self.sourceType(resolved, types: types, names: names) else { return nil }
                return .init(name: try names.resolve(parameter.int32(2)), sourceType: type, isVararg: false, hasDefaultValue: false)
            }
            guard contextParameters.count == contextMessages.count else { continue }
            let parameterMessages = try function.messages(6)
            var parameters: [JVMKotlinFunction.Parameter] = []
            var hasFunctionTypes = resultType.contains("->") || (receiverType?.contains("->") ?? false)
            var valid = true
            for parameter in parameterMessages {
                let parameterName = try names.resolve(parameter.int32(2))
                let flags = parameter.int32(1) ?? 0
                let hasDefaultValue = flags & 2 != 0
                if let vararg = try types.resolve(parameter, inline: 4, indexed: 6) {
                    guard let element = try Self.sourceType(vararg, types: types, names: names) else {
                        valid = false
                        break
                    }
                    parameters.append(JVMKotlinFunction.Parameter(name: parameterName, sourceType: element, isVararg: true, hasDefaultValue: hasDefaultValue))
                    hasFunctionTypes = hasFunctionTypes || element.contains("->")
                    continue
                }
                guard let resolved = try types.resolve(parameter, inline: 3, indexed: 5),
                      let type = try Self.sourceType(resolved, types: types, names: names) else {
                    valid = false
                    break
                }
                parameters.append(JVMKotlinFunction.Parameter(name: parameterName, sourceType: type, isVararg: false,
                    hasDefaultValue: hasDefaultValue, isCrossinline: flags & 4 != 0, isNoinline: flags & 8 != 0))
                hasFunctionTypes = hasFunctionTypes || type.contains("->")
            }
            guard valid, hasFunctionTypes || (isFileFacade == true) || receiver != nil || isInfix else { continue }
            let isSuspend = flags & (1 << 13) != 0
            if !hasFunctionTypes, descriptor == nil {
                // The signature extension can omit descriptors that the JVM
                // backend derives from Kotlin types. Recover them so overloads
                // with the same arity are matched by their actual carriers.
                var inputs = contextTypes + [receiver].compactMap { $0 }
                for parameter in parameterMessages {
                    if let type = try types.resolve(parameter, inline: 3, indexed: 5) {
                        inputs.append(type)
                    }
                }
                let carriers = try inputs.compactMap {
                    try Self.resultType($0, types: types, names: names)
                }
                guard carriers.count == parameters.count + contextParameters.count + (receiver == nil ? 0 : 1),
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
                typeParameters: typeParameters,
                contextParameters: contextParameters,
                receiver: receiverType,
                isSuspend: isSuspend,
                isInline: flags & (1 << 10) != 0,
                isOperator: flags & (1 << 8) != 0,
                isInfix: isInfix
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
        guard let name = try names.resolve(type.int32(6)) else {
            let id = type.int32(7)
            let name = try id.flatMap { types.parameterNames[$0] }
                ?? names.resolve(type.int32(9)).flatMap { value in
                    types.parameterNames.values.contains(value) ? value : nil
                }
            return name.map { "`\($0)`" + suffix }
        }
        if let arity = functionArity(name) {
            let arguments = try type.messages(2)
            guard arguments.count == arity + 1 else { return nil }
            var rendered: [String] = []
            for argument in arguments {
                guard let argumentType = try argumentSource(argument, types: types, names: names, depth: depth + 1) else { return nil }
                rendered.append(argumentType)
            }
            let isLoweredSuspendFunction = (type.int32(1) ?? 0) & 1 != 0
                && !name.hasPrefix("kotlin/SuspendFunction")
            let isSuspendFunction = isLoweredSuspendFunction || name.hasPrefix("kotlin/SuspendFunction")
            let isExtension = try hasTypeAnnotation("kotlin/ExtensionFunctionType", type: type, names: names)
            let isComposable = try hasTypeAnnotation("androidx/compose/runtime/Composable", type: type, names: names)
            let returnType: String
            let inputs: [String]
            if isLoweredSuspendFunction {
                // Kotlin/JVM metadata can encode suspend function types as
                // FunctionN with a trailing Continuation<R> and Any? result.
                guard arity > 0, let continuation = try types.resolve(arguments[arity - 1], inline: 2, indexed: 3),
                      try names.resolve(continuation.type.int32(6)) == "kotlin/coroutines/Continuation",
                      let argument = try continuation.type.message(2),
                      let result = try types.resolve(argument, inline: 2, indexed: 3),
                      let sourceResult = try sourceType(result, types: types, names: names, depth: depth + 1)
                else { return nil }
                returnType = sourceResult
                inputs = Array(rendered.prefix(arity - 1))
            } else {
                returnType = rendered[arity]
                inputs = Array(rendered.dropLast())
            }
            let contextCount = try contextFunctionParameterCount(type, names: names)
            guard contextCount <= inputs.count else { return nil }
            let contextInputs = inputs.prefix(contextCount)
            let remaining = inputs.dropFirst(contextCount)
            let receiver: String?
            let parameters: [String]
            if isExtension {
                guard let extensionReceiver = remaining.first else { return nil }
                receiver = extensionReceiver
                parameters = Array(remaining.dropFirst())
            } else {
                receiver = nil
                parameters = Array(remaining)
            }
            let parameterList = parameters.joined(separator: ", ")
            let body: String
            if let receiver {
                body = receiver + ".(" + parameterList + ") -> " + returnType
            } else {
                body = "(" + parameterList + ") -> " + returnType
            }
            let context = contextInputs.isEmpty ? "" : "context(" + contextInputs.joined(separator: ", ") + ") "
            let functionType = (isComposable ? "@androidx.compose.runtime.Composable " : "") + context
                + (isSuspendFunction ? "suspend " : "") + body
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

    private static func hasTypeAnnotation(_ name: String, type: ProtoFields, names: JVMMetadataNames) throws -> Bool {
        for annotation in try type.messages(100) {
            if try names.resolve(annotation.int32(1)) == name { return true }
        }
        return false
    }

    private static func contextFunctionParameterCount(_ type: ProtoFields, names: JVMMetadataNames) throws -> Int {
        for annotation in try type.messages(100) where try names.resolve(annotation.int32(1)) == "kotlin/ContextFunctionTypeParams" {
            guard let argument = try annotation.message(2), let value = try argument.message(2),
                  let zigzag = value.varint(2), zigzag % 2 == 0, let count = Int(exactly: zigzag >> 1) else {
                throw JVMClassReader.Invalid()
            }
            return count
        }
        return 0
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
