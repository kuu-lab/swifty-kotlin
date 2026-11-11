extension CallTypeChecker {
    /// SequenceScope is contravariant: calling a SequenceScope<X> extension
    /// on the builder receiver requires X <: T, just like yield(X). Use the
    /// selected call's specialized receiver, so rejected overloads contribute
    /// no bounds and generic extensions retain their inferred arguments.
    func sequenceBuilderExtensionElementTypes(
        lambdaExprID: ExprID,
        ctx: TypeInferenceContext
    ) -> [TypeID] {
        let sema = ctx.sema
        let receiverSymbol = SyntheticSymbolScheme.lambdaReceiverSymbol(for: lambdaExprID)
        let scopeName = ["kotlin", "sequences", "SequenceScope"].map(ctx.interner.intern)
        return sema.bindings.callBindings.sorted { $0.key.rawValue < $1.key.rawValue }.compactMap { id, binding in
            guard sema.bindings.exprType(for: id) != sema.types.errorType,
                  isScopeExtensionCandidate(binding.chosenCallee, ctx: ctx)
                    || sema.symbols.memberExtensionOwnerSymbol(for: binding.chosenCallee) != nil,
                  let signature = sema.symbols.functionSignature(for: binding.chosenCallee),
                  let declaredReceiver = signature.receiverType
            else { return nil }

            let suppliedByBuilder: Bool
            switch ctx.ast.arena.expr(id) {
            case .call:
                suppliedByBuilder = (sema.bindings.implicitExtensionReceiver(for: id)
                    ?? sema.bindings.implicitReceiverOuterReceiver(for: id)) == receiverSymbol
            case let .memberCall(receiver, _, _, _, _):
                suppliedByBuilder = sema.bindings.identifierSymbol(for: receiver) == receiverSymbol
            default:
                suppliedByBuilder = false
            }
            guard suppliedByBuilder else { return nil }

            let variables = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            var substitution: [TypeVarID: TypeID] = [:]
            for (symbol, type) in zip(signature.typeParameterSymbols, binding.substitutedTypeArguments) {
                if let variable = variables[symbol] { substitution[variable] = type }
            }
            let specializedReceiver = sema.types.substituteTypeParameters(
                in: declaredReceiver, substitution: substitution, typeVarBySymbol: variables
            )
            guard let receiverClass = resolveClassType(specializedReceiver, sema: sema),
                  sema.symbols.symbol(receiverClass.classSymbol)?.fqName == scopeName,
                  let argument = receiverClass.args.first
            else { return nil }
            switch argument {
            case let .invariant(type), let .in(type), let .out(type): return type
            case .star: return nil
            }
        }
    }
}
