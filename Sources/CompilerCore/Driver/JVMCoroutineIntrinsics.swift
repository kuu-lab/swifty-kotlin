extension JVMProgramBuilder {
    func coroutineIntrinsics() -> [JVMFunction] {
        guard needsSuspendCoroutine else { return [] }
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let block = JVMValue(slot: 0, type: .reference("kotlin/jvm/functions/Function1", nullable: false))
        let completion = JVMValue(slot: 1, type: .reference("kotlin/coroutines/Continuation", nullable: false))
        let safe = JVMValue(slot: 2, type: .reference("kotlin/coroutines/SafeContinuation", nullable: false))
        let argument = JVMValue(slot: 3, type: object), returned = JVMValue(slot: 4, type: object)
        let ctor = JVMForeignMethod(owner: "kotlin/coroutines/SafeContinuation", name: "<init>", descriptor: "(Lkotlin/coroutines/Continuation;)V", parameters: [completion.type], result: safe.type, isStatic: false, isInterface: false, isAbstract: false)
        let invoke = JVMForeignMethod(owner: "kotlin/jvm/functions/Function1", name: "invoke", descriptor: "(Ljava/lang/Object;)Ljava/lang/Object;", parameters: [object], result: object, isStatic: false, isInterface: true, isAbstract: true)
        let get = JVMForeignMethod(owner: ctor.owner, name: "getOrThrow", descriptor: "()Ljava/lang/Object;", parameters: [], result: object, isStatic: false, isInterface: false, isAbstract: false)
        return [rawFunction(coroutineIntrinsicOwner, name: "$suspendCoroutine", parameters: [block.type, completion.type], result: object, access: 0x1009, locals: [block, completion, safe, argument, returned], instructions: [.allocate(ctor.owner, safe), .foreignCall(ctor, receiver: safe, arguments: [completion], result: nil), .copy(safe, argument), .foreignCall(invoke, receiver: block, arguments: [argument], result: nil), .foreignCall(get, receiver: safe, arguments: [], result: returned), .returnValue(returned)])]
    }
}

extension JVMFunctionBuilder {
    func coroutineCall(_ symbol: SemanticSymbol, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        let name = symbol.fqName.map(context.interner.resolve)
        guard args.count == 1, name == ["kotlin", "coroutines", "suspendCoroutine"] || context.options.stdlibOnly && name == ["kotlin", "jvm", "internal", "__jvmSuspendCoroutine"] else { return nil }
        let callback = try requireValue(args[0].expr)
        program.needsSuspendCoroutine = true
        var method = JVMForeignMethod(owner: program.coroutineIntrinsicOwner, name: "$suspendCoroutine", descriptor: "(" + callback.type.descriptor + ")Ljava/lang/Object;", parameters: [callback.type], result: .reference("java/lang/Object", nullable: true), isStatic: true, isInterface: false, isAbstract: false)
        method.isSuspend = true
        let result = try program.expressionType(id), returned = result == .unit ? nil : try value(result)
        instructions.append(.foreignCall(method, receiver: nil, arguments: [callback], result: returned))
        return JVMIntrinsicResult(value: returned)
    }
    func coroutineMember(_ receiver: ExprID, name: String, args: [CallArgument], id: ExprID) throws -> JVMIntrinsicResult? {
        let object: JVMValueType = .reference("java/lang/Object", nullable: true)
        let continuation: JVMValueType = .reference("kotlin/coroutines/Continuation", nullable: false)
        if name == "startCoroutine", let signature = functionType(receiver), signature.isSuspend {
            let source = try requireValue(receiver)
            var values = [source]
            for arg in args { values.append(try requireValue(arg.expr)) }
            guard values.count == (signature.receiver == nil ? 2 : 3) else { throw fail("Unsupported startCoroutine arguments.", id) }
            let parameters: [JVMValueType] = [.reference("kotlin/jvm/functions/Function" + String(signature.receiver == nil ? 1 : 2), nullable: false)] + (signature.receiver == nil ? [] : [object]) + [continuation]
            return JVMIntrinsicResult(value: try jdkCall("kotlin/coroutines/ContinuationKt", "startCoroutine", parameters, .unit, arguments: values))
        }
        guard let semantic = program.sema.bindings.exprType(for: receiver) else { return nil }
        func nominal(_ id: TypeID, _ target: String, visited: Set<SymbolID> = []) -> Bool {
            switch program.sema.types.kind(of: id) {
            case let .classType(t):
                guard !visited.contains(t.classSymbol) else { return false }
                if (try? program.className(t.classSymbol)) == target { return true }
                return program.sema.symbols.directSupertypes(for: t.classSymbol).contains { nominal(program.sema.types.make(.classType(ClassType(classSymbol: $0))), target, visited: visited.union([t.classSymbol])) }
            case let .typeParam(t):
                guard !visited.contains(t.symbol) else { return false }
                return program.sema.symbols.typeParameterUpperBounds(for: t.symbol).contains { nominal($0, target, visited: visited.union([t.symbol])) }
            default: return false
            }
        }
        if nominal(semantic, "kotlin/coroutines/Continuation") {
            if name == "context", args.isEmpty { return JVMIntrinsicResult(value: try jdkCall(continuation.referenceName!, "getContext", [], .reference("kotlin/coroutines/CoroutineContext", nullable: false), receiver: requireValue(receiver), interface: true)) }
            if ["resume", "resumeWith", "resumeWithException"].contains(name), args.count == 1 {
                let receiver = try requireValue(receiver), argument = try requireValue(args[0].expr)
                let result = try name == "resumeWithException" ? jdkCall("kotlin/ResultKt", "createFailure", [.reference("java/lang/Throwable", nullable: false)], object, arguments: [argument])! : convert(argument, to: object)
                return JVMIntrinsicResult(value: try jdkCall(continuation.referenceName!, "resumeWith", [object], .unit, receiver: receiver, arguments: [result], interface: true))
            }
        }
        if nominal(semantic, "kotlin/Result"), args.isEmpty {
            let source = try requireValue(receiver)
            if name == "getOrThrow" {
                _ = try jdkCall("kotlin/ResultKt", "throwOnFailure", [object], .unit, arguments: [source])
                if try program.expressionType(id) == .unit { return JVMIntrinsicResult(value: nil) }
                return JVMIntrinsicResult(value: try convert(source, to: program.expressionType(id)))
            }
            if ["isSuccess", "isFailure"].contains(name) {
                let check = try value(.boolean)
                instructions.append(.instanceOf(source, "kotlin/Result$Failure", check))
                if name == "isSuccess" { instructions.append(.unary(.not, check, check)) }
                return JVMIntrinsicResult(value: check)
            }
            if name == "exceptionOrNull" {
                let check = try value(.boolean), result = try value(.reference("java/lang/Throwable", nullable: true)), no = label(), end = label()
                instructions.append(.instanceOf(source, "kotlin/Result$Failure", check)); instructions.append(.jumpIfFalse(check, no))
                let failure = try convert(source, to: .reference("kotlin/Result$Failure", nullable: false))
                instructions.append(.getField(JVMField(owner: "kotlin/Result$Failure", name: "exception", type: .reference("java/lang/Throwable", nullable: false), access: 0x11), failure, result)); jump(end)
                mark(no); instructions.append(.constant(.null, result)); mark(end)
                return JVMIntrinsicResult(value: result)
            }
        }
        return nil
    }
}
