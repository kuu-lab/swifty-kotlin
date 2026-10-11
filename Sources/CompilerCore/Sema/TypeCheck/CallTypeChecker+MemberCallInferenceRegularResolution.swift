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

        if isClassNameReceiver,
           args.isEmpty,
           let ownerSymbol = classNameReceiverNominalSymbol,
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: ownerSymbol,
               memberName: calleeName,
               sema: sema
           )
        {
            if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
               !ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(for: memberSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
            sema.bindings.bindExprType(id, type: staticMember.type)
            return staticMember.type
        }

        if isClassNameReceiver,
           let ownerSymbol = classNameReceiverNominalSymbol,
           let owner = sema.symbols.symbol(ownerSymbol)
        {
            let staticMethodFQName = owner.fqName + [calleeName]
            var staticMethodCandidates = sema.symbols.lookupAll(fqName: staticMethodFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.parentSymbol(for: candidate) == ownerSymbol,
                      let signature = sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.receiverType == nil
            }
            if staticMethodCandidates.isEmpty {
                staticMethodCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.parentSymbol(for: candidate) == ownerSymbol,
                          let signature = sema.symbols.functionSignature(for: candidate)
                    else {
                        return false
                    }
                    return signature.receiverType == nil
                }
            }
            if !staticMethodCandidates.isEmpty {
                let (visibleStaticMethods, invisibleStaticMethods) = ctx.filterByVisibility(staticMethodCandidates)
                if let firstInvisible = invisibleStaticMethods.first {
                    driver.helpers.emitVisibilityError(
                        for: firstInvisible,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if !visibleStaticMethods.isEmpty {
                    let callArgs = zip(args, argTypes).map { arg, type in
                        CallArg(label: arg.label, isSpread: arg.isSpread, type: type)
                    }
                    let call = CallExpr(
                        range: range,
                        calleeName: calleeName,
                        args: callArgs,
                        explicitTypeArgs: explicitTypeArgs
                    )
                    let resolved = ctx.resolver.resolveCall(
                        candidates: visibleStaticMethods,
                        call: call,
                        expectedType: expectedType,
                        ctx: sema
                    )
                    if let diagnostic = resolved.diagnostic {
                        ctx.semaCtx.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    if let chosen = resolved.chosenCallee,
                       let signature = sema.symbols.functionSignature(for: chosen)
                    {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: resolved.substitutedTypeArguments
                                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                    .map(\.value),
                                parameterMapping: resolved.parameterMapping
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                        sema.bindings.bindIdentifier(id, symbol: chosen)
                        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                        let resultType = sema.types.substituteTypeParameters(
                            in: signature.returnType,
                            substitution: resolved.substitutedTypeArguments,
                            typeVarBySymbol: typeVarBySymbol
                        )
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }

            if owner.kind == .enumClass {
                // A class-name receiver can also select a source-backed extension
                // declared on the nominal type itself. This is distinct from the
                // companion-extension path below: enum APIs such as
                // `RequiresOptIn.Level.entries` are represented as extensions on
                // `Level`, while `valueOf`/`entries` generated by enum synthesis
                // remain companion members. Imported stdlib artifacts expose the
                // source-backed form as synthetic symbols, so recover it by short
                // name when it is not present in the file scope.
                let ownerType = sema.types.make(.classType(ClassType(
                    classSymbol: ownerSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                if args.isEmpty,
                   sema.bundledIndex.contains(
                       ownerFQName: owner.fqName,
                       name: calleeName,
                       arity: 0
                   ),
                   let extensionPropertyType = resolveExtensionPropertyGetter(
                       id: id,
                       calleeName: calleeName,
                       range: range,
                       receiverType: ownerType,
                       expectedType: expectedType,
                       ctx: ctx
                   )
                {
                    sema.bindings.bindExprType(receiverID, type: ownerType)
                    sema.bindings.bindExprType(id, type: extensionPropertyType)
                    return extensionPropertyType
                }

                var ownerExtensionCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let receiver = signature.receiverType
                    else {
                        return false
                    }
                    guard sema.bundledIndex.contains(
                        ownerFQName: owner.fqName,
                        name: calleeName,
                        arity: signature.parameterTypes.count
                    ) else {
                        return false
                    }
                    return extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: ownerType,
                        declaredReceiver: receiver,
                        sema: sema
                    )
                }
                if ownerExtensionCandidates.isEmpty {
                    ownerExtensionCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              symbol.flags.contains(.synthetic),
                              let signature = sema.symbols.functionSignature(for: candidate),
                              let receiver = signature.receiverType
                        else {
                            return false
                        }
                        guard sema.bundledIndex.contains(
                            ownerFQName: owner.fqName,
                            name: calleeName,
                            arity: signature.parameterTypes.count
                        ) else {
                            return false
                        }
                        return extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: ownerType,
                            declaredReceiver: receiver,
                            sema: sema
                        )
                    }
                }
                let (visibleOwnerExtensions, invisibleOwnerExtensions) = ctx.filterByVisibility(ownerExtensionCandidates)
                if let firstInvisible = invisibleOwnerExtensions.first {
                    driver.helpers.emitVisibilityError(
                        for: firstInvisible,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if !visibleOwnerExtensions.isEmpty {
                    let callArgs = zip(args, argTypes).map { arg, type in
                        CallArg(label: arg.label, isSpread: arg.isSpread, type: type)
                    }
                    let call = CallExpr(
                        range: range,
                        calleeName: calleeName,
                        args: callArgs,
                        explicitTypeArgs: explicitTypeArgs
                    )
                    let resolved = ctx.resolver.resolveCall(
                        candidates: visibleOwnerExtensions,
                        call: call,
                        expectedType: expectedType,
                        implicitReceiverType: ownerType,
                        ctx: sema
                    )
                    if let diagnostic = resolved.diagnostic {
                        ctx.semaCtx.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    if let chosen = resolved.chosenCallee,
                       let signature = sema.symbols.functionSignature(for: chosen)
                    {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: resolved.substitutedTypeArguments
                                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                    .map(\.value),
                                parameterMapping: resolved.parameterMapping
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                        sema.bindings.bindIdentifier(id, symbol: chosen)
                        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                        let resultType = sema.types.substituteTypeParameters(
                            in: signature.returnType,
                            substitution: resolved.substitutedTypeArguments,
                            typeVarBySymbol: typeVarBySymbol
                        )
                        driver.helpers.checkDeprecation(
                            for: chosen,
                            sema: sema,
                            interner: interner,
                            range: range,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                        driver.helpers.checkOptIn(
                            for: chosen,
                            ctx: ctx,
                            range: range,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                        sema.bindings.bindExprType(receiverID, type: ownerType)
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }

            let nestedOwnerFQName = owner.fqName + [calleeName]
            var nestedOwnerSymbols = sema.symbols.lookupAll(fqName: nestedOwnerFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate) else {
                    return false
                }
                guard sema.symbols.parentSymbol(for: candidate) == ownerSymbol else {
                    return false
                }
                switch symbol.kind {
                case .class, .interface, .enumClass, .object, .annotationClass:
                    return true
                default:
                    return false
                }
            }
            if nestedOwnerSymbols.isEmpty {
                let shortNameNestedOwners = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else {
                        return false
                    }
                    guard sema.symbols.parentSymbol(for: candidate) == ownerSymbol else {
                        return false
                    }
                    switch symbol.kind {
                    case .class, .interface, .enumClass, .object, .annotationClass:
                        return true
                    default:
                        return false
                    }
                }
                if shortNameNestedOwners.count == 1 {
                    nestedOwnerSymbols = shortNameNestedOwners
                }
            }
            // `Owner.Nested` and `Owner.Nested()` share the same zero-arg
            // `.memberCall` shape, but the AST arena records whether parentheses
            // were written. This is mostly unambiguous when
            // no valid constructor-call reading could exist in the first
            // place: enum class constructors are always implicitly private
            // (never callable from outside the enum body) and `object`
            // declarations have no constructor at all, so a nested enum/object
            // reference must be the bare type/nested-owner (needed e.g. for
            // `Owner.Nested.ENTRY`, where `Nested` is the receiver of a
            // further static member access). Parenthesis-less nested classes,
            // interfaces and annotation classes are likewise classifiers,
            // including on the left of `::class`; only explicit calls construct instances.
            if args.isEmpty, let nestedOwner = nestedOwnerSymbols.first,
               let nestedOwnerKind = sema.symbols.symbol(nestedOwner)?.kind,
               nestedOwnerKind == .enumClass || nestedOwnerKind == .object
                   || ((nestedOwnerKind == .class || nestedOwnerKind == .interface || nestedOwnerKind == .annotationClass)
                       && !ast.arena.isExplicitCall(id))
            {
                if let nestedSymbol = sema.symbols.symbol(nestedOwner),
                   !ctx.visibilityChecker.isAccessible(
                       nestedSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: nestedSymbol, name: interner.resolve(calleeName),
                        range: range, diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let nestedType = sema.types.make(.classType(ClassType(
                    classSymbol: nestedOwner,
                    args: [],
                    nullability: .nonNull
                )))
                sema.bindings.bindIdentifier(id, symbol: nestedOwner)
                sema.bindings.bindExprType(id, type: nestedType)
                return nestedType
            }
            let nestedCtorFQName = owner.fqName + [calleeName, knownNames.initName]
            var nestedCtorCandidates = sema.symbols.lookupAll(fqName: nestedCtorFQName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate) else {
                    return false
                }
                return symbol.kind == .constructor
            }
            if nestedCtorCandidates.isEmpty {
                if !nestedOwnerSymbols.isEmpty {
                    let initName = knownNames.initName
                    nestedCtorCandidates = sema.symbols.lookupByShortName(initName).filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .constructor
                        else {
                            return false
                        }
                        guard let parent = sema.symbols.parentSymbol(for: candidate) else {
                            return false
                        }
                        return nestedOwnerSymbols.contains(parent)
                    }
                }
            }
            if !nestedCtorCandidates.isEmpty {
                let (visibleNested, invisibleNested) = ctx.filterByVisibility(nestedCtorCandidates)
                if let firstInvisible = invisibleNested.first {
                    driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if !visibleNested.isEmpty {
                    if args.isEmpty {
                        let zeroArgNested = visibleNested.first { candidate in
                            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                                return false
                            }
                            return signature.parameterTypes.isEmpty && signature.typeParameterSymbols.isEmpty
                        }
                        if let zeroArgNested,
                           let signature = sema.symbols.functionSignature(for: zeroArgNested)
                        {
                            sema.bindings.bindCall(
                                id,
                                binding: CallBinding(
                                    chosenCallee: zeroArgNested,
                                    substitutedTypeArguments: [],
                                    parameterMapping: [:]
                                )
                            )
                            let resultType = signature.returnType
                            if ast.arena.isExplicitCall(id),
                               let nestedOwner = sema.symbols.parentSymbol(for: zeroArgNested),
                               let nestedOwnerSymbol = sema.symbols.symbol(nestedOwner),
                               nestedOwnerSymbol.kind == .class,
                               !nestedOwnerSymbol.flags.contains(.innerClass)
                            {
                                sema.bindings.markTypeQualifiedConstructorCallExpr(id)
                            }
                            sema.bindings.bindExprType(id, type: resultType)
                            return resultType
                        }
                    }
                    let callArgs = zip(args, argTypes).map { arg, type in
                        CallArg(label: arg.label, isSpread: arg.isSpread, type: type)
                    }
                    let call = CallExpr(range: range, calleeName: calleeName, args: callArgs, explicitTypeArgs: explicitTypeArgs)
                    let resolved = ctx.resolver.resolveCall(
                        candidates: visibleNested,
                        call: call,
                        expectedType: expectedType,
                        ctx: sema
                    )
                    if let diagnostic = resolved.diagnostic {
                        ctx.semaCtx.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    if let chosen = resolved.chosenCallee,
                       let signature = sema.symbols.functionSignature(for: chosen)
                    {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: resolved.substitutedTypeArguments
                                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                    .map(\.value),
                                parameterMapping: resolved.parameterMapping
                            )
                        )
                        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                        let resultType = sema.types.substituteTypeParameters(
                            in: signature.returnType,
                            substitution: resolved.substitutedTypeArguments,
                            typeVarBySymbol: typeVarBySymbol
                        )
                        if ast.arena.isExplicitCall(id),
                           let nestedOwner = sema.symbols.parentSymbol(for: chosen),
                           let nestedOwnerSymbol = sema.symbols.symbol(nestedOwner),
                           nestedOwnerSymbol.kind == .class,
                           !nestedOwnerSymbol.flags.contains(.innerClass)
                        {
                            sema.bindings.markTypeQualifiedConstructorCallExpr(id)
                        }
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }
        }

        if !isClassNameReceiver,
           args.isEmpty,
           !ast.arena.isExplicitCall(id),
           driver.helpers.lookupMemberProperty(
               named: calleeName, receiverType: memberLookupType, sema: sema
           ) == nil,
           let sourceFile = ctx.currentASTFile,
           let preferredSourcePackage = preferredBundledStdlibPackage(
               sourceFile: sourceFile,
               candidates: sema.symbols.lookupByShortName(calleeName),
               receiverType: memberLookupType,
               sema: sema
           ),
           let extensionPropertyType = resolveExtensionPropertyGetter(
               id: id,
               calleeName: calleeName,
               range: range,
               receiverType: memberLookupType,
               expectedType: expectedType,
               ctx: ctx,
               preferredSourcePackage: preferredSourcePackage
           )
        {
            let finalType = safeCall ? sema.types.makeNullable(extensionPropertyType) : extensionPropertyType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        if !isClassNameReceiver,
           args.isEmpty,
           !ast.arena.isExplicitCall(id),
           let propResult = driver.helpers.lookupMemberProperty(
               named: calleeName,
               // Property reads are resolved from the receiver's static type.
               // In particular, `super.p` must select the direct superclass
               // declaration instead of the most-derived override.
               receiverType: isSuperCall ? lookupReceiverType : memberLookupType,
               sema: sema
           )
        {
            if let propSymbol = sema.symbols.symbol(propResult.symbol),
               !ctx.visibilityChecker.isAccessible(
                   propSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(
                    for: propSymbol,
                    name: interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: propResult.symbol)
            sema.bindings.bindExprType(id, type: propResult.type)
            let narrowedType: TypeID? = if let reference = ctx.dataFlow.resolveStableReference(
                id, locals: locals, ast: ast, sema: sema, interner: interner
            ), reference.isStable {
                ctx.dataFlow.resolvedTypeFromFlowState(
                    ctx.flowState.includingMembers(from: locals), reference: reference.symbol
                )
            } else {
                nil
            }
            let propertyType = narrowedType ?? propResult.type
            let finalType = safeCall ? sema.types.makeNullable(propertyType) : propertyType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        if !isClassNameReceiver,
           args.isEmpty,
           !ast.arena.isExplicitCall(id),
           let extensionPropertyType = resolveExtensionPropertyGetter(
               id: id,
               calleeName: calleeName,
               range: range,
               receiverType: memberLookupType,
               expectedType: expectedType,
               ctx: ctx
           )
        {
            let finalType = safeCall ? sema.types.makeNullable(extensionPropertyType) : extensionPropertyType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // Track the companion type so we can pass it (not the owner class type)
        // as the implicit receiver when resolving the call.
        var companionReceiverType: TypeID?

        var allCandidates: [SymbolID]
        if isClassNameReceiver {
            // Class-name receiver: only companion members are valid targets.
            // Search from the companion, rather than the owner class, so its
            // inherited members are included without exposing owner instances.
            if let ownerNominal = classNameReceiverNominalSymbol,
               let companionSymbol = sema.symbols.companionObjectSymbol(for: ownerNominal)
            {
                let companionTypeForExtensionLookup = sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))

                // Try companion property access when no arguments are provided
                // (e.g. Foo.MAX_COUNT).  When args are present this is a function
                // call, so skip the property short-circuit to avoid shadowing a
                // companion function of the same name.
                if args.isEmpty {
                    if let propResult = driver.helpers.lookupMemberProperty(
                        named: calleeName,
                        receiverType: companionTypeForExtensionLookup,
                        sema: sema
                    )
                    {
                        let propSymbol = propResult.symbol
                        let propType = propResult.type
                        // Check visibility before returning the property.
                        if let propSym = sema.symbols.symbol(propSymbol),
                           !ctx.visibilityChecker.isAccessible(
                               propSym,
                               fromFile: ctx.currentFileID,
                               enclosingClass: ctx.enclosingClassSymbol
                           )
                        {
                            driver.helpers.emitVisibilityError(for: propSym, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
                            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                        }
                        driver.helpers.checkDeprecation(
                            for: propSymbol,
                            sema: sema,
                            interner: interner,
                            range: range,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                        driver.helpers.checkOptIn(
                            for: propSymbol,
                            ctx: ctx,
                            range: range,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                        // Re-bind receiver to companion type for correct KIR lowering
                        sema.bindings.bindExprType(receiverID, type: companionTypeForExtensionLookup)
                        sema.bindings.bindIdentifier(id, symbol: propSymbol)
                        sema.bindings.bindExprType(id, type: propType)
                        return propType
                    }

                    // Fall back to a Companion-scoped extension property
                    // (e.g. `val Duration.Companion.ZERO: Duration`) written as
                    // Kotlin source at package scope with the Companion as receiver.
                    let compTypeForExt = sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
                    if let extensionPropertyType = resolveExtensionPropertyGetter(
                        id: id,
                        calleeName: calleeName,
                        range: range,
                        receiverType: compTypeForExt,
                        expectedType: expectedType,
                        ctx: ctx
                    ) {
                        sema.bindings.bindExprType(receiverID, type: compTypeForExt)
                        sema.bindings.bindExprType(id, type: extensionPropertyType)
                        return extensionPropertyType
                    }
                }

                // Then try companion function candidates
                var companionCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: companionTypeForExtensionLookup,
                    sema: sema,
                    interner: interner
                )
                // Precompiled library extensions are not inserted into
                // file scopes, because their receiver is resolved during
                // member-call inference. Recover those synthetic
                // declarations by short name for class-name receivers.
                let syntheticCompanionCandidates = {
                    sema.symbols.lookupByShortName(calleeName).filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              symbol.flags.contains(.synthetic),
                              let signature = sema.symbols.functionSignature(for: candidate),
                              let recv = signature.receiverType
                        else {
                            return false
                        }
                        return self.extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: companionTypeForExtensionLookup,
                            declaredReceiver: recv,
                            sema: sema
                        )
                    }
                }
                if companionCandidates.isEmpty {
                    // Fall back to Companion-scoped extension functions
                    // (e.g. `fun Duration.Companion.parse(value: String): Duration`)
                    // written as Kotlin source at package scope. These are resolved
                    // via scope lookup (like ordinary extension functions), not the
                    // companion member lookup above.
                    companionCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                        guard let symbol = ctx.cachedSymbol(candidate),
                              symbol.kind == .function,
                              let signature = sema.symbols.functionSignature(for: candidate),
                              let recv = signature.receiverType
                        else { return false }
                        return extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: companionTypeForExtensionLookup,
                            declaredReceiver: recv,
                            sema: sema
                        )
                    }
                    if !companionCandidates.isEmpty {
                        // A scoped supertype-receiver extension (e.g.
                        // `fun Base64.encode` resolved through companion
                        // `Default`) satisfies this lookup, but the companion's
                        // synthetic members (inherited `Base64.encode(ByteArray)`)
                        // are still valid targets: keep them in the same set so
                        // member calls are not shadowed by the extension.
                        for candidate in syntheticCompanionCandidates() where !companionCandidates.contains(candidate) {
                            companionCandidates.append(candidate)
                        }
                    }
                }
                if companionCandidates.isEmpty {
                    companionCandidates = syntheticCompanionCandidates()
                }
                if !companionCandidates.isEmpty {
                    companionReceiverType = companionTypeForExtensionLookup
                    // Re-bind receiver expression to companion type so KIR
                    // lowering passes the companion singleton (not the owner
                    // class) as the first argument to the companion function.
                    sema.bindings.bindExprType(receiverID, type: companionReceiverType!)
                }
                allCandidates = companionCandidates
            } else {
                allCandidates = []
            }
        } else {
            // Normal instance receiver: use standard member lookup with
            // companion fallback via collectMemberFunctionCandidates.
            let allowedOwnerSymbols = isSuperCall && !supertypeSymbols.isEmpty ?
                supertypeSymbols : nil
            let hasScopedExactRangeExtension = rangeSourceMemberLookupType.map { sourceReceiverType in
                guard isULongProgressionFirstLastMember,
                      let sourceReceiverSymbol = driver.helpers.nominalSymbol(
                    of: sema.types.makeNonNullable(sourceReceiverType),
                    types: sema.types
                ) else {
                    return false
                }
                return ctx.cachedScopeLookup(calleeName).contains { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes.count == args.count,
                          let declaredReceiver = signature.receiverType,
                          let declaredReceiverSymbol = driver.helpers.nominalSymbol(
                              of: sema.types.makeNonNullable(declaredReceiver),
                              types: sema.types
                          )
                    else {
                        return false
                    }
                    return declaredReceiverSymbol == sourceReceiverSymbol
                }
            } ?? false
            let rangeSourceCandidates = hasScopedExactRangeExtension
                ? []
                : rangeSourceMemberLookupType.map {
                    collectRangeSourceExtensionCandidates(
                        named: calleeName,
                        receiverType: $0,
                        sema: sema,
                        interner: interner
                    )
                } ?? []
            // Source-backed range overloads are recovered from the bundled
            // declaration index because their extensions are not generally
            // visible through member lookup. A same-named extension in the
            // active Kotlin scope still has normal overload priority, though;
            // keep it ahead of the bundled candidates so a user declaration
            // is not silently replaced by the stdlib fallback.
            let rangeReceiverKind = MemberRuntimeDispatch.rangeReceiverKind(
                receiverExpr: receiverID,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
            let scopedRangeUserCandidates: [SymbolID] = if calleeName == knownNames.contains,
                                                               let rangeSourceMemberLookupType,
                                                               rangeReceiverKind == .intRange
            {
                collectScopedRangeUserExtensionCandidates(
                    named: calleeName,
                    receiverType: rangeSourceMemberLookupType,
                    ctx: ctx,
                    sema: sema,
                    interner: interner
                ).filter { candidate in
                    guard isIntRangeCrossTypeContainsCandidate(candidate, sema: sema),
                          args.count == 1,
                          argTypes.count == 1,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes[0] == argTypes[0]
                    else {
                        return false
                    }
                    guard let label = args[0].label else { return true }
                    guard signature.valueParameterSymbols.count == 1,
                          let parameter = sema.symbols.symbol(signature.valueParameterSymbols[0])
                    else {
                        return false
                    }
                    return parameter.name == label
                }
            } else if calleeName == knownNames.contains,
                      let rangeSourceMemberLookupType,
                      rangeReceiverKind == .uintRange
            {
                collectScopedRangeUserExtensionCandidates(
                    named: calleeName,
                    receiverType: rangeSourceMemberLookupType,
                    ctx: ctx,
                    sema: sema,
                    interner: interner
                ).filter { candidate in
                    guard isUIntRangeCrossTypeContainsCandidate(candidate, sema: sema),
                          args.count == 1,
                          argTypes.count == 1,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes[0] == argTypes[0]
                    else {
                        return false
                    }
                    guard let label = args[0].label else { return true }
                    guard signature.valueParameterSymbols.count == 1,
                          let parameter = sema.symbols.symbol(signature.valueParameterSymbols[0])
                    else {
                        return false
                    }
                    return parameter.name == label
                }
            } else if calleeName == knownNames.contains,
                      let rangeSourceMemberLookupType,
                      rangeReceiverKind == .longRange,
                      !isLongRangeLiteralContainsCall
            {
                collectScopedRangeUserExtensionCandidates(
                    named: calleeName,
                    receiverType: rangeSourceMemberLookupType,
                    ctx: ctx,
                    sema: sema,
                    interner: interner
                ).filter { candidate in
                    guard args.count == 1,
                          argTypes.count == 1,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes.count == 1,
                          signature.parameterTypes[0] == argTypes[0],
                          [sema.types.byteType, sema.types.intType, sema.types.shortType]
                              .contains(signature.parameterTypes[0])
                    else {
                        return false
                    }
                    guard let label = args[0].label else { return true }
                    guard signature.valueParameterSymbols.count == 1,
                          let parameter = sema.symbols.symbol(signature.valueParameterSymbols[0])
                    else {
                        return false
                    }
                    return parameter.name == label
                }
            } else {
                []
            }
            let bundledStdlibCandidates = collectBundledStdlibExtensionCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                sourceFile: ctx.currentASTFile,
                sema: sema,
                interner: interner
            )
            let instantValueSemanticsCandidates = collectInstantValueSemanticsCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                sema: sema,
                interner: interner
            )
            let primitiveArraySourceCandidates = collectPrimitiveArraySourceMembers(
                named: calleeName,
                receiverType: memberLookupType,
                sema: sema,
                interner: interner
            )
            let arrayConversionSourceCandidates = collectArraySourceBackedCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                ctx: ctx,
                sema: sema,
                interner: interner
            )
            var mutableMapPutAllSourceCandidates: [SymbolID] = []
            if calleeName == knownNames.putAll,
               ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType),
               args.count == 1,
               let argumentType = argTypes.first,
               !ReceiverClassifier(sema: sema, interner: interner).isMapLikeCollectionType(argumentType)
            {
                let argumentExpr = args[0].expr
                let isArrayArgument = ReceiverClassifier(sema: sema, interner: interner)
                    .isArrayLikeReceiver(receiverID: argumentExpr)
                let isSequenceArgument = ReceiverClassifier(sema: sema, interner: interner)
                    .isSequenceLikeType(argumentType)
                mutableMapPutAllSourceCandidates = sema.symbols.lookupAll(
                    fqName: knownNames.kotlinCollectionsPackage + [calleeName]
                ).filter { candidate in
                    guard let candidateSymbol = sema.symbols.symbol(candidate),
                          candidateSymbol.kind == .function,
                          (!candidateSymbol.flags.contains(.synthetic)
                              || sema.symbols.isSourceBackedSymbol(candidate)),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let receiver = signature.receiverType,
                          signature.parameterTypes.count == 1,
                          let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                          let receiverInfo = sema.symbols.symbol(receiverSymbol),
                          let parameterSymbol = driver.helpers.nominalSymbol(
                              of: signature.parameterTypes[0], types: sema.types
                          ),
                          let parameterInfo = sema.symbols.symbol(parameterSymbol)
                    else {
                        return false
                    }
                    guard receiverInfo.fqName == knownNames.kotlinCollectionsMutableMapFQName else {
                        return false
                    }
                    if isArrayArgument {
                        return parameterInfo.fqName == knownNames.kotlinArrayFQName
                    }
                    if isSequenceArgument {
                        return parameterInfo.fqName == knownNames.kotlinSequenceFQName
                    }
                    return parameterInfo.fqName == knownNames.kotlinCollectionsIterableFQName
                }
            }
            let standardMemberCandidates: [SymbolID]
            if !arrayConversionSourceCandidates.isEmpty {
                standardMemberCandidates = arrayConversionSourceCandidates
            } else if !mutableMapPutAllSourceCandidates.isEmpty {
                standardMemberCandidates = mutableMapPutAllSourceCandidates
            } else if !primitiveArraySourceCandidates.isEmpty {
                // Primitive-array source members are bundled Kotlin extensions. Prefer the
                // exact source receiver over synthetic member stubs, including
                // joinToString(transform), whose legacy stub shares the same name.
                standardMemberCandidates = primitiveArraySourceCandidates
            } else if !scopedRangeUserCandidates.isEmpty {
                standardMemberCandidates = scopedRangeUserCandidates
            } else if !rangeSourceCandidates.isEmpty {
                standardMemberCandidates = rangeSourceCandidates
            } else if !instantValueSemanticsCandidates.isEmpty {
                // Instant's source-backed value-semantics extensions intentionally
                // replace inherited Any members for a statically typed Instant.
                // Without this preference, the nominal source shell makes
                // Any.equals/hashCode/toString win before extension fallback.
                standardMemberCandidates = instantValueSemanticsCandidates
            } else if !bundledStdlibCandidates.isEmpty {
                // Source-backed bundled declarations are the live implementation
                // for migrated atomic APIs and should win over residual synthetic
                // candidates such as inherited Any members.
                standardMemberCandidates = bundledStdlibCandidates
            } else {
                standardMemberCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: memberLookupType,
                    sema: sema,
                    allowedOwnerSymbols: allowedOwnerSymbols,
                    interner: interner
                )
            }
            // Duration.toString(DurationUnit, Int) is a bundled source extension
            // that overloads Duration's ordinary zero-argument toString member.
            // Keep the source extension in the same candidate set when a member
            // with the same name already exists; otherwise the non-empty argument
            // call would stop at the zero-argument member and never reach the
            // normal extension fallback.
            let sourceBackedOverloads: [SymbolID] = {
                let memberName = interner.resolve(calleeName)
                // kotlinx.io.bytestring Base64 codec functions are bundled source
                // extensions whose first parameter is ByteString, disjoint from
                // every same-named kotlin.io.encoding.Base64 member's
                // ByteArray/CharSequence source, so merging them is unambiguous.
                guard memberName == "toString" || memberName == "replace"
                    || memberName == "encode" || memberName == "decode"
                    || memberName == "encodeToByteArray" || memberName == "encodeIntoByteArray"
                    || memberName == "decodeIntoByteArray" || memberName == "encodeToAppendable"
                else {
                    return []
                }
                if memberName == "toString" {
                    guard !args.isEmpty else { return [] }
                } else if memberName == "replace" {
                    guard args.count == 2,
                          ast.arena.expr(args[1].expr)?.isLambdaOrCallableRef == true
                    else {
                        return []
                    }
                }
                let receiverForExtensionLookup = sema.types.makeNonNullable(memberLookupType)
                return sema.symbols.lookupByShortName(calleeName).filter { candidate in
                    guard sema.symbols.isSourceBackedSymbol(candidate),
                          let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType,
                          signature.parameterTypes.count >= args.count
                    else {
                        return false
                    }
                    guard extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: receiverForExtensionLookup,
                        declaredReceiver: declaredReceiver,
                        sema: sema
                    ) else {
                        return false
                    }
                    if memberName != "replace" {
                        return true
                    }

                    // String has a legacy member-shaped `replace(Regex, String)`
                    // candidate. Keep the bundled CharSequence transform overload
                    // beside it so its function parameter supplies the lambda's
                    // implicit `it` type before overload resolution rejects the
                    // String replacement candidate.
                    func isNominalType(_ type: TypeID, fqName: [String]) -> Bool {
                        guard let nominal = driver.helpers.nominalSymbol(of: type, types: sema.types),
                              let symbol = sema.symbols.symbol(nominal)
                        else {
                            return false
                        }
                        return symbol.fqName.map(interner.resolve) == fqName
                    }
                    guard args.count == 2,
                          signature.parameterTypes.count == 2,
                          isNominalType(declaredReceiver, fqName: ["kotlin", "CharSequence"]),
                          isNominalType(signature.parameterTypes[0], fqName: ["kotlin", "text", "Regex"]),
                          case let .functionType(transformType) = sema.types.kind(
                              of: sema.types.makeNonNullable(signature.parameterTypes[1])
                          ),
                          transformType.params.count == 1,
                          isNominalType(transformType.params[0], fqName: ["kotlin", "text", "MatchResult"]),
                          isNominalType(transformType.returnType, fqName: ["kotlin", "CharSequence"])
                    else {
                        return false
                    }
                    return true
                }
            }()
            // Imported extensions can be reached both through the explicit
            // source-backed overload path above and through ordinary member
            // collection after the compact index restores their receiver
            // owner. Keep one instance of the same symbol so overload
            // resolution does not report a self-ambiguity.
            var seenMemberCandidates: Set<SymbolID> = []
            let memberCandidates = (sourceBackedOverloads + standardMemberCandidates).filter {
                seenMemberCandidates.insert($0).inserted
                    && primitiveCompareToCandidateMatches(
                        $0, calleeName: calleeName, receiverType: memberLookupType,
                        argTypes: argTypes, sema: sema
                    )
            }
            if !memberCandidates.isEmpty {
                // Check if the found candidates belong to a companion object so we
                // can supply the correct implicit receiver type later.
                if let first = memberCandidates.first,
                   let parentSymbol = sema.symbols.parentSymbol(for: first),
                   let ownerNominal = driver.helpers.nominalSymbol(of: memberLookupType, types: sema.types),
                   parentSymbol != ownerNominal,
                   sema.symbols.companionObjectSymbol(for: ownerNominal) == parentSymbol
                {
                    companionReceiverType = sema.types.make(.classType(ClassType(classSymbol: parentSymbol, args: [], nullability: .nonNull)))
                }
                allCandidates = memberCandidates
            } else {
                // Try inner class constructor resolution: outer.Inner() → Inner's <init>
                let innerCtorCandidates = driver.helpers.collectInnerClassConstructorCandidates(
                    named: calleeName,
                    receiverType: memberLookupType,
                    sema: sema,
                    interner: interner
                )
                if !innerCtorCandidates.isEmpty {
                    allCandidates = innerCtorCandidates
                } else {
                    allCandidates = collectExtensionCallCandidates(
                        named: calleeName,
                        memberLookupType: memberLookupType,
                        isSuperCall: isSuperCall,
                        supertypeSymbols: supertypeSymbols,
                        ctx: ctx,
                        locals: locals,
                        sema: sema,
                        interner: interner
                    )
                    if allCandidates.isEmpty, let callableReferenceFunctionType {
                        // Callable references are also function values. Keep KFunction as the
                        // primary lookup type for reflection extensions, then retry extensions
                        // declared on the underlying function type when no reflective candidate
                        // applies to this member name.
                        allCandidates = collectExtensionCallCandidates(
                            named: calleeName,
                            memberLookupType: callableReferenceFunctionType,
                            isSuperCall: isSuperCall,
                            supertypeSymbols: supertypeSymbols,
                            ctx: ctx,
                            locals: locals,
                            sema: sema,
                            interner: interner
                        )
                    }
                }
            }
        }
        // MutableMap.remove(key) has a source-backed projected-key overload in
        // addition to the retained interface member. Prefer the Kotlin source
        // declaration for ordinary MutableMap receiver calls while preserving
        // the synthetic member for interface and lowering bridges.
        if calleeName == knownNames.remove,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType),
           args.count == 1
        {
            let mutableMapRemoveCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let candidateSymbol = sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapRemoveCandidates.isEmpty {
                allCandidates = mutableMapRemoveCandidates
            }
        }
        // A mutable map has a source-backed iterator overload whose return type
        // is MutableIterator<MutableMap.MutableEntry<K, V>>. If the inherited
        // synthetic collection surface won the initial lookup, prefer the
        // exact bundled extension before ordinary overload resolution.
        if calleeName == knownNames.iterator,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType)
        {
            let mutableMapIteratorCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapIteratorCandidates.isEmpty {
                allCandidates = mutableMapIteratorCandidates
            }
        }
        // `MutableMap.getValue(key)` is the read-only Map extension. The
        // MutableMap delegated accessor has the same short name but requires
        // `(thisRef, KProperty<*>)`; keep that two-argument delegate surface
        // out of ordinary one-argument member calls.
        if calleeName == knownNames.getValue,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType),
           args.count == 1
        {
            let mapGetValueCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let candidateSymbol = sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == knownNames.kotlinCollectionsMapFQName
            }
            if !mapGetValueCandidates.isEmpty {
                allCandidates = mapGetValueCandidates
            }
        }

        let isNullLiteralReceiver = if case .nullLiteral = ast.arena.expr(receiverID) {
            true
        } else {
            false
        }

        let isChannelReceiver = ReceiverClassifier(sema: sema, interner: interner)
            .isChannelReceiverType(lookupReceiverType)
        if !isClassNameReceiver, isChannelReceiver {
            let memberName = interner.resolve(calleeName)
            // KSP-678: close / isClosedForReceive / isClosedForSend are resolved
            // through bundled Kotlin source (Channels.kt) via normal candidate
            // resolution below; only the suspension core send / receive are
            // special-cased here.
            switch (memberName, args.count) {
            case ("send", 1):
                let resultType = sema.types.unitType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            // KUU-1453: `ch.receive` without parentheses is property-access
            // syntax on a function — fall through so the invocation-syntax
            // check rejects it like any other bound function.
            case ("receive", 0) where ast.arena.isExplicitCall(id):
                let resultType = sema.types.nullableAnyType
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            default:
                break
            }
        }

        // Prefer the concrete kotlin.text String.compareTo overloads over the
        // generic Comparable<T>.compareTo member, which otherwise leaves
        // String.compareTo(String) ambiguous after both surfaces are available.
        if !isClassNameReceiver,
           calleeName == knownNames.compareTo,
           args.count == 1 || args.count == 2
        {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            let arg0Type = sema.types.makeNonNullable(argTypes[0])
            let stringArgMatches = sema.types.isSubtype(arg0Type, sema.types.stringType)
            let boolArgMatches = args.count == 1
                || sema.types.isSubtype(sema.types.makeNonNullable(argTypes[1]), sema.types.booleanType)
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType),
               stringArgMatches,
               boolArgMatches
            {
                if let boundType = tryBindSyntheticStringMemberFallback(
                    id,
                    calleeName: calleeName,
                    receiverType: receiverTypeForCheck,
                    args: args,
                    argTypes: argTypes,
                    range: range,
                    ctx: ctx,
                    expectedType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    safeCall: safeCall
                ) {
                    return boundType
                }
                let finalType = safeCall
                    ? sema.types.makeNullable(sema.types.intType)
                    : sema.types.intType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // KSP-1403: CharSequence.substring overloads must keep normal member
        // and user-extension precedence before the source fallback is used.
        if let boundType = tryBindSyntheticStringSubstringFallback(
            id,
            calleeName: calleeName,
            receiverType: lookupReceiverType,
            args: args,
            argTypes: argTypes,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall,
            existingCandidates: allCandidates
        ) {
            return boundType
        }

        // KSP-1402: the nominal CharSequence.subSequence(Int, Int) candidate
        // shadows the source-backed IntRange extension during member lookup.
        // Resolve the range overload before the nominal candidate resolver sees
        // the scalar representation of an inline range literal.
        if let boundType = tryBindSyntheticStringRangeSubSequenceFallback(
            id,
            calleeName: calleeName,
            receiverType: lookupReceiverType,
            args: args,
            argTypes: argTypes,
            range: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            safeCall: safeCall,
            existingCandidates: allCandidates
        ) {
            return boundType
        }

        let stringMemberName = interner.resolve(calleeName)
        if ["minWith", "minWithOrNull"].contains(stringMemberName),
           isSyntheticStringLikeType(lookupReceiverType, sema: sema),
           args.count == 1,
           let comparatorElementType = resolvedComparatorElementType(
               of: argTypes[0],
               sema: sema,
               interner: interner
           ),
           sema.types.nullability(of: argTypes[0]) != .nullable,
           sema.types.isSubtype(sema.types.charType, comparatorElementType)
        {
            // The source-backed Comparator<in Char> parameter is valid for a
            // Comparator<Char> argument, but the regular resolver currently
            // rejects that variance. Bind the uniquely named CharSequence
            // declaration after the normal candidates have been considered.
            bindSyntheticStringMemberDirectlyIfAvailable(
                id,
                calleeName: calleeName,
                argumentCount: args.count,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
            if sema.bindings.callBindings[id] != nil {
                let resultType = stringMemberName == "minWithOrNull"
                    ? sema.types.make(.primitive(.char, .nullable))
                    : sema.types.make(.primitive(.char, .nonNull))
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        // A lexical extension function value outranks package extensions,
        // while actual receiver members retain their usual priority.
        let hasReceiverMember = driver.helpers.collectMemberFunctionCandidates(
            named: calleeName, receiverType: memberLookupType, sema: sema, interner: interner
        ).contains {
            ctx.cachedSymbol($0)?.flags.contains(.extensionMemberAlias) != true
                && !driver.helpers.declaresExtensionReceiver($0, sema: sema, interner: interner)
        }
        if !isSuperCall, ast.arena.isExplicitCall(id),
           !hasReceiverMember,
           let result = inferLexicalExtensionCallableInvocation(request, receiverType: receiverType, locals: &locals)
        {
            return result
        }

        if !isSuperCall,
           let local = locals[calleeName],
           let receiver = sema.symbols.functionSignature(for: local.symbol)?.receiverType,
           extensionSyntheticFallbackReceiverMatches(
               callSiteReceiver: memberLookupType, declaredReceiver: receiver, sema: sema
           ),
           !hasReceiverMember
        {
            allCandidates = [local.symbol]
        }

        // Direct member lookup and short-name extension recovery can bypass
        // cachedScopeLookup, which normally removes an expect declaration once
        // its matching actual is linked. Apply the same rule before resolving
        // member-style calls, or the identical expect/actual signatures become
        // two viable overloads and produce a false ambiguity.
        let candidateSet = Set(allCandidates)
        let resolvedCandidates = allCandidates.filter { candidate in
            if ctx.cachedSymbol(candidate)?.flags.contains(.localFunction) == true,
               locals[calleeName]?.symbol != candidate
            {
                return false
            }
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.flags.contains(.expectDeclaration)
            else {
                return true
            }
            guard let actual = sema.symbols.actualSymbol(for: candidate) else {
                return true
            }
            return !candidateSet.contains(actual)
        }
        let (visible, invisible) = ctx.filterByVisibility(resolvedCandidates)
        let memberName = interner.resolve(calleeName)
        if !isClassNameReceiver,
           !safeCall,
           args.isEmpty,
           explicitTypeArgs.isEmpty,
           ast.arena.isExplicitCall(id),
           invisible.isEmpty,
           sema.types.nullability(of: receiverType) == .nullable,
           memberName == "toString" || memberName == "hashCode",
           !visible.contains(where: { candidate in
               guard let signature = sema.symbols.functionSignature(for: candidate),
                     signature.parameterTypes.isEmpty,
                     let declaredReceiver = signature.receiverType,
                     sema.types.nullability(of: declaredReceiver) == .nullable
               else {
                   return false
               }
               return sema.types.isSubtype(receiverType, declaredReceiver)
           })
        {
            // Kotlin exposes toString() and hashCode() through nullable Any
            // extensions. Flat-representation and class receivers can expose
            // only non-null synthetic members, which the normal resolver must
            // reject for a nullable receiver before KIR can use the Any ABI.
            let resultType = memberName == "toString" ? sema.types.stringType : sema.types.intType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }
        var candidates = preferMostSpecificMemberReceiverCandidates(
            visible,
            receiverType: lookupReceiverType,
            argumentTypes: argTypes,
            sema: sema,
            interner: interner
        )
        if calleeName == knownNames.forEach {
            let receiverClassification = ReceiverClassifier(sema: sema, interner: interner).classify(
                receiverID: receiverID,
                receiverType: lookupReceiverType,
                ast: ast
            )
            let isEligibleIterableReceiver = receiverClassification.isIterableReceiver
                || (
                    !receiverClassification.isCollectionReceiver
                        && !receiverClassification.isSequenceReceiver
                        && !receiverClassification.isArrayReceiver
                        && !receiverClassification.isMapReceiver
                        && !receiverClassification.isSetReceiver
                )
            if !isEligibleIterableReceiver {
                let iterableFQName = knownNames.kotlinCollectionsIterableFQName
                candidates.removeAll { candidate in
                    guard sema.symbols.isSourceBackedSymbol(candidate),
                          let signatureReceiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                          let (_, receiverSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema)
                    else {
                        return false
                    }
                    return receiverSymbol.fqName == iterableFQName
                }
            }
        }
        // Kotlin selects MutableMap.withDefault over the less-specific
        // Map.withDefault extension for a MutableMap receiver. Resolve this
        // subtype preference before trailing-lambda overload inference sees
        // two otherwise identical function shapes.
        if calleeName == knownNames.withDefault,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(lookupReceiverType)
        {
            let mutableMapCandidates = candidates.filter { candidate in
                guard sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapCandidates.isEmpty {
                candidates = mutableMapCandidates
            }
        }
        if calleeName == knownNames.coerceIn,
           !args.contains(where: { sema.bindings.isFloatingPointRangeExpr($0.expr) })
        {
            // The generic ClosedFloatingPointRange overload must not turn a
            // scalar call with the wrong arity or argument type into a type
            // constraint failure. Kotlin reports those calls as no overload.
            candidates.removeAll { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      signature.parameterTypes.count == 1,
                      let (_, parameterSymbol) = resolveClassTypeSymbol(
                          signature.parameterTypes[0], sema: sema
                      )
                else {
                    return false
                }
                return parameterSymbol.name == knownNames.closedFloatingPointRange
            }
        }
        if calleeName == knownNames.coerceIn,
           args.contains(where: { sema.bindings.isFloatingPointRangeExpr($0.expr) })
        {
            // Imported `.kklib` metadata does not make a generic extension whose
            // receiver is a type parameter visible through the receiver-type
            // fallback above. Recover the source-backed range overloads here so
            // the same call resolves with bundled source injection and a library.
            let genericRangeCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      signature.parameterTypes.count == 1,
                      let (_, parameterSymbol) = resolveClassTypeSymbol(
                          signature.parameterTypes[0], sema: sema
                      )
                else {
                    return false
                }
                return parameterSymbol.name == knownNames.closedFloatingPointRange
            }
            candidates.append(contentsOf: genericRangeCandidates.filter { !candidates.contains($0) })
        }
        if calleeName == knownNames.coerceAtLeast
            || calleeName == knownNames.coerceAtMost
            || calleeName == knownNames.coerceIn
        {
            // A concrete `Int.coerceIn`/`UByte.coerceAtLeast`-style overload is
            // strictly more specific than the generic `T.coerceX` extensions
            // (upstream's overload ranking). Keeping both in the candidate set
            // turns calls whose arguments need literal coercion (or whose
            // argument type makes the generic's bound fail) into a constraint
            // error instead of binding the concrete overload. Keep the generic
            // only when no concrete overload has the same arity — i.e.
            // user-defined `Comparable` receivers, or shapes no concrete
            // overload covers (e.g. `Double.coerceIn(ClosedFloatingPointRange)`).
            let concreteArities = Set(candidates.compactMap { candidate -> Int? in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.isEmpty
                else {
                    return nil
                }
                return signature.parameterTypes.count
            })
            candidates.removeAll { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      let receiver = signature.receiverType,
                      resolveClassTypeSymbol(receiver, sema: sema) == nil
                else {
                    return false
                }
                return concreteArities.contains(signature.parameterTypes.count)
            }
        }
        if calleeName == knownNames.toList {
            candidates = preferCollectionToListCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == knownNames.take {
            candidates = preferListTakeCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == knownNames.unzip {
            candidates = preferListUnzipCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if isNullLiteralReceiver,
           args.isEmpty,
           calleeName == knownNames.isNullOrEmpty,
           let charSequenceType = syntheticCharSequenceType(sema: sema),
           candidates.contains(where: { candidate in
               sema.symbols.functionSignature(for: candidate)?.receiverType == sema.types.makeNullable(charSequenceType)
           })
        {
            // Kotlin stdlib also provides Array/Collection/Map nullable-receiver
            // isNullOrEmpty overloads. They are still lowered through synthetic
            // typed-receiver fallbacks here, but a bare null receiver must see the
            // same ambiguous overload set as kotlinc.
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0003",
                "Ambiguous overload resolution.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if hasLeadingLocaleArgument {
            candidates.removeAll { candidate in
                isSyntheticStringFormatCandidate(candidate, sema: sema, interner: interner)
            }
        }
        if calleeName == knownNames.trimMargin {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                if !explicitTypeArgs.isEmpty {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                let trimMarginFQName = knownNames.kotlinTextPackage + [calleeName]
                let chosen = sema.symbols.lookupAll(fqName: trimMarginFQName).first(where: { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.receiverType == sema.types.stringType
                    else {
                        return false
                    }
                    switch args.count {
                    case 0:
                        return signature.parameterTypes.isEmpty
                    case 1:
                        return signature.parameterTypes.count == 1
                            && sema.types.isSubtype(sema.types.makeNonNullable(argTypes[0]), signature.parameterTypes[0])
                    default:
                        return false
                    }
                })
                if let chosen {
                    let returnType = bindCallAndResolveReturnType(
                        id,
                        chosen: chosen,
                        resolved: ResolvedCall(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [:],
                            parameterMapping: args.isEmpty ? [:] : [0: 0],
                            diagnostic: nil
                        ),
                        sema: sema
                    )
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }
        if candidates.isEmpty {
            return inferRegularMemberCallWithoutCandidates(
                request,
                receiverType: receiverType,
                lookupReceiverType: lookupReceiverType,
                memberLookupType: memberLookupType,
                argTypes: argTypes,
                isClassNameReceiver: isClassNameReceiver,
                classNameReceiverNominalSymbol: classNameReceiverNominalSymbol,
                isNullLiteralReceiver: isNullLiteralReceiver,
                isFlowReceiver: isFlowReceiver,
                flowElementType: flowElementType,
                hasLeadingLocaleArgument: hasLeadingLocaleArgument,
                invisibleCandidates: invisible,
                isSuperCall: isSuperCall,
                locals: &locals
            )
        }

        // Use the companion type as implicit receiver when the candidates were
        // redirected from the owner class to its companion object.
        let mutableMapSuperReceiverType: TypeID? = {
            guard isSuperCall,
                  [interner.intern("put"), knownNames.putAll, knownNames.remove, knownNames.clear].contains(calleeName),
                  let currentType = ctx.implicitReceiverType,
                  case let .classType(current) = sema.types.kind(of: currentType),
                  case let .classType(superclass) = sema.types.kind(of: lookupReceiverType),
                  let mutableMap = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsMutableMapFQName),
                  sema.types.isNominalSubtypeSymbol(superclass.classSymbol, of: mutableMap),
                  let arguments = sema.types.liftedNominalSupertypeArgs(
                      from: current.classSymbol, childArgs: current.args, to: superclass.classSymbol
                  )
            else { return nil }
            return sema.types.make(.classType(ClassType(classSymbol: superclass.classSymbol, args: arguments)))
        }()
        let callableReferenceExtensionReceiverType: TypeID? = {
            guard let callableReferenceFunctionType,
                  candidates.contains(where: { candidate in
                      guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType else {
                          return false
                      }
                      if case .functionType = sema.types.kind(of: receiver) {
                          return true
                      }
                      return false
                  })
            else {
                return nil
            }
            return callableReferenceFunctionType
        }()
        let effectiveReceiverType = companionReceiverType
            ?? mutableMapSuperReceiverType
            ?? rangeSourceMemberLookupType
            ?? rangeExtensionLookupType
            ?? callableReferenceExtensionReceiverType
            ?? lookupReceiverType
        // STDLIB-pipeline §5: take/drop/chunked/windowed have real require()
        // validation in SequenceWindowChunk.kt as of MIGRATION-SEQ-005. When
        // normal candidate lookup already resolved one of these names to that
        // source declaration, the synthetic collection-member fallback below
        // must not discard it — Kotlin-source candidates take priority over
        // the synthetic shortcut so chosenCallee binds to the real
        // declaration and its require() executes.
        //
        // Excludes calls with a trailing HOF lambda (chunked(size) { ... },
        // windowed(size, step) { ... }): tryCollectionMemberFallback below
        // derives the transform overload's result element type from the
        // lambda body's inferred return type (see
        // CallTypeChecker+CollectionMemberFallback.swift), which the generic
        // overload resolver cannot reproduce and fails with conflicting type
        // variable bounds. Those overloads keep going through the synthetic
        // fallback and their require() bypass is tracked separately.
        let hasTrailingLambdaArg = args.last.map { ast.arena.expr($0.expr)?.isLambdaOrCallableRef ?? false } ?? false
        // STDLIB-pipeline §5 / KSP-441: Source-backed Sequence transforms
        // (map, filter, etc.) must bind to the real Kotlin declaration so the
        // object-expression pipeline runs instead of a `kk_*` runtime shortcut.
        let memberNameText = interner.resolve(calleeName)
        let isMutableMapIteratorSource = memberNameText == "iterator"
            && ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType)
        // MutableSet inherits independent Set.iterator and MutableIterable.iterator
        // candidates. Keep the mutable-aware collection fallback when lookup is
        // ambiguous, while a unique source member retains normal dispatch.
        let isUniqueIteratorSource = memberNameText == "iterator" && candidates.count == 1
        let isListSourceBackedMember: Bool = {
            guard ["get", "indexOf", "lastIndexOf", "subList"].contains(memberNameText),
                  let listOwner = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsListFQName)
            else { return false }
            return driver.helpers.allNominalSymbols(of: memberLookupType, types: sema.types, symbols: sema.symbols).contains {
                sema.types.isNominalSubtypeSymbol($0, of: listOwner)
            }
        }()
        // KSP-687 resolves Array.joinToString through the dedicated primitive
        // and generic-array source candidates. KSP-429's broad trailing-lambda
        // gate is for List/Iterable source calls; applying it to Array receivers
        // prevents the array resolver from binding the source overload.
        let isArrayJoinToString = memberNameText == "joinToString"
            && isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isArraySourceBackedMember = isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
            && !collectArraySourceBackedCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                ctx: ctx,
                sema: sema,
                interner: interner
            ).isEmpty
        let isSourceBackedMemberName = (calleeName == knownNames.zip
            && isSequenceLikeType(lookupReceiverType, sema: sema, interner: interner))
            || Self.sourceBackedCollectionMemberNames.contains(memberNameText)
            || (Self.sourceBackedTrailingLambdaMemberNames.contains(memberNameText) && !isArrayJoinToString)
            || isArraySourceBackedMember
            || isMutableMapIteratorSource
            || isUniqueIteratorSource
            || isListSourceBackedMember
        let hasSourceBackedCandidate = isSourceBackedMemberName
            && (isArraySourceBackedMember || !Self.sourceBackedCollectionMemberNames.contains(memberNameText) || !hasTrailingLambdaArg)
            && candidates.contains { candidateID in
                sema.symbols.isSourceBackedSymbol(candidateID)
            }
        // Synthetic collection members need to short-circuit before the generic
        // overload resolver so their trailing-lambda expectations stay concrete.
        if !hasSourceBackedCandidate, let fallbackType = tryCollectionMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            expectedType: expectedType,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindThreadLocalGetOrSetFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        if let fallbackType = tryBindComparatorMemberFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return fallbackType
        }
        // Scope/import priority precedes function-vs-property priority. Do this
        // before lambda preparation, which would otherwise infer a package
        // property's block as the implicitly imported T.apply receiver lambda.
        if !isClassNameReceiver, !isSuperCall,
           let functionPriority = candidates.map({ callableInvocationScopePriority($0, named: calleeName, ctx: ctx) }).min(),
           functionPriority > 0,
           let propertyType = tryInferCallableMemberPropertyInvocation(
               request, memberLookupType: memberLookupType, argTypes: argTypes,
               isClassNameReceiver: false, locals: &locals,
               maximumPropertyPriority: functionPriority - 1
           ) {
            return propertyType
        }
        var cachedNonLambdaArgTypes: [Int: TypeID] = [:]
        for (index, argument) in args.enumerated() {
            guard let argumentExpr = ast.arena.expr(argument.expr) else {
                continue
            }
            switch argumentExpr {
            case .lambdaLiteral, .callableRef:
                continue
            default:
                cachedNonLambdaArgTypes[index] = argTypes[index]
            }
        }
        let preparedArgs = prepareCallArguments(
            args: args,
            candidates: candidates,
            preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
            expectedTypeOverrides: {
                if isLongRangeLiteralContainsCall {
                    return [0: sema.types.longType]
                }
                if isULongRangeLiteralContainsCall {
                    return [0: sema.types.ulongType]
                }
                return [:]
            }(),
            contextualCallResultType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: effectiveReceiverType,
            ctx: ctx,
            locals: &locals
        )
        // Older imported stdlib artifacts may still expose a String callback
        // bridge alongside the bundled CharSequence declaration. Lambda
        // preparation intentionally erases return types while finding a shared
        // input shape, so prefer that compatibility bridge only when it is
        // actually present and applicable; bundled source continues through
        // the CharSequence declaration.
        if memberNameText == "replace",
           args.count == 2,
           sema.types.makeNonNullable(argTypes[0]) == sema.types.stringType,
           preparedArgs.lambdaLiteralIndices.contains(1),
           case let .functionType(lambdaType) = sema.types.kind(
               of: sema.types.makeNonNullable(preparedArgs.argTypes[1])
           ),
           sema.types.isSubtype(lambdaType.returnType, sema.types.stringType)
        {
            let regexStringBridgeCandidates = candidates.filter {
                sema.symbols.externalLinkName(for: $0) == "__kk_regex_replace_lambda"
            }
            if !regexStringBridgeCandidates.isEmpty {
                candidates = regexStringBridgeCandidates
            }
        }
        let isDeferredAwait = candidates.contains {
            sema.symbols.externalLinkName(for: $0) == "kk_kxmini_async_await"
        }
        let resolutionExpectedType = isDeferredAwait ? nil : expectedType
        var resolved = resolveCallRespectingLambdaReturnType(
            candidates: candidates,
            args: args,
            argTypes: preparedArgs.argTypes,
            range: range,
            calleeName: calleeName,
            explicitTypeArgs: explicitTypeArgs,
            expectedType: resolutionExpectedType,
            implicitReceiverType: effectiveReceiverType,
            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
            inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
            blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
            ctx: ctx
        )
        // Ambiguous applicable members retain precedence over extensions.
        if let diagnostic = resolved.diagnostic,
           diagnostic.code == "KSWIFTK-SEMA-0003"
        {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        // A same-named member that cannot accept the call must not hide an
        // applicable extension. Only retried after ordinary resolution failed, so
        // a viable member (including range/lambda arguments whose provisional
        // types are unreliable before resolution) always keeps precedence.
        if resolved.diagnostic != nil,
           // Class-name receivers resolve through the companion object, so an
           // extension on a companion supertype (e.g. `Base64.encode` via
           // `Default`) must still be retried when an inherited member exists
           // but cannot accept the call.
           (!isClassNameReceiver || companionReceiverType != nil),
           !isSuperCall,
           !args.contains(where: { ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true }),
           !candidates.isEmpty
        {
            let receiverForExtensionLookup = sema.types.makeNonNullable(effectiveReceiverType)
            func receiverMatchingExtensions(_ scopeCandidates: [SymbolID]) -> [SymbolID] {
                scopeCandidates.filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType,
                          !isHiddenByDeprecatedAnnotation(candidate, symbols: sema.symbols)
                    else { return false }
                    let isUser = symbol.declSite.map {
                        driver.sourceManager?.origin(of: $0.start.file) == .user
                    } ?? false
                    guard isUser || sema.symbols.isSourceBackedSymbol(candidate),
                          ctx.visibilityChecker.isAccessible(
                              symbol,
                              fromFile: ctx.currentFileID,
                              enclosingClass: ctx.enclosingClassSymbol
                          )
                    else { return false }
                    return extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: receiverForExtensionLookup,
                        declaredReceiver: declaredReceiver,
                        sema: sema
                    )
                }
            }
            // Viable user extensions shadow outer bindings, not inapplicable ones.
            var extensionCandidates = receiverMatchingExtensions(ctx.scope.lookup(calleeName))
            if extensionCandidates.isEmpty || ctx.resolver.probeCall(
                candidates: extensionCandidates,
                call: CallExpr(range: range, calleeName: calleeName, args: preparedArgs.argTypes.map { CallArg(type: $0) }),
                expectedType: expectedType,
                implicitReceiverType: receiverForExtensionLookup,
                ctx: ctx.semaCtx
            ).viableCandidates.isEmpty {
                extensionCandidates = receiverMatchingExtensions(ctx.scope.lookupMergingChain(calleeName))
            }
            if !extensionCandidates.isEmpty {
                let extensionArgs = prepareCallArguments(
                    args: args,
                    candidates: extensionCandidates,
                    preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
                    contextualCallResultType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    receiverType: effectiveReceiverType,
                    ctx: ctx,
                    locals: &locals
                )
                let retried = resolveCallRespectingLambdaReturnType(
                    candidates: extensionCandidates,
                    args: args,
                    argTypes: extensionArgs.argTypes,
                    range: range,
                    calleeName: calleeName,
                    explicitTypeArgs: explicitTypeArgs,
                    expectedType: expectedType,
                    implicitReceiverType: effectiveReceiverType,
                    lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                    inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                    blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                    hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                    ctx: ctx
                )
                if retried.diagnostic == nil {
                    candidates = extensionCandidates
                    resolved = retried
                }
            }
        }
        if let diagnostic = resolved.diagnostic {
            if diagnostic.code == "KSWIFTK-SEMA-BOUND" {
                let callee = interner.resolve(calleeName)
                if callee == "sorted" || callee == "sortedDescending" {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
            }
            if isClassNameReceiver,
               args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: calleeName,
                   sema: sema
               )
            {
                if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: memberSymbol,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
                sema.bindings.bindExprType(id, type: staticMember.type)
                return staticMember.type
            }
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: calleeName,
                range: range,
                sema: sema,
                interner: interner
            ) {
                ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let fallbackType = tryRegexMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryKFunctionMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryStringMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryNativePlacementAllocExtensionFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                explicitTypeArgs: explicitTypeArgs,
                ctx: ctx
            ) {
                return fallbackType
            }
            if let fallbackType = tryNativeCInteropReadValueExtensionFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx
            ) {
                return fallbackType
            }
            if let fallbackType = tryFileMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryArrayMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryRangeMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let retried = retryResolutionReinferringNestedCallArguments(
                candidates: candidates,
                args: args,
                argTypes: preparedArgs.argTypes,
                range: range,
                calleeName: calleeName,
                explicitTypeArgs: explicitTypeArgs,
                expectedType: expectedType,
                implicitReceiverType: effectiveReceiverType,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                ctx: ctx,
                locals: &locals
            ) {
                resolved = retried
            }
            // KUU-946: an inapplicable member must not shadow same-named
            // extensions — retry against the extension candidate set before
            // reporting the member failure.
            if resolved.diagnostic != nil,
               let fallbackType = tryBindShadowedExtensionCallFallback(
                   request,
                   receiverType: receiverType,
                   lookupReceiverType: lookupReceiverType,
                   memberLookupType: memberLookupType,
                   argTypes: argTypes,
                   isClassNameReceiver: isClassNameReceiver,
                   isSuperCall: isSuperCall,
                   locals: &locals
               )
            {
                return fallbackType
            }
            if resolved.diagnostic != nil,
               let propertyType = tryInferCallableMemberPropertyInvocation(
                   request, memberLookupType: memberLookupType, argTypes: argTypes,
                   isClassNameReceiver: isClassNameReceiver, locals: &locals
               ) { return propertyType }
            if resolved.diagnostic != nil {
                if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                    candidates: candidates,
                    receiverType: lookupReceiverType,
                    calleeName: calleeName,
                    range: range,
                    sema: sema,
                    interner: interner
                ) {
                    ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
                } else {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                }
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
        }
        guard let chosen = resolved.chosenCallee else {
            if isClassNameReceiver,
               args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: calleeName,
                   sema: sema
               )
            {
                if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: memberSymbol,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
                sema.bindings.bindExprType(id, type: staticMember.type)
                return staticMember.type
            }
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: calleeName,
                range: range,
                sema: sema,
                interner: interner
            ) {
                ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let fallbackType = tryCommonMemberCallFallbacks(
                request,
                isClassNameReceiver: isClassNameReceiver,
                collectionFallbackFirst: true,
                admitNominalIterableReceiver: false,
                locals: &locals
            ) {
                return fallbackType
            }
            // KUU-946: members that produced no viable callee must not shadow
            // same-named extensions — retry against the extension candidate
            // set before reporting the member failure.
            if let fallbackType = tryBindShadowedExtensionCallFallback(
                request,
                receiverType: receiverType,
                lookupReceiverType: lookupReceiverType,
                memberLookupType: memberLookupType,
                argTypes: argTypes,
                isClassNameReceiver: isClassNameReceiver,
                isSuperCall: isSuperCall,
                locals: &locals
            ) {
                return fallbackType
            }
            if let propertyType = tryInferCallableMemberPropertyInvocation(
                request, memberLookupType: memberLookupType, argTypes: argTypes,
                isClassNameReceiver: isClassNameReceiver, locals: &locals
            ) { return propertyType }
            ctx.semaCtx.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(interner.resolve(calleeName))'.", range: range)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        markRegexReplaceLambdaIfNeeded(chosenCallee: chosen, args: args, ctx: ctx)
        driver.helpers.checkDeprecation(
            for: chosen,
            sema: sema,
            interner: interner,
            range: range,
            diagnostics: ctx.semaCtx.diagnostics
        )
        driver.helpers.checkOptIn(
            for: chosen,
            ctx: ctx,
            range: range,
            diagnostics: ctx.semaCtx.diagnostics
        )
        // P5-112: Prohibit super.foo() calls to abstract members.
        if isSuperCall,
           let chosenSym = sema.symbols.symbol(chosen),
           chosenSym.flags.contains(SymbolFlags.abstractType),
           chosenSym.kind == SymbolKind.function || chosenSym.kind == SymbolKind.property
        {
            let memberName = interner.resolve(calleeName)
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-ABSTRACT",
                "Cannot call abstract member '\(memberName)' via super.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        // kotlinc prohibits a super-call from omitting an argument that carries
        // a default value ("super-calls with default arguments are prohibited.
        // Specify all arguments of 'super.<name>' explicitly.") -- resolving the
        // default and dispatching statically to the base implementation can
        // never re-evaluate an override's own default expression. The call is
        // otherwise fully well-typed, so diagnose without erroring the
        // expression's type -- an error type here would risk cascading into a
        // second, spurious kswiftc-only diagnostic on an unrelated line.
        if isSuperCall,
           let signature = sema.symbols.functionSignature(for: chosen)
        {
            let suppliedParameterIndices = Set(resolved.parameterMapping.values)
            let hasOmittedDefaultArgument = signature.valueParameterHasDefaultValues.indices.contains { index in
                signature.valueParameterHasDefaultValues[index] && !suppliedParameterIndices.contains(index)
            }
            if hasOmittedDefaultArgument {
                let memberName = interner.resolve(calleeName)
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0306",
                    "Super-calls with default arguments are prohibited. Specify all arguments of 'super.\(memberName)' explicitly.",
                    range: range
                )
            }
        }

        // --- Use-site variance projection check ---
        // When the receiver has projected type arguments (e.g. MutableList<out Number>),
        // check that the member access respects variance constraints.
        if let signature = sema.symbols.functionSignature(for: chosen),
           let varianceResult = sema.types.buildVarianceProjectionSubstitutions(
               receiverType: lookupReceiverType,
               signature: signature,
               symbols: sema.symbols
           )
        {
            // Check if any parameter uses a write-forbidden type parameter
            if !allowsProjectedReceiverUnsafeVariance(chosen, sema: sema, interner: interner),
               let violatingParamIndex = sema.types.checkVarianceViolationInParameters(
                   signature: signature,
                   writeForbiddenSymbols: varianceResult.writeForbiddenSymbols
               )
            {
                let paramType = sema.types.displayName(
                    of: signature.parameterTypes[violatingParamIndex],
                    symbols: sema.symbols,
                    interner: interner
                )
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-VAR-OUT",
                    "A type projection on the receiver prevents calling '\(interner.resolve(calleeName))' because the type parameter appears in an 'in' position (parameter type '\(paramType)').",
                    range: range
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }

            // For projected types, merge the solver's substitution with the
            // variance projection (projection overrides receiver type params).
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let mergedSubstitution = resolved.substitutedTypeArguments.merging(
                varianceResult.covariantSubstitution,
                uniquingKeysWith: { _, projected in projected }
            )
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: mergedSubstitution
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                        .map(\.value),
                    parameterMapping: resolved.parameterMapping
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            let projectedReturnType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: mergedSubstitution,
                typeVarBySymbol: typeVarBySymbol
            )
            if isSuperCall { sema.bindings.markSuperCall(id) }
            let finalType = safeCall ? sema.types.makeNullable(projectedReturnType) : projectedReturnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        contextualizeArrayReduceRightLambda(args: args, resolved: resolved, ctx: ctx, locals: &locals)
        contextualizeResolvedIntegerArguments(args: args, resolved: resolved, ctx: ctx, locals: &locals)
        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        // STDLIB-592 definite assignment: `x.let { ... }` / `x.apply { ... }` /
        // `x.also { ... }` / `x.run { ... }` resolve as ordinary member calls
        // through this path, so their `callsInPlace` contracts must be applied
        // here too (not just for the unqualified-call path in CallTypeChecker.swift).
        applyContractEffects(
            id: id,
            chosen: chosen,
            args: args,
            ctx: ctx,
            locals: &locals
        )
        // Narrow `CoroutineScope.async` / `Deferred.await()` using the element
        // type tracked by `coroutineBuilderNarrowedReturnType` for the
        // `async {}` call that produced this receiver.
        let adjustedReturnType: TypeID = if sema.symbols.externalLinkName(for: chosen) == "kk_coroutine_scope_async",
                                          let block = args.first(where: { $0.label == interner.intern("block") }) ?? args.last
        {
            coroutineBuilderNarrowedReturnType(
                id: id, launcherName: "async", lambdaArgExpr: block.expr,
                fallback: returnType, ast: ast, sema: sema
            )
        } else if sema.symbols.externalLinkName(for: chosen) == "kk_kxmini_async_await" {
            deferredAwaitResultType(receiverID: receiverID, fallback: returnType, ast: ast, sema: sema)
        } else {
            returnType
        }
        if isSuperCall { sema.bindings.markSuperCall(id) }
        let finalType = safeCall ? sema.types.makeNullable(adjustedReturnType) : adjustedReturnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
