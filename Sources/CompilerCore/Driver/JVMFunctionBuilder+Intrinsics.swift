import Foundation

struct JVMIntrinsicResult { let value: JVMValue? }

extension JVMProgramBuilder {
    func builtinMethod(_ symbolID: SymbolID) -> JVMForeignMethod? {
        guard let symbol = sema.symbols.symbol(symbolID), symbol.kind == .constructor,
              let parent = sema.symbols.parentSymbol(for: symbolID), classes[parent] == nil,
              let source = try? className(parent), let name = JVMClasspathIndex.builtinName(source),
              (name.hasPrefix("java/lang/") || ["java/util/NoSuchElementException", "java/util/AbstractList", "java/util/AbstractSet", "java/util/AbstractMap", "kotlin/UninitializedPropertyAccessException"].contains(name)), let signature = sema.symbols.functionSignature(for: symbolID),
              let parameters = try? signature.parameterTypes.map(type) else { return nil }
        return JVMForeignMethod(owner: name, name: "<init>", descriptor: "(" + parameters.map(\.descriptor).joined() + ")V", parameters: parameters, result: .reference(name, nullable: false), isStatic: false, isInterface: false, isAbstract: false)
    }
}

extension JVMFunctionBuilder {
    func jdkCall(_ owner: String, _ name: String, _ parameters: [JVMValueType], _ resultType: JVMValueType, receiver: JVMValue? = nil, arguments: [JVMValue] = [], interface: Bool = false, resolved: JVMValueType? = nil) throws -> JVMValue? {
        var args: [JVMValue] = []
        for (arg, type) in zip(arguments, parameters) { args.append(try convert(arg, to: type)) }
        let method = JVMForeignMethod(owner: owner, name: name, descriptor: "(" + parameters.map(\.descriptor).joined() + ")" + resultType.descriptor, parameters: parameters, result: resultType, isStatic: receiver == nil, isInterface: interface, isAbstract: false)
        let result = resultType == .unit ? nil : try value(resolved ?? resultType)
        instructions.append(.foreignCall(method, receiver: receiver, arguments: args, result: result))
        return result
    }
    func constructJDK(_ name: String, parameters: [JVMValueType] = [], arguments: [JVMValue] = []) throws -> JVMValue {
        let object = try value(.reference(name, nullable: false))
        instructions.append(.allocate(name, object))
        let method = JVMForeignMethod(owner: name, name: "<init>", descriptor: "(" + parameters.map(\.descriptor).joined() + ")V", parameters: parameters, result: object.type, isStatic: false, isInterface: false, isAbstract: false)
        instructions.append(.foreignCall(method, receiver: object, arguments: arguments, result: nil))
        return object
    }
    func intrinsicCall(_ symbolID: SymbolID, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        if let method = program.builtinMethod(symbolID) { return JVMIntrinsicResult(value: try foreign(method, receiver: nil, args: args, id: id)) }
        guard let symbol = program.sema.symbols.symbol(symbolID), symbol.declSite.map({ context.sourceManager.origin(of: $0.start.file) != .user }) ?? true else { return nil }
        if let delegate = try delegationIntrinsic(symbol, args: args, id: id) { return delegate }
        if let coroutine = try coroutineCall(symbol, args: args, id: id) { return coroutine }
        let fq = symbol.fqName.map(context.interner.resolve).joined(separator: "/")
        let name = context.interner.resolve(symbol.name)
        let resultType = try program.expressionType(id)
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        if context.options.stdlibOnly, fq.hasPrefix("kotlin/jvm/internal/__jvm") {
            let values = try args.map { try requireValue($0.expr) }
            if ["__jvmMonitorEnter", "__jvmMonitorExit"].contains(name), values.count == 1 {
                instructions.append(.monitor(values[0], enter: name == "__jvmMonitorEnter")); return JVMIntrinsicResult(value: nil)
            }
            if name == "__jvmEnumEntries", values.count == 1 {
                let array: JVMValueType = .reference("[Ljava/lang/Enum;", nullable: false)
                return JVMIntrinsicResult(value: try convert(constructJDK(program.coroutineIntrinsicOwner + "$EnumEntries", parameters: [array], arguments: [convert(values[0], to: array)]), to: resultType))
            }
            if name == "__jvmResultValue", let first = values.first {
                return JVMIntrinsicResult(value: try jdkCall("kotlin/Result", "unbox-impl", [], object, receiver: first))
            }
            if name == "__jvmResume", values.count == 2 { return JVMIntrinsicResult(value: try jdkCall("kotlin/coroutines/Continuation", "resumeWith", [object], .unit, receiver: values[0], arguments: [values[1]], interface: true)) }
            if let operation = program.platformOperations[name] { return JVMIntrinsicResult(value: try platformOperation(operation, arguments: values, result: resultType)) }
            if ["__jvmPrint", "__jvmPrintln", "__jvmNewline"].contains(name) {
                instructions.append(.print(values.first, newline: name != "__jvmPrint")); return JVMIntrinsicResult(value: nil)
            }
            throw fail("Unknown JVM stdlib platform operation.", id)
        }
        if fq == "kotlin/Char", args.count == 1 { return JVMIntrinsicResult(value: try charFromCode(requireValue(args[0].expr))) }
        if fq.hasPrefix("kotlin/"), resultType.referenceName?.hasPrefix("[") == true {
            let factory = name == "arrayOf" || name == "emptyArray" || name.hasSuffix("ArrayOf")
            let sized = name == "arrayOfNulls" || symbol.kind == .constructor
            guard factory || sized else { return nil }
            let element = try arrayComponent(resultType)
            let count: JVMValue
            if sized {
                guard args.count == 1 else { throw fail("JVM array construction requires a size.", id) }
                count = try convert(requireValue(args[0].expr), to: .int)
            } else { count = try constant(.int(Int32(args.count)), .int) }
            let result = try allocateArray(resultType, semantic: program.sema.bindings.exprType(for: id), count: count, id: id)
            if factory {
                for (i, arg) in args.enumerated() {
                    let index = try constant(.int(Int32(i)), .int), source = try convert(requireValue(arg.expr), to: element)
                    instructions.append(.arraySet(result, index, source))
                }
            }
            return JVMIntrinsicResult(value: result)
        }
        if fq.hasPrefix("kotlin/collections/"), ["listOf", "mutableListOf", "setOf", "mutableSetOf", "emptyList", "emptySet", "mutableMapOf", "mapOf", "emptyMap"].contains(name) {
            let map = name.lowercased().contains("map"), set = name.lowercased().contains("set")
            let owner = map ? "java/util/LinkedHashMap" : (set ? "java/util/LinkedHashSet" : "java/util/ArrayList")
            // Kotlin evaluates the whole vararg before hashing keys/elements.
            let items = try args.map { try requireValue($0.expr) }
            if items.count == 1, name == "mapOf" {
                let key = try jdkCall("kotlin/Pair", "getFirst", [], object, receiver: items[0])!
                let value = try jdkCall("kotlin/Pair", "getSecond", [], object, receiver: items[0])!
                return JVMIntrinsicResult(value: try jdkCall("java/util/Collections", "singletonMap", [object, object], .reference("java/util/Map", nullable: false), arguments: [key, value], resolved: resultType))
            }
            if items.count == 1, name == "setOf" {
                return JVMIntrinsicResult(value: try jdkCall("java/util/Collections", "singleton", [object], .reference("java/util/Set", nullable: false), arguments: items, resolved: resultType))
            }
            let collection = try constructJDK(owner)
            for item in items {
                if map {
                    let key = try jdkCall("kotlin/Pair", "getFirst", [], object, receiver: item)!
                    let value = try jdkCall("kotlin/Pair", "getSecond", [], object, receiver: item)!
                    _ = try jdkCall(owner, "put", [object, object], object, receiver: collection, arguments: [key, value])
                } else { _ = try jdkCall(owner, "add", [object], .boolean, receiver: collection, arguments: [item]) }
            }
            let mutable = name.hasPrefix("mutable")
            if mutable { return JVMIntrinsicResult(value: try convert(collection, to: resultType)) }
            let interface = "java/util/" + (map ? "Map" : (set ? "Set" : "List"))
            return JVMIntrinsicResult(value: try jdkCall("java/util/Collections", "unmodifiable" + (map ? "Map" : (set ? "Set" : "List")), [.reference(interface, nullable: false)], .reference(interface, nullable: false), arguments: [collection], resolved: resultType))
        }
        return nil
    }
    func intrinsicMember(_ receiverID: ExprID, name: InternedString, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        let member = context.interner.resolve(name)
        if let sourceType = try? program.expressionType(receiverID), sourceType.referenceName == "java/lang/Object" {
            let object = try requireValue(receiverID)
            if ["hashCode", "toString"].contains(member), args.isEmpty {
                return JVMIntrinsicResult(value: try jdkCall("java/lang/Object", member, [], member == "hashCode" ? .int : .string, receiver: object))
            }
            if member == "equals", args.count == 1 {
                return JVMIntrinsicResult(value: try jdkCall("java/lang/Object", member, [.reference("java/lang/Object", nullable: true)], .boolean, receiver: object, arguments: [requireValue(args[0].expr)]))
            }
        }
        if let text = try stringMember(receiverID, name: member, args: args, id: id) { return text }
        if let scalar = try scalarMember(receiverID, name: member, args: args, id: id) { return scalar }
        if let reflection = try reflectionMember(receiverID, name: member, args: args, id: id) { return reflection }
        guard let sourceType = try? program.expressionType(receiverID) else { return nil }
        if sourceType.referenceName == "kotlin/properties/Delegates", ["notNull", "observable", "vetoable"].contains(member) {
            let receiver = try requireValue(receiverID)
            let object: JVMValueType = .reference("java/lang/Object", nullable: true)
            let parameters: [JVMValueType] = member == "notNull" ? [] : [object, .reference("kotlin/jvm/functions/Function3", nullable: false)]
            let ordered = try arguments(args, binding: program.sema.bindings.callBinding(for: id), parameters: parameters, declarations: nil, id: id)
            return JVMIntrinsicResult(value: try jdkCall("kotlin/properties/Delegates", member, parameters, .reference("kotlin/properties/ReadWriteProperty", nullable: false), receiver: receiver, arguments: ordered.values))
        }
        if sourceType.referenceName == "kotlin/Lazy" {
            let object = try requireValue(receiverID)
            if member == "value", args.isEmpty { return JVMIntrinsicResult(value: try jdkCall("kotlin/Lazy", "getValue", [], .reference("java/lang/Object", nullable: true), receiver: object, interface: true, resolved: program.expressionType(id))) }
            if member == "isInitialized", args.isEmpty { return JVMIntrinsicResult(value: try jdkCall("kotlin/Lazy", "isInitialized", [], .boolean, receiver: object, interface: true)) }
        }
        if ["kotlin/reflect/KProperty", "kotlin/reflect/KMutableProperty"].contains(sourceType.referenceName ?? ""), member == "name", args.isEmpty {
            return JVMIntrinsicResult(value: try jdkCall("kotlin/reflect/KCallable", "getName", [], .string, receiver: requireValue(receiverID), interface: true))
        }
        if let coroutine = try coroutineMember(receiverID, name: member, args: args, id: id) { return coroutine }
        let binding = program.sema.bindings.callBinding(for: id)
        let builtinHOF = binding.flatMap { program.sema.symbols.symbol($0.chosenCallee) }?.fqName.map(context.interner.resolve).starts(with: ["kotlin", "collections"]) == true
        // Array HOF inference may leave no callee binding, including when its
        // callback is an existing function value rather than a lambda literal.
        let intrinsicHOF = binding == nil && higherOrderReceiver(receiverID) && args.last.flatMap { functionType($0.expr) } != nil
        if ["map", "filter", "forEach", "fold"].contains(member), builtinHOF || intrinsicHOF {
            return JVMIntrinsicResult(value: try higherOrder(receiverID, operation: member, args: args, id: id))
        }
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        // `to` is resolved as an extension; evaluate its receiver before the value.
        if member == "to", let binding = program.sema.bindings.callBinding(for: id),
           let symbol = program.sema.symbols.symbol(binding.chosenCallee), symbol.fqName.map(context.interner.resolve) == ["kotlin", "to"], args.count == 1 {
            let left = try convert(requireValue(receiverID), to: object), right = try convert(requireValue(args[0].expr), to: object)
            return JVMIntrinsicResult(value: try constructJDK("kotlin/Pair", parameters: [object, object], arguments: [left, right]))
        }
        guard var owner = sourceType.referenceName else { return nil }
        if owner.hasPrefix("["), member == "copyInto" {
            guard let sourceComponent = try? arrayComponent(sourceType), args.count <= 4 else {
                throw fail("JVM array copyInto requires a compatible array and at most four arguments.", id)
            }
            let source = try requireValue(receiverID)
            var supplied: [Int: JVMValue] = [:]
            let binding = program.sema.bindings.callBinding(for: id)
            for (position, arg) in args.enumerated() {
                let index = binding?.parameterMapping[position]
                    ?? arg.label.flatMap { label in ["destination": 0, "destinationOffset": 1, "startIndex": 2, "endIndex": 3][context.interner.resolve(label)] }
                    ?? position
                guard (0..<4).contains(index), supplied[index] == nil else {
                    throw fail("Invalid JVM array copyInto argument mapping.", id)
                }
                supplied[index] = try requireValue(arg.expr)
            }
            guard let rawDestination = supplied[0] else { throw fail("JVM array copyInto requires a destination.", id) }
            let destination = try convert(rawDestination, to: source.type)
            guard (try? arrayComponent(destination.type)) == sourceComponent else {
                throw fail("JVM array copyInto requires matching array element types.", id)
            }
            let destinationOffset = try convert(supplied[1] ?? constant(.int(0), .int), to: .int)
            let startIndex = try convert(supplied[2] ?? constant(.int(0), .int), to: .int)
            let endIndex: JVMValue
            if let explicitEnd = supplied[3] { endIndex = try convert(explicitEnd, to: .int) }
            else {
                endIndex = try value(.int)
                instructions.append(.arrayLength(source, endIndex))
            }
            let count = try value(.int)
            instructions.append(.binary(.subtract, endIndex, startIndex, count))
            _ = try jdkCall("java/lang/System", "arraycopy", [.reference("java/lang/Object", nullable: false), .int, .reference("java/lang/Object", nullable: false), .int, .int], .unit, arguments: [source, startIndex, destination, destinationOffset, count])
            return JVMIntrinsicResult(value: try convert(destination, to: program.expressionType(id)))
        }
        if ["java/lang/Number", "java/lang/Byte", "java/lang/Short", "java/lang/Integer", "java/lang/Long", "java/lang/Float", "java/lang/Double"].contains(owner) {
            let conversions: [String: (String, JVMValueType)] = ["toByte": ("byteValue", .byte), "toShort": ("shortValue", .short), "toInt": ("intValue", .int), "toLong": ("longValue", .long), "toFloat": ("floatValue", .float), "toDouble": ("doubleValue", .double)]
            if let conversion = conversions[member], args.isEmpty {
                return JVMIntrinsicResult(value: try jdkCall("java/lang/Number", conversion.0, [], conversion.1, receiver: requireValue(receiverID)))
            }
        }
        if owner.hasPrefix("["), member == "get", args.count == 1 {
            return JVMIntrinsicResult(value: try indexedGet(receiverID, [args[0].expr], id))
        }
        if owner.hasPrefix("["), member == "set", args.count == 2 {
            try indexedSet(receiverID, [args[0].expr], args[1].expr, id); return JVMIntrinsicResult(value: nil)
        }
        if member == "indices", args.isEmpty, owner == "[I" || owner.hasPrefix("[L") || owner.hasPrefix("[[") {
            let array: JVMValueType = .reference(owner == "[I" ? "[I" : "[Ljava/lang/Object;", nullable: false)
            return JVMIntrinsicResult(value: try jdkCall("kotlin/collections/ArraysKt", "getIndices", [array], .reference("kotlin/ranges/IntRange", nullable: false), arguments: [requireValue(receiverID)]))
        }
        if owner == "[I", member == "lastIndex", args.isEmpty {
            return JVMIntrinsicResult(value: try jdkCall("kotlin/collections/ArraysKt", "getLastIndex", [.reference("[I", nullable: false)], .int, arguments: [requireValue(receiverID)]))
        }
        if owner.hasPrefix("["), member == "size", args.isEmpty {
            let source = try requireValue(receiverID), result = try value(.int)
            instructions.append(.arrayLength(source, result)); return JVMIntrinsicResult(value: result)
        }
        let collections: Set<String> = ["java/util/ArrayList", "java/lang/Iterable", "java/util/Iterator", "java/util/Collection", "java/util/List", "kotlin/enums/EnumEntries", "java/util/Set", "java/util/Map", "kotlin/text/MatchGroupCollection"]
        if collections.contains(owner) {
            // JDK collection interfaces retain the virtual Object contract;
            // their implementations provide structural equality and hashing.
            if ["hashCode", "toString"].contains(member), args.isEmpty {
                return JVMIntrinsicResult(value: try jdkCall("java/lang/Object", member, [], member == "hashCode" ? .int : .string, receiver: requireValue(receiverID)))
            }
            if member == "equals", args.count == 1 {
                let receiver = try requireValue(receiverID), argument = try requireValue(args[0].expr)
                return JVMIntrinsicResult(value: try jdkCall("java/lang/Object", member, [object], .boolean, receiver: receiver, arguments: [argument]))
            }
            if let selected = try mappedBuiltinMemberOwner(id), collections.contains(selected) { owner = selected }
            if owner == "java/util/ArrayList" { owner = "java/util/List" }
            if ["set", "add", "remove", "removeAt", "put", "clear"].contains(member) { try requireMutableCollection(receiverID, at: id) }
            if ["set", "add", "put"].contains(member) { try requireWritableArguments(receiverID, at: id) }
            let source = try convert(requireValue(receiverID), to: .reference(owner, nullable: false))
            let result = try program.expressionType(id)
            var values: [JVMValue] = []
            for arg in args { values.append(try requireValue(arg.expr)) }
            let parameters: [JVMValueType], returns: JVMValueType, actual: String
            switch member {
            case "size": actual = "size"; parameters = []; returns = .int
            case "keys": actual = "keySet"; parameters = []; returns = .reference("java/util/Set", nullable: false)
            case "values": actual = "values"; parameters = []; returns = .reference("java/util/Collection", nullable: false)
            case "isEmpty", "hasNext": actual = member; parameters = []; returns = .boolean
            case "iterator": actual = member; parameters = []; returns = .reference("java/util/Iterator", nullable: false)
            case "next": actual = member; parameters = []; returns = object
            case "get": actual = member; parameters = [["java/util/List", "kotlin/enums/EnumEntries"].contains(owner) ? .int : object]; returns = object
            case "set": actual = owner == "java/util/Map" ? "put" : "set"; parameters = [["java/util/List", "kotlin/enums/EnumEntries"].contains(owner) ? .int : object, object]; returns = object
            case "add", "remove", "contains", "containsKey": actual = member; parameters = [object]; returns = owner == "java/util/Map" && member == "remove" ? object : .boolean
            case "removeAt": actual = "remove"; parameters = [.int]; returns = object
            case "put": actual = member; parameters = [object, object]; returns = object
            case "clear": actual = member; parameters = []; returns = .unit
            default: throw fail("Unsupported JVM collection member: \(member).", id)
            }
            guard values.count == parameters.count else { throw fail("JVM collection argument mismatch.", id) }
            let value = try jdkCall(owner, actual, parameters, returns, receiver: source, arguments: values, interface: true, resolved: result == .unit ? returns : result)
            return JVMIntrinsicResult(value: result == .unit ? nil : value)
        }
        if owner == "kotlin/Pair", ["first", "second"].contains(member) {
            return JVMIntrinsicResult(value: try jdkCall(owner, member == "first" ? "getFirst" : "getSecond", [], object, receiver: requireValue(receiverID), resolved: program.expressionType(id)))
        }
        let throwable = program.sema.symbols.lookup(fqName: [context.interner.intern("kotlin"), context.interner.intern("Throwable")])
        let throwableType = throwable.map { program.sema.types.make(.classType(ClassType(classSymbol: $0))) }
        let semanticReceiver = program.sema.bindings.exprType(for: receiverID)
        if member == "message", args.isEmpty, let throwableType, let semanticReceiver, program.sema.types.isSubtype(semanticReceiver, throwableType) {
            return JVMIntrinsicResult(value: try jdkCall("java/lang/Throwable", "getMessage", [], .reference("java/lang/String", nullable: true), receiver: requireValue(receiverID)))
        }
        return nil
    }
    func reifiedArrayElement(_ arg: TypeArg) -> TypeID? {
        switch arg { case let .invariant(t), let .out(t): return t; default: return nil }
    }
    func allocateArray(_ type: JVMValueType, semantic: TypeID?, count: JVMValue, id: ExprID) throws -> JVMValue {
        guard let semantic, isReifiableArray(semantic) else { throw fail("JVM array creation requires a reifiable element type.", id) }
        let result = try value(type), element = try arrayComponent(type)
        // Constructors and factories need the same runtime component token;
        // exported inline bodies must retain an allocation reification marker.
        if case let .classType(t) = program.sema.types.kind(of: semantic), let arg = t.args.first,
           let component = reifiedArrayElement(arg) {
            if let token = try runtimeReifiedToken(component) {
                instructions.append(.copy(try convert(reflectiveArray(token.klass, count: count), to: type), result))
            } else if let name = program.reifiedUse(component) { instructions.append(.reifiedOperation(0, name, count, result)) }
            else { instructions.append(.newArray(element, count: count, result: result)) }
        } else { instructions.append(.newArray(element, count: count, result: result)) }
        return result
    }
    func isReifiableArray(_ id: TypeID) -> Bool {
        guard case let .classType(t) = program.sema.types.kind(of: program.specialized(id)), (try? program.className(t.classSymbol)) == "kotlin/Array" else { return true }
        guard let arg = t.args.first else { return false }
        let element: TypeID
        switch arg { case let .invariant(t), let .out(t): element = t; default: return true }
        if case .typeParam = program.sema.types.kind(of: element) { return program.isReifiedParameter(element) }
        return isReifiableArray(element)
    }
    func arrayComponent(_ type: JVMValueType) throws -> JVMValueType {
        guard let name = type.referenceName, name.hasPrefix("[") else { throw fail("Expected a JVM array.") }
        if case let .unsignedArray(p, _) = type { return .primitive(p) }
        let descriptor = String(name.dropFirst())
        switch descriptor {
        case "B": return .byte
        case "S": return .short
        case "C": return .char
        case "I": return .int
        case "J": return .long
        case "F": return .float
        case "D": return .double
        case "Z": return .boolean
        default:
            if descriptor.hasPrefix("[") { return .reference(descriptor, nullable: true) }
            guard descriptor.hasPrefix("L"), descriptor.hasSuffix(";") else { throw fail("Unsupported JVM array component.") }
            return .reference(String(descriptor.dropFirst().dropLast()), nullable: true)
        }
    }
    func indexedGet(_ receiver: ExprID, _ indices: [ExprID], _ id: ExprID) throws -> JVMValue {
        guard indices.count == 1 else { throw fail("JVM indexing requires one index.", id) }
        if let call = try textLibraryCall(indices.map { CallArgument(expr: $0) }, receiver: receiver, id: id), let value = call.value { return value }
        var object = try requireValue(receiver)
        // An intersection can retain Iterable as its erased local type while
        // Sema selects List.get from a smart-cast branch.
        if let owner = try mappedBuiltinMemberOwner(id),
           ["java/util/List", "java/util/Map", "kotlin/enums/EnumEntries"].contains(owner) {
            object = try convert(object, to: .reference(owner, nullable: false))
        }
        return try indexedRead(object, index: requireValue(indices[0]), type: program.expressionType(id))
    }
    func indexedRead(_ object: JVMValue, index: JVMValue, type: JVMValueType) throws -> JVMValue {
        if object.type.referenceName == "java/util/ArrayList" {
            return try indexedRead(convert(object, to: .reference("java/util/List", nullable: false)), index: index, type: type)
        }
        if object.type.isCharSequence {
            let owner = object.type.referenceName!, source = try convert(object, to: .reference(owner, nullable: false))
            return try jdkCall(owner, "charAt", [.int], .char, receiver: source, arguments: [index], interface: owner == "java/lang/CharSequence")!
        }
        if object.type.referenceName?.hasPrefix("[") == true {
            let index = try convert(index, to: .int), result = try value(type)
            instructions.append(.arrayGet(object, index, result)); return result
        }
        guard let owner = object.type.referenceName, ["java/util/List", "kotlin/enums/EnumEntries", "java/util/Map"].contains(owner) else { throw fail("Unsupported JVM indexed receiver.") }
        return try jdkCall(owner, "get", [["java/util/List", "kotlin/enums/EnumEntries"].contains(owner) ? .int : .reference("java/lang/Object", nullable: true)], .reference("java/lang/Object", nullable: true), receiver: object, arguments: [index], interface: true, resolved: type)!
    }
    func requireWritableArguments(_ receiver: ExprID, at id: ExprID) throws {
        guard let semantic = program.sema.bindings.exprType(for: receiver), case let .classType(t) = program.sema.types.kind(of: semantic) else { return }
        for argument in t.args {
            switch argument {
            case .out, .star: throw fail("Cannot write through an out/star-projected JVM type.", id)
            case .invariant, .in: break
            }
        }
    }
    func requireMutableCollection(_ receiver: ExprID, at id: ExprID) throws {
        func mutable(_ type: TypeID) -> Bool {
            switch program.sema.types.kind(of: type) {
            case let .classType(t):
                let name = (try? program.className(t.classSymbol)) ?? ""
                return name.hasPrefix("kotlin/collections/Mutable") || name.hasPrefix("java/util/")
            case let .typeParam(t): return program.sema.symbols.typeParameterUpperBounds(for: t.symbol).contains(where: mutable)
            default: return false
            }
        }
        guard let type = program.sema.bindings.exprType(for: receiver), mutable(type) else { throw fail("Cannot mutate a read-only JVM collection.", id) }
    }
    func indexedSet(_ receiver: ExprID, _ indices: [ExprID], _ source: ExprID, _ id: ExprID) throws {
        guard indices.count == 1 else { throw fail("JVM indexing requires one index.", id) }
        let object = try requireValue(receiver), index = try requireValue(indices[0]), value = try requireValue(source)
        try requireWritableArguments(receiver, at: id)
        if object.type.referenceName?.hasPrefix("[") != true && object.type.referenceName != "java/lang/StringBuilder" { try requireMutableCollection(receiver, at: id) }
        try indexedWrite(object, index: index, source: value)
    }
    func indexedWrite(_ object: JVMValue, index: JVMValue, source: JVMValue) throws {
        if object.type.referenceName == "java/util/ArrayList" {
            try indexedWrite(convert(object, to: .reference("java/util/List", nullable: false)), index: index, source: source); return
        }
        if object.type.referenceName == "java/lang/StringBuilder" {
            _ = try jdkCall("java/lang/StringBuilder", "setCharAt", [.int, .char], .unit, receiver: object, arguments: [index, source]); return
        }
        if object.type.referenceName?.hasPrefix("[") == true {
            let index = try convert(index, to: .int), source = try convert(source, to: arrayComponent(object.type))
            instructions.append(.arraySet(object, index, source)); return
        }
        guard let owner = object.type.referenceName, ["java/util/List", "kotlin/enums/EnumEntries", "java/util/Map"].contains(owner) else { throw fail("Unsupported JVM indexed receiver.") }
        let any: JVMValueType = .reference("java/lang/Object", nullable: true)
        _ = try jdkCall(owner, ["java/util/List", "kotlin/enums/EnumEntries"].contains(owner) ? "set" : "put", [["java/util/List", "kotlin/enums/EnumEntries"].contains(owner) ? .int : any, any], any, receiver: object, arguments: [index, source], interface: true)
    }
    func indexedCompound(_ op: CompoundAssignOp, _ receiver: ExprID, _ indices: [ExprID], _ source: ExprID, _ id: ExprID) throws -> JVMValue? {
        guard indices.count == 1 else { throw fail("JVM indexing requires one index.", id) }
        let object = try requireValue(receiver), index = try requireValue(indices[0])
        try requireWritableArguments(receiver, at: id)
        if object.type.referenceName?.hasPrefix("[") != true && object.type.referenceName != "java/lang/StringBuilder" { try requireMutableCollection(receiver, at: id) }
        let type: JVMValueType
        if object.type.referenceName?.hasPrefix("[") == true { type = try arrayComponent(object.type) }
        else if let semantic = program.sema.bindings.exprType(for: receiver), case let .classType(t) = program.sema.types.kind(of: semantic), let arg = object.type.referenceName == "java/util/Map" ? t.args.last : t.args.first,
                case let .invariant(element) = arg { type = try program.type(object.type.referenceName == "java/util/Map" ? program.sema.types.withNullability(.nullable, for: element) : element) }
        else { type = try program.expressionType(source) }
        let left = try indexedRead(object, index: index, type: type), right = try compoundOperand(source, target: type)
        if terminated { return nil }
        guard try permitsCompound(left.type, right.type) else { throw fail("Unsupported JVM indexed compound assignment.", id) }
        let result = try value(left.type)
        let ops: [CompoundAssignOp: BinaryOp] = [.plusAssign: .add, .minusAssign: .subtract, .timesAssign: .multiply, .divAssign: .divide, .modAssign: .modulo]
        try compoundInstruction(ops[op]!, left, right, result); try indexedWrite(object, index: index, source: result)
        return arena.incrementDecrementReturnsValue(id) ? result : nil
    }
}

