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
        var calls: [(ExprID, SymbolID)] = []
        collectSequenceExtensionCalls(in: lambdaExprID, activeReceiver: receiverSymbol, ctx: ctx, calls: &calls)
        return calls.compactMap { id, activeReceiver in
            guard sema.bindings.exprType(for: id) != sema.types.errorType,
                  let binding = sema.bindings.callBindings[id],
                  isScopeExtensionCandidate(binding.chosenCallee, ctx: ctx)
                    || sema.symbols.memberExtensionOwnerSymbol(for: binding.chosenCallee) != nil,
                  let signature = sema.symbols.functionSignature(for: binding.chosenCallee),
                  let declaredReceiver = signature.receiverType
            else { return nil }

            let suppliedByBuilder: Bool
            switch ctx.ast.arena.expr(id) {
            case .call:
                // The active tower entry deliberately has no capture symbol.
                // Inherit it through ordinary lambdas, but replace it when a
                // nested lambda introduces its own receiver.
                let outerReceiver = sema.symbols.memberExtensionOwnerSymbol(for: binding.chosenCallee) == nil
                    ? sema.bindings.implicitReceiverOuterReceiver(for: id) : nil
                suppliedByBuilder = (sema.bindings.implicitExtensionReceiver(for: id)
                    ?? outerReceiver ?? activeReceiver) == receiverSymbol
            case let .memberCall(receiver, _, _, _, _), let .safeMemberCall(receiver, _, _, _, _):
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

    private func collectSequenceExtensionCalls(
        in id: ExprID,
        activeReceiver: SymbolID,
        ctx: TypeInferenceContext,
        calls: inout [(ExprID, SymbolID)]
    ) {
        guard let expr = ctx.ast.arena.expr(id) else { return }
        var receiver = activeReceiver
        let children: [ExprID]
        switch expr {
        case let .lambdaLiteral(_, body, _, _):
            if let type = ctx.sema.bindings.exprType(for: id),
               case let .functionType(function) = ctx.sema.types.kind(of: type),
               function.receiver != nil {
                receiver = SyntheticSymbolScheme.lambdaReceiverSymbol(for: id)
            }
            children = [body]
        case let .call(callee, _, args, _):
            calls.append((id, receiver))
            children = [callee] + args.map(\.expr)
        case let .memberCall(base, _, _, args, _), let .safeMemberCall(base, _, _, args, _):
            calls.append((id, receiver))
            children = [base] + args.map(\.expr)
        case let .blockExpr(statements, trailing, _):
            children = statements + (trailing.map { [$0] } ?? [])
        case let .localDecl(_, _, _, value, _, _, _), let .returnExpr(value, _, _):
            children = value.map { [$0] } ?? []
        case let .forExpr(_, iterable, body, _, _), let .forDestructuringExpr(_, iterable, body, _, _),
             let .whileExpr(iterable, body, _, _), let .doWhileExpr(iterable, body, _, _):
            children = [iterable, body]
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            children = [condition, thenExpr] + (elseExpr.map { [$0] } ?? [])
        case let .whenExpr(subject, branches, elseExpr, _):
            children = (subject.map { [$0] } ?? [])
                + branches.flatMap { $0.conditions + ($0.guard_.map { [$0] } ?? []) + [$0.body] }
                + (elseExpr.map { [$0] } ?? [])
        case let .tryExpr(body, catches, finallyExpr, _):
            children = [body] + catches.map(\.body) + (finallyExpr.map { [$0] } ?? [])
        case let .binary(_, lhs, rhs, _), let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            children = [lhs, rhs]
        case let .unaryExpr(_, value, _), let .nullAssert(value, _), let .throwExpr(value, _),
             let .asCast(value, _, _, _), let .isCheck(value, _, _, _),
             let .localAssign(_, value, _), let .compoundAssign(_, _, value, _),
             let .destructuringDecl(_, _, value, _):
            children = [value]
        case let .memberAssign(base, _, value, _), let .safeMemberAssign(base, _, value, _),
             let .memberCompoundAssign(_, base, _, value, _):
            children = [base, value]
        case let .indexedAccess(base, indices, _):
            children = [base] + indices
        case let .indexedAssign(base, indices, value, _), let .indexedCompoundAssign(_, base, indices, value, _):
            children = [base] + indices + [value]
        case let .stringTemplate(parts, _):
            children = parts.compactMap { if case let .expression(value) = $0 { return value }; return nil }
        default:
            children = []
        }
        for child in children {
            collectSequenceExtensionCalls(in: child, activeReceiver: receiver, ctx: ctx, calls: &calls)
        }
    }
}
