extension TypeCheckDriver {
    /// SequenceScope permits suspension only through its own receiver. Check
    /// resolved receiver identities after lambda and overload inference finish.
    func validateJVMSequenceSuspensionContexts(inlineLambdaArguments: Set<ExprID>, suspendLambdaArguments: Set<ExprID>) {
        guard sema.requiresResolvedLibraryCalls else { return }
        let scope = sema.symbols.lookup(fqName: ["kotlin", "sequences", "SequenceScope"].map(interner.intern))
        func isScope(_ type: TypeID?, visiting: Set<SymbolID> = []) -> Bool {
            guard let type, let scope else { return false }
            switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
            case let .classType(t): return sema.types.isNominalSubtypeSymbol(t.classSymbol, of: scope)
            case let .typeParam(t):
                guard !visiting.contains(t.symbol) else { return false }
                return sema.symbols.typeParameterUpperBounds(for: t.symbol).contains { isScope($0, visiting: visiting.union([t.symbol])) }
            case let .intersection(parts): return parts.contains { isScope($0, visiting: visiting) }
            default: return false
            }
        }
        func functionType(_ id: ExprID) -> FunctionType? {
            guard let type = sema.bindings.exprType(for: id), case let .functionType(f) = sema.types.kind(of: type) else { return nil }
            return f
        }
        for id in callSuspensionContexts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let context = callSuspensionContexts[id], !suspendingCallNames(for: id).isEmpty else { continue }
            // The trusted builder implements yield using the lower-level suspension primitive.
            if sema.isJVMStdlibBuild, let owner = context.function,
               sema.symbols.symbol(owner).map({ let name = $0.fqName.map(interner.resolve); return name.dropLast() == ["kotlin", "sequences", "BuilderIterator"] && ["yield", "yieldAll"].contains(name.last ?? "") }) == true { continue }
            var restricted: SymbolID?
            var currentThis: SymbolID?
            if let owner = context.function, let signature = sema.symbols.functionSignature(for: owner), signature.receiverType != nil {
                currentThis = SyntheticSymbolScheme.receiverParameterSymbol(for: owner)
                if signature.isSuspend, isScope(signature.receiverType) { restricted = currentThis }
            }
            for lambda in context.lambdas {
                let function = functionType(lambda)
                if function?.receiver != nil { currentThis = SyntheticSymbolScheme.lambdaReceiverSymbol(for: lambda) }
                if function?.isSuspend == true || suspendLambdaArguments.contains(lambda) {
                    restricted = isScope(function?.receiver) ? SyntheticSymbolScheme.lambdaReceiverSymbol(for: lambda) : nil
                } else if !inlineLambdaArguments.contains(lambda) { restricted = nil }
            }
            let callee = sema.bindings.callBinding(for: id)?.chosenCallee
            let signature = callee.flatMap { sema.symbols.functionSignature(for: $0) }
            let parent = callee.flatMap { sema.symbols.parentSymbol(for: $0) }.flatMap { sema.symbols.symbol($0) }
            let scopeMember = parent?.fqName.map(interner.resolve) == ["kotlin", "sequences", "SequenceScope"]
            let scopeExtension = isScope(signature?.receiverType)
            let callable = sema.bindings.callableValueCallBinding(for: id).flatMap { binding -> FunctionType? in
                if case let .functionType(f) = sema.types.kind(of: binding.functionType) { return f }; return nil
            }
            let scopeCallable = isScope(callable?.receiver)
            // Kotlin permits the raw argument form f(scope), including forwarding
            // from an ordinary suspend function. Receiver syntax and .invoke
            // still obey restricted-receiver identity rules.
            if scopeCallable, let callable, case let .call(_, _, args, _) = ast.arena.expr(id), args.count == callable.params.count + 1 { continue }
            guard restricted != nil || scopeMember || scopeExtension || scopeCallable else { continue }
            var receiver: SymbolID?
            switch ast.arena.expr(id) {
            case let .memberCall(object, _, _, _, _):
                if case .thisRef = ast.arena.expr(object) {
                    receiver = sema.bindings.identifierSymbol(for: object) ?? currentThis
                }
            case .safeMemberCall: break
            default:
                receiver = sema.bindings.implicitExtensionReceiver(for: id)
                    ?? sema.bindings.implicitReceiverOuterReceiver(for: id)
                    ?? sema.bindings.callBinding(for: id)?.dispatchReceiverSymbol
                    ?? currentThis
            }
            if restricted == nil || !(scopeMember || scopeExtension || scopeCallable) || receiver != restricted {
                diagnostics.error("KSWIFTK-SEMA-0310", "Restricted SequenceScope suspension may only call suspending members or extensions on the same receiver.", range: ast.arena.exprRange(id))
            }
        }
    }
}
