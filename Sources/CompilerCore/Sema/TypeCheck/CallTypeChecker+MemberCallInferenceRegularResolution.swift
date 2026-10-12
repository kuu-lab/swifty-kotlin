import Foundation

// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// Names of stdlib collection members backed by bundled Kotlin sources.
    /// Shared by member-call resolution paths that compare the resolved callee
    /// text; interned-String comparisons live on `KnownCompilerNames`.
    static let sourceBackedCollectionMemberNames: Set<String> = ["take", "drop", "chunked", "windowed", "asSequence", "constrainOnce", "orEmpty", "distinct", "flatten", "filterNotNull", "withIndex", "toList", "toMutableList", "toSet", "toMutableSet", "toHashSet", "toSortedSet", "toSortedMap", "toCollection", "toMap", "unzip", "union", "intersect", "subtract", "plus", "plusElement", "minus", "minusElement", "average", "sliceArray", "reversedArray", "asList", "toTypedArray", "putAll", "remove", "clear"]
    static let sourceBackedTrailingLambdaMemberNames: Set<String> = ["map", "filter", "filterNot", "mapIndexed", "mapNotNull", "filterIndexed", "onEach", "onEachIndexed", "ifEmpty", "flatMap", "flatMapIndexed", "joinTo", "joinToString", "isNotEmpty", "forEach"]

    func inferRegularMemberCall(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        if calleeName == knownNames.async,
           isCoroutineScopeType(receiverType, sema: sema, interner: interner)
        {
            for argument in args {
                if case .lambdaLiteral = ast.arena.expr(argument.expr) {
                    sema.bindings.markCoroutineLauncherLambdaExpr(argument.expr)
                }
            }
        }
        let isFlowReceiver = if sema.bindings.isFlowExpr(receiverID) {
            true
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  sema.bindings.isFlowSymbol(receiverSymbol)
        {
            true
        } else {
            false
        }
        let flowElementType: TypeID = if let elementType = sema.bindings.flowElementType(forExpr: receiverID) {
            elementType
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  let elementType = sema.bindings.flowElementType(forSymbol: receiverSymbol)
        {
            elementType
        } else {
            sema.types.anyType
        }
        // Infer argument types for the normal resolution path (scope functions,
        // collection HOFs, and comparator HOFs infer their lambda args with
        // expected type above and return).
        // Skip lambda literals and callable refs so that their first inference
        // happens inside prepareCallArguments with a contextual expected type,
        // preventing a stale no-expectedType binding from poisoning the cache.
        let isLongRangeLiteralContainsCall = calleeName == knownNames.contains
            && args.count == 1
            && MemberRuntimeDispatch.rangeReceiverKind(
                receiverExpr: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            ) == .longRange
            && driver.callChecker.isContextualizableIntegerLiteral(args[0].expr, ast: ast)
        let isULongRangeLiteralContainsCall = calleeName == knownNames.contains
            && args.count == 1
            && MemberRuntimeDispatch.rangeReceiverKind(
                receiverExpr: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            ) == .ulongRange
            && driver.callChecker.isContextualizableUnsignedIntegerLiteral(args[0].expr, ast: ast)
        contextualizeArrayComparatorArgument(
            calleeName: calleeName, receiverID: receiverID, receiverType: receiverType,
            args: args, ctx: ctx, locals: &locals
        )
        let argTypes = args.map { arg -> TypeID in
            if let expr = ast.arena.expr(arg.expr) {
                switch expr {
                case .lambdaLiteral, .callableRef:
                    return sema.bindings.exprType(for: arg.expr) ?? sema.types.anyType
                default:
                    break
                }
            }
            if isLongRangeLiteralContainsCall {
                return driver.inferExpr(
                    arg.expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: sema.types.longType
                )
            }
            if isULongRangeLiteralContainsCall {
                return driver.inferExpr(
                    arg.expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: sema.types.ulongType
                )
            }
            // Speculative declaration checks can leave a name reference bound
            // to a placeholder type. Read its current local/member type again.
            let inferredType: TypeID
            if case .nameRef = ast.arena.expr(arg.expr) {
                inferredType = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
            } else {
                inferredType = sema.bindings.exprType(for: arg.expr)
                    ?? driver.inferExpr(arg.expr, ctx: ctx, locals: &locals)
            }
            if calleeName == knownNames.coerceIn,
               let rangeType = floatingPointRangeArgumentType(
                   arg.expr,
                   ast: ast,
                   sema: sema,
                   interner: interner
               )
            {
                // Floating-point range expressions use a scalar lowering type for
                // the existing range runtime path, but source-backed coerceIn
                // resolves against ClosedFloatingPointRange<T>.
                return rangeType
            }
            return inferredType
        }

        let hasLeadingLocaleArgument = calleeName == knownNames.format
            && argTypes.first.map { isJavaUtilLocaleType($0, sema: sema, interner: interner) } == true
        let baseLookupReceiverType = safeCall ? sema.types.makeNonNullable(receiverType) : receiverType
        let callableReferenceFunctionType: TypeID? = {
            guard case let .functionType(functionType) = sema.types.kind(of: baseLookupReceiverType),
                  functionType.isCallableReference
            else {
                return nil
            }
            return baseLookupReceiverType
        }()
        let lookupReceiverType: TypeID
        if case let .functionType(functionType) = sema.types.kind(of: baseLookupReceiverType),
           functionType.isCallableReference
        {
            if let result = inferCallableReferenceMember(
                id, receiverID: receiverID, functionType: functionType, calleeName: calleeName,
                args: args, safeCall: safeCall, ctx: ctx, locals: &locals
            ) {
                return result
            }
            // Extensions on `KCallable<R>` / `KFunction<R>` (kotlin.reflect.full:
            // `callSuspend`, ...) must see a callable reference as its reflective type.
            if let kFunctionSymbol = sema.types.kFunctionInterfaceSymbol {
                lookupReceiverType = sema.types.make(.classType(ClassType(
                    classSymbol: kFunctionSymbol,
                    args: [.out(functionType.returnType)],
                    nullability: functionType.nullability
                )))
            } else {
                lookupReceiverType = baseLookupReceiverType
            }
        } else {
            lookupReceiverType = baseLookupReceiverType
        }
        // `f.invoke(...)` where `f`'s own type is a function type
        // (`(Int) -> Int`, `Int.(Int) -> Int`, ...) has no nominal owner at
        // all -- `allNominalSymbolsImpl` (Helpers+TypeArgsAndMemberLookup.swift)
        // has no `.functionType` case, so ordinary member-candidate lookup
        // would always end in "Unresolved member function 'invoke'"
        // (KSWIFTK-SEMA-0024). Intercept here, before any nominal lookup
        // runs, and delegate to the same invocation logic used for a bare
        // call (`f(3)`) or extension-receiver call sugar (`1.ef(2)`). Unlike
        // those two forms, an explicit `.invoke(...)` call has no
        // implicit-receiver shape: a receiver-typed callee must always
        // supply it positionally as argument 0 (`ef.invoke(5, 6)`, never
        // `ef.invoke(6)`).
        // A non-safe `x.invoke` on a nullable function value is left for
        // the existing fallback (KUU-644): `h?.f.invoke(3)` must stay
        // illegal, while `h?.f?.invoke(3)` unwraps first via `safeCall`.
        if calleeName == knownNames.invoke,
           explicitTypeArgs.isEmpty,
           case let .functionType(invokeFunctionType) = sema.types.kind(of: baseLookupReceiverType),
           invokeFunctionType.nullability != .nullable,
           let result = inferCallableValueInvocation(
               id,
               calleeType: baseLookupReceiverType,
               callableTarget: driver.helpers.callableTargetForCalleeExpr(receiverID, sema: sema),
               args: args,
               argTypes: argTypes,
               range: range,
               ctx: ctx,
               locals: &locals,
               expectedType: expectedType,
               arityPolicy: .receiverRequiredExplicit
           )
        {
            let finalType = safeCall ? sema.types.makeNullable(result) : result
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        let isSyntacticRangeCollectionMember = (calleeName == knownNames.plus || calleeName == knownNames.minus)
            && ControlFlowTypeChecker.isRangeExpression(receiverID, ast: ast)
        // Primitive member function: Int/Long/UInt/ULong.inv() → same type (P5-103, TYPE-005)
        if let result = tryInferRegularMemberCallPrimitiveSpecials(
            request,
            receiverType: receiverType,
            lookupReceiverType: lookupReceiverType,
            argTypes: argTypes,
            locals: &locals
        ) {
            return result
        }

        var isSuperCall = false
        var supertypeSymbols: Set<SymbolID> = []
        if !safeCall, case .superRef = ast.arena.expr(receiverID) {
            isSuperCall = true
            if let selectedSupertype = driver.helpers.nominalSymbol(of: lookupReceiverType, types: sema.types) {
                var queue = [selectedSupertype]
                while !queue.isEmpty {
                    let next = queue.removeFirst()
                    if supertypeSymbols.insert(next).inserted {
                        queue.append(contentsOf: sema.symbols.directSupertypes(for: next))
                    }
                }
            }
        }

        let isULongProgressionFirstLastMember = knownNames.progressionFirstLastMemberNames
            .contains(calleeName)
            && args.isEmpty
            && sourceLevelRangeMemberReceiverKind(
                receiverExpr: receiverID,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            ) == .ulongProgression
        let rangeSourceMemberLookupType: TypeID? = if !isSuperCall,
                                                      (isBundledRangeSourceMember(calleeName, interner: interner)
                                                          || isULongProgressionFirstLastMember)
        {
            sourceLevelRangeMemberLookupType(
                receiverExpr: receiverID,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner,
                allowSyntacticRangeExpression: isSyntacticRangeCollectionMember
            )
        } else {
            nil
        }
        // Inferred primitive ranges retain a scalar handle type for lowering.
        // Restore their nominal receiver for ordinary member/extension lookup
        // and overload inference as well as the named bundled range fallbacks.
        // Leave explicitly typed receivers intact, including their nullability.
        let rangeExtensionLookupType: TypeID? = if !isSuperCall,
                                                  case .primitive = sema.types.kind(of: lookupReceiverType)
        {
            sourceLevelRangeMemberLookupType(
                receiverExpr: receiverID,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        } else {
            nil
        }
        let memberLookupType = rangeSourceMemberLookupType ?? rangeExtensionLookupType ?? lookupReceiverType

        // `ClosedRange.isEmpty` is also a valid candidate for a syntactic
        // ULongRange expression. Prefer the exact bundled ULongRange source
        // extension before ordinary member resolution can select that broader
        // interface helper.
        if !isSuperCall,
           calleeName == knownNames.isEmpty,
           args.isEmpty,
           sourceLevelRangeMemberReceiverKind(
               receiverExpr: receiverID,
               receiverType: lookupReceiverType,
               sema: sema,
               interner: interner,
               allowSyntacticRangeExpression: true
           ) == .ulongRange,
           let sourceType = bindSourceRangeHOFCall(
               id,
               memberName: "isEmpty",
               calleeName: calleeName,
               receiverID: receiverID,
               args: args,
               safeCall: safeCall,
               ctx: ctx,
               locals: &locals
           )
        {
            return sourceType
        }

        // Detect class-name receiver: when the receiver is a name reference to
        // a class/interface/enumClass symbol, only companion members should be
        // accessible (not instance methods).  This prevents `Foo.instanceMethod()`
        // from resolving when there is no companion with that name.
        let classNameReceiverNominalSymbol: SymbolID? = {
            // BUG-inner-outer: a qualified `this@Label`/`super@Label` is by
            // definition an instance receiver, never a type/class-name
            // qualifier -- regardless of what symbol kind its
            // `identifierSymbol` carries. An object literal stashes an
            // ancestor `inner class`'s own class symbol there (see
            // `ObjectLiteralInference.swift`'s `objectOuterReceiverTypes`
            // fill) purely as a capture key for `CaptureAnalyzer`/
            // `resolveOuterChainValue`, not as a class-name-receiver marker;
            // without this guard `this@Outer.tag` misclassifies exactly like
            // `Outer.tag` and only resolves companion members.
            let receiverIsQualifiedThisOrSuper: Bool = switch ast.arena.expr(receiverID) {
            case .thisRef, .superRef: true
            default: false
            }
            if !receiverIsQualifiedThisOrSuper,
               let receiverSymbolID = sema.bindings.identifierSymbol(for: receiverID),
               let receiverSymbol = sema.symbols.symbol(receiverSymbolID)
            {
                switch receiverSymbol.kind {
                case .class, .interface, .enumClass, .annotationClass:
                    return receiverSymbolID
                default:
                    // A resolved value must not fall back to a same-named imported classifier.
                    return nil
                }
            }
            if case let .nameRef(receiverName, _) = ast.arena.expr(receiverID) {
                return ctx.cachedScopeLookup(receiverName).first { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else {
                        return false
                    }
                    switch symbol.kind {
                    case .class, .interface, .enumClass, .annotationClass:
                        return true
                    default:
                        return false
                    }
                }
            }
            return nil
        }()
        let isClassNameReceiver = classNameReceiverNominalSymbol != nil

        if let result = tryInferRegularMemberCallClassNameReceiver(
            request,
            isClassNameReceiver: isClassNameReceiver,
            classNameReceiverNominalSymbol: classNameReceiverNominalSymbol,
            argTypes: argTypes
        ) {
            return result
        }

        if let result = tryInferRegularMemberCallPropertyAccess(
            request,
            isClassNameReceiver: isClassNameReceiver,
            isSuperCall: isSuperCall,
            lookupReceiverType: lookupReceiverType,
            memberLookupType: memberLookupType,
            locals: locals
        ) {
            return result
        }

        let collected = collectRegularMemberCallCandidates(
            request,
            argTypes: argTypes,
            isClassNameReceiver: isClassNameReceiver,
            classNameReceiverNominalSymbol: classNameReceiverNominalSymbol,
            isSuperCall: isSuperCall,
            supertypeSymbols: supertypeSymbols,
            lookupReceiverType: lookupReceiverType,
            memberLookupType: memberLookupType,
            rangeSourceMemberLookupType: rangeSourceMemberLookupType,
            isULongProgressionFirstLastMember: isULongProgressionFirstLastMember,
            isLongRangeLiteralContainsCall: isLongRangeLiteralContainsCall,
            callableReferenceFunctionType: callableReferenceFunctionType,
            locals: locals
        )
        if let result = collected.earlyReturnType {
            return result
        }
        var allCandidates = collected.allCandidates
        let companionReceiverType = collected.companionReceiverType

        let isNullLiteralReceiver = if case .nullLiteral = ast.arena.expr(receiverID) {
            true
        } else {
            false
        }

        if let result = tryInferRegularMemberCallSpecialCases(
            request,
            receiverType: receiverType,
            lookupReceiverType: lookupReceiverType,
            memberLookupType: memberLookupType,
            argTypes: argTypes,
            isClassNameReceiver: isClassNameReceiver,
            isSuperCall: isSuperCall,
            allCandidates: &allCandidates,
            locals: &locals
        ) {
            return result
        }

        let filtered = filterRegularMemberCallCandidates(
            request,
            allCandidates: allCandidates,
            argTypes: argTypes,
            receiverType: receiverType,
            lookupReceiverType: lookupReceiverType,
            memberLookupType: memberLookupType,
            isClassNameReceiver: isClassNameReceiver,
            classNameReceiverNominalSymbol: classNameReceiverNominalSymbol,
            isNullLiteralReceiver: isNullLiteralReceiver,
            isFlowReceiver: isFlowReceiver,
            flowElementType: flowElementType,
            hasLeadingLocaleArgument: hasLeadingLocaleArgument,
            isSuperCall: isSuperCall,
            locals: &locals
        )
        if let result = filtered.earlyReturnType {
            return result
        }
        var candidates = filtered.candidates

        let receiverSelection = selectRegularMemberCallReceiverAndFallbacks(
            request,
            candidates: candidates,
            argTypes: argTypes,
            isClassNameReceiver: isClassNameReceiver,
            isSuperCall: isSuperCall,
            companionReceiverType: companionReceiverType,
            rangeSourceMemberLookupType: rangeSourceMemberLookupType,
            rangeExtensionLookupType: rangeExtensionLookupType,
            callableReferenceFunctionType: callableReferenceFunctionType,
            lookupReceiverType: lookupReceiverType,
            memberLookupType: memberLookupType,
            locals: &locals
        )
        if let result = receiverSelection.earlyReturnType {
            return result
        }
        let effectiveReceiverType = receiverSelection.effectiveReceiverType

        let resolution = prepareAndResolveRegularMemberCall(
            request,
            candidates: candidates,
            argTypes: argTypes,
            effectiveReceiverType: effectiveReceiverType,
            isClassNameReceiver: isClassNameReceiver,
            isSuperCall: isSuperCall,
            companionReceiverType: companionReceiverType,
            isLongRangeLiteralContainsCall: isLongRangeLiteralContainsCall,
            isULongRangeLiteralContainsCall: isULongRangeLiteralContainsCall,
            locals: &locals
        )
        if let result = resolution.earlyReturnType {
            return result
        }
        candidates = resolution.candidates
        let preparedArgs = resolution.preparedArgs
        var resolved = resolution.resolved

        if let result = handleRegularMemberResolutionDiagnostic(
            request,
            candidates: candidates,
            preparedArgs: preparedArgs,
            resolved: &resolved,
            argTypes: argTypes,
            receiverType: receiverType,
            lookupReceiverType: lookupReceiverType,
            memberLookupType: memberLookupType,
            effectiveReceiverType: effectiveReceiverType,
            isClassNameReceiver: isClassNameReceiver,
            classNameReceiverNominalSymbol: classNameReceiverNominalSymbol,
            isSuperCall: isSuperCall,
            locals: &locals
        ) {
            return result
        }

        return bindChosenRegularMemberCall(
            request,
            candidates: candidates,
            resolved: resolved,
            argTypes: argTypes,
            receiverType: receiverType,
            lookupReceiverType: lookupReceiverType,
            memberLookupType: memberLookupType,
            isClassNameReceiver: isClassNameReceiver,
            classNameReceiverNominalSymbol: classNameReceiverNominalSymbol,
            isSuperCall: isSuperCall,
            locals: &locals
        )
    }

}
// swiftlint:enable cyclomatic_complexity file_length function_body_length