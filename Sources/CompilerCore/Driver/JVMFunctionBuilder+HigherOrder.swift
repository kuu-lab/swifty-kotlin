extension JVMFunctionBuilder {
    func higherOrderReceiver(_ id: ExprID) -> Bool {
        if (try? program.expressionType(id).referenceName?.hasPrefix("[")) == true { return true }
        func iterable(_ type: TypeID, visited: Set<SymbolID>) -> Bool {
            switch program.sema.types.kind(of: type) {
            case let .typeParam(t):
                guard !visited.contains(t.symbol) else { return false }
                return program.sema.symbols.typeParameterUpperBounds(for: t.symbol).contains { iterable($0, visited: visited.union([t.symbol])) }
            case let .classType(t):
                guard !visited.contains(t.classSymbol) else { return false }
                if let name = try? program.className(t.classSymbol), ["kotlin/collections/Iterable", "java/lang/Iterable"].contains(name) { return true }
                return program.sema.symbols.directSupertypes(for: t.classSymbol).contains {
                    iterable(program.sema.types.make(.classType(ClassType(classSymbol: $0))), visited: visited.union([t.classSymbol]))
                }
            default: return false
            }
        }
        return program.sema.bindings.exprType(for: id).map { iterable($0, visited: []) } ?? false
    }
    private func isDirectInlineArrayInitializer(_ id: ExprID) -> Bool {
        guard case let .nameRef(name, _) = arena.expr(id) else { return false }
        if inlineArgument(name) != nil { return true }
        // Producer bodies have ordinary locals rather than expanded lambdas.
        // Compare semantic symbols so a local with the same name remains legal.
        guard declaration.isInline,
              let symbol = program.sema.bindings.identifierSymbol(for: id),
              let index = semanticSignature?.valueParameterSymbols.firstIndex(of: symbol),
              declaration.valueParams.indices.contains(index)
        else { return false }
        return !declaration.valueParams[index].isNoinline
    }
    func arrayConstructor(_ args: [CallArgument], id: ExprID) throws -> JVMValue {
        guard (1...2).contains(args.count), args.allSatisfy({ !$0.isSpread }) else { throw fail("Unsupported JVM array constructor.", id) }
        let type = try program.expressionType(id)
        var supplied: [Int: (ExprID, JVMValue)] = [:]
        var initializer: InlineLambda?
        var count: JVMValue?, allocated: JVMValue?
        // Kotlin allocates immediately after evaluating size. An initializer
        // written before size is evaluated first; one after size is skipped if
        // allocation fails, even when it is an ordinary function expression.
        for (i, arg) in args.enumerated() {
            let index = arg.label.map { context.interner.resolve($0) == "size" ? 0 : 1 } ?? i
            if index == 0 {
                let size = try convert(requireValue(arg.expr), to: .int)
                count = size
                allocated = try allocateArray(type, semantic: program.sema.bindings.exprType(for: id), count: size, id: id)
            } else if case .lambdaLiteral = arena.expr(arg.expr) {
                initializer = InlineLambda(id: arg.expr, scopes: scopes, dispatch: thisValue, receiver: extensionValue, contexts: contextualReceivers, returns: inlineReturns, arguments: inlineArguments, lexicalLambda: lambdaID)
            } else if isDirectInlineArrayInitializer(arg.expr) {
                throw fail("An inline parameter must be invoked inside an array initializer lambda or declared noinline.", arg.expr)
            } else { supplied[index] = (arg.expr, try requireValue(arg.expr)) }
        }
        guard let count, let result = allocated else { throw fail("JVM array constructor requires size.", id) }
        let callback = supplied[1]?.1
        let element = try arrayComponent(type)
        if initializer != nil || callback != nil {
            let index = try value(.int), test = label(), end = label()
            instructions.append(.constant(.int(0), index)); mark(test)
            let check = try value(.boolean); instructions.append(.binary(.lessThan, index, count, check)); instructions.append(.jumpIfFalse(check, end))
            let initialized: JVMValue?
            if let initializer { initialized = try expandLambda(initializer, values: [index], id: id) }
            else {
                guard let callback, let signature = supplied[1].flatMap({ functionType($0.0) }) else { throw fail("Array initializer requires a function.", id) }
                initialized = try invoke(callback, signature: signature, arguments: [index], resultType: element)
            }
            guard let initialized else { throw fail("Array initializer must produce an element.", id) }
            instructions.append(.arraySet(result, index, try convert(initialized, to: element)))
            let one = try constant(.int(1), .int); instructions.append(.binary(.add, index, one, index)); jump(test); mark(end)
        }
        return result
    }
    func higherOrder(_ receiverID: ExprID, operation: String, args: [CallArgument], id: ExprID) throws -> JVMValue? {
        guard higherOrderReceiver(receiverID) else { throw fail("JVM higher-order operations require an array or Iterable.", id) }
        guard args.count == (operation == "fold" ? 2 : 1), args.allSatisfy({ !$0.isSpread }) else { throw fail("Unsupported JVM higher-order arguments.", id) }
        let receiver = try requireValue(receiverID)
        var supplied: [Int: (ExprID, JVMValue)] = [:]
        let binding = program.sema.bindings.callBinding(for: id)
        for (i, arg) in args.enumerated() {
            let index = binding?.parameterMapping[i] ?? arg.label.map { context.interner.resolve($0) == "initial" ? 0 : (operation == "fold" ? 1 : 0) } ?? i
            supplied[index] = (arg.expr, try requireValue(arg.expr))
        }
        guard let callbackEntry = supplied[operation == "fold" ? 1 : 0], let signature = functionType(callbackEntry.0) else { throw fail("Missing JVM higher-order callback.", id) }
        let array = receiver.type.referenceName?.hasPrefix("[") == true
        let iterator = array ? nil : try jdkCall("java/lang/Iterable", "iterator", [], .reference("java/util/Iterator", nullable: false), receiver: receiver, interface: true)
        let index = array ? try value(.int) : nil, size = array ? try value(.int) : nil
        if let index, let size { instructions.append(.constant(.int(0), index)); instructions.append(.arrayLength(receiver, size)) }
        let accumulator: JVMValue?
        if operation == "fold" {
            let initial = supplied[0]!.1, stored = try value(program.expressionType(id))
            instructions.append(.copy(try convert(initial, to: stored.type), stored)); accumulator = stored
        } else if operation == "reduce" {
            let stored = try value(program.expressionType(id))
            let empty = label(), ready = label()
            let hasFirst: JVMValue
            if let index, let size {
                hasFirst = try value(.boolean)
                instructions.append(.binary(.lessThan, index, size, hasFirst))
            } else {
                hasFirst = try jdkCall("java/util/Iterator", "hasNext", [], .boolean, receiver: iterator, interface: true)!
            }
            instructions.append(.jumpIfFalse(hasFirst, empty))
            let first: JVMValue
            if let index {
                first = try value(.reference("java/lang/Object", nullable: true))
                instructions.append(.arrayGet(receiver, index, first))
                instructions.append(.constant(.int(1), index))
            } else {
                first = try jdkCall("java/util/Iterator", "next", [], .reference("java/lang/Object", nullable: true), receiver: iterator, interface: true)!
            }
            instructions.append(.copy(try convert(first, to: stored.type), stored))
            jump(ready)
            mark(empty)
            let error = try constructJDK(
                "java/lang/UnsupportedOperationException",
                parameters: [.string],
                arguments: [try constant(.string("Empty collection can't be reduced."), .string)]
            )
            instructions.append(.throwValue(error)); terminated = true
            mark(ready)
            accumulator = stored
        } else { accumulator = nil }
        let callback = callbackEntry.1
        let list = operation == "map" || operation == "filter" ? try constructJDK("java/util/ArrayList") : nil
        let test = label(), advance = label(), end = label()
        mark(test)
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let check: JVMValue
        if let index, let size { check = try value(.boolean); instructions.append(.binary(.lessThan, index, size, check)) }
        else { check = try jdkCall("java/util/Iterator", "hasNext", [], .boolean, receiver: iterator, interface: true)! }
        instructions.append(.jumpIfFalse(check, end))
        let item: JVMValue
        if let index { item = try value(object); instructions.append(.arrayGet(receiver, index, item)) }
        else { item = try jdkCall("java/util/Iterator", "next", [], object, receiver: iterator, interface: true)! }
        switch operation {
        case "forEach": _ = try invoke(callback, signature: signature, arguments: [item], resultType: .unit)
        case "map":
            let transformed = try invoke(callback, signature: signature, arguments: [item], resultType: object)!
            _ = try jdkCall("java/util/ArrayList", "add", [object], .boolean, receiver: list, arguments: [transformed])
        case "filter":
            let matches = try invoke(callback, signature: signature, arguments: [item], resultType: .boolean)!
            instructions.append(.jumpIfFalse(matches, advance))
            _ = try jdkCall("java/util/ArrayList", "add", [object], .boolean, receiver: list, arguments: [item])
        case "fold":
            let next = try invoke(callback, signature: signature, arguments: [accumulator!, item], resultType: accumulator!.type)!
            instructions.append(.copy(next, accumulator!))
        case "reduce":
            let next = try invoke(callback, signature: signature, arguments: [accumulator!, item], resultType: accumulator!.type)!
            instructions.append(.copy(next, accumulator!))
        default: throw fail("Unsupported JVM higher-order operation.", id)
        }
        mark(advance)
        if let index { let one = try constant(.int(1), .int); instructions.append(.binary(.add, index, one, index)) }
        jump(test); mark(end)
        if let list { return try convert(list, to: program.expressionType(id)) }
        return accumulator
    }
}
