extension CallTypeChecker {
    private enum MemberInputApplicability {
        case applicable
        case inapplicable
        case deferred
    }

    /// A member name alone does not stop Kotlin's implicit-receiver tower.
    /// Reject only arity mismatches or closed signatures with already-typed
    /// scalar inputs. Open inference and postponed arguments stay on the normal
    /// call path; expected return types never make a member inapplicable here.
    func scopeCallCandidatesAfterInapplicableMembers(
        named name: InternedString,
        args: [CallArgument],
        range: SourceRange,
        explicitTypeArgs: [TypeID],
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> (candidates: [SymbolID], excludedMembers: Set<SymbolID>, knownApplicableMembers: Set<SymbolID>) {
        let original = scopeCallCandidatesConsideringImplicitReceivers(named: name, ctx: ctx)
        guard locals[name] == nil,
              let activeReceiver = ctx.implicitReceiverType ?? ctx.implicitReceiverMemberLookupEntries().first?.type
        else {
            return (original, [], [])
        }
        let sema = ctx.sema
        let initialMembers = ctx.filterByVisibility(
            driver.helpers.collectMemberFunctionCandidates(
                named: name, receiverType: activeReceiver, sema: sema, interner: ctx.interner
            ).filter {
                isRegularNominalScopeMember($0, ctx: ctx)
                    && !ctx.isCandidateBlockedByDslMarker($0)
                    && (sema.symbols.isSourceBackedSymbol($0)
                        || sema.symbols.symbol($0)?.flags.contains(.synthetic) == false)
            }
        ).visible
        guard !initialMembers.isEmpty else { return (original, [], []) }
        var members = initialMembers
        var receiver = activeReceiver
        var excluded: Set<SymbolID> = []
        while true {
            switch closedMemberInputApplicability(
                members, args: args, range: range, explicitTypeArgs: explicitTypeArgs,
                receiverType: receiver, name: name, ctx: ctx, locals: locals
            ) {
            case .applicable:
                return (excluded.isEmpty ? original : members, excluded, Set(members))
            case .deferred:
                return (excluded.isEmpty ? original : members, excluded, [])
            case .inapplicable:
                excluded.formUnion(members)
            }
            // Keep lexical/import tiers. Do not search the global short-name
            // table, which would admit missing imports or private declarations.
            let next = ctx.scope.lookup(name, matching: { candidate in
                guard !excluded.contains(candidate), let symbol = ctx.cachedSymbol(candidate) else { return false }
                return (symbol.kind == .function || symbol.kind == .constructor)
                    && !ctx.isCandidateBlockedByDslMarker(candidate)
                    && ctx.visibilityChecker.isAccessible(
                        symbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
                    )
            })
            guard !next.isEmpty else { return ([], excluded, []) }
            guard next.allSatisfy({ isRegularNominalScopeMember($0, ctx: ctx) }),
                  let nextReceiver = ctx.implicitReceiverMemberLookupEntries().first(where: { entry in
                      next.allSatisfy { candidate in
                          guard let declared = sema.symbols.functionSignature(for: candidate)?.receiverType else { return false }
                          return sema.types.isSubtype(entry.type, declared)
                      }
                  })
            else { return (next, excluded, []) }
            let visibleNext = ctx.filterByVisibility(next.filter { !ctx.isCandidateBlockedByDslMarker($0) }).visible
            // Preserve the normal inaccessible-declaration diagnostic.
            guard !visibleNext.isEmpty else { return (next, excluded, []) }
            members = visibleNext
            receiver = nextReceiver.type
        }
    }

    private func isRegularNominalScopeMember(_ candidate: SymbolID, ctx: TypeInferenceContext) -> Bool {
        let symbols = ctx.sema.symbols
        guard let symbol = symbols.symbol(candidate), symbol.kind == .function,
              symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
              let owner = symbols.parentSymbol(for: candidate), let ownerInfo = symbols.symbol(owner),
              [.class, .interface, .enumClass, .object].contains(ownerInfo.kind),
              symbol.fqName == ownerInfo.fqName + [symbol.name],
              symbols.functionSignature(for: candidate)?.receiverType != nil
        else { return false }
        return true
    }

    private func closedMemberInputApplicability(
        _ candidates: [SymbolID], args: [CallArgument], range: SourceRange, explicitTypeArgs: [TypeID],
        receiverType: TypeID, name: InternedString, ctx: TypeInferenceContext, locals: LocalBindings
    ) -> MemberInputApplicability {
        let sema = ctx.sema
        let arityCompatible = candidates.filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
            return isCallableArityCompatible(signature: signature, argCount: args.count)
                && parameterMappingForCallArguments(args, in: signature, ctx: ctx) != nil
        }
        guard !arityCompatible.isEmpty else { return .inapplicable }
        guard arityCompatible.allSatisfy({ candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.typeParameterSymbols.isEmpty,
                  signature.contextReceiverTypes.allSatisfy({ isClosedMemberInputType($0, sema: sema) }),
                  signature.parameterTypes.allSatisfy({ isClosedMemberInputType($0, sema: sema) }),
                  isClosedMemberInputType(signature.returnType, sema: sema),
                  let declaredReceiver = signature.receiverType
            else { return false }
            return isClosedMemberInputType(declaredReceiver, sema: sema)
        }) else { return .deferred }
        guard args.allSatisfy({ argument in
            guard let expression = ctx.ast.arena.expr(argument.expr) else { return false }
            switch expression {
            case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
                 .floatLiteral, .doubleLiteral, .charLiteral, .stringLiteral,
                 .boolLiteral, .nullLiteral:
                return true
            case let .nameRef(name, _):
                // Do not infer an unknown property/getter, or bind an open
                // local input, merely to probe the receiver tower.
                guard let knownType = locals[name]?.type ?? sema.bindings.exprType(for: argument.expr)
                else { return false }
                return isClosedMemberInputType(knownType, sema: sema)
            case let .unaryExpr(op, operand, _):
                guard op == .unaryPlus || op == .unaryMinus else { return false }
                if case .intLiteral = ctx.ast.arena.expr(operand) { return true }
                return false
            default:
                return false
            }
        }) else { return .deferred }
        let checkpoint = ctx.semaCtx.diagnostics.checkpoint()
        defer { ctx.semaCtx.diagnostics.rollback(to: checkpoint) }
        var probeLocals = locals
        let prepared = prepareCallArguments(
            args: args, candidates: arityCompatible, explicitTypeArgs: explicitTypeArgs,
            receiverType: receiverType, ctx: ctx, locals: &probeLocals
        )
        guard !prepared.argTypes.contains(sema.types.errorType),
              prepared.argTypes.allSatisfy({ isClosedMemberInputType($0, sema: sema) }),
              !ctx.semaCtx.diagnostics.diagnostics.dropFirst(checkpoint).contains(where: { $0.severity == .error })
        else { return .deferred }
        let resolved = resolveCallRespectingLambdaReturnType(
            candidates: arityCompatible, args: args, argTypes: prepared.argTypes,
            range: range,
            calleeName: name, explicitTypeArgs: explicitTypeArgs, expectedType: nil,
            implicitReceiverType: receiverType,
            lambdaLiteralIndices: prepared.lambdaLiteralIndices,
            inputOnlyLambdaIndices: prepared.inputOnlyLambdaIndices,
            blockedLambdaRefinement: prepared.blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: prepared.hasUnresolvableImplicitLambdaParameter, ctx: ctx
        )
        if resolved.chosenCallee != nil || resolved.diagnostic?.code == "KSWIFTK-SEMA-0003" { return .applicable }
        return resolved.diagnostic?.code == "KSWIFTK-SEMA-0002" ? .inapplicable : .deferred
    }

