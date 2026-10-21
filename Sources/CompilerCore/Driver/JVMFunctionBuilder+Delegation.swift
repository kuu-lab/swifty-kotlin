import Foundation

extension JVMFunctionBuilder {
    func propertyToken(name: String, owner: String, signature: String, topLevel: Bool, mutable: Bool = false) throws -> JVMValue {
        let klass = try javaClass(.reference(owner, nullable: false))
        let methodSignature = try value(.string)
        if let paren = signature.firstIndex(of: "(") {
            instructions.append(.callableSignature(owner, String(signature[..<paren]), String(signature[paren...]), methodSignature))
        } else { instructions.append(.constant(.string(signature), methodSignature)) }
        let implementation = "kotlin/jvm/internal/" + (mutable ? "MutablePropertyReference" : "PropertyReference") + (topLevel ? "0Impl" : "1Impl")
        return try constructJDK(implementation, parameters: [klass.type, .string, .string, .int], arguments: [klass, constant(.string(name), .string), methodSignature, constant(.int(topLevel ? 1 : 0), .int)])
    }
    func delegateToken(_ symbol: SymbolID, plan: JVMClassPlan) throws -> JVMValue {
        if let field = plan.propertyTokens[symbol] {
            let token = try value(field.type); instructions.append(.getStatic(field, token)); return token
        }
        return try constant(.null, .reference("kotlin/reflect/KProperty", nullable: true))
    }
    func delegateThis(_ symbol: SymbolID) throws -> JVMValue {
        if program.sema.symbols.symbol(symbol)?.kind != .local, owner?.isFacade != true, let thisValue { return thisValue }
        return try constant(.null, .reference("java/lang/Object", nullable: true))
    }
    func delegateCall(_ symbol: SymbolID, delegate: JVMValue, arguments: [JVMValue]) throws -> JVMValue? {
        if let parent = program.sema.symbols.parentSymbol(for: symbol), let ownerName = try? program.className(parent), ["kotlin/properties/ReadOnlyProperty", "kotlin/properties/ReadWriteProperty"].contains(ownerName) {
            let object: JVMValueType = .reference("java/lang/Object", nullable: true)
            let token: JVMValueType = .reference("kotlin/reflect/KProperty", nullable: false)
            let name = context.interner.resolve(program.sema.symbols.symbol(symbol)!.name)
            return try jdkCall(ownerName, name, name == "getValue" ? [object, token] : [object, token, object], name == "getValue" ? object : .unit, receiver: convert(delegate, to: .reference(ownerName, nullable: false)), arguments: arguments, interface: true)
        }
        if let method = program.methods[symbol] ?? context.jvmImports?.methods[symbol] {
            let extensionMethod = program.extensionSymbols.contains(symbol)
            let inputs = (extensionMethod ? [delegate] : []) + arguments
            var args: [JVMValue] = []
            for (arg, type) in zip(inputs, method.parameters) { args.append(try convert(arg, to: type)) }
            let result = method.result == .unit ? nil : try value(method.result)
            instructions.append(.foreignCall(method, receiver: method.isStatic ? nil : (extensionMethod ? try enclosingInstance(program.sema.symbols.parentSymbol(for: symbol)!) : try convert(delegate, to: .reference(method.owner, nullable: false))), arguments: args, result: result)); return result
        }
        if let ref = program.references[symbol] {
            var args: [JVMValue] = []
            for (arg, type) in zip([delegate] + arguments, ref.parameters) { args.append(try convert(arg, to: type)) }
            let result = ref.result == .unit ? nil : try value(ref.result)
            instructions.append(.call(ref, args, result)); return result
        }
        throw fail("Unsupported JVM property delegate operator.")
    }
    func provideDelegate(_ initial: JVMValue, symbol: SymbolID, token: JVMValue) throws -> JVMValue {
        guard let method = program.sema.symbols.delegateProvideDelegateSymbol(for: symbol) else { return initial }
        guard let result = try delegateCall(method, delegate: initial, arguments: [delegateThis(symbol), token]) else { throw fail("JVM provideDelegate must return a delegate.") }
        return result
    }
    func readDelegate(_ delegate: JVMValue, symbol: SymbolID, token: JVMValue, type: JVMValueType) throws -> JVMValue {
        if program.isLazyDelegate(symbol) {
            return try jdkCall("kotlin/Lazy", "getValue", [], .reference("java/lang/Object", nullable: true), receiver: convert(delegate, to: .reference("kotlin/Lazy", nullable: false)), interface: true, resolved: type)!
        }
        guard let method = program.sema.symbols.delegateGetValueSymbol(for: symbol), let result = try delegateCall(method, delegate: delegate, arguments: [delegateThis(symbol), token]) else { throw fail("Missing JVM getValue operator.") }
        return try convert(result, to: type)
    }
    func writeDelegate(_ delegate: JVMValue, symbol: SymbolID, token: JVMValue, source: JVMValue) throws {
        guard let method = program.sema.symbols.delegateSetValueSymbol(for: symbol) else { throw fail("Missing JVM setValue operator.") }
        _ = try delegateCall(method, delegate: delegate, arguments: [delegateThis(symbol), token, source])
    }
    func checkLateinit(_ source: JVMValue, name: String) throws -> JVMValue {
        let missing = try constant(.null, source.type), initialized = try value(.boolean), end = label()
        instructions.append(.referenceCompare(.notEqual, source, missing, initialized))
        let errorLabel = label(); instructions.append(.jumpIfFalse(initialized, errorLabel)); jump(end); mark(errorLabel)
        let message = try constant(.string("lateinit property " + name + " has not been initialized"), .string)
        let error = try constructJDK("kotlin/UninitializedPropertyAccessException", parameters: [.string], arguments: [message])
        instructions.append(.throwValue(error)); terminated = true; mark(end)
        return source
    }
    func lateinitInitialized(_ receiver: ExprID) throws -> JVMValue? {
        guard case let .callableRef(objectID, _, _) = arena.expr(receiver), let symbol = program.sema.bindings.identifierSymbol(for: receiver), let property = program.properties[symbol], property.modifiers.contains(.lateinit), let field = property.field else { return nil }
        let stored = try value(field.type)
        if property.getter.isStatic { instructions.append(.getStatic(field, stored)) }
        else { instructions.append(.getField(field, try objectID.map(requireValue) ?? instance(receiver), stored)) }
        let result = try value(.boolean), missing = try constant(.null, field.type)
        instructions.append(.referenceCompare(.notEqual, stored, missing, result)); return result
    }
    func delegationIntrinsic(_ symbol: SemanticSymbol, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        let fq = symbol.fqName.map(context.interner.resolve)
        guard fq == ["kotlin", "lazy"] else { return nil }
        let signature = program.sema.symbols.functionSignature(for: symbol.id)!
        let types = try signature.parameterTypes.map(program.type)
        let ordered = try arguments(args, binding: program.sema.bindings.callBinding(for: id), parameters: types, declarations: nil, id: id)
        return JVMIntrinsicResult(value: try jdkCall("kotlin/LazyKt", "lazy", types, .reference("kotlin/Lazy", nullable: false), arguments: ordered.values))
    }
}

