extension JVMFunctionBuilder {
    struct InlineReturn {
        let lambda: ExprID?
        let result: JVMValue?
        let end: Int
        let finalizerDepth: Int
    }
    struct InlineLambda {
        let id: ExprID
        let scopes: [[InternedString: Local]]
        let dispatch: JVMValue?
        let receiver: JVMValue?
        let contexts: [SymbolID: JVMValue]
        let returns: [InlineReturn]
        let arguments: [InternedString: InlineLambda]
        let lexicalLambda: ExprID?
    }
    func inlineArgument(_ name: InternedString) -> InlineLambda? {
        // A block-local function value can shadow an inline parameter.
        guard !scopes.contains(where: { $0[name] != nil }) else { return nil }
        return inlineArguments[name]
    }
    func inlineCall(_ args: [CallArgument], receiver: ExprID? = nil, id: ExprID) throws -> JVMIntrinsicResult? {
        guard let binding = program.sema.bindings.callBinding(for: id),
              let declaration = program.inlineDeclarations[binding.chosenCallee] else { return nil }
        guard !inlineStack.contains(binding.chosenCallee),
              args.allSatisfy({ !$0.isSpread }) else { throw fail("Recursive or unsupported JVM inline call.", id) }
        let savedScopes = scopes, savedThis = thisValue, savedReceiver = extensionValue, savedContexts = contextualReceivers
        let savedArguments = inlineArguments, savedReturns = inlineReturns, savedLambda = lambdaID
        let method = program.methods[binding.chosenCallee]
        let dispatch = try method.map { _ in try receiver != nil && declaration.receiverType == nil ? requireValue(receiver!) : instance(id) }
        let extensionReceiver = try declaration.receiverType == nil ? nil : receiver.map(requireValue) ?? implicitExtensionReceiver(id)
        var parameters: [InternedString: Local] = [:], lambdas: [InternedString: InlineLambda] = [:]
        var supplied: Set<Int> = []
        for (sourceIndex, argument) in args.enumerated() {
            let i = binding.parameterMapping[sourceIndex] ?? sourceIndex
            guard declaration.valueParams.indices.contains(i), supplied.insert(i).inserted else { throw fail("Invalid inline argument mapping.", id) }
            let parameter = declaration.valueParams[i]
            if !parameter.isNoinline && !parameter.isCrossinline, case .lambdaLiteral = arena.expr(argument.expr) {
                lambdas[parameter.name] = InlineLambda(id: argument.expr, scopes: scopes, dispatch: thisValue, receiver: extensionValue, contexts: contextualReceivers, returns: inlineReturns, arguments: inlineArguments, lexicalLambda: lambdaID)
            } else if !parameter.isNoinline && !parameter.isCrossinline, case let .nameRef(name, _) = arena.expr(argument.expr), let forwarded = inlineArgument(name) {
                lambdas[parameter.name] = forwarded
            } else {
                let source = try requireValue(argument.expr), snapshot = try value(source.type)
                instructions.append(.copy(source, snapshot))
                var local = Local(value: snapshot, mutable: false)
                if let signature = program.sema.symbols.functionSignature(for: binding.chosenCallee) {
                    local.symbol = signature.valueParameterSymbols.indices.contains(i) ? signature.valueParameterSymbols[i] : nil
                    if case let .functionType(f) = program.sema.types.kind(of: signature.parameterTypes[i]) { local.functionType = f }
                }
                parameters[parameter.name] = local
            }
        }
        let savedTypes = program.inlineTypeArguments
        if let signature = program.sema.symbols.functionSignature(for: binding.chosenCallee) {
            let symbols = signature.typeParameterSymbols
            let arguments = binding.substitutedTypeArguments
            let selected = symbols.count == arguments.count ? symbols : Array(symbols.suffix(arguments.count))
            let actual = arguments.map { program.specialized($0) }
            for (symbol, type) in zip(selected, actual) {
                if program.sema.symbols.symbol(symbol)?.flags.contains(.reifiedTypeParameter) == true, !program.validReifiedArgument(type) {
                    throw fail("A non-reified type parameter cannot be used as a reified argument.", id)
                }
                program.inlineTypeArguments[symbol] = type
            }
        }
        scopes = [parameters, [:]]; inlineArguments = lambdas; lambdaID = nil
        thisValue = dispatch; extensionValue = extensionReceiver
        contextualReceivers = [:]
        if let dispatch, let owner = program.sema.symbols.parentSymbol(for: binding.chosenCallee) {
            contextualReceivers[owner] = dispatch
            contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: owner)] = dispatch
        }
        if let receiver = extensionReceiver ?? dispatch { contextualReceivers[SyntheticSymbolScheme.receiverParameterSymbol(for: binding.chosenCallee)] = receiver }
        inlineStack.insert(binding.chosenCallee)
        defer {
            program.inlineTypeArguments = savedTypes
            scopes = savedScopes; thisValue = savedThis; extensionValue = savedReceiver; contextualReceivers = savedContexts
            inlineArguments = savedArguments; inlineReturns = savedReturns; lambdaID = savedLambda
            inlineStack.remove(binding.chosenCallee)
        }
        for (i, parameter) in declaration.valueParams.enumerated() where !supplied.contains(i) {
            guard let expression = parameter.defaultValue else { throw fail("Missing inline default expression.", id) }
            if !parameter.isNoinline && !parameter.isCrossinline, case .lambdaLiteral = arena.expr(expression) {
                inlineArguments[parameter.name] = InlineLambda(id: expression, scopes: scopes, dispatch: thisValue, receiver: extensionValue, contexts: contextualReceivers, returns: inlineReturns, arguments: inlineArguments, lexicalLambda: lambdaID)
            } else {
                let returned = try self.expression(expression)
                if terminated { return JVMIntrinsicResult(value: nil) }
                guard let source = returned else { throw fail("Inline default requires a value.", id) }
                var local = Local(value: source, mutable: false)
                if let signature = program.sema.symbols.functionSignature(for: binding.chosenCallee), signature.parameterTypes.indices.contains(i), case let .functionType(f) = program.sema.types.kind(of: signature.parameterTypes[i]) { local.functionType = f }
                scopes[0][parameter.name] = local
            }
        }
        let type = try program.expressionType(id)
        let physicalResult = program.references[binding.chosenCallee]?.result ?? method?.result
        // Safe calls lift Unit to Unit?, but inline Unit bodies have no result.
        // The safe-call join materializes Unit only on the non-null edge.
        let result = type == .unit || physicalResult == .unit ? nil : try value(type), end = label()
        inlineReturns = [InlineReturn(lambda: nil, result: result, end: end, finalizerDepth: finalizers.count)]
        switch declaration.body {
        case let .expr(body, _):
            let returned = try expression(body, discarded: result == nil)
            if !terminated, let result, let returned { instructions.append(.copy(try convert(returned, to: result.type), result)) }
        case let .block(body, _): for statement in body where !terminated { _ = try expression(statement, discarded: true) }
        case .unit: throw fail("Inline function requires a body.", id)
        }
        // A non-local return may have no edge back into this expression.
        mark(end)
        return JVMIntrinsicResult(value: result)
    }
    func expandLambda(_ lambda: InlineLambda, args: [CallArgument], id: ExprID, receiver: JVMValue? = nil) throws -> JVMValue? {
        guard let signature = functionType(lambda.id) else { throw fail("Unsupported inline lambda.", id) }
        var values: [JVMValue] = []
        if signature.receiver != nil, args.count == signature.params.count {
            guard let receiver = receiver ?? extensionValue ?? thisValue else { throw fail("Inline receiver lambda requires this.", id) }
            values.append(receiver)
        }
        for argument in args { values.append(try requireValue(argument.expr)) }
        return try expandLambda(lambda, values: values, id: id)
    }
    func expandLambda(_ lambda: InlineLambda, values inputs: [JVMValue], id: ExprID) throws -> JVMValue? {
        guard case let .lambdaLiteral(names, body, _, _) = arena.expr(lambda.id), let signature = functionType(lambda.id) else { throw fail("Unsupported inline lambda.", id) }
        var values = inputs
        guard values.count == signature.params.count + (signature.receiver == nil ? 0 : 1) else { throw fail("Inline lambda arity mismatch.", id) }
        let savedScopes = scopes, savedThis = thisValue, savedReceiver = extensionValue, savedContexts = contextualReceivers
        let savedArguments = inlineArguments, savedReturns = inlineReturns, savedLambda = lambdaID
        scopes = lambda.scopes + [[:]]; thisValue = lambda.dispatch; extensionValue = lambda.receiver; contextualReceivers = lambda.contexts
        inlineArguments = lambda.arguments; inlineReturns = lambda.returns; lambdaID = lambda.lexicalLambda
        defer {
            scopes = savedScopes; thisValue = savedThis; extensionValue = savedReceiver; contextualReceivers = savedContexts
            inlineArguments = savedArguments; inlineReturns = savedReturns; lambdaID = savedLambda
        }
        if signature.receiver != nil {
            extensionValue = values.removeFirst()
            contextualReceivers[SyntheticSymbolScheme.lambdaReceiverSymbol(for: lambda.id)] = extensionValue
        }
        let parameters = names.isEmpty && signature.params.count == 1 ? [context.interner.intern("it")] : names
        for (i, pair) in zip(parameters, values).enumerated() {
            let symbol = SymbolID(rawValue: Int32(clamping: -1_000_000 - Int64(lambda.id.rawValue) * 256 - Int64(i + (signature.receiver == nil ? 0 : 1))))
            var local = Local(value: pair.1, mutable: false, symbol: symbol)
            if case let .functionType(f) = program.sema.types.kind(of: signature.params[i]) { local.functionType = f }
            scopes[scopes.count - 1][pair.0] = local
        }
        let type = try program.type(signature.returnType), result = type == .unit ? nil : try value(type), end = label()
        inlineReturns.append(InlineReturn(lambda: lambda.id, result: result, end: end, finalizerDepth: finalizers.count))
        let returned = try expression(body, discarded: result == nil)
        if !terminated, let result, let returned { instructions.append(.copy(try convert(returned, to: result.type), result)) }
        mark(end)
        return result
    }
    func inlineReturn(_ id: ExprID, returned: ExprID?) throws -> Bool {
        let target = program.sema.bindings.lambdaReturnTargets[id]
        let frame = target.flatMap { target in inlineReturns.last { $0.lambda == target } } ?? (target == nil ? inlineReturns.last { $0.lambda == nil } : nil)
        guard let frame else { return false }
        let value = try returned.flatMap { try expression($0, discarded: frame.result == nil) }
        if terminated { return true }
        if let result = frame.result {
            guard let value else { throw fail("Inline return requires a value.", id) }
            instructions.append(.copy(try convert(value, to: result.type), result))
        }
        try emitFinalizers(leavingInline: frame.finalizerDepth)
        if !terminated { jump(frame.end) }
        return true
    }
}
