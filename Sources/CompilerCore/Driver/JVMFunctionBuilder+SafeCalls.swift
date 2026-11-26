extension JVMFunctionBuilder {
    // Float/Double.toRawBits()/toBits() are @InlineOnly in kotlin-stdlib, so there is
    // no kotlin.NumbersKt facade method to call. Match them by the *callee* symbol
    // (not the call-site name, so aliased imports resolve too) and only for the
    // bundled-stdlib declarations, so user/library extensions of the same name win.
    func stdlibBitReinterpretIsRaw(_ callee: SymbolID, args: [CallArgument]) -> Bool? {
        guard args.isEmpty, let symbol = program.sema.symbols.symbol(callee),
              symbol.declSite.map({ context.sourceManager.origin(of: $0.start.file) != .user }) ?? true
        else { return nil }
        // Restrict to the bundled kotlin.* declarations by fqName: a same-named
        // extension loaded from a classpath JAR (e.g. package ext) also carries a
        // non-.user declSite origin, so the origin guard alone would misroute it
        // to the java.lang intrinsic instead of the user's extension.
        let fqName = symbol.fqName
        guard fqName.count == 2, context.interner.resolve(fqName[0]) == "kotlin" else { return nil }
        switch context.interner.resolve(fqName[1]) {
        case "toRawBits": return true
        case "toBits": return false
        default: return nil
        }
    }

    // Float/Double.fromBits are inline companion functions in kotlin-stdlib.
    // The primitive companions have no runtime receiver in the JVM mapping, so
    // lower them directly to the java.lang bit-conversion intrinsics.
    func stdlibFromBitsIsFloat(_ callee: SymbolID, args: [CallArgument]) -> Bool? {
        guard args.count == 1, !args[0].isSpread, let symbol = program.sema.symbols.symbol(callee),
              symbol.declSite.map({ context.sourceManager.origin(of: $0.start.file) != .user }) ?? true
        else { return nil }
        let fqName = symbol.fqName
        guard fqName.count == 2, context.interner.resolve(fqName[0]) == "kotlin",
              context.interner.resolve(fqName[1]) == "fromBits",
              let signature = program.sema.symbols.functionSignature(for: callee),
              let receiverType = signature.receiverType,
              case let .classType(companionType) = program.sema.types.kind(of: receiverType),
              let companion = program.sema.symbols.symbol(companionType.classSymbol)
        else { return nil }
        switch companion.fqName.map(context.interner.resolve) {
        case ["kotlin", "Float", "Companion"]: return true
        case ["kotlin", "Double", "Companion"]: return false
        default: return nil
        }
    }

    func emitFromBits(args: [CallArgument], isFloat: Bool, id: ExprID) throws -> JVMValue? {
        guard args.count == 1 else { return nil }
        let argument = try requireValue(args[0].expr)
        if isFloat {
            let bits = try convert(argument, to: .int)
            return try jdkCall("java/lang/Float", "intBitsToFloat", [.int], .float, arguments: [bits], resolved: program.expressionType(id))
        }
        let bits = try convert(argument, to: .long)
        return try jdkCall("java/lang/Double", "longBitsToDouble", [.long], .double, arguments: [bits], resolved: program.expressionType(id))
    }

    func emitBitReinterpret(callee: SymbolID, receiver: JVMValue, isRaw: Bool, id: ExprID) throws -> JVMValue? {
        guard let signature = program.sema.symbols.functionSignature(for: callee),
              let receiverTypeRef = signature.receiverType else { return nil }
        let receiverType = try program.type(receiverTypeRef)
        let primitive = try convert(receiver, to: receiverType)
        switch receiverType {
        case .float:
            return try jdkCall("java/lang/Float", isRaw ? "floatToRawIntBits" : "floatToIntBits", [.float], .int, arguments: [primitive], resolved: program.expressionType(id))
        case .double:
            return try jdkCall("java/lang/Double", isRaw ? "doubleToRawLongBits" : "doubleToLongBits", [.double], .long, arguments: [primitive], resolved: program.expressionType(id))
        default:
            return nil
        }
    }

    func memberExpression(_ id: ExprID, receiver: ExprID, name: InternedString, typeArgs: [TypeRefID], args: [CallArgument]) throws -> JVMValue? {
        if let argument = samConstructorArgument(args, id: id) { return try expression(argument) }
        if context.interner.resolve(name) == "isInitialized", args.isEmpty, let result = try lateinitInitialized(receiver) { return result }
        if let callee = program.sema.bindings.callBinding(for: id)?.chosenCallee,
           let isRaw = stdlibBitReinterpretIsRaw(callee, args: args),
           let emitted = try emitBitReinterpret(callee: callee, receiver: requireValue(receiver), isRaw: isRaw, id: id) {
            return emitted
        }
        if let callee = program.sema.bindings.callBinding(for: id)?.chosenCallee,
           let isFloat = stdlibFromBitsIsFloat(callee, args: args),
           let emitted = try emitFromBits(args: args, isFloat: isFloat, id: id) {
            return emitted
        }
        if let symbol = program.sema.bindings.callBinding(for: id)?.chosenCallee,
           let result = try resultCompanionCall(symbol, args: args, id: id) { return result.value }
        if let symbol = program.sema.bindings.callBinding(for: id)?.chosenCallee,
           let result = try stringCompanionFormatCall(symbol, receiver: receiver, args: args, id: id) { return result.value }
        if !arena.isExplicitCall(id), let value = try nominalValue(id) { return value }
        if !arena.isExplicitCall(id), let value = try readCompositionLocal(id, receiver: receiver) { return value }
        if !arena.isExplicitCall(id), context.interner.resolve(name) == "Companion",
           let receiverSymbol = program.sema.bindings.identifierSymbol(for: receiver),
           let value = try importedCompanionValue(for: receiverSymbol) { return value }
        if let value = try nominalCall(id, receiver: receiver, name: context.interner.resolve(name), args: args) { return value.value }
        let member = context.interner.resolve(name)
        let collectionOwners: Set<String> = ["java/lang/Iterable", "java/util/Iterator", "java/util/ListIterator", "java/util/Collection", "java/util/List", "java/util/Set", "java/util/Map", "java/util/ArrayList", "kotlin/enums/EnumEntries"]
        let collectionMembers: Set<String> = ["add", "addAll", "clear", "contains", "containsAll", "containsKey", "containsValue", "equals", "get", "hasNext", "hasPrevious", "hashCode", "indexOf", "isEmpty", "iterator", "lastIndexOf", "listIterator", "next", "nextIndex", "previous", "previousIndex", "put", "remove", "removeAll", "removeAt", "retainAll", "set", "subList", "toString"]
        if let receiverType = try? program.expressionType(receiver),
           collectionOwners.contains(receiverType.referenceName ?? ""), collectionMembers.contains(member),
           let result = try intrinsicMember(receiver, name: name, args: args, id: id) {
            return result.value
        }
        if !arena.isExplicitCall(id), let property = propertyBinding(id) {
            if let literal = property.field?.constantValue,
               let symbol = program.sema.bindings.identifierSymbol(for: receiver),
               program.classes[symbol]?.isObject == true || program.sema.symbols.companionObjectSymbol(for: symbol) != nil {
                return try constant(literal, property.type)
            }
            let object: JVMValue
            if property.getter.isStatic && property.getter.parameters.isEmpty { object = try constant(.null, .reference("java/lang/Object", nullable: true)) }
            else if case let .nameRef(qualifier, _) = arena.expr(receiver), !scopes.contains(where: { $0[qualifier] != nil }),
                    let plan = program.classes.values.first(where: { $0.name == property.getter.owner && $0.isObject }),
                    program.sema.symbols.symbol(plan.symbol)?.name == qualifier {
                object = try singleton(plan)
            } else { object = try requireValue(receiver) }
            return try convert(readProperty(property, receiver: object, at: id, special: isSuper(receiver), superReceiver: receiver), to: program.expressionType(id))
        }
        if !arena.isExplicitCall(id), let result = try textLibraryProperty(id, receiver: receiver) { return result }
        if let result = try nominalPropertyInvocation(id, receiver: receiver, args: args) { return result.value }
        if let result = try textLibraryCall(args, receiver: receiver, id: id) { return result.value }
        if let result = try inlineCall(args, receiver: receiver, id: id) { return result.value }
        if member == "call",
           let result = try reflectionMember(receiver, name: member, args: args, id: id) { return result.value }
        if let result = try sourceCall(args, receiver: receiver, id: id) { return result.value }
        if let result = try extensionOrInvoke(receiver, name: name, args: args, id: id) { return result.value }
        if let result = try intrinsicMember(receiver, name: name, args: args, id: id) { return result.value }
        if let atomicArray = try javaAtomicArrayMethod(receiver, id: id, name: name, args: args) {
            let object = try convert(requireValue(receiver), to: .reference(atomicArray.owner, nullable: false))
            return try jdkCall(atomicArray.owner, atomicArray.name, atomicArray.parameters, atomicArray.result, receiver: object, arguments: try args.map { try requireValue($0.expr) }, resolved: atomicArray.resolved)
        }
        if let atomic = try javaAtomicReferenceMethod(id, name: name, args: args) {
            let object = try convert(requireValue(receiver), to: .reference("java/util/concurrent/atomic/AtomicReference", nullable: false))
            return try jdkCall("java/util/concurrent/atomic/AtomicReference", atomic.name, atomic.parameters, atomic.result, receiver: object, arguments: try args.map { try requireValue($0.expr) }, resolved: atomic.resolved)
        }
        if let binding = program.sema.bindings.callBinding(for: id), var method = program.methods[binding.chosenCallee] ?? context.jvmImports?.method(for: binding.chosenCallee) ?? program.builtinMethod(binding.chosenCallee) {
            guard args.allSatisfy({ $0.label == nil && !$0.isSpread }) else { throw fail("Unsupported JVM foreign arguments.", id) }
            if isSuper(receiver) { method = try superMethod(method, receiver: receiver) }
            let object = method.isStatic || method.isConstructor ? nil : try requireValue(receiver)
            return try foreign(method, receiver: object, args: args, id: id)
        }
        if member == "step", typeArgs.isEmpty, args.count == 1, !args[0].isSpread,
           let result = try rangeStepCall(receiver: receiver, step: args[0].expr) {
            return result
        }
        if member == "compare", args.count == 2,
           let receiverType = try? program.expressionType(receiver),
           receiverType.referenceName == "java/util/Comparator",
           args.allSatisfy({ $0.label == nil && !$0.isSpread }) {
            let comparator = try convert(requireValue(receiver), to: .reference("java/util/Comparator", nullable: false))
            let object = JVMValueType.reference("java/lang/Object", nullable: true)
            let values = try args.map { try convert(requireValue($0.expr), to: object) }
            return try jdkCall("java/util/Comparator", "compare", [object, object], .int, receiver: comparator, arguments: values, interface: true)
        }
        let source = try requireValue(receiver)
        if member == "not", source.type == .boolean, args.isEmpty, typeArgs.isEmpty {
            let result = try value(.boolean)
            instructions.append(.unary(.not, source, result))
            return result
        }
        let targets = Self.numericConversions
        guard source.type.isNumeric, args.isEmpty, typeArgs.isEmpty,
              let target = targets[context.interner.resolve(name)] else { throw fail("Unsupported JVM member: \(context.interner.resolve(name)).", id) }
        return try convert(source, to: target)
    }

    private func javaAtomicReferenceMethod(_ id: ExprID, name: InternedString, args: [CallArgument]) throws -> (name: String, parameters: [JVMValueType], result: JVMValueType, resolved: JVMValueType)? {
        guard let binding = program.sema.bindings.callBinding(for: id),
              let parent = program.sema.symbols.parentSymbol(for: binding.chosenCallee),
              (try? program.className(parent)) == "java/util/concurrent/atomic/AtomicReference",
              args.allSatisfy({ $0.label == nil && !$0.isSpread }) else { return nil }
        let member = context.interner.resolve(name)
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let javaName: String
        let parameters: [JVMValueType]
        switch member {
        case "load", "get":
            javaName = "get"; parameters = []
        case "store", "set":
            javaName = "set"; parameters = [object]
        case "exchange", "getAndSet":
            javaName = "getAndSet"; parameters = [object]
        case "compareAndSet", "compareAndExchange":
            javaName = member; parameters = [object, object]
        default:
            return nil
        }
        guard args.count == parameters.count else { return nil }
        let result: JVMValueType = javaName == "set" ? .unit : (javaName == "compareAndSet" ? .boolean : object)
        return (javaName, parameters, result, try program.expressionType(id))
    }

    private func javaAtomicArrayMethod(_ receiver: ExprID, id: ExprID, name: InternedString, args: [CallArgument]) throws -> (owner: String, name: String, parameters: [JVMValueType], result: JVMValueType, resolved: JVMValueType)? {
        guard let binding = program.sema.bindings.callBinding(for: id),
              let symbol = program.sema.symbols.symbol(binding.chosenCallee),
              symbol.declSite.map({ context.sourceManager.origin(of: $0.start.file) != .user }) ?? true,
              args.allSatisfy({ $0.label == nil && !$0.isSpread }),
              let receiverType = try? program.expressionType(receiver),
              let owner = receiverType.referenceName else { return nil }
        let element: JVMValueType
        switch owner {
        case "java/util/concurrent/atomic/AtomicIntegerArray": element = .int
        case "java/util/concurrent/atomic/AtomicLongArray": element = .long
        default: return nil
        }
        if context.interner.resolve(name) == "compareAndExchangeAt", context.options.jvmTarget == .java8 { return nil }
        let index: JVMValueType = .int
        let javaName: String
        let parameters: [JVMValueType]
        let result: JVMValueType
        switch context.interner.resolve(name) {
        case "loadAt":
            javaName = "get"; parameters = [index]; result = element
        case "storeAt":
            javaName = "set"; parameters = [index, element]; result = .unit
        case "exchangeAt":
            javaName = "getAndSet"; parameters = [index, element]; result = element
        case "compareAndSetAt":
            javaName = "compareAndSet"; parameters = [index, element, element]; result = .boolean
        case "compareAndExchangeAt":
            javaName = "compareAndExchange"; parameters = [index, element, element]; result = element
        case "fetchAndAddAt":
            javaName = "getAndAdd"; parameters = [index, element]; result = element
        case "addAndFetchAt":
            javaName = "addAndGet"; parameters = [index, element]; result = element
        case "fetchAndIncrementAt":
            javaName = "getAndIncrement"; parameters = [index]; result = element
        case "incrementAndFetchAt":
            javaName = "incrementAndGet"; parameters = [index]; result = element
        case "fetchAndDecrementAt":
            javaName = "getAndDecrement"; parameters = [index]; result = element
        case "decrementAndFetchAt":
            javaName = "decrementAndGet"; parameters = [index]; result = element
        default:
            return nil
        }
        guard args.count == parameters.count else { return nil }
        return (owner, javaName, parameters, result, try program.expressionType(id))
    }

    func safeMemberExpression(_ id: ExprID, receiver: ExprID, name: InternedString, typeArgs: [TypeRefID], args: [CallArgument], discarded: Bool) throws -> JVMValue? {
        let source = try requireValue(receiver)
        let type = try program.expressionType(id)
        if source.type.referenceName == nil {
            let saved = evaluatedOperands
            evaluatedOperands[receiver] = source
            defer { evaluatedOperands = saved }
            return try memberExpression(id, receiver: receiver, name: name, typeArgs: typeArgs, args: args).map { try convert($0, to: type) }
        }
        let result = type == .unit || discarded ? nil : try value(type)
        let nullCase = label(), end = label()
        if source.type.referenceName != nil {
            let null = try constant(.null, .reference("java/lang/Object", nullable: true)), check = try value(.boolean)
            instructions.append(.referenceCompare(.notEqual, source, null, check))
            instructions.append(.jumpIfFalse(check, nullCase))
        }
        let saved = evaluatedOperands
        defer { evaluatedOperands = saved }
        let nonNullType: JVMValueType
        if let semantic = program.sema.bindings.exprType(for: receiver),
           case let .primitive(primitive, _) = program.sema.types.kind(of: program.specialized(semantic)) {
            nonNullType = .primitive(primitive)
        } else if let name = source.type.referenceName { nonNullType = .reference(name, nullable: false) }
        else { nonNullType = source.type }
        evaluatedOperands[receiver] = try convert(source, to: nonNullType)
        let returned: JVMValue?
        do { returned = try memberExpression(id, receiver: receiver, name: name, typeArgs: typeArgs, args: args) }
        catch is JVMTerminatedExpression { returned = nil }
        if !terminated {
            if let result {
                if let returned { instructions.append(.copy(try convert(returned, to: type), result)) }
                else {
                    guard type.referenceName == "kotlin/Unit" else { throw fail("JVM safe member call must produce a value.", id) }
                    program.functionArities.insert(0)
                    instructions.append(.getStatic(JVMField(owner: "kotlin/Unit", name: "INSTANCE", type: .reference("kotlin/Unit", nullable: false), access: 0x19), result))
                }
            }
            jump(end)
        }
        mark(nullCase)
        if let result { instructions.append(.constant(.null, result)) }
        mark(end)
        return result
    }
}