extension JVMFunctionBuilder {
    func specialLocal(_ id: ExprID, name: InternedString, mutable: Bool, initializer: ExprID?, delegated: Bool, late: Bool) throws {
        guard scopes.last?[name] == nil, let symbol = program.sema.bindings.identifierSymbol(for: id), let semantic = program.sema.symbols.propertyType(for: symbol) else { throw fail("Missing JVM local property binding.", id) }
        let type = try program.type(semantic)
        let placeholder = try value(type)
        var local = Local(value: placeholder, mutable: mutable, symbol: symbol)
        if delegated {
            guard let initializer else { throw fail("Missing JVM delegate initializer.", id) }
            let initial = try requireValue(initializer)
            let token: JVMValue
            if !program.needsDelegateToken(symbol) { token = try constant(.null, .reference("kotlin/reflect/KProperty", nullable: true)) }
            else { token = try propertyToken(name: context.interner.resolve(name), owner: owner?.name ?? program.facadeName, signature: "<local>", topLevel: true, mutable: mutable) }
            let stored = try provideDelegate(initial, symbol: symbol, token: token)
            let object: JVMValueType = .reference("java/lang/Object", nullable: true)
            let cell = try value(.reference("[Ljava/lang/Object;", nullable: false)), count = try constant(.int(2), .int)
            instructions.append(.newArray(object, count: count, result: cell))
            instructions.append(.arraySet(cell, try constant(.int(0), .int), try convert(stored, to: object)))
            instructions.append(.arraySet(cell, try constant(.int(1), .int), try convert(token, to: object)))
            local.cell = cell; local.delegateSymbol = symbol
        } else if late {
            guard type.referenceName != nil, mutable else { throw fail("JVM lateinit requires a mutable reference local.", id) }
            let element = try erasedLocalStorageType(semantic)
            let cell = try value(.reference("[" + element.descriptor, nullable: false)), count = try constant(.int(1), .int)
            instructions.append(.newArray(element, count: count, result: cell))
            local.cell = cell; local.lateName = context.interner.resolve(name)
        }
        scopes[scopes.count - 1][name] = local
    }
    func localDelegate(_ local: Local) throws -> (JVMValue, JVMValue) {
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let delegate = try value(object), token = try value(.reference("kotlin/reflect/KProperty", nullable: true))
        instructions.append(.arrayGet(local.cell!, try constant(.int(0), .int), delegate))
        let rawToken = try value(object)
        instructions.append(.arrayGet(local.cell!, try constant(.int(1), .int), rawToken)); instructions.append(.copy(rawToken, token))
        return (delegate, token)
    }
}