extension JVMFunctionBuilder {
    func sequenceLoop(_ name: InternedString, _ iterable: ExprID, _ body: ExprID, _ id: ExprID) throws {
        let source = try requireValue(iterable)
        let elementType: JVMValueType
        if source.type.isCharSequence { elementType = .char }
        else if source.type.referenceName == "kotlin/ranges/IntRange" { elementType = .int }
        else if let semantic = program.sema.bindings.exprType(for: iterable), case let .classType(t) = program.sema.types.kind(of: semantic), let arg = t.args.first {
            switch arg {
            case let .invariant(t), let .out(t): elementType = try program.type(t)
            default: elementType = .reference("java/lang/Object", nullable: true)
            }
        } else if source.type.referenceName?.hasPrefix("[") == true { elementType = try arrayComponent(source.type) }
        else { throw fail("JVM for requires an array or iterable collection.", id) }
        let local = try value(elementType), test = label(), advance = label(), exit = label()
        scopes.append([name: Local(value: local, mutable: false)]); defer { scopes.removeLast() }
        if source.type.referenceName?.hasPrefix("[") == true || source.type.isCharSequence {
            let index = try value(.int)
            let fixedSize = source.type.referenceName != "java/lang/String" && source.type.referenceName?.hasPrefix("[") != true ? nil : try textLength(source)
            instructions.append(.constant(.int(0), index))
            mark(test)
            // CharSequence may change length while the body executes.
            let size = try fixedSize ?? textLength(source)
            let check = try value(.boolean); instructions.append(.binary(.lessThan, index, size, check)); instructions.append(.jumpIfFalse(check, exit))
            let item = try indexedRead(source, index: index, type: elementType)
            instructions.append(.copy(item, local))
            loops.append((exit, advance, pendingAllocations.count)); _ = try expression(body, discarded: true); loops.removeLast()
            mark(advance)
            let one = try constant(.int(1), .int)
            instructions.append(.binary(.add, index, one, index)); jump(test)
        } else {
            let iterator = try jdkCall(source.type.referenceName == "kotlin/sequences/Sequence" ? "kotlin/sequences/Sequence" : "java/lang/Iterable", "iterator", [], .reference("java/util/Iterator", nullable: false), receiver: source, interface: true)!
            mark(test)
            let check = try jdkCall("java/util/Iterator", "hasNext", [], .boolean, receiver: iterator, interface: true)!
            instructions.append(.jumpIfFalse(check, exit))
            let next = try jdkCall("java/util/Iterator", "next", [], .reference("java/lang/Object", nullable: true), receiver: iterator, interface: true, resolved: elementType)!
            instructions.append(.copy(next, local))
            loops.append((exit, advance, pendingAllocations.count)); _ = try expression(body, discarded: true); loops.removeLast()
            mark(advance); jump(test)
        }
        mark(exit)
    }
}
