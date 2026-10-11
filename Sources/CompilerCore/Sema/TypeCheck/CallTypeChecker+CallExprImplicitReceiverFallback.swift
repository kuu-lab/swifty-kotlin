// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Implicit-receiver fallback paths for `inferCallExpr`: the `emit` member
/// guard, kx-mini coroutine builtins, builder-DSL member shortcuts, and the
/// implicit-receiver member-call fallback (including the range/progression
/// operator members).
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
extension CallTypeChecker {
    func inferImplicitReceiverFallbackCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        candidates: [SymbolID],
        memberExtensionReceiverMarks: inout [SymbolID: SymbolID]
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        // KUU-963: `emit` is also an ordinary member name (e.g. a user-defined
        // `Sink.emit`). The Flow builtin fallback must not shadow a real
        // member on an in-scope implicit receiver — when any receiver in the
        // implicit-receiver tower declares `emit`, defer to the member
        // resolution below so the call binds to the real declaration.
        let emitMemberExistsOnImplicitReceiver: Bool = {
            guard let calleeName,
                  calleeName == knownNames.emit
            else {
                return false
            }
            var receiverTypes: [TypeID] = []
            if let implicitReceiverType = ctx.implicitReceiverType {
                receiverTypes.append(implicitReceiverType)
            }
            for outerReceiver in ctx.outerReceiverTypes {
                receiverTypes.append(outerReceiver.type)
            }
            return receiverTypes.contains { receiverType in
                !driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: sema.types.makeNonNullable(receiverType),
                    sema: sema,
                    interner: interner
                ).isEmpty
            }
        }()
        if !emitMemberExistsOnImplicitReceiver,
           let builtinType = driver.helpers.kxMiniCoroutineBuiltinReturnType(
               calleeName: calleeName,
               argumentCount: args.count,
               sema: sema,
               interner: interner
           )
        {
            sema.bindings.bindExprType(id, type: builtinType)
            return builtinType
        }
        // Builder DSL member functions (STDLIB-002).
        // Inside builder lambdas, unqualified `append`/`add`/`put` resolve as
        // implicit-receiver member calls that return Unit.
        if let calleeName, ctx.isBuilderLambdaScope, let activeBuilderKind = ctx.builderKind {
            let name = interner.resolve(calleeName)
            let isBuilderMember: Bool = switch activeBuilderKind {
            case .buildList, .buildSet:
                (name == "add" && args.count == 1) || (name == "addAll" && args.count == 1)
            case .buildMap: name == "put" && args.count == 2
            }
            if isBuilderMember {
                for argument in args {
                    _ = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                }
                sema.bindings.markBuilderDSLExpr(id, kind: activeBuilderKind)
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
        }
        // STDLIB-004: Inside receiver lambdas (run/apply/with), unqualified
        // function calls resolve as member calls on the implicit receiver.
        if let calleeName, let receiverType = ctx.implicitReceiverType {
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            let name = interner.resolve(calleeName)
            if sema.types.isSubtype(nonNullReceiver, sema.types.charType),
               args.isEmpty,
               let member = syntheticCharMemberSpec(named: name)
            {
                let resultType = member.returnKind.typeID(
                    in: sema.types,
                    symbols: sema.symbols,
                    interner: interner
                )
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }

            // Boolean.not() / Boolean.and(other) / Boolean.or(other) / Boolean.xor(other) (STDLIB-308)
            if sema.types.isSubtype(nonNullReceiver, sema.types.booleanType) {
                let resultType = sema.types.booleanType
                let finalType = receiverType == nonNullReceiver
                    ? resultType
                    : sema.types.makeNullable(resultType)
                switch name {
                case "not" where args.isEmpty:
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                case "and" where args.count == 1,
                     "or" where args.count == 1,
                     "xor" where args.count == 1:
                    for arg in args {
                        _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
                    }
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                default:
                    break
                }
            }

            if let resultType = inferSequenceScopeYieldAllImplicitReceiverCall(
                id,
                calleeName: calleeName,
                args: args,
                ctx: ctx,
                locals: &locals,
                explicitTypeArgs: explicitTypeArgs
            ) {
                return resultType
            }

            // General member function lookup via implicit receiver
            var memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: nonNullReceiver,
                sema: sema,
                interner: interner
            )
            if interner.resolve(calleeName) == "toList" {
                memberCandidates = preferCollectionToListCandidates(
                    memberCandidates,
                    receiverType: nonNullReceiver,
                    sema: sema,
                    interner: interner
                )
            }
            if !memberCandidates.isEmpty {
                // Member extensions surface under the dispatch receiver type
                // but resolve against the implicit receiver tower entry picked
                // for their declared extension receiver. Regular members take
                // precedence over member extensions on the same receiver.
                var regularMemberCandidates: [SymbolID] = []
                var innermostMemberExtensionGroups: [(
                    symbols: [SymbolID], receiverType: TypeID, symbol: SymbolID?
                )] = []
                for candidate in memberCandidates {
                    guard let signature = sema.symbols.functionSignature(for: candidate),
                          sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil,
                          let declaredReceiver = signature.receiverType
                    else {
                        regularMemberCandidates.append(candidate)
                        continue
                    }
                    guard let picked = ctx.implicitReceiverMemberLookupEntries().first(where: { entry in
                        sema.types.isSubtype(
                            sema.types.makeNonNullable(entry.type),
                            sema.types.makeNonNullable(declaredReceiver)
                        )
                    })
                    else { continue }
                    if let groupIndex = innermostMemberExtensionGroups.firstIndex(where: {
                        $0.receiverType == picked.type
                    }) {
                        innermostMemberExtensionGroups[groupIndex].symbols.append(candidate)
                    } else {
                        innermostMemberExtensionGroups.append(([candidate], picked.type, picked.symbol))
                    }
                }
                var orderedMemberGroups: [(
                    symbols: [SymbolID], receiverType: TypeID, extensionSymbol: SymbolID?
                )] = regularMemberCandidates.isEmpty
                    ? []
                    : [(regularMemberCandidates, receiverType, nil)]
                orderedMemberGroups.append(
                    contentsOf: innermostMemberExtensionGroups.map {
                        ($0.symbols, $0.receiverType, $0.symbol)
                    }
                )
                // Eagerly infer argument types for overload resolution.
                // Integer literals still see the candidates' parameter type
                // so calls like `onTimeout(30)` can narrow `30` to `Long`.
                let memberArgTypes = args.enumerated().map { index, argument in
                    var literalExpectedType: TypeID?
                    if let argumentExpr = ctx.ast.arena.expr(argument.expr) {
                        let isSignedIntegerLike: Bool = {
                            switch argumentExpr {
                            case .intLiteral:
                                return true
                            case .unaryExpr(let op, let operandID, _):
                                guard op == .unaryPlus || op == .unaryMinus,
                                      case .intLiteral = ctx.ast.arena.expr(operandID)
                                else {
                                    return false
                                }
                                return true
                            default:
                                return false
                            }
                        }()
                        switch argumentExpr {
                        case _ where isSignedIntegerLike:
                            literalExpectedType = uniformNumericLiteralParameterType(
                                at: index, argumentLabel: argument.label, candidates: memberCandidates, sema: sema
                            )
                        case .uintLiteral:
                            literalExpectedType = uniformUnsignedLiteralParameterType(
                                at: index, argumentLabel: argument.label, candidates: memberCandidates, sema: sema
                            )
                        default:
                            break
                        }
                    }
                    let inferredType = driver.inferExpr(
                        argument.expr, ctx: ctx, locals: &locals, expectedType: literalExpectedType
                    )
                    return sourceLevelRangeArgumentType(
                        argument.expr, inferredType: inferredType, ctx: ctx
                    )
                }
                let resolvedArgs = zip(args, memberArgTypes).map { argument, type in
                    CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
                }
                for group in orderedMemberGroups {
                    let resolved = ctx.resolver.resolveCall(
                        candidates: group.symbols,
                        call: CallExpr(
                            range: range,
                            calleeName: calleeName,
                            args: resolvedArgs,
                            explicitTypeArgs: explicitTypeArgs,
                            dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
                        ),
                        expectedType: overloadResolutionExpectedType(from: expectedType, sema: sema),
                        implicitReceiverType: group.receiverType,
                        ctx: ctx.semaCtx
                    )
                    if let chosen = resolved.chosenCallee {
                        let resultType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
                        sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                        if let extensionSymbol = group.extensionSymbol {
                            sema.bindings.markImplicitExtensionReceiver(id, symbol: extensionSymbol)
                        }
                        markCoroutineScopeImplicitReceiverCallIfNeeded(
                            id,
                            chosenCallee: chosen,
                            receiverType: receiverType,
                            ctx: ctx
                        )
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
                if regularMemberCandidates.count == 1,
                   let bestCandidate = regularMemberCandidates.first,
                   let sig = sema.symbols.functionSignature(for: bestCandidate)
                {
                    // Fallback: bind directly if resolver could not pick (single candidate).
                    var mapping: [Int: Int] = [:]
                    for i in args.indices { mapping[i] = i }
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: bestCandidate,
                            substitutedTypeArguments: [],
                            parameterMapping: mapping
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(bestCandidate))
                    sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                    let resultType = sig.returnType
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
            }
            // Kotlin's implicit-receiver tower: when the innermost receiver
            // has no matching member, unqualified calls continue outward
            // through enclosing receivers — e.g. a class enclosing an object
            // literal (`object : Any() { fun f() = fetch(0) }`). Only entries
            // carrying a receiver symbol participate: the symbol is what
            // capture analysis stores into the object literal's fields, so
            // KIR lowering can materialize the receiver value from it.
            for outerReceiver in ctx.outerReceiverTypes.reversed() {
                let outerNonNullReceiver = sema.types.makeNonNullable(outerReceiver.type)
                guard let outerReceiverSymbol = outerReceiver.symbol,
                      outerNonNullReceiver != nonNullReceiver
                else {
                    continue
                }
                let outerCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: outerNonNullReceiver,
                    sema: sema,
                    interner: interner
                )
                guard !outerCandidates.isEmpty else {
                    continue
                }
                // Member extensions consume two implicit receivers: the tower
                // entry dispatches them while a (usually innermost) receiver
                // supplies their declared extension receiver — `bump()` inside
                // `Int.add()` binds `Base.bump` on dispatch `this@Derived` with
                // receiver `Int`. Resolve them apart from plain members, which
                // check the tower entry itself.
                var outerMemberExtensionCandidates: [(symbol: SymbolID, receiverType: TypeID)] = []
                var outerRegularCandidates: [SymbolID] = []
                for candidate in outerCandidates {
                    guard sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil else {
                        outerRegularCandidates.append(candidate)
                        continue
                    }
                    guard let signature = sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType,
                          let picked = ctx.implicitReceiverMemberLookupEntries().first(where: { entry in
                              sema.types.isSubtype(
                                  sema.types.makeNonNullable(entry.type),
                                  sema.types.makeNonNullable(declaredReceiver)
                              )
                          })
                    else { continue }
                    outerMemberExtensionCandidates.append((candidate, picked.type))
                    if let pickedSymbol = picked.symbol {
                        memberExtensionReceiverMarks[candidate] = pickedSymbol
                    }
                }
                let outerArgTypes = args.map { argument in
                    driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                }
                let resolvedOuterArgs = zip(args, outerArgTypes).map { argument, type in
                    CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
                }
                let resolvedOuter = ctx.resolver.resolveCall(
                    candidates: outerRegularCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: calleeName,
                        args: resolvedOuterArgs,
                        explicitTypeArgs: explicitTypeArgs,
                        dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
                    ),
                    expectedType: overloadResolutionExpectedType(from: expectedType, sema: sema),
                    implicitReceiverType: outerReceiver.type,
                    ctx: ctx.semaCtx
                )
                if resolvedOuter.chosenCallee == nil {
                    var seenExtensionReceivers = Set<TypeID>()
                    for receiverType in outerMemberExtensionCandidates.map(\.receiverType)
                    where seenExtensionReceivers.insert(receiverType).inserted
                    {
                        let receiverCandidates = outerMemberExtensionCandidates
                            .filter { $0.receiverType == receiverType }
                            .map(\.symbol)
                        let resolvedExtension = ctx.resolver.resolveCall(
                            candidates: receiverCandidates,
                            call: CallExpr(
                                range: range,
                                calleeName: calleeName,
                                args: resolvedOuterArgs,
                                explicitTypeArgs: explicitTypeArgs,
                                dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
                            ),
                            expectedType: overloadResolutionExpectedType(from: expectedType, sema: sema),
                            implicitReceiverType: receiverType,
                            ctx: ctx.semaCtx
                        )
                        if let chosen = resolvedExtension.chosenCallee {
                            let resultType = bindCallAndResolveReturnType(
                                id,
                                chosen: chosen,
                                resolved: resolvedExtension,
                                sema: sema
                            )
                            sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                            sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: outerReceiverSymbol)
                            if let extensionReceiverSymbol = memberExtensionReceiverMarks[chosen] {
                                sema.bindings.markImplicitExtensionReceiver(id, symbol: extensionReceiverSymbol)
                            }
                            markCoroutineScopeImplicitReceiverCallIfNeeded(
                                id,
                                chosenCallee: chosen,
                                receiverType: outerReceiver.type,
                                ctx: ctx
                            )
                            sema.bindings.bindExprType(id, type: resultType)
                            return resultType
                        }
                    }
                }
                if let chosen = resolvedOuter.chosenCallee {
                    let resultType = bindCallAndResolveReturnType(
                        id,
                        chosen: chosen,
                        resolved: resolvedOuter,
                        sema: sema
                    )
                    sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                    sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: outerReceiverSymbol)
                    if let extensionReceiverSymbol = memberExtensionReceiverMarks[chosen] {
                        sema.bindings.markImplicitExtensionReceiver(id, symbol: extensionReceiverSymbol)
                    }
                    markCoroutineScopeImplicitReceiverCallIfNeeded(
                        id,
                        chosenCallee: chosen,
                        receiverType: outerReceiver.type,
                        ctx: ctx
                    )
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
                if outerCandidates.count == 1,
                   let bestCandidate = outerCandidates.first,
                   let sig = sema.symbols.functionSignature(for: bestCandidate)
                {
                    var mapping: [Int: Int] = [:]
                    for i in args.indices { mapping[i] = i }
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: bestCandidate,
                            substitutedTypeArguments: [],
                            parameterMapping: mapping
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(bestCandidate))
                    sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                    sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: outerReceiverSymbol)
                    if let extensionReceiverSymbol = memberExtensionReceiverMarks[bestCandidate] {
                        sema.bindings.markImplicitExtensionReceiver(id, symbol: extensionReceiverSymbol)
                    }
                    let resultType = sig.returnType
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
            }
            if let fallbackType = tryBindImplicitReceiverSyntheticExtensionCall(
                id, calleeName: calleeName, receiverType: nonNullReceiver, args: args,
                range: range, ctx: ctx, locals: &locals, expectedType: expectedType,
                explicitTypeArgs: explicitTypeArgs
            ) { return fallbackType }
        }
        return nil
    }
}
