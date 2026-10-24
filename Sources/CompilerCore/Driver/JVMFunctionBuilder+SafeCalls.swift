extension JVMFunctionBuilder {
    func memberExpression(_ id: ExprID, receiver: ExprID, name: InternedString, typeArgs: [TypeRefID], args: [CallArgument]) throws -> JVMValue? {
        if context.interner.resolve(name) == "isInitialized", args.isEmpty, let result = try lateinitInitialized(receiver) { return result }
        if let symbol = program.sema.bindings.callBinding(for: id)?.chosenCallee,
           let result = try resultCompanionCall(symbol, args: args, id: id) { return result.value }
        if !arena.isExplicitCall(id), let value = try nominalValue(id) { return value }
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
                // A qualified delegated property can bind its owner without
                // attaching a separate value binding to the object qualifier.
                object = try singleton(plan)
            } else { object = try requireValue(receiver) }
            return try convert(readProperty(property, receiver: object, special: isSuper(receiver), superReceiver: receiver), to: program.expressionType(id))
        }
        if !arena.isExplicitCall(id), let result = try textLibraryProperty(id, receiver: receiver) { return result }
        if let result = try nominalPropertyInvocation(id, receiver: receiver, args: args) { return result.value }
        if let result = try textLibraryCall(args, receiver: receiver, id: id) { return result.value }
        if let result = try inlineCall(args, receiver: receiver, id: id) { return result.value }
        if let result = try sourceCall(args, receiver: receiver, id: id) { return result.value }
        if let result = try extensionOrInvoke(receiver, name: name, args: args, id: id) { return result.value }
        if let result = try intrinsicMember(receiver, name: name, args: args, id: id) { return result.value }
        if let binding = program.sema.bindings.callBinding(for: id), var method = program.methods[binding.chosenCallee] ?? context.jvmImports?.methods[binding.chosenCallee] ?? program.builtinMethod(binding.chosenCallee) {
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
        let targets = Self.numericConversions
        guard source.type.isNumeric, args.isEmpty, typeArgs.isEmpty,
              let target = targets[context.interner.resolve(name)] else { throw fail("Unsupported JVM member: \(context.interner.resolve(name)).", id) }
        return try convert(source, to: target)
    }

    func safeMemberExpression(_ id: ExprID, receiver: ExprID, name: InternedString, typeArgs: [TypeRefID], args: [CallArgument], discarded: Bool) throws -> JVMValue? {
        // Snapshot the receiver before branching. Arguments and the ordinary
        // member dispatcher execute only on the non-null edge.
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
