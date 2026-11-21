extension TypeCheckDriver {
    func suspendingCallNames(for id: ExprID) -> [String] {
        var callees: [SymbolID] = []
        if let call = sema.bindings.callBinding(for: id) { callees.append(call.chosenCallee) }
        if let call = sema.bindings.indexedCompoundAssignElementOperatorBindings[id]?.call { callees.append(call.chosenCallee) }
        if let call = sema.bindings.indexedCompoundAssignOperatorBindings[id]?.setCall { callees.append(call.chosenCallee) }
        if let loop = sema.bindings.loopIterationBindings[id] {
            if let call = loop.iteratorCall { callees.append(call.chosenCallee) }
            callees.append(loop.hasNextCall.chosenCallee)
            callees.append(loop.nextCall.chosenCallee)
        }
        if let components = sema.bindings.destructuringComponentCallees[id] {
            for index in components.keys.sorted() {
                if let callee = components[index] { callees.append(callee) }
            }
        }
        var seen: Set<SymbolID> = []
        var names = callees.compactMap { callee -> String? in
            guard seen.insert(callee).inserted,
                  sema.symbols.functionSignature(for: callee)?.isSuspend == true,
                  let symbol = sema.symbols.symbol(callee) else { return nil }
            return interner.resolve(symbol.name)
        }
        if let binding = sema.bindings.callableValueCallBinding(for: id),
           case let .functionType(function) = sema.types.kind(of: binding.functionType),
           function.isSuspend {
            names.append("invoke")
        }
        if let specialName = specialSuspendingCallNames[id] {
            names.append(specialName)
        }
        return names
    }

    func validateSuspensionContexts(
        inlineLambdaArguments: Set<ExprID>,
        suspendLambdaArguments: Set<ExprID>
    ) {
        validateJVMSequenceSuspensionContexts(inlineLambdaArguments: inlineLambdaArguments, suspendLambdaArguments: suspendLambdaArguments)
        func functionType(_ exprID: ExprID) -> FunctionType? {
            guard let type = sema.bindings.samUnderlyingFunctionType(for: exprID) ?? sema.bindings.exprTypes[exprID] else { return nil }
            if case let .functionType(function) = sema.types.kind(of: sema.types.makeNonNullable(type)) {
                return function
            }
            return sema.types.nominalFunctionType(for: type)
        }

        func allowsSuspension(in context: SuspensionContext) -> Bool {
            var allowed = context.function.flatMap { sema.symbols.functionSignature(for: $0) }?.isSuspend == true
            for lambda in context.lambdas {
                if functionType(lambda)?.isSuspend == true || suspendLambdaArguments.contains(lambda) {
                    allowed = true
                } else if !inlineLambdaArguments.contains(lambda) {
                    allowed = false
                }
            }
            return allowed
        }

        for id in callSuspensionContexts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let context = callSuspensionContexts[id] else { continue }
            if !allowsSuspension(in: context) {
                for name in suspendingCallNames(for: id) {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0308",
                        "Suspend function '\(name)' can only be called from a coroutine or another suspend function.",
                        range: ast.arena.exprRange(id)
                    )
                }
            }
        }

        for id in coroutineContextPropertySuspensionContexts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let context = coroutineContextPropertySuspensionContexts[id], !allowsSuspension(in: context) else { continue }
            diagnostics.error(
                "KSWIFTK-SEMA-0313",
                "Suspend property 'val coroutineContext: CoroutineContext' can only be accessed from a coroutine or suspend function.",
                range: ast.arena.exprRange(id)
            )
        }
    }
}