    /// Local to the speculative tower probe. The general lambda-inference
    /// predicate has a different purpose and does not cover every type shape.
    /// Unknown/error types, star projections and recursion limits defer to
    /// normal call inference rather than excluding a member prematurely.
    private func isClosedMemberInputType(_ type: TypeID, sema: SemaModule) -> Bool {
        var activeTypes: Set<TypeID> = []
        func isClosed(_ current: TypeID, depth: Int) -> Bool {
            guard depth < 64, activeTypes.insert(current).inserted else { return false }
            defer { activeTypes.remove(current) }
            switch sema.types.kind(of: current) {
            case .unit, .nullableUnit, .nothing, .any, .stringStruct, .primitive:
                return true
            case let .classType(classType):
                guard sema.symbols.symbol(classType.classSymbol) != nil else { return false }
                return classType.args.allSatisfy { argument in
                    switch argument {
                    case let .invariant(inner), let .out(inner), let .in(inner):
                        return isClosed(inner, depth: depth + 1)
                    case .star:
                        return false
                    }
                }
            case let .functionType(functionType):
                return functionType.contextReceivers.allSatisfy { isClosed($0, depth: depth + 1) }
                    && (functionType.receiver.map { isClosed($0, depth: depth + 1) } ?? true)
                    && functionType.params.allSatisfy { isClosed($0, depth: depth + 1) }
                    && isClosed(functionType.returnType, depth: depth + 1)
                    && functionType.throws.allSatisfy { isClosed($0, depth: depth + 1) }
            case let .intersection(parts):
                return !parts.isEmpty && parts.allSatisfy { isClosed($0, depth: depth + 1) }
            case let .kClassType(kClassType):
                return isClosed(kClassType.argument, depth: depth + 1)
            default:
                return false
            }
        }
        return isClosed(type, depth: 0)
    }
}
