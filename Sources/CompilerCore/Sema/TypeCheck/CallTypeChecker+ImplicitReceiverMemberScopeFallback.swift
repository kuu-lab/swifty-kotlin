extension CallTypeChecker {
    /// Keep member precedence, but do not contextualize lambda bodies against
    /// a member tier already ruled out by argument types, arity, or labels.
    /// The displaced visible scope tier must get its own argument preparation.
    func preferScopeCandidatesForInapplicableImplicitMembers(
        args: [CallArgument],
        calleeName: InternedString?,
        scopeCandidates: [SymbolID],
        candidates: inout [SymbolID],
        receiverType: inout TypeID?,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) {
        guard let calleeName,
              locals[calleeName] == nil,
              let implicitReceiverType = ctx.implicitReceiverType,
              !candidates.isEmpty
        else { return }
        let members = Set(driver.helpers.collectMemberFunctionCandidates(
            named: calleeName, receiverType: implicitReceiverType, sema: ctx.sema, interner: ctx.interner
        ))
        guard candidates.allSatisfy({ members.contains($0) }) else { return }
        var fallbackCandidates = scopeCandidates.filter { !members.contains($0) }
        if fallbackCandidates.isEmpty {
            // Extension bodies can carry their receiver's member scope in
            // the lexical chain. Ordinary lookup then stops at the member
            // itself, before candidate collection can save the outer tier.
            let outerCandidates = ctx.scope.lookup(calleeName, matching: { candidate in
                guard !members.contains(candidate),
                      let symbol = ctx.cachedSymbol(candidate)
                else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }).filter { !ctx.isCandidateBlockedByDslMarker($0) }
            fallbackCandidates = ctx.filterByVisibility(outerCandidates).visible
        }
        guard !fallbackCandidates.isEmpty else { return }

        let checkpoint = ctx.sema.diagnostics.checkpoint()
        defer { ctx.sema.diagnostics.rollback(to: checkpoint) }
        var probeLocals = locals
        var nonLambdaArgumentTypes: [Int: TypeID] = [:]
        for (index, argument) in args.enumerated() {
            // Only use types independent of a candidate's expected type. Calls,
            // conditionals and blocks may contain lambdas or numeric literals
            // that require that context; do not infer their bodies speculatively.
            switch ctx.ast.arena.expr(argument.expr) {
            case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
                 .floatLiteral, .doubleLiteral, .charLiteral, .nullLiteral,
                 .boolLiteral, .stringLiteral:
                nonLambdaArgumentTypes[index] = driver.inferExpr(argument.expr, ctx: ctx, locals: &probeLocals)
            case .nameRef:
                let type = driver.inferExpr(argument.expr, ctx: ctx, locals: &probeLocals)
                nonLambdaArgumentTypes[index] = driver.helpers.retypeClassNameAsCompanionValue(
                    argument.expr, currentType: type, ast: ctx.ast, sema: ctx.sema
                ) ?? type
            case .stringTemplate:
                nonLambdaArgumentTypes[index] = ctx.sema.types.stringType
            case let .binary(op, _, _, _):
                switch op {
                case .equal, .notEqual, .identityEqual, .notIdentityEqual,
                     .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual,
                     .logicalAnd, .logicalOr:
                    nonLambdaArgumentTypes[index] = ctx.sema.types.booleanType
                default:
                    break
                }
            case let .unaryExpr(op, operand, _):
                if (op == .unaryPlus || op == .unaryMinus),
                   case .intLiteral = ctx.ast.arena.expr(operand)
                {
                    nonLambdaArgumentTypes[index] = driver.inferExpr(argument.expr, ctx: ctx, locals: &probeLocals)
                }
            default:
                break
            }
        }
        guard narrowedCallCandidates(
            candidates: candidates, args: args, inferredNonLambdaArgTypes: nonLambdaArgumentTypes,
            receiverType: receiverType, forImplicitMemberApplicability: true, ctx: ctx
        ).isEmpty else { return }

        candidates = fallbackCandidates
        receiverType = ctx.implicitReceiverMemberLookupEntries().first { entry in
            candidates.contains { candidate in
                guard let declaredReceiver = ctx.sema.symbols.functionSignature(for: candidate)?.receiverType
                else { return false }
                return extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: entry.type, declaredReceiver: declaredReceiver, sema: ctx.sema
                )
            }
        }?.type ?? ctx.implicitReceiverType
    }
}
