// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// Runs before ordinary member/extension lookup. Named object qualifiers
    /// share only the nested-classifier path; their members use instance lookup.
    /// Returns nil when no classifier-qualifier path applies.
    func tryInferRegularMemberCallClassNameReceiver(
        _ request: MemberCallInferenceRequest,
        isClassNameReceiver: Bool,
        classNameReceiverNominalSymbol: SymbolID?,
        argTypes: [TypeID],
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        // KUU-3237: a typealias qualifier cannot reach nested classifiers
        // (`A2.Nested`, `A2.Inner`, `A2.Companion` are all unresolved in
        // Kotlin), but companion members and enum entries stay visible
        // through the alias, so only `.object` member values are skipped.
        let receiverViaTypeAlias = receiverQualifierIsTypeAlias(
            receiverID: request.receiverID, ctx: ctx
        )
        if isClassNameReceiver,
           args.isEmpty,
           let ownerSymbol = classNameReceiverNominalSymbol,
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: ownerSymbol,
               memberName: calleeName,
               sema: sema
           ),
           !(receiverViaTypeAlias
               && sema.symbols.symbol(staticMember.symbol)?.kind == .object),
           // An explicit `()` on a nested `object` is a function invocation,
           // not a value read — fall through so `invoke` can dispatch
           // (KUU-3662).
           !(ast.arena.isExplicitCall(id)
               && sema.symbols.symbol(staticMember.symbol)?.kind == .object)
        {
            if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
               !ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(for: memberSymbol, name: interner.resolve(calleeName), range: range, diagnostics: ctx.sema.diagnostics)
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
                        diagnostics: ctx.sema.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if !visibleStaticMethods.isEmpty {
                    let callArgs = zip(args, argTypes).map { arg, type in
                        CallArg.source(arg, type: type, callRange: range, ast: ctx.ast)
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
                        ctx.sema.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    if let chosen = resolved.chosenCallee,
                       let signature = sema.symbols.functionSignature(for: chosen)
                    {
                        bindResolvedFunctionValueSamArguments(id, chosen: chosen, resolved: resolved, sema: sema)
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
                // declared on the nominal type itself. Enum APIs such as
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
                        guard isUnsignedRandomExtensionVisible(symbol, named: calleeName, ctx: ctx) else {
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
                        diagnostics: ctx.sema.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if !visibleOwnerExtensions.isEmpty {
                    let callArgs = zip(args, argTypes).map { arg, type in
                        CallArg.source(arg, type: type, callRange: range, ast: ctx.ast)
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
                        ctx.sema.diagnostics.emit(diagnostic)
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
                            diagnostics: ctx.sema.diagnostics
                        )
                        driver.helpers.checkOptIn(
                            for: chosen,
                            ctx: ctx,
                            range: range,
                            diagnostics: ctx.sema.diagnostics
                        )
                        sema.bindings.bindExprType(receiverID, type: ownerType)
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }
        }

        let nestedClassifierOwnerSymbol: SymbolID? = {
            if isClassNameReceiver {
                // Nested classifiers are not reachable through a typealias
                // qualifier (KUU-3237); keep the nominal only for a genuine
                // class-name receiver.
                return receiverViaTypeAlias ? nil : classNameReceiverNominalSymbol
            }
            guard !request.safeCall else {
                return nil
            }
            // A named object is both a value and a classifier qualifier.
            // Values with the object's type (including this) cannot qualify
            // nested classes, so require the object declaration binding.
            switch ast.arena.expr(receiverID) {
            case .nameRef:
                break
            case .memberCall where !ast.arena.isExplicitCall(receiverID):
                break
            default:
                return nil
            }
            guard let symbolID = sema.bindings.identifierSymbol(for: receiverID),
                  sema.symbols.symbol(symbolID)?.kind == .object
            else {
                return nil
            }
            return symbolID
        }()
        if let ownerSymbol = nestedClassifierOwnerSymbol,
           let owner = sema.symbols.symbol(ownerSymbol)
        {
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
            if let nestedOwner = nestedOwnerSymbols.first,
               let samType = inferQualifiedNestedClassifierSamConstruction(
                   id,
                   calleeName: calleeName,
                   classifierSymbol: nestedOwner,
                   args: args,
                   argTypes: argTypes,
                   ctx: ctx,
                   locals: &locals,
                   expectedType: expectedType,
                   explicitTypeArgs: explicitTypeArgs
               )
            {
                return samType
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
            // An explicit `()` on a nested `object` is instead a function
            // invocation — it must fall through so `invoke` can dispatch
            // (KUU-3662).
            if args.isEmpty, let nestedOwner = nestedOwnerSymbols.first,
               let nestedOwnerKind = sema.symbols.symbol(nestedOwner)?.kind,
               nestedOwnerKind == .enumClass
                   || ((nestedOwnerKind == .class || nestedOwnerKind == .object
                        || nestedOwnerKind == .interface || nestedOwnerKind == .annotationClass)
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
                        range: range, diagnostics: ctx.sema.diagnostics
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
            // `Outer.I()` reaches here as a classifier qualifier — there is
            // no containing-class instance on the receiver side, so an inner
            // class constructor cannot be called this way. Object qualifiers
            // only reach this path through the value binding above and are
            // already instances.
            if isClassNameReceiver,
               let nestedOwner = nestedOwnerSymbols.first,
               sema.symbols.symbol(nestedOwner)?.flags.contains(.innerClass) == true
            {
                let innerName = sema.symbols.symbol(nestedOwner)
                    .map { interner.resolve($0.name) } ?? interner.resolve(calleeName)
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0437",
                    "constructor of the inner class '\(innerName)' can only be called with a receiver of the containing class.",
                    range: range
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
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
                let hasFactoryFunctionCandidates: Bool = {
                    let factoryOwner = owner.kind == .object
                        ? ownerSymbol : sema.symbols.companionObjectSymbol(for: ownerSymbol)
                    guard let factoryOwner else {
                        return false
                    }
                    let factoryType = sema.types.make(.classType(ClassType(
                        classSymbol: factoryOwner,
                        args: [],
                        nullability: .nonNull
                    )))
                    if !driver.helpers.collectMemberFunctionCandidates(
                        named: calleeName,
                        receiverType: factoryType,
                        sema: sema,
                        interner: interner
                    ).isEmpty {
                        return true
                    }
                    // Mirror ordinary object/companion lookup's scoped and
                    // imported-library extension fallbacks.
                    let extensionCandidates = ctx.cachedScopeLookup(calleeName)
                        + sema.symbols.lookupByShortName(calleeName).filter {
                            sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
                        }
                    return extensionCandidates.contains { candidate in
                        guard sema.symbols.symbol(candidate)?.kind == .function,
                              let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType
                        else {
                            return false
                        }
                        return extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: factoryType,
                            declaredReceiver: receiver,
                            sema: sema
                        )
                    }
                }()
                let (visibleNested, invisibleNested) = ctx.filterByVisibility(nestedCtorCandidates)
                if visibleNested.isEmpty, let firstInvisible = invisibleNested.first {
                    // An inaccessible constructor must not hide an accessible
                    // object or companion factory. Let ordinary lookup resolve it.
                    if hasFactoryFunctionCandidates {
                        return nil
                    }
                    // Nor the nested classifier's own companion/object
                    // `invoke` (KUU-3662).
                    if let nestedOwner = nestedOwnerSymbols.first,
                       let invokeType = inferQualifiedNestedClassifierCompanionInvoke(
                           request,
                           classifierSymbol: nestedOwner,
                           argTypes: argTypes,
                           locals: &locals
                       )
                    {
                        return invokeType
                    }
                    driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.sema.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                if !visibleNested.isEmpty {
                    if args.isEmpty, explicitTypeArgs.isEmpty {
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
                               (nestedOwnerSymbol.kind == .class || nestedOwnerSymbol.kind == .annotationClass),
                               !nestedOwnerSymbol.flags.contains(.innerClass)
                            {
                                sema.bindings.markTypeQualifiedConstructorCallExpr(id)
                            }
                            sema.bindings.bindExprType(id, type: resultType)
                            return resultType
                        }
                    }
                    // Nested constructors return before ordinary member-call
                    // preparation, so infer lambdas and callable references
                    // against their constructor parameter types here too.
                    var cachedNonLambdaArgTypes: [Int: TypeID] = [:]
                    for (index, argument) in args.enumerated() {
                        if ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                            continue
                        }
                        cachedNonLambdaArgTypes[index] = argTypes[index]
                    }
                    var expectedTypeOverrides: [Int: TypeID] = [:]
                    var lambdaContextOverrides: [Int: TypeInferenceContext] = [:]
                    let argumentDiagnosticsCheckpoint = sema.diagnostics.checkpoint()
                    let originalArgumentLocals = locals
                    let expectedTypeHintIndices = prepareCallExprArgumentContexts(
                        args: args,
                        callRange: range,
                        ctx: ctx,
                        expectedType: expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        calleeName: calleeName,
                        candidates: visibleNested,
                        locals: locals,
                        withContextExpectedLambdaType: nil,
                        expectedTypeOverrides: &expectedTypeOverrides,
                        lambdaContextOverrides: &lambdaContextOverrides
                    )
                    let preparedArgs = prepareCallArguments(
                        args: args,
                        callRange: range,
                        candidates: visibleNested,
                        preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
                        expectedTypeOverrides: expectedTypeOverrides,
                        expectedTypeHintIndices: expectedTypeHintIndices,
                        contextualCallResultType: ctx.isCallResultDiscarded && ctx.isUnitCoercionContext
                            ? sema.types.unitType : expectedType,
                        explicitTypeArgs: explicitTypeArgs,
                        lambdaContextOverrides: lambdaContextOverrides,
                        ctx: ctx,
                        locals: &locals
                    )
                    let resolved = resolveCallRespectingLambdaReturnType(
                        candidates: visibleNested,
                        args: args,
                        argTypes: preparedArgs.argTypes,
                        range: range,
                        calleeName: calleeName,
                        explicitTypeArgs: explicitTypeArgs,
                        expectedType: expectedType,
                        implicitReceiverType: nil,
                        lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                        inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                        blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                        hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                        ctx: ctx
                    )
                    if let diagnostic = resolved.diagnostic {
                        if ctx.allowsLiftedCallExpectedTypeHints, !expectedTypeHintIndices.isEmpty {
                            sema.diagnostics.rollback(to: argumentDiagnosticsCheckpoint)
                            locals = originalArgumentLocals
                            var retryContext = ctx
                            retryContext.allowsLiftedCallExpectedTypeHints = false
                            // Member calls reuse already-bound argument types.
                            // Refresh speculative arguments before the retry
                            // so Box<Any> cannot survive a natural Box<Int> pass.
                            for index in expectedTypeHintIndices.sorted() {
                                guard isInferableNestedCallExpr(args[index].expr, ast: ast) else { continue }
                                _ = driver.inferExpr(args[index].expr, ctx: retryContext, locals: &locals)
                            }
                            return driver.inferExpr(id, ctx: retryContext, locals: &locals, expectedType: expectedType)
                        }
                        // Kotlin gives applicable nested constructors priority
                        // for Owner.Name(...), but retries object/companion functions
                        // when no constructor is applicable. Keep constructor
                        // ambiguity instead of silently choosing a factory.
                        // A result-type mismatch does not make an otherwise
                        // applicable constructor yield to a companion function.
                        let ctorInapplicable = diagnostic.code != "KSWIFTK-SEMA-0003"
                            && (expectedType == nil || ctx.resolver.probeCall(
                                candidates: visibleNested,
                                call: CallExpr(
                                    range: range,
                                    calleeName: calleeName,
                                    args: zip(args, preparedArgs.argTypes).map { argument, type in
                                        CallArg(
                                            label: argument.label,
                                            isSpread: argument.isSpread,
                                            type: type,
                                            isTrailingLambda: argument.isTrailingLambda
                                        )
                                    },
                                    explicitTypeArgs: explicitTypeArgs
                                ),
                                expectedType: nil,
                                ctx: sema
                            ).viableCandidates.isEmpty)
                        if ctorInapplicable {
                            if hasFactoryFunctionCandidates {
                                return nil
                            }
                            // No constructor applies — the nested classifier's
                            // own companion/object `invoke` is next in Kotlin's
                            // resolution order (KUU-3662).
                            if let nestedOwner = nestedOwnerSymbols.first,
                               let invokeType = inferQualifiedNestedClassifierCompanionInvoke(
                                   request,
                                   classifierSymbol: nestedOwner,
                                   argTypes: argTypes,
                                   locals: &locals
                               )
                            {
                                return invokeType
                            }
                        }
                        ctx.sema.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    if let chosen = resolved.chosenCallee,
                       let signature = sema.symbols.functionSignature(for: chosen)
                    {
                        contextualizeResolvedIntegerArguments(args: args, resolved: resolved, ctx: ctx, locals: &locals)
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
                           (nestedOwnerSymbol.kind == .class || nestedOwnerSymbol.kind == .annotationClass),
                           !nestedOwnerSymbol.flags.contains(.innerClass)
                        {
                            sema.bindings.markTypeQualifiedConstructorCallExpr(id)
                        }
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
            }
            if nestedCtorCandidates.isEmpty,
               let nestedOwner = nestedOwnerSymbols.first,
               let companionInvokeType = inferQualifiedNestedClassifierCompanionInvoke(
                   request,
                   classifierSymbol: nestedOwner,
                   argTypes: argTypes,
                   locals: &locals
               )
            {
                return companionInvokeType
            }
        }

        return nil
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
