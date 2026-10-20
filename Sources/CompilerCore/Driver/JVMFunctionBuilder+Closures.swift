import Foundation

extension JVMProgramBuilder {
    func noteFunctionTypes(_ id: TypeID) {
        switch sema.types.kind(of: id) {
        case let .functionType(f):
            functionArities.insert(f.params.count + (f.receiver == nil ? 0 : 1) + (f.isSuspend ? 1 : 0))
            for t in [f.receiver].compactMap({ $0 }) + f.params + [f.returnType] { noteFunctionTypes(t) }
        case let .classType(t):
            for arg in t.args { switch arg { case let .invariant(t), let .out(t), let .in(t): noteFunctionTypes(t); case .star: break } }
        default: break
        }
    }
    func addingSyntheticMethods(_ type: JVMClass) -> JVMClass {
        var result = type; result.functions += syntheticFunctions[type.name] ?? []; return result
    }
}

extension JVMFunctionBuilder {
    func readLocal(_ local: Local) throws -> JVMValue {
        if let symbol = local.delegateSymbol {
            let (delegate, token) = try localDelegate(local)
            return try readDelegate(delegate, symbol: symbol, token: token, type: local.value.type)
        }
        let resultType: JVMValueType = local.lateName == nil ? local.value.type : .reference(local.value.type.referenceName!, nullable: true)
        let result = try value(resultType)
        if let cell = local.cell {
            let index = try constant(.int(0), .int); instructions.append(.arrayGet(cell, index, result))
        } else { instructions.append(.copy(local.value, result)) }
        if let name = local.lateName { _ = try checkLateinit(result, name: name); return try convert(result, to: local.value.type) }
        return result
    }
    func writeLocal(_ local: Local, _ source: JVMValue) throws {
        if let symbol = local.delegateSymbol {
            let (delegate, token) = try localDelegate(local)
            try writeDelegate(delegate, symbol: symbol, token: token, source: source); return
        }
        if let cell = local.cell {
            let index = try constant(.int(0), .int); instructions.append(.arraySet(cell, index, source))
        } else { instructions.append(.copy(source, local.value)) }
    }
    func functionType(_ id: ExprID) -> FunctionType? {
        guard let type = program.sema.bindings.samUnderlyingFunctionType(for: id) ?? program.sema.bindings.exprType(for: id), case let .functionType(f) = program.sema.types.kind(of: type) else { return nil }
        return f
    }
    func invoke(_ function: JVMValue, signature: FunctionType, arguments: [JVMValue], resultType: JVMValueType? = nil) throws -> JVMValue? {
        let parameters = [signature.receiver].compactMap { $0 } + signature.params
        guard arguments.count == parameters.count, parameters.count <= 22 else { throw fail("JVM function-value argument count mismatch.") }
        program.functionArities.insert(parameters.count + (signature.isSuspend ? 1 : 0))
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        var args: [JVMValue] = []
        for arg in arguments { args.append(try convert(arg, to: object)) }
        let result = try resultType ?? program.type(signature.returnType)
        if signature.isSuspend {
            var method = JVMForeignMethod(owner: "kotlin/jvm/functions/Function" + String(parameters.count + 1), name: "invoke", descriptor: "(" + Array(repeating: object.descriptor, count: parameters.count).joined() + ")" + object.descriptor, parameters: Array(repeating: object, count: parameters.count), result: object, isStatic: false, isInterface: true, isAbstract: true)
            method.isSuspend = true
            let returned = result == .unit ? nil : try value(result)
            instructions.append(.foreignCall(method, receiver: function, arguments: args, result: returned))
            return returned
        }
        return try jdkCall("kotlin/jvm/functions/Function" + String(parameters.count), "invoke", Array(repeating: object, count: args.count), object, receiver: function, arguments: args, interface: true, resolved: result == .unit ? object : result).flatMap { result == .unit ? nil : $0 }
    }
    func functionValueCall(_ callee: ExprID, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        if case let .nameRef(name, _) = arena.expr(callee), let lambda = inlineArgument(name) { return JVMIntrinsicResult(value: try expandLambda(lambda, args: args, id: id)) }
        if let binding = program.sema.bindings.callBinding(for: id), program.references[binding.chosenCallee] != nil || program.methods[binding.chosenCallee] != nil || context.jvmImports?.methods[binding.chosenCallee] != nil { return nil }
        var signature = functionType(callee)
        if let bound = program.sema.bindings.callableValueCallBinding(for: id), case let .functionType(f) = program.sema.types.kind(of: bound.functionType) { signature = f }
        if signature == nil, case let .nameRef(name, _) = arena.expr(callee) { signature = try? lookup(name).functionType }
        guard let signature else { return nil }
        guard args.allSatisfy({ $0.label == nil && !$0.isSpread }) else { throw fail("Unsupported JVM function arguments.", id) }
        let function = try requireValue(callee)
        var values: [JVMValue] = []
        if signature.receiver != nil, args.count == signature.params.count {
            guard let receiver = implicitExtensionReceiver(id) else { throw fail("Function with receiver requires an argument.", id) }
            values.append(receiver)
        }
        for arg in args { values.append(try requireValue(arg.expr)) }
        return JVMIntrinsicResult(value: try invoke(function, signature: signature, arguments: values, resultType: program.expressionType(id)))
    }
    func extensionOrInvoke(_ receiver: ExprID, name: InternedString, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard args.allSatisfy({ !$0.isSpread }) else { return nil }
        if let result = try inlineCall(args, receiver: receiver, id: id) { return result }
        if context.interner.resolve(name) == "invoke", case let .nameRef(n, _) = arena.expr(receiver), let lambda = inlineArgument(n) { return JVMIntrinsicResult(value: try expandLambda(lambda, args: args, id: id)) }
        // An explicit invoke receiver is already the function value. Reading
        // its property again would use that function as the getter's owner.
        if context.interner.resolve(name) == "invoke", let signature = functionType(receiver) {
            let function = try requireValue(receiver)
            var values: [JVMValue] = []
            for arg in args { values.append(try requireValue(arg.expr)) }
            return JVMIntrinsicResult(value: try invoke(function, signature: signature, arguments: values, resultType: program.expressionType(id)))
        }
        if let lambda = inlineArgument(name), functionType(lambda.id)?.receiver != nil {
            return JVMIntrinsicResult(value: try expandLambda(lambda, args: args, id: id, receiver: requireValue(receiver)))
        }
        if let bound = program.sema.bindings.callableValueCallBinding(for: id),
           let callee = bound.extensionCallableExpr,
           case let .functionType(signature) = program.sema.types.kind(of: bound.functionType) {
            // Sema's lexical reference preserves the property's dispatch owner;
            // the call-site receiver belongs only to the returned function.
            let object = try requireValue(receiver), function = try requireValue(callee)
            var values = [object]
            for arg in args { values.append(try requireValue(arg.expr)) }
            return JVMIntrinsicResult(value: try invoke(function, signature: signature, arguments: values, resultType: program.expressionType(id)))
        }
        if let bound = program.sema.bindings.callableValueCallBinding(for: id),
           case let .localValue(symbol) = bound.target,
           let property = program.properties[symbol],
           case let .functionType(signature) = program.sema.types.kind(of: bound.functionType) {
            let object = try requireValue(receiver)
            let function = try readProperty(property, receiver: object, special: isSuper(receiver), superReceiver: receiver)
            var values: [JVMValue] = signature.receiver != nil && args.count == signature.params.count ? [object] : []
            for arg in args { values.append(try requireValue(arg.expr)) }
            return JVMIntrinsicResult(value: try invoke(function, signature: signature, arguments: values, resultType: program.expressionType(id)))
        }
        if let bound = program.sema.bindings.invokeOperatorPropertyCalls[id], let property = program.properties[bound.property], case let .functionType(signature) = program.sema.types.kind(of: bound.propertyType) {
            let function = try readProperty(property, receiver: requireValue(receiver), special: false)
            var values: [JVMValue] = []
            for arg in args { values.append(try requireValue(arg.expr)) }
            return JVMIntrinsicResult(value: try invoke(function, signature: signature, arguments: values, resultType: program.expressionType(id)))
        }
        if let bound = program.sema.bindings.callableValueCallBinding(for: id),
           case let .localValue(symbol) = bound.target,
           let local = try? lookup(name), local.symbol == symbol,
           case let .functionType(signature) = program.sema.types.kind(of: bound.functionType), signature.receiver != nil {
            let object = try requireValue(receiver), function = try readLocal(local)
            var values = [object]
            for arg in args { values.append(try requireValue(arg.expr)) }
            return JVMIntrinsicResult(value: try invoke(function, signature: signature, arguments: values, resultType: program.expressionType(id)))
        }
        guard let binding = program.sema.bindings.callBinding(for: id), let signature = program.sema.symbols.functionSignature(for: binding.chosenCallee), signature.receiverType != nil, program.extensionSymbols.contains(binding.chosenCallee) else { return nil }
        if let reference = program.references[binding.chosenCallee] {
            var values = [try convert(requireValue(receiver), to: reference.parameters[0])]
            for (arg, type) in zip(args, reference.parameters.dropFirst()) { values.append(try convert(requireValue(arg.expr), to: type)) }
            guard values.count == reference.parameters.count else { throw fail("JVM extension argument mismatch.", id) }
            let result = reference.result == .unit ? nil : try value(reference.result)
            instructions.append(.call(reference, values, result))
            return JVMIntrinsicResult(value: try result.map { try convert($0, to: program.expressionType(id)) })
        }
        if let method = program.methods[binding.chosenCallee] {
            let dispatch = try instance(id), extensionReceiver = try convert(requireValue(receiver), to: method.parameters[0])
            var values = [extensionReceiver]
            for (arg, type) in zip(args, method.parameters.dropFirst()) { values.append(try convert(requireValue(arg.expr), to: type)) }
            guard values.count == method.parameters.count else { throw fail("JVM member extension argument mismatch.", id) }
            let result = method.result == .unit ? nil : try value(program.expressionType(id))
            instructions.append(.foreignCall(method, receiver: dispatch, arguments: values, result: result))
            return JVMIntrinsicResult(value: result)
        }
        return nil
    }
    func closure(_ id: ExprID, destination: JVMValue? = nil) throws -> JVMValue {
        guard case let .lambdaLiteral(parameters, body, _, _) = arena.expr(id), let function = functionType(id), function.contextReceivers.isEmpty else { throw fail("Unsupported JVM lambda type or SAM conversion.", id) }
        program.noteFunctionTypes(program.sema.bindings.exprType(for: id)!)
        let number = program.nextClosure; program.nextClosure += 1
        let container = owner?.name ?? program.facadeName
        let name = container + "$Lambda" + String(number)
        var visible: [InternedString: Local] = [:]
        for scope in scopes { visible.merge(scope, uniquingKeysWith: { _, new in new }) }
        let symbols = Set(visible.values.compactMap(\.symbol))
        var free = Set(CaptureAnalyzer().collectCapturedOuterSymbols(in: body, ast: program.ast, sema: program.sema, outerSymbols: symbols, skipNestedClosures: false))
        // Receiver-style calls to function locals have no nameRef AST child.
        // Retain the semantically selected callable, including in nested lambdas.
        if let range = arena.exprRange(body) {
            for (call, binding) in program.sema.bindings.callableValueCalls {
                guard case let .localValue(symbol) = binding.target, symbols.contains(symbol),
                      let callRange = arena.exprRange(call), callRange.start.file == range.start.file,
                      callRange.start.offset >= range.start.offset, callRange.end.offset <= range.end.offset else { continue }
                free.insert(symbol)
            }
        }
        let captured = visible.filter { $0.value.symbol.map { free.contains($0) } ?? true }.sorted {
            context.interner.resolve($0.key).utf8.lexicographicallyPrecedes(context.interner.resolve($1.key).utf8)
        }
        var captures: [(String, JVMValue)] = captured.enumerated().map { ("capture\($0.offset)", $0.element.value.cell ?? $0.element.value.value) }
        let dispatchIndex: Int? = !beforeDelegation && thisValue != nil ? captures.count : nil
        if let thisValue, !beforeDelegation { captures.append(("dispatch", thisValue)) }
        let extensionIndex: Int? = extensionValue != nil ? captures.count : nil
        if let extensionValue { captures.append(("extension", extensionValue)) }
        let contexts = contextualReceivers.filter { !beforeDelegation || $0.value.slot != thisValue?.slot }.sorted { $0.key.rawValue < $1.key.rawValue }
        let contextIndex = captures.count
        for (i, receiver) in contexts.enumerated() { captures.append(("receiver\(i)", receiver.value)) }
        // Escaping helpers receive resolved type tokens, so they never execute
        // an unresolved reified marker after the caller has finished inlining.
        let tokenIndex = captures.count
        let tokenTypes = reifiedCaptureTypes(body)
        for (i, type) in tokenTypes.enumerated() {
            let token = try materializeReifiedToken(type)
            captures.append(("type\(i)Class", token.klass))
            captures.append(("type\(i)Nullable", token.nullable))
            captures.append(("type\(i)MutableKind", token.mutableKind))
        }
        let inputTypes = try ([function.receiver].compactMap { $0 } + function.params).map(program.type)
        let resultType = try program.type(function.returnType)
        let helperRef = JVMFunctionReference(name: "$lambda" + String(number), parameters: captures.map { $0.1.type } + inputTypes, result: resultType, owner: container, ownerIsInterface: owner?.isInterface == true)
        guard helperRef.parameters.reduce(0, { $0 + $1.width }) <= 255, captures.map({ $0.1.type }).reduce(1, { $0 + $1.width }) <= 255 else { throw fail("JVM lambda capture/parameter slot limit exceeded.", id) }
        let declaration = FunDecl(range: arena.exprRange(id)!, name: context.interner.intern(helperRef.name), modifiers: [], valueParams: [], body: .expr(body, arena.exprRange(body)!))
        let helper = JVMFunctionBuilder(program: program, declaration: declaration, reference: helperRef, owner: owner)
        helper.isStaticBody = true; helper.lambdaID = id; helper.isSuspendBody = function.isSuspend
        helper.backingProperty = backingProperty
        let values = try helperRef.parameters.map { try helper.value($0) }
        for (i, entry) in captured.enumerated() {
            var local = entry.value
            if local.cell != nil { local.cell = values[i]; local = Local(value: try helper.value(entry.value.value.type), mutable: entry.value.mutable, cell: values[i], functionType: entry.value.functionType, symbol: entry.value.symbol) }
            else { local = Local(value: values[i], mutable: false, functionType: entry.value.functionType, symbol: entry.value.symbol) }
            local.delegateSymbol = entry.value.delegateSymbol; local.lateName = entry.value.lateName
            helper.scopes[0][entry.key] = local
        }
        if let dispatchIndex { helper.thisValue = values[dispatchIndex] }
        if let extensionIndex { helper.extensionValue = values[extensionIndex] }
        for (i, entry) in contexts.enumerated() { helper.contextualReceivers[entry.key] = values[contextIndex + i] }
        for (i, type) in tokenTypes.enumerated() {
            if case let .typeParam(t) = program.sema.types.kind(of: type) {
                let offset = tokenIndex + i * ReifiedRuntimeToken.captureWidth
                helper.reifiedRuntimeTokens[t.symbol] = ReifiedRuntimeToken(klass: values[offset], nullable: values[offset + 1], mutableKind: values[offset + 2])
            }
        }
        var inputIndex = captures.count
        if function.receiver != nil {
            helper.extensionValue = values[inputIndex]
            helper.contextualReceivers[SyntheticSymbolScheme.lambdaReceiverSymbol(for: id)] = values[inputIndex]
            inputIndex += 1
        }
        let names = parameters.isEmpty && function.params.count == 1 ? [context.interner.intern("it")] : parameters
        guard names.count == function.params.count else { throw fail("JVM lambda parameter count mismatch.", id) }
        helper.scopes.append([:])
        for (i, param) in names.enumerated() {
            var local = Local(value: values[inputIndex + i], mutable: false)
            if case let .functionType(type) = program.sema.types.kind(of: function.params[i]) { local.functionType = type }
            local.symbol = SymbolID(rawValue: Int32(clamping: -1_000_000 - Int64(id.rawValue) * 256 - Int64(i + (function.receiver == nil ? 0 : 1))))
            helper.scopes[helper.scopes.count - 1][param] = local
        }
        let returned = try helper.expression(body, discarded: resultType == .unit)
        if !helper.terminated {
            if resultType == .unit { helper.instructions.append(.returnValue(nil)) }
            else {
                guard let returned else { throw fail("JVM lambda must return a value.", id) }
                helper.instructions.append(.returnValue(try helper.convert(returned, to: resultType)))
            }
        }
        program.syntheticFunctions[container, default: []].append(helper.finish())
        program.closureClasses.append(try program.closureClass(name, captures: captures.map { ($0.0, $0.1.type) }, inputs: inputTypes, result: resultType, helper: helperRef, suspend: function.isSuspend))
        let object = try destination ?? value(.reference(name, nullable: false))
        instructions.append(.allocate(name, object))
        let constructor = JVMForeignMethod(owner: name, name: "<init>", descriptor: "(" + captures.map { $0.1.type.descriptor }.joined() + ")V", parameters: captures.map { $0.1.type }, result: object.type, isStatic: false, isInterface: false, isAbstract: false)
        instructions.append(.foreignCall(constructor, receiver: object, arguments: captures.map { $0.1 }, result: nil))
        if program.sema.bindings.samUnderlyingFunctionType(for: id) != nil || program.sema.bindings.samInterfaceType(for: id) != nil {
            return try convert(object, to: .reference("kotlin/jvm/functions/Function" + String(inputTypes.count + (function.isSuspend ? 1 : 0)), nullable: false))
        }
        return destination == nil ? try convert(object, to: program.expressionType(id)) : object
    }
}

extension JVMFunctionBuilder {
    func implicitExtensionCall(_ symbol: SymbolID, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        guard program.extensionSymbols.contains(symbol), let signature = program.sema.symbols.functionSignature(for: symbol), signature.receiverType != nil,
              program.references[symbol] != nil || program.methods[symbol] != nil else { return nil }
        guard let receiver = implicitExtensionReceiver(id) else { throw fail("Missing implicit JVM extension receiver.", id) }
        let reference = program.references[symbol]
        let method = program.methods[symbol]
        let parameters = reference?.parameters ?? method!.parameters
        guard parameters.count == args.count + 1 else { throw fail("JVM extension argument count mismatch.", id) }
        var values = [try convert(receiver, to: parameters[0])]
        for (arg, type) in zip(args, parameters.dropFirst()) { values.append(try convert(requireValue(arg.expr), to: type)) }
        let resultType = reference?.result ?? method!.result
        let result = resultType == .unit ? nil : try value(program.expressionType(id))
        if let reference { instructions.append(.call(reference, values, result)) }
        else if let method { instructions.append(.foreignCall(method, receiver: try instance(id), arguments: values, result: result)) }
        return JVMIntrinsicResult(value: result)
    }
}
