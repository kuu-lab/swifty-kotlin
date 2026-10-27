extension TypeCheckDriver {
    /// Includes implicit operator calls that are stored outside callBindings.
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
        // The Channel.send intrinsic has no call binding, but still requires
        // the same suspension context as the source SendChannel declaration.
        let channelCall: (receiver: ExprID, callee: InternedString, args: [CallArgument])?
        switch ast.arena.expr(id) {
        case let .memberCall(receiver, callee, _, args, _),
             let .safeMemberCall(receiver, callee, _, args, _):
            channelCall = (receiver, callee, args)
        default:
            channelCall = nil
        }
        if sema.bindings.callBinding(for: id) == nil,
           let channelCall,
           interner.resolve(channelCall.callee) == "send", channelCall.args.count == 1,
           let resultType = sema.bindings.exprType(for: id), resultType != sema.types.errorType,
           let receiverType = sema.bindings.exprType(for: channelCall.receiver),
           ReceiverClassifier(sema: sema, interner: interner).isChannelReceiverType(receiverType)
        {
            names.append("send")
        }
        return names
    }

    /// Validate after inference: inline argument mappings and suspend lambda
    /// types may not be available while their bodies are first visited.
    /// `suspendLambdaArguments` records lambda literals bound to a parameter
    /// declared as a `suspend` function type; that bound signature is
    /// authoritative even when the lambda's own `exprTypes` entry kept the
    /// non-suspend inferred shape.
    func validateSuspensionContexts(
        inlineLambdaArguments: Set<ExprID>,
        suspendLambdaArguments: Set<ExprID>
    ) {
        validateJVMSequenceSuspensionContexts(inlineLambdaArguments: inlineLambdaArguments, suspendLambdaArguments: suspendLambdaArguments)
        func functionType(_ exprID: ExprID) -> FunctionType? {
            // SAM conversion replaces the expression type with the nominal
            // interface; its callable signature still owns suspension context.
            guard let type = sema.bindings.samUnderlyingFunctionType(for: exprID) ?? sema.bindings.exprTypes[exprID] else { return nil }
            if case let .functionType(function) = sema.types.kind(of: sema.types.makeNonNullable(type)) {
                return function
            }
            return sema.types.nominalFunctionType(for: type)
        }

        func allowsSuspension(in context: SuspensionContext) -> Bool {
            // Only inlined ordinary lambdas may inherit a surrounding
            // suspension context. A suspend lambda supplies its own context.
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
