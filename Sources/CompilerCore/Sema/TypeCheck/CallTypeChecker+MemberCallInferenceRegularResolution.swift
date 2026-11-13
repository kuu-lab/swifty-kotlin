import Foundation

// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// `sourceBackedCollectionMemberNames` and
    /// `sourceBackedTrailingLambdaMemberNames` live on `KnownCompilerNames`
    /// as per-interner `Set<InternedString>` tables.

    func inferRegularMemberCall(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID {
        if request.calleeName == request.knownNames.async,
           isCoroutineScopeType(receiverType, sema: request.sema, interner: request.interner)
        {
            for argument in request.args {
                if case .lambdaLiteral = request.ast.arena.expr(argument.expr) {
                    request.sema.bindings.markCoroutineLauncherLambdaExpr(argument.expr)
                }
            }
        }
        let isFlowReceiver = if request.sema.bindings.isFlowExpr(request.receiverID) {
            true
        } else if case .nameRef = request.ast.arena.expr(request.receiverID),
                  let receiverSymbol = request.sema.bindings.identifierSymbol(for: request.receiverID),
                  request.sema.bindings.isFlowSymbol(receiverSymbol)
        {
            true
        } else {
            false
        }
        let flowElementType: TypeID = if let elementType = request.sema.bindings.flowElementType(forExpr: request.receiverID) {
            elementType
        } else if case .nameRef = request.ast.arena.expr(request.receiverID),
                  let receiverSymbol = request.sema.bindings.identifierSymbol(for: request.receiverID),
                  let elementType = request.sema.bindings.flowElementType(forSymbol: receiverSymbol)
        {
            elementType
        } else {
            request.sema.types.anyType
        }
        let isLongRangeLiteralContainsCall = request.calleeName == request.knownNames.contains
            && request.args.count == 1
            && MemberRuntimeDispatch.rangeReceiverKind(
                receiverExpr: request.receiverID,
                receiverType: receiverType,
                sema: request.sema,
                interner: request.interner
            ) == .longRange
            && driver.callChecker.isContextualizableIntegerLiteral(request.args[0].expr, ast: request.ast)
        let isULongRangeLiteralContainsCall = request.calleeName == request.knownNames.contains
            && request.args.count == 1
            && MemberRuntimeDispatch.rangeReceiverKind(
                receiverExpr: request.receiverID,
                receiverType: receiverType,
                sema: request.sema,
                interner: request.interner
            ) == .ulongRange
            && driver.callChecker.isContextualizableUnsignedIntegerLiteral(request.args[0].expr, ast: request.ast)
        let isLongBitwiseOperator: Bool = switch request.interner.resolve(request.calleeName) {
        case "and", "or", "xor": true
        default: false
        }
        let isLongBitwiseLiteralCall = isLongBitwiseOperator
            && request.args.count == 1
            && request.sema.types.makeNonNullable(receiverType) == request.sema.types.longType
            && driver.callChecker.isContextualizableIntegerLiteral(request.args[0].expr, ast: request.ast)
        contextualizeArrayComparatorArgument(
            calleeName: request.calleeName, receiverID: request.receiverID, receiverType: receiverType,
            args: request.args, ctx: request.ctx, locals: &locals
        )
        // callBy supplies the parameter-map context to nested generic calls.
        // Infer it before context-free argument probing can emit a stale error.
        let callableReceiverType = request.safeCall ? request.sema.types.makeNonNullable(receiverType) : receiverType
        if request.calleeName == request.knownNames.callBy,
           case let .functionType(functionType) = request.sema.types.kind(of: callableReceiverType),
           functionType.isCallableReference,
           let result = inferCallableReferenceMember(
               request.id, functionType: functionType, calleeName: request.calleeName,
               args: request.args, safeCall: request.safeCall, ctx: request.ctx, locals: &locals
           )
        {
            return result
        }
        // Skip lambda literals and callable refs so that their first inference
        // happens inside prepareCallArguments with a contextual expected type,
        // preventing a stale no-expectedType binding from poisoning the cache.
        // Arguments inferred here sit in a call-argument position: a bare
        // `emptyList()` keeps its Nothing-shaped intermediate so the chosen
        // member parameter can pin it afterwards (KUU-4002).
        var memberArgumentCtx = request.ctx
        let argTypes = request.args.map { arg -> TypeID in
            memberArgumentCtx.callArgumentExprBeingInferred = arg.expr
            if let expr = request.ast.arena.expr(arg.expr) {
                switch expr {
                case .lambdaLiteral, .callableRef:
                    return request.sema.bindings.exprType(for: arg.expr) ?? request.sema.types.anyType
                default:
                    break
                }
            }
            if isLongRangeLiteralContainsCall {
                return driver.inferExpr(
                    arg.expr,
                    ctx: memberArgumentCtx,
                    locals: &locals,
                    expectedType: request.sema.types.longType
                )
            }
            if isULongRangeLiteralContainsCall {
                return driver.inferExpr(
                    arg.expr,
                    ctx: memberArgumentCtx,
                    locals: &locals,
                    expectedType: request.sema.types.ulongType
                )
            }
            if isLongBitwiseLiteralCall {
                return driver.inferExpr(
                    arg.expr,
                    ctx: memberArgumentCtx,
                    locals: &locals,
                    expectedType: request.sema.types.longType
                )
            }
            // Speculative declaration checks can leave names bound to
            // placeholder types and nested calls bound to ErrorType before an
            // inferred member is available. Re-read names and retry inferable
            // nested calls whose cached result still contains an error.
            let inferredType: TypeID
            if request.ctx.builderInference != nil || {
                if case .nameRef = request.ast.arena.expr(arg.expr) { return true }
                return false
            }() {
                inferredType = driver.inferExpr(arg.expr, ctx: memberArgumentCtx, locals: &locals)
            } else if let boundType = request.sema.bindings.exprType(for: arg.expr) {
                if typeContainsErrorType(boundType, sema: request.sema),
                   isInferableNestedCallExpr(arg.expr, ast: request.ast)
                {
                    inferredType = driver.inferExpr(arg.expr, ctx: memberArgumentCtx, locals: &locals)
                } else {
                    inferredType = boundType
                }
            } else {
                inferredType = driver.inferExpr(arg.expr, ctx: memberArgumentCtx, locals: &locals)
            }
            if request.calleeName == request.knownNames.coerceIn,
               let rangeType = floatingPointRangeArgumentType(
                   arg.expr,
                   ast: request.ast,
                   sema: request.sema,
                   interner: request.interner
               )
            {
                // Floating-point range expressions use a scalar lowering type for
                // the existing range runtime path, but source-backed coerceIn
                // resolves against ClosedFloatingPointRange<T>.
                return rangeType
            }
            return inferredType
        }

        let hasLeadingLocaleArgument = request.calleeName == request.knownNames.format
            && argTypes.first.map { isJavaUtilLocaleType($0, sema: request.sema, interner: request.interner) } == true
        let baseLookupReceiverType = request.safeCall ? request.sema.types.makeNonNullable(receiverType) : receiverType
        let callableReferenceFunctionType: TypeID? = {
            guard case let .functionType(functionType) = request.sema.types.kind(of: baseLookupReceiverType),
                  functionType.isCallableReference
            else {
                return nil
            }
            return baseLookupReceiverType
        }()
        let lookupReceiverType: TypeID
        if case let .functionType(functionType) = request.sema.types.kind(of: baseLookupReceiverType),
           functionType.isCallableReference
        {
            if let result = inferCallableReferenceMember(
                request.id, functionType: functionType, calleeName: request.calleeName,
                args: request.args, safeCall: request.safeCall, ctx: request.ctx, locals: &locals
            ) {
                return result
            }
            // Extensions on `KCallable<R>` / `KFunction<R>` (kotlin.reflect.full:
            // `callSuspend`, ...) must see a callable reference as its reflective type.
            if let kFunctionSymbol = request.sema.types.kFunctionInterfaceSymbol {
                lookupReceiverType = request.sema.types.make(.classType(ClassType(
                    classSymbol: kFunctionSymbol,
                    args: [.out(functionType.returnType)],
                    nullability: functionType.nullability
                )))
            } else {
                lookupReceiverType = baseLookupReceiverType
            }
        } else {
            lookupReceiverType = driver.helpers.actualImplementationType(
                of: baseLookupReceiverType,
                sema: request.sema
            ) ?? baseLookupReceiverType
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
        // A non-safe `x.invoke` on a nullable function value is rejected by
        // the callable-value arm itself (KUU-644, KUU-4138): `h?.f.invoke(3)`
        // stays illegal, while `h?.f?.invoke(3)` unwraps first via `safeCall`.
        // Callable references also retain their structural function type here.
        // The reflective KFunction lookup view above is for metadata/extensions;
        // it must not hide the parameter types needed for explicit invocation.
        // A smart-cast intersection (`f as KFunction<*>`) keeps its unique
        // structural function conjunct invocable the same way (KUU-3652).
        if request.calleeName == request.knownNames.invoke,
           request.explicitTypeArgs.isEmpty,
           request.sema.types.uniqueStructuralFunctionType(for: baseLookupReceiverType) != nil,
           let result = inferCallableValueInvocation(
               request.id,
               calleeType: baseLookupReceiverType,
               callableTarget: driver.helpers.callableTargetForCalleeExpr(request.receiverID, sema: request.sema),
               args: request.args,
               argTypes: argTypes,
               range: request.range,
               ctx: request.ctx,
               locals: &locals,
               expectedType: request.expectedType,
               arityPolicy: .receiverRequiredExplicit,
               safeCall: request.safeCall,
               calleeValueExpr: request.receiverID
           )
        {
            let finalType = request.safeCall ? request.sema.types.makeNullable(result) : result
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }
        let isSyntacticRangeCollectionMember = (request.calleeName == request.knownNames.plus || request.calleeName == request.knownNames.minus)
            && ControlFlowTypeChecker.isRangeExpression(request.receiverID, ast: request.ast)
        // Numeric mod is an extension, so an applicable user extension in a
        // nearer scope must be resolved before the primitive fallback.
        let hasUserNumericMod = {
            guard request.calleeName == request.knownNames.mod, request.args.count == 1,
                  case .primitive = request.sema.types.kind(of: request.sema.types.makeNonNullable(lookupReceiverType))
            else { return false }
            let candidates = collectExtensionCallCandidates(
                named: request.calleeName,
                memberLookupType: lookupReceiverType,
                isSuperCall: false,
                supertypeSymbols: [],
                ctx: request.ctx,
                locals: locals,
                sema: request.sema,
                interner: request.interner,
                callShapeMatches: {
                    self.extensionCandidateMatchesCallShape(
                        $0, request: request, argumentTypes: argTypes, receiverType: lookupReceiverType
                    )
                },
                requiresInfix: request.ast.arena.isInfixCall(request.id)
            )
            return candidates.contains { candidate in
                guard let symbol = request.sema.symbols.symbol(candidate),
                      request.ctx.visibilityChecker.isAccessible(
                          symbol, fromFile: request.ctx.currentFileID, enclosingClass: request.ctx.enclosingClassSymbol
                      ),
                      extensionCandidateMatchesCallShape(
                          candidate, request: request, argumentTypes: argTypes, receiverType: lookupReceiverType
                      )
                else { return false }
                if let file = symbol.declSite?.start.file, let origin = driver.sourceManager?.origin(of: file) {
                    return origin == .user
                }
                return symbol.fqName.first != request.interner.intern("kotlin")
            }
        }()
        if hasUserNumericMod,
           let result = tryBindShadowedExtensionCallFallback(
               request,
               receiverType: receiverType,
               lookupReceiverType: lookupReceiverType,
               memberLookupType: lookupReceiverType,
               argTypes: argTypes,
               isClassNameReceiver: false,
               isSuperCall: false,
               locals: &locals
           )
        {
            return result
        }
        if !hasUserNumericMod, let result = tryInferRegularMemberCallPrimitiveSpecials(
            request,
            receiverType: receiverType,
            lookupReceiverType: lookupReceiverType,
            argTypes: argTypes,
            locals: &locals) {
            return result
        }

        var isSuperCall = false
        var supertypeSymbols: Set<SymbolID> = []
        if !request.safeCall, case .superRef = request.ast.arena.expr(request.receiverID) {
            isSuperCall = true
            if let selectedSupertype = driver.helpers.nominalSymbol(of: lookupReceiverType, types: request.sema.types) {
                var queue = [selectedSupertype]
                while !queue.isEmpty {
                    let next = queue.removeFirst()
                    if supertypeSymbols.insert(next).inserted {
                        queue.append(contentsOf: request.sema.symbols.directSupertypes(for: next))
                    }
                }
            }
        }

        let isULongProgressionFirstLastMember = request.knownNames.progressionFirstLastMemberNames
            .contains(request.calleeName)
            && request.args.isEmpty
            && sourceLevelRangeMemberReceiverKind(
                receiverExpr: request.receiverID,
                receiverType: lookupReceiverType,
                sema: request.sema,
                interner: request.interner
            ) == .ulongProgression
        let rangeSourceMemberLookupType: TypeID? = if !isSuperCall,
                                                      (isBundledRangeSourceMember(request.calleeName, interner: request.interner)
                                                          || isULongProgressionFirstLastMember)
        {
            sourceLevelRangeMemberLookupType(
                receiverExpr: request.receiverID,
                receiverType: lookupReceiverType,
                sema: request.sema,
                interner: request.interner,
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
                                                  case .primitive = request.sema.types.kind(of: lookupReceiverType)
        {
            floatingPointRangeArgumentType(
                request.receiverID,
                ast: request.ast,
                sema: request.sema,
                interner: request.interner
            ) ?? sourceLevelRangeMemberLookupType(
                receiverExpr: request.receiverID,
                receiverType: lookupReceiverType,
                sema: request.sema,
                interner: request.interner
            )
        } else {
            nil
        }
        // Final numeric bounds expose the same builtin compareTo overloads as
        // their primitive. Keep nonnumeric extension calls on the original T.
        let primitiveComparisonReceiver: TypeID? = {
            guard request.calleeName == request.knownNames.compareTo, argTypes.count == 1,
                  let receiver = resolvePrimitiveArithmeticUpperBound(
                      of: lookupReceiverType, types: request.sema.types, symbols: request.sema.symbols
                  ),
                  let argument = resolvePrimitiveArithmeticUpperBound(
                      of: argTypes[0], types: request.sema.types, symbols: request.sema.symbols
                  )
            else { return nil }
            let bothArithmetic = receiver != request.sema.types.charType && argument != request.sema.types.charType
                && request.sema.types.isBuiltinArithmeticOperand(receiver)
                && request.sema.types.isBuiltinArithmeticOperand(argument)
                && request.sema.types.isUnsigned(receiver) == request.sema.types.isUnsigned(argument)
            return bothArithmetic ? receiver : nil
        }()
        let channelBoundReceiverType = request.calleeName == request.knownNames.receive
            ? ReceiverClassifier(sema: request.sema, interner: request.interner).channelUpperBoundType(of: lookupReceiverType)
            : nil
        let memberLookupType = rangeSourceMemberLookupType
            ?? rangeExtensionLookupType
            ?? primitiveComparisonReceiver
            ?? channelBoundReceiverType
            ?? lookupReceiverType

        // A precompiled `UIntRange.contains(UInt)` can otherwise lose to the
        // inherited `ClosedRange<T>.contains(T)` member before the ordinary
        // range source fallback runs. Bind the exact bundled overload first,
        // while leaving a same-scope user extension to normal overload rules.
        let hasScopedExactUIntRangeContains = {
            guard !isSuperCall,
                  request.calleeName == request.knownNames.contains,
                  request.args.count == 1,
                  argTypes == [request.sema.types.uintType],
                  MemberRuntimeDispatch.rangeReceiverKind(
                      receiverExpr: request.receiverID,
                      receiverType: lookupReceiverType,
                      sema: request.sema,
                      interner: request.interner
                  ) == .uintRange,
                  let actualReceiver = driver.helpers.nominalSymbol(of: memberLookupType, types: request.sema.types),
                  let actualOwner = request.sema.symbols.symbol(actualReceiver)?.fqName
            else {
                return false
            }
            return collectScopedRangeUserExtensionCandidates(
                named: request.calleeName,
                receiverType: memberLookupType,
                ctx: request.ctx,
                sema: request.sema,
                interner: request.interner
            ).contains { candidate in
                guard let parentID = request.sema.symbols.parentSymbol(for: candidate),
                      let parent = request.sema.symbols.symbol(parentID),
                      !parent.fqName.starts(with: request.knownNames.kotlinRangesPackage),
                      let signature = request.sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes == [request.sema.types.uintType],
                      let declaredReceiver = signature.receiverType,
                      let declaredSymbol = driver.helpers.nominalSymbol(of: declaredReceiver, types: request.sema.types),
                      let declaredOwner = request.sema.symbols.symbol(declaredSymbol)?.fqName
                else {
                    return false
                }
                return declaredOwner == actualOwner
            }
        }()

        if !hasScopedExactUIntRangeContains,
           !isSuperCall,
           request.calleeName == request.knownNames.contains,
           request.args.count == 1,
           argTypes == [request.sema.types.uintType],
           MemberRuntimeDispatch.rangeReceiverKind(
               receiverExpr: request.receiverID,
               receiverType: lookupReceiverType,
               sema: request.sema,
               interner: request.interner
           ) == .uintRange,
           let sourceType = bindSourceRangeHOFCall(
               request.id,
               calleeName: request.calleeName,
               receiverID: request.receiverID,
               args: request.args,
               safeCall: request.safeCall,
               ctx: request.ctx,
               locals: &locals
           )
        {
            return sourceType
        }

        // `ClosedRange.isEmpty` is also a valid candidate for a syntactic
        // ULongRange expression. Prefer the exact bundled ULongRange source
        // extension before ordinary member resolution can select that broader
        // interface helper.
        if !isSuperCall,
           request.calleeName == request.knownNames.isEmpty,
           request.args.isEmpty,
           sourceLevelRangeMemberReceiverKind(
               receiverExpr: request.receiverID,
               receiverType: lookupReceiverType,
               sema: request.sema,
               interner: request.interner,
               allowSyntacticRangeExpression: true
           ) == .ulongRange,
           let sourceType = bindSourceRangeHOFCall(
               request.id,
               calleeName: request.calleeName,
               receiverID: request.receiverID,
               args: request.args,
               safeCall: request.safeCall,
               ctx: request.ctx,
               locals: &locals
           )
        {
            return sourceType
        }

        // When the receiver is a name reference to a class/interface/enumClass
        // symbol, only companion members should be accessible (not instance
        // methods).  This prevents `Foo.instanceMethod()` from resolving when
        // there is no companion with that name.
        let classNameReceiverNominalSymbol: SymbolID? = {
            func nominalSymbol(for symbolID: SymbolID) -> SymbolID? {
                guard let symbol = request.sema.symbols.symbol(symbolID) else { return nil }
                switch symbol.kind {
                case .class, .interface, .enumClass, .annotationClass:
                    return symbolID
                case .typeAlias:
                    let aliasParams = request.sema.symbols.typeAliasTypeParameters(for: symbolID)
                    let expanded = driver.helpers.expandTypeAlias(
                        symbolID,
                        typeArgs: [],
                        sema: request.sema,
                        visited: [],
                        depth: 0
                    )
                    guard aliasParams.isEmpty,
                          let expanded
                    else {
                        return nil
                    }
                    let targetID: SymbolID
                    switch request.sema.types.kind(of: expanded) {
                    case let .classType(aliasTarget):
                        targetID = request.sema.symbols.actualSymbol(for: aliasTarget.classSymbol)
                            ?? aliasTarget.classSymbol
                    case .stringStruct:
                        guard let stringClassSymbol = request.sema.types.stringClassSymbol else { return nil }
                        targetID = stringClassSymbol
                    default:
                        return nil
                    }
                    guard let target = request.sema.symbols.symbol(targetID) else { return nil }
                    switch target.kind {
                    case .class, .interface, .enumClass, .annotationClass:
                        return targetID
                    default:
                        return nil
                    }
                default:
                    return nil
                }
            }

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
            let receiverIsQualifiedThisOrSuper: Bool = switch request.ast.arena.expr(request.receiverID) {
            case .thisRef, .superRef: true
            default: false
            }
            if !receiverIsQualifiedThisOrSuper,
               let receiverSymbolID = request.sema.bindings.identifierSymbol(for: request.receiverID)
            {
                // A resolved value must not fall back to a same-named imported classifier.
                return nominalSymbol(for: receiverSymbolID)
            }
            if case let .nameRef(receiverName, _) = request.ast.arena.expr(request.receiverID) {
                return request.ctx.cachedScopeLookup(receiverName).first { candidate in
                    nominalSymbol(for: candidate) != nil
                }
                .flatMap(nominalSymbol)
            }
            return nil
        }()
        let isClassNameReceiver = classNameReceiverNominalSymbol != nil

        if let result = tryInferRegularMemberCallClassNameReceiver(
            request,
            isClassNameReceiver: isClassNameReceiver,
            classNameReceiverNominalSymbol: classNameReceiverNominalSymbol,
            argTypes: argTypes,
            locals: &locals
        ) {
            return result
        }

        if let result = tryInferRegularMemberCallPropertyAccess(
            request,
            isClassNameReceiver: isClassNameReceiver,
            isSuperCall: isSuperCall,
            lookupReceiverType: lookupReceiverType,
            memberLookupType: memberLookupType,
            callableReferenceFunctionType: callableReferenceFunctionType,
            locals: locals
        ) {
            return result
        }

        var typeAliasConstructor: TypeAliasConstructorContext?
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
            locals: locals,
            typeAliasConstructor: &typeAliasConstructor
        )
        if let result = collected.earlyReturnType {
            return result
        }
        var allCandidates = collected.allCandidates
        // With no eligible callable, type-check the ordinary primitive shape
        // solely to preserve SEMA-0307 at the entry point (e.g. `2 plus 3`).
        // Any infix extension, even an inapplicable one, prevents this fallback.
        if request.ast.arena.isInfixCall(request.id), allCandidates.isEmpty,
           let result = tryInferRegularMemberCallPrimitiveSpecials(
               request, receiverType: receiverType, lookupReceiverType: lookupReceiverType,
               argTypes: argTypes, locals: &locals, enforceInfixEligibility: false
           )
        {
            return result
        }
        let companionReceiverType = collected.companionReceiverType

        let isNullLiteralReceiver = if case .nullLiteral = request.ast.arena.expr(request.receiverID) {
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

        driver.inferDelegatedForwardingMethodReturnTypesIfNeeded(for: candidates)

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
        let effectiveReceiverType = primitiveComparisonReceiver ?? receiverSelection.effectiveReceiverType

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
            typeAliasConstructor: typeAliasConstructor,
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
            typeAliasConstructor: typeAliasConstructor,
            locals: &locals
        )
    }

}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
