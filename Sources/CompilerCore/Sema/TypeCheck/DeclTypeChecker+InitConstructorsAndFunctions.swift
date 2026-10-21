extension DeclTypeChecker {
    func localTypeForParameter(
        at index: Int,
        signature: FunctionSignature,
        sema: SemaModule,
        interner: StringInterner,
        referenceVarargAsArray: Bool = true
    ) -> TypeID {
        let parameterType = index < signature.parameterTypes.count
            ? signature.parameterTypes[index]
            : sema.types.anyType
        guard index < signature.valueParameterIsVararg.count,
              signature.valueParameterIsVararg[index]
        else {
            return parameterType
        }
        if let arrayType = primitiveVarargArrayType(
            elementType: parameterType,
            sema: sema,
            interner: interner
        ) {
            return arrayType
        }
        // Local functions use the source-visible generic array directly so
        // their call boundary and body agree on the vararg representation.
        if referenceVarargAsArray,
           let arraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("Array"),
           ])
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.out(parameterType)],
                nullability: .nonNull
            )))
        }
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = sema.symbols.lookup(fqName: listFQName) else {
            return parameterType
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.invariant(parameterType)],
            nullability: .nonNull
        )))
    }

    /// Type-checks each parameter's default-value expression (if any) against its
    /// declared type, visiting parameters in declaration order and revealing each
    /// parameter symbol to `locals` only after its own default has been checked.
    /// This mirrors the visibility that `CallSupportLowerer.generateDefaultStubFunction`
    /// assumes when it lowers these same expressions: a default value may reference
    /// the current or an earlier parameter, but not a later one.
    ///
    /// Without this, default-value expressions are never visited by Sema at all, so
    /// `sema.bindings` (call bindings, expr types, ...) stay empty for them and KIR
    /// lowering silently mis-resolves anything beyond a literal (constructor calls,
    /// property reads, ...).
    func typeCheckParameterDefaultValues(
        _ valueParams: [ValueParamDecl],
        signature: FunctionSignature,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        baseLocals: LocalBindings = [:]
    ) {
        let ctx = ctx.withoutSuspensionContext()
        let sema = ctx.sema
        var locals = baseLocals
        for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
            guard let param = sema.symbols.symbol(paramSymbol) else { continue }
            let type = localTypeForParameter(
                at: index, signature: signature, sema: sema, interner: ctx.interner
            )
            if index < valueParams.count, let defaultExprID = valueParams[index].defaultValue {
                // A vararg declaration default is the whole source array,
                // even when the non-local body's existing storage uses List.
                let defaultExpectedType = localTypeForParameter(
                    at: index, signature: signature, sema: sema, interner: ctx.interner,
                    referenceVarargAsArray: true
                )
                // Infer vararg defaults from their own expression shape before
                // checking the required source-array type. Passing the array
                // expectation into overload resolution can silently accept a
                // List-producing call such as listOf(...).
                let inferenceExpectedType = valueParams[index].isVararg ? nil : defaultExpectedType
                let defaultType = driver.inferExpr(
                    defaultExprID, ctx: ctx, locals: &locals, expectedType: inferenceExpectedType
                )
                driver.emitSubtypeConstraint(
                    left: defaultType, right: defaultExpectedType,
                    range: ctx.ast.arena.exprRange(defaultExprID),
                    solver: solver, sema: sema, diagnostics: diagnostics
                )
            }
            locals[param.name] = (type, paramSymbol, false, true)
        }
    }

    /// Primary constructor parameters never go through `typeCheckSecondaryConstructors`
    /// or a function body check, so without this call their defaults would never be
    /// visited by Sema at all (see `typeCheckParameterDefaultValues`).
    func typeCheckPrimaryConstructorDefaultValues(
        _ classDecl: ClassDecl,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        baseLocals: LocalBindings = [:]
    ) {
        guard classDecl.primaryConstructorParams.contains(where: { $0.defaultValue != nil }) else {
            return
        }
        let sema = ctx.sema
        let primaryCtorSymbol = sema.symbols.symbols(atDeclSite: classDecl.range)
            .compactMap { sema.symbols.symbol($0) }
            .first { $0.kind == .constructor }
        guard let primaryCtorSymbol,
              let signature = sema.symbols.functionSignature(for: primaryCtorSymbol.id)
        else {
            return
        }
        typeCheckParameterDefaultValues(
            classDecl.primaryConstructorParams,
            signature: signature,
            ctx: ctx,
            solver: solver,
            diagnostics: diagnostics,
            baseLocals: baseLocals
        )
    }

    /// The arguments live in the primary constructor's scope, so they are
    /// checked with the primary constructor parameters seeded as locals — the
    /// same scope `typeCheckClassDelegation` builds for `by` expressions.
    /// `extraLocals` seeds the delegation-argument scope with bindings that
    /// outrank nothing but sit alongside the ctor params — used by the
    /// KUU-555 local-class path, where `Base(x)` can reference a captured
    /// outer local; named classes pass the default `[:]`.
    func typeCheckPrimaryConstructorSuperDelegation(
        _ classDecl: ClassDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        extraLocals: LocalBindings = [:]
    ) {
        let sema = ctx.sema
        // Enum's name/ordinal superclass arguments are synthesized during lowering.
        guard sema.symbols.symbol(symbol)?.kind != .enumClass else { return }
        guard let superclassSymbol = superclassSymbol(of: symbol, sema: sema),
              let superclassInfo = sema.symbols.symbol(superclassSymbol),
              let primaryCtorSymbol = sema.symbols.symbols(atDeclSite: classDecl.range)
              .compactMap({ sema.symbols.symbol($0) })
              .first(where: { $0.kind == .constructor })
        else {
            return
        }

        let args = classDecl.superTypeEntries.first { !$0.constructorArgs.isEmpty }?.constructorArgs ?? []

        var delegationCtx = ctx
        var locals: LocalBindings = extraLocals
        if let signature = sema.symbols.functionSignature(for: primaryCtorSymbol.id) {
            let ctorScope = BaseScope(parent: ctx.scope, symbols: sema.symbols)
            for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
                ctorScope.insert(paramSymbol)
                guard let paramInfo = sema.symbols.symbol(paramSymbol) else { continue }
                locals[paramInfo.name] = (
                    type: localTypeForParameter(
                        at: index, signature: signature, sema: sema, interner: ctx.interner
                    ),
                    symbol: paramSymbol,
                    isMutable: false,
                    isInitialized: true
                )
            }
            // Supertype initializer arguments run before `this` (and any outer
            // instance) is available, so instance members must not resolve.
            delegationCtx = ctx.copying(
                scope: ctorScope,
                implicitReceiverType: .some(nil),
                outerReceiverTypes: []
            ).excludingEnclosingClassReceiver()
        }

        let candidates = sema.symbols
            .lookupAll(fqName: superclassInfo.fqName + [ctx.interner.intern("<init>")])
            .filter { candidate in
                guard let candidateInfo = sema.symbols.symbol(candidate) else { return false }
                return candidateInfo.kind == .constructor
                    && sema.symbols.parentSymbol(for: candidate) == superclassSymbol
                    && candidate != primaryCtorSymbol.id
            }
        guard !candidates.isEmpty else { return }

        let resolved = inferConstructorDelegationArguments(
            args,
            candidates: candidates,
            range: classDecl.range,
            targetType: constructorSuperclassType(
                ownerSymbol: symbol, superclassSymbol: superclassSymbol, ctx: ctx
            ),
            ctx: delegationCtx,
            locals: &locals
        )
        if let chosenCallee = resolved.chosenCallee {
            sema.bindings.bindConstructorDelegationCall(
                primaryCtorSymbol.id,
                binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: resolved.substitutedTypeArguments
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                        .map(\.value),
                    parameterMapping: resolved.parameterMapping
                )
            )
        }
    }

    func inferConstructorDelegationArguments(
        _ args: [CallArgument],
        candidates: [SymbolID],
        range: SourceRange,
        targetType: TypeID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> ResolvedCall {
        let sema = ctx.sema
        let typeArguments: [TypeID]
        if let targetType, case let .classType(classType) = ctx.sema.types.kind(of: targetType) {
            typeArguments = classType.args.map { arg in
                switch arg {
                case let .invariant(type), let .in(type), let .out(type): type
                case .star: ctx.sema.types.anyType
                }
            }
        } else {
            typeArguments = []
        }
        let expectedTypeOverrides = constructorDelegationExpectedParameterTypes(
            args: args,
            candidates: candidates,
            targetType: targetType,
            range: range,
            ctx: ctx
        )
        let prepared = driver.callChecker.prepareCallArguments(
            args: args,
            callRange: range,
            candidates: candidates,
            expectedTypeOverrides: expectedTypeOverrides,
            explicitTypeArgs: typeArguments,
            ctx: ctx,
            locals: &locals
        )
        var selectedThisReceiversByCandidate: [SymbolID: [Int: (type: TypeID, symbol: SymbolID?)]] = [:]
        func resolveArguments(_ argTypes: [TypeID], candidates candidateSubset: [SymbolID]? = nil) -> ResolvedCall {
            let candidatesToResolve = candidateSubset ?? candidates
            selectedThisReceiversByCandidate = contextualConstructorThisArgumentReceivers(
                args: args,
                argTypes: argTypes,
                candidates: candidatesToResolve,
                targetType: targetType,
                callRange: range,
                ctx: ctx,
                locals: locals
            )
            let candidateArgumentTypes = selectedThisReceiversByCandidate.mapValues { receivers in
                Dictionary<Int, TypeID>(uniqueKeysWithValues: receivers.compactMap {
                    argumentIndex, receiver -> (Int, TypeID)? in
                    guard argTypes.indices.contains(argumentIndex),
                          argTypes[argumentIndex] != receiver.type
                    else { return nil }
                    return (argumentIndex, receiver.type)
                })
            }
            return driver.callChecker.resolveCallRespectingLambdaReturnType(
                candidates: candidatesToResolve,
                args: args,
                argTypes: argTypes,
                range: range,
                calleeName: ctx.interner.intern("<init>"),
                explicitTypeArgs: typeArguments,
                expectedType: targetType,
                implicitReceiverType: nil,
                candidateArgumentTypes: candidateArgumentTypes,
                lambdaLiteralIndices: prepared.lambdaLiteralIndices,
                inputOnlyLambdaIndices: prepared.inputOnlyLambdaIndices,
                blockedLambdaRefinement: prepared.blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: prepared.hasUnresolvableImplicitLambdaParameter,
                ctx: ctx
            )
        }
        var resolved = resolveArguments(prepared.argTypes)
        var callArgs = zip(args, prepared.argTypes).map { argument, type in
            CallArg.source(argument, type: type, callRange: range, ast: ctx.ast)
        }
        if resolved.diagnostic != nil,
           reinferConstructorDelegationArguments(
               args: args,
               candidates: candidates,
               expectedType: targetType,
               argTypes: &callArgs,
               ctx: ctx,
               locals: &locals
           )
        {
            resolved = resolveArguments(callArgs.map(\.type))
        }
        if resolved.diagnostic != nil {
            let contextualCandidates = selectedThisReceiversByCandidate.keys.filter { candidate in
                guard let selectedReceivers = selectedThisReceiversByCandidate[candidate] else { return false }
                return selectedReceivers.contains { argumentIndex, receiver in
                    guard args.indices.contains(argumentIndex), callArgs.indices.contains(argumentIndex) else {
                        return false
                    }
                    return callArgs[argumentIndex].type != receiver.type
                }
            }
            if !contextualCandidates.isEmpty {
                let contextualResolved = resolveArguments(callArgs.map(\.type), candidates: contextualCandidates)
                if contextualResolved.diagnostic == nil {
                    resolved = contextualResolved
                }
            }
        }
        if let chosenCallee = resolved.chosenCallee {
            for (argumentIndex, receiver) in selectedThisReceiversByCandidate[chosenCallee] ?? [:]
            where args.indices.contains(argumentIndex) {
                let expression = args[argumentIndex].expr
                if let receiverSymbol = receiver.symbol {
                    sema.bindings.bindIdentifier(expression, symbol: receiverSymbol)
                }
                sema.bindings.bindExprType(expression, type: receiver.type)
            }
        }
        if let diagnostic = resolved.diagnostic {
            ctx.sema.diagnostics.emit(diagnostic)
        }
        driver.callChecker.contextualizeResolvedIntegerArguments(
            args: args, resolved: resolved, ctx: ctx, locals: &locals
        )
        return resolved
    }

    func superclassSymbol(of symbol: SymbolID, sema: SemaModule) -> SymbolID? {
        sema.symbols.directSupertypes(for: symbol).first {
            let kind = sema.symbols.symbol($0)?.kind
            return kind == .class || kind == .enumClass
        }.map { linkedActualConstructorOwner($0, sema: sema) }
    }

    private func linkedActualConstructorOwner(_ owner: SymbolID, sema: SemaModule) -> SymbolID {
        guard let actual = sema.symbols.actualSymbol(for: owner),
              sema.symbols.symbol(actual)?.kind == sema.symbols.symbol(owner)?.kind
        else {
            return owner
        }
        return actual
    }

    /// Inheritance binding adds kotlin.Any to classes without an explicit
    /// superclass. That implicit edge represents nominal inheritance, but it
    /// is not an explicit constructor delegation target for `super()`.
    func explicitClassSuperclassSymbol(
        _ classDecl: ClassDecl,
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        for entry in classDecl.superTypeEntries {
            let resolved = driver.helpers.resolveTypeRef(
                entry.typeRef,
                ast: ctx.ast,
                sema: ctx.sema,
                interner: ctx.interner,
                scope: ctx.scope,
                diagnostics: nil
            )
            if resolved == ctx.sema.types.anyType,
               let anySymbol = ctx.sema.symbols.lookup(fqName: [
                   ctx.interner.intern("kotlin"),
                   ctx.interner.intern("Any"),
               ])
            {
                return anySymbol
            }
            guard case let .classType(classType) = ctx.sema.types.kind(of: resolved),
                  let symbol = ctx.sema.symbols.symbol(classType.classSymbol)
            else {
                continue
            }
            switch symbol.kind {
            case .class, .enumClass, .annotationClass:
                return classType.classSymbol
            default:
                continue
            }
        }
        return nil
    }

    /// Kotlin scopes primary constructor parameters declared without `val`/`var`
    /// to property initializers and `init {}` blocks only — not to regular
    /// member functions. Property-backed parameters (`val`/`var`) are already
    /// reachable as members through `classScope`, so only the non-property
    /// parameters need to be threaded through here as `locals`.
    func primaryConstructorParameterLocals(
        classDecl: ClassDecl,
        ctx: TypeInferenceContext
    ) -> LocalBindings {
        guard !classDecl.primaryConstructorParams.isEmpty else { return [:] }
        let sema = ctx.sema
        guard let ctorSymbol = sema.symbols.symbols(atDeclSite: classDecl.range)
            .compactMap({ sema.symbols.symbol($0) })
            .first(where: { $0.kind == .constructor }),
            let signature = sema.symbols.functionSignature(for: ctorSymbol.id)
        else {
            return [:]
        }
        var locals: LocalBindings = [:]
        for (index, param) in classDecl.primaryConstructorParams.enumerated() {
            guard !param.isProperty, index < signature.valueParameterSymbols.count else { continue }
            let paramSymbol = signature.valueParameterSymbols[index]
            let type = localTypeForParameter(
                at: index, signature: signature, sema: sema, interner: ctx.interner
            )
            locals[param.name] = (type, paramSymbol, false, true)
            if driver.helpers.isOpenEndRangeType(type, sema: sema, interner: ctx.interner) {
                sema.bindings.markRangeSymbol(paramSymbol)
            }
            if index < signature.valueParameterIsVararg.count,
               signature.valueParameterIsVararg[index],
               primitiveVarargArrayType(
                   elementType: signature.parameterTypes[index],
                   sema: sema,
                   interner: ctx.interner
               ) == nil
            {
                sema.bindings.markCollectionSymbol(paramSymbol)
            }
        }
        return locals
    }

    func typeCheckInitBlocks(
        _ blocks: [FunctionBody],
        ctx: TypeInferenceContext,
        baseLocals: LocalBindings = [:]
    ) {
        var runningLocals = baseLocals
        if let classSymbol = ctx.enclosingClassSymbol ?? ctx.currentDeclSymbol,
           let classType = ctx.implicitReceiverType {
            let thisName = ctx.interner.intern("this")
            if runningLocals[thisName] == nil {
                let syntheticThisSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: classSymbol)
                runningLocals[thisName] = (classType, syntheticThisSymbol, false, true)
            }
        }
        for block in blocks {
            var locals: LocalBindings = runningLocals
            var initCtx = ctx
            initCtx.allowsValPropertyInitialization = true
            _ = inferFunctionBodyType(block, ctx: initCtx, locals: &locals, expectedType: nil)
            runningLocals.memberFlow = locals.memberFlow
        }
    }

    func typeCheckSecondaryConstructors(
        _ constructors: [ConstructorDecl],
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        ownerSymbol: SymbolID? = nil,
        hasPrimaryConstructor: Bool = true,
        explicitSuperclassSymbol: SymbolID? = nil,
        baseLocals: LocalBindings = [:]
    ) {
        let sema = ctx.sema
        for ctor in constructors {
            var locals = baseLocals
            let ctorSymbols = sema.symbols.symbols(atDeclSite: ctor.range)
                .compactMap { sema.symbols.symbol($0) }
                .filter { $0.kind == .constructor }
            let currentCtorSymbolID = ctorSymbols.first?.id
            let constructorScope = FunctionScope(parent: ctx.scope, symbols: sema.symbols)
            var constructorCtx = ctx.copying(scope: constructorScope)
            if let ctorSymbol = ctorSymbols.first {
                if let signature = sema.symbols.functionSignature(for: ctorSymbol.id) {
                    for typeParameterSymbol in signature.typeParameterSymbols {
                        constructorScope.insert(typeParameterSymbol)
                    }
                    for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
                        guard let param = sema.symbols.symbol(paramSymbol) else { continue }
                        let type = localTypeForParameter(
                            at: index,
                            signature: signature,
                            sema: sema,
                            interner: ctx.interner
                        )
                        locals[param.name] = (type, paramSymbol, false, true)
                        if driver.helpers.isOpenEndRangeType(type, sema: sema, interner: ctx.interner) {
                            sema.bindings.markRangeSymbol(paramSymbol)
                        }
                        if index < signature.valueParameterIsVararg.count,
                           signature.valueParameterIsVararg[index],
                           primitiveVarargArrayType(
                               elementType: signature.parameterTypes[index],
                               sema: sema,
                               interner: ctx.interner
                           ) == nil
                        {
                            sema.bindings.markCollectionSymbol(paramSymbol)
                        }
                    }
                    constructorCtx = ctx.copying(scope: constructorScope)
                    typeCheckParameterDefaultValues(
                        ctor.valueParams,
                        signature: signature,
                        ctx: constructorCtx,
                        solver: solver,
                        diagnostics: diagnostics,
                        baseLocals: baseLocals
                    )
                }
            }

            constructorCtx.allowsValPropertyInitialization = true
            if ctor.delegationCall == nil, hasPrimaryConstructor {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0054",
                    "Secondary constructor must delegate to another constructor via this() or super().",
                    range: ctor.range
                )
            }

            typeCheckConstructorDelegation(
                ctor: ctor,
                currentCtorSymbolID: currentCtorSymbolID,
                ownerSymbol: ownerSymbol,
                explicitSuperclassSymbol: explicitSuperclassSymbol,
                ctx: constructorCtx,
                locals: &locals
            )
            let constructorBodyContext: TypeInferenceContext
            if let currentCtorSymbolID {
                constructorBodyContext = constructorCtx.copying(
                    lambdaDepth: 0,
                    enclosingFunctionReturnType: sema.types.unitType,
                    enclosingFunctionSymbol: currentCtorSymbolID,
                    enclosingLambdaExprIDs: [],
                    currentDeclSymbol: currentCtorSymbolID
                )
            } else {
                constructorBodyContext = constructorCtx
            }
            let thisReceiverSymbol = ownerSymbol ?? ctx.enclosingClassSymbol ?? currentCtorSymbolID
            if let thisReceiverSymbol,
               let receiverType = ctx.implicitReceiverType {
                let thisName = ctx.interner.intern("this")
                if locals[thisName] == nil {
                    let syntheticThisSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: thisReceiverSymbol)
                    locals[thisName] = (receiverType, syntheticThisSymbol, false, true)
                }
            }
            _ = inferFunctionBodyType(
                ctor.body,
                ctx: constructorBodyContext,
                locals: &locals,
                expectedType: nil
            )
        }
    }

    private func typeCheckConstructorDelegation(
        ctor: ConstructorDecl,
        currentCtorSymbolID: SymbolID?,
        ownerSymbol: SymbolID?,
        explicitSuperclassSymbol: SymbolID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
        guard let delegation = ctor.delegationCall else { return }

        // Resolve candidates and their expected superclass type with the same owner.
        let explicitSuperclassSymbol = explicitSuperclassSymbol.map { superclass in
            linkedActualConstructorOwner(superclass, sema: sema)
        }
        let targetOwner = delegation.kind == .this ? ownerSymbol : explicitSuperclassSymbol
        let delegationTargetFQName = resolveDelegationTarget(
            delegation: delegation,
            ownerSymbol: ownerSymbol,
            explicitSuperclassSymbol: explicitSuperclassSymbol,
            ctx: ctx
        )

        if !delegationTargetFQName.isEmpty {
            let candidates = sema.symbols.lookupAll(fqName: delegationTargetFQName)
                .filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else { return false }
                    return symbol.kind == .constructor
                        && sema.symbols.parentSymbol(for: candidate) == targetOwner
                        && candidate != currentCtorSymbolID
                }

            if candidates.isEmpty {
                emitUnresolvedDelegation(delegation: delegation, sema: sema)
            } else {
                let resolved = inferConstructorDelegationArguments(
                    delegation.args,
                    candidates: candidates,
                    range: delegation.range,
                    targetType: delegation.kind == .this
                        ? constructorOwnerType(ownerSymbol, ctx: ctx)
                        : constructorSuperclassType(
                            ownerSymbol: ownerSymbol,
                            superclassSymbol: explicitSuperclassSymbol,
                            ctx: ctx
                        ),
                    ctx: ctx,
                    locals: &locals
                )
                if let chosenCallee = resolved.chosenCallee, let currentCtorSymbolID {
                    sema.bindings.bindConstructorDelegationCall(
                        currentCtorSymbolID,
                        binding: CallBinding(
                            chosenCallee: chosenCallee,
                            substitutedTypeArguments: resolved.substitutedTypeArguments
                                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                .map(\.value),
                            parameterMapping: resolved.parameterMapping
                        )
                    )
                }
            }
        } else if ownerSymbol != nil {
            emitUnresolvedDelegation(delegation: delegation, sema: sema)
        }
    }

    private func constructorDelegationExpectedParameterTypes(
        args: [CallArgument],
        candidates: [SymbolID],
        targetType: TypeID?,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> [Int: TypeID] {
        let sema = ctx.sema
        guard let targetType,
              case let .classType(ownerType) = sema.types.kind(of: targetType)
        else { return [:] }
        let ownerParameters = sema.types.allTypeParameterSymbols(for: ownerType.classSymbol)
        let ownerArguments = sema.types.allTypeArguments(for: ownerType)
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(ownerParameters)
        var substitution: [TypeVarID: TypeID] = [:]
        for (parameter, argument) in zip(ownerParameters, ownerArguments) {
            guard let variable = typeVarBySymbol[parameter] else { continue }
            switch argument {
            case let .invariant(type), let .in(type), let .out(type):
                substitution[variable] = type
            case .star:
                continue
            }
        }
        let mockCallArgs = args.map { CallArg.source($0, type: sema.types.anyType, callRange: range, ast: ctx.ast) }
        let candidateMappings = candidates.compactMap { candidate -> [Int: TypeID]? in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let mapping = ctx.resolver.buildParameterMapping(
                      signature: signature,
                      callArgs: mockCallArgs,
                      symbols: sema.symbols,
                      typeSystem: sema.types
                  )
            else { return nil }
            return Dictionary(uniqueKeysWithValues: mapping.compactMap { argumentIndex, parameterIndex in
                guard args.indices.contains(argumentIndex),
                      let argumentType = driver.callChecker.contextualCallArgumentType(
                          args[argumentIndex], parameterIndex: parameterIndex,
                          in: signature, ctx: ctx
                      )
                else { return nil }
                return (
                    argumentIndex,
                    sema.types.substituteTypeParameters(
                        in: argumentType,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    )
                )
            })
        }
        guard let first = candidateMappings.first else { return [:] }
        var uniformTypes: [Int: TypeID] = [:]
        for (index, expected) in first {
            if candidateMappings.allSatisfy({ $0[index] == expected }) {
                uniformTypes[index] = expected
            }
        }
        return uniformTypes
    }

    private func reinferConstructorDelegationArguments(
        args: [CallArgument],
        candidates: [SymbolID],
        expectedType: TypeID?,
        argTypes: inout [CallArg],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> Bool {
        let sema = ctx.sema
        guard let expectedType,
              case let .classType(ownerType) = sema.types.kind(of: expectedType)
        else { return false }
        let ownerParameters = sema.types.allTypeParameterSymbols(for: ownerType.classSymbol)
        let ownerArguments = sema.types.allTypeArguments(for: ownerType)
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(ownerParameters)
        var substitution: [TypeVarID: TypeID] = [:]
        for (parameter, argument) in zip(ownerParameters, ownerArguments) {
            guard let variable = typeVarBySymbol[parameter] else { continue }
            switch argument {
            case let .invariant(type), let .in(type), let .out(type):
                substitution[variable] = type
            case .star:
                continue
            }
        }
        let candidateParameterTypes = candidates.compactMap { candidate -> [Int: TypeID]? in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let mapping = ctx.resolver.buildParameterMapping(
                      signature: signature,
                      callArgs: argTypes,
                      symbols: sema.symbols,
                      typeSystem: sema.types
                  )
            else { return nil }
            let parameterTypes = mapping.mapValues { parameterIndex in
                sema.types.substituteTypeParameters(
                    in: signature.parameterTypes[parameterIndex],
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
            for (index, argument) in args.enumerated() {
                let originalType = argTypes[index].type
                guard !argument.isSpread,
                      driver.callChecker.isInferableNestedCallExpr(argument.expr, ast: ctx.ast),
                      driver.callChecker.typeContainsNothingType(originalType, sema: sema),
                      let parameterType = parameterTypes[index]
                else { continue }
                if !sema.types.isSubtype(originalType, parameterType),
                   driver.callChecker.concreteNestedCallExpectedType(
                       originalArgumentType: originalType,
                       boundType: parameterType,
                       sema: sema
                   ) == nil
                {
                    return nil
                }
            }
            return parameterTypes
        }
        guard let firstCandidate = candidateParameterTypes.first else { return false }

        var didReinfer = false
        for (index, argument) in args.enumerated() {
            let originalType = argTypes[index].type
            guard driver.callChecker.isInferableNestedCallExpr(argument.expr, ast: ctx.ast),
                  driver.callChecker.typeContainsNothingType(originalType, sema: sema),
                  let parameterType = firstCandidate[index],
                  candidateParameterTypes.allSatisfy({ $0[index] == parameterType }),
                  let argumentExpectedType = driver.callChecker.concreteNestedCallExpectedType(
                      originalArgumentType: originalType,
                      boundType: parameterType,
                      sema: sema
                  )
            else { continue }
            let type = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals, expectedType: argumentExpectedType)
            argTypes[index] = CallArg(
                label: argument.label, isSpread: argument.isSpread, type: type,
                isTrailingLambda: argTypes[index].isTrailingLambda
            )
            didReinfer = true
        }
        return didReinfer
    }

    private func constructorOwnerType(
        _ ownerSymbol: SymbolID?,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        guard let ownerSymbol else { return nil }
        let typeArguments = ctx.sema.types.allTypeParameterSymbols(for: ownerSymbol).map {
            TypeArg.invariant(ctx.sema.types.make(.typeParam(TypeParamType(symbol: $0))))
        }
        return ctx.sema.types.make(.classType(ctx.sema.types.classType(
            for: ownerSymbol,
            arguments: typeArguments,
            nullability: .nonNull
        )))
    }

    /// A secondary `super(...)` delegates to the instantiated superclass in
    /// the class header. Its type arguments are known even when none of the
    /// constructor arguments mention them.
    func constructorSuperclassType(
        ownerSymbol: SymbolID?,
        superclassSymbol: SymbolID?,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        guard let ownerSymbol, let superclassSymbol else { return nil }
        let directSupertypes = ctx.sema.symbols.directSupertypes(for: ownerSymbol)
        // Local classes and object literals can retain the expect edge's key.
        let registeredSuperclass = directSupertypes.contains(superclassSymbol)
            ? superclassSymbol
            : directSupertypes.first {
                linkedActualConstructorOwner($0, sema: ctx.sema) == superclassSymbol
            } ?? superclassSymbol
        let typeArguments = ctx.sema.symbols.supertypeTypeArgs(
            for: ownerSymbol, supertype: registeredSuperclass
        )
        return ctx.sema.types.make(.classType(ctx.sema.types.classType(
            for: superclassSymbol,
            arguments: typeArguments,
            nullability: .nonNull
        )))
    }

    private func resolveDelegationTarget(
        delegation: ConstructorDelegationCall,
        ownerSymbol: SymbolID?,
        explicitSuperclassSymbol: SymbolID?,
        ctx: TypeInferenceContext
    ) -> [InternedString] {
        let sema = ctx.sema
        switch delegation.kind {
        case .this:
            if let owner = ownerSymbol {
                if let ownerSym = sema.symbols.symbol(owner) {
                    return ownerSym.fqName + [ctx.interner.intern("<init>")]
                }
            }
            return []
        case .super_:
            guard ownerSymbol != nil, let superclass = explicitSuperclassSymbol,
                  let superSym = sema.symbols.symbol(superclass)
            else { return [] }
            return superSym.fqName + [ctx.interner.intern("<init>")]
        }
    }

    private func emitUnresolvedDelegation(
        delegation: ConstructorDelegationCall,
        sema: SemaModule
    ) {
        let targetKind = delegation.kind == .this ? "this" : "super"
        sema.diagnostics.error(
            "KSWIFTK-SEMA-0055",
            "Unresolved \(targetKind)() delegation target: no matching constructor found.",
            range: delegation.range
        )
    }

    /// - Parameter baseLocals: Seeds the function body's local-name resolution
    ///   with bindings from an enclosing scope. Empty for ordinary member
    ///   functions (a named class has no enclosing local scope to capture).
    ///   Object-literal member functions pass the enclosing function's
    ///   `locals` here so the body can resolve captured outer variables the
    ///   same way lambda bodies do (KSP-CAP-001).
    func typeCheckFunctionDecl(
        _ function: FunDecl,
        symbol: SymbolID,
        ctx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        baseLocals: LocalBindings = [:]
    ) {
        let tracksInferredFunction = driver.inferredReturnFunctions[symbol] != nil
        if tracksInferredFunction {
            guard !driver.checkedInferredReturnFunctions.contains(symbol),
                  driver.checkingInferredReturnFunctions.insert(symbol).inserted
            else { return }
            driver.deferredInferredReturnFunctions.remove(symbol)
        }
        defer {
            if tracksInferredFunction {
                driver.checkingInferredReturnFunctions.remove(symbol)
                // Speculative callers may roll diagnostics back. Declarations
                // with their own diagnostics need an authoritative recheck.
                if !diagnostics.hasError,
                   !driver.deferredInferredReturnFunctions.contains(symbol),
                   !diagnostics.diagnostics.contains(where: {
                       $0.primaryRange.map(function.range.contains) ?? true
                   })
                {
                    driver.checkedInferredReturnFunctions.insert(symbol)
                }
            }
        }
        typeCheckAnnotationFactories(function.annotations, symbol: symbol, ctx: ctx)
        let sema = ctx.sema
        guard let signature = sema.symbols.functionSignature(for: symbol) else {
            return
        }

        validateFunctionHeaderOptInTypes(
            symbol,
            ctx: ctx.with(currentDeclSymbol: symbol),
            hasExplicitReturnType: function.returnType != nil
        )
        let hasRuntimeBridge = function.modifiers.contains(.external)
            || function.annotations.contains {
                KnownCompilerAnnotation.ksSymbolName.matches($0.name)
            }
        if hasRuntimeBridge, function.body == .unit {
            return
        }

        var locals: LocalBindings = baseLocals
        for (index, paramSymbol) in signature.valueParameterSymbols.enumerated() {
            guard let param = sema.symbols.symbol(paramSymbol) else {
                continue
            }
            let type = localTypeForParameter(
                at: index,
                signature: signature,
                sema: sema,
                interner: ctx.interner
            )
            locals[param.name] = (type, paramSymbol, false, true)
            if driver.helpers.isOpenEndRangeType(type, sema: sema, interner: ctx.interner) {
                sema.bindings.markRangeSymbol(paramSymbol)
            }
            if index < signature.valueParameterIsVararg.count,
               signature.valueParameterIsVararg[index],
               primitiveVarargArrayType(
                   elementType: signature.parameterTypes[index],
                   sema: sema,
                   interner: ctx.interner
               ) == nil
            {
                sema.bindings.markCollectionSymbol(paramSymbol)
            }
        }
        let effectiveReceiverType = signature.receiverType ?? ctx.implicitReceiverType
        if let receiverType = effectiveReceiverType {
            let thisName = ctx.interner.intern("this")
            let syntheticThisSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)
            locals[thisName] = (receiverType, syntheticThisSymbol, false, true)
            if driver.helpers.isOpenEndRangeType(receiverType, sema: sema, interner: ctx.interner) {
                sema.bindings.markRangeSymbol(syntheticThisSymbol)
            }
            // A named `context(name: Type)` parameter addresses the same value as
            // the first context receiver: alias it to the receiver parameter so
            // `name.member` resolves identically to `this.member`. Member functions
            // keep their owner as the signature receiver, so the alias only applies
            // to context declarations whose receiver came from the context clause.
            if ctx.enclosingClassSymbol == nil,
               signature.receiverType != nil,
               function.contextReceivers.first?.isContextParameter != true,
               let contextParamName = function.contextReceiverNames.first.flatMap({ $0 })
            {
                locals[contextParamName] = (receiverType, syntheticThisSymbol, false, true)
            }
        }

        let functionScope = FunctionScope(parent: ctx.scope, symbols: sema.symbols)
        for typeParameterSymbol in signature.typeParameterSymbols {
            functionScope.insert(typeParameterSymbol)
        }
        var functionCtx = ctx.copying(
            scope: functionScope,
            implicitReceiverType: effectiveReceiverType,
            lambdaDepth: 0,
            enclosingFunctionReturnType: signature.returnType,
            enclosingFunctionSymbol: symbol,
            enclosingLambdaExprIDs: [],
            currentDeclSymbol: symbol
        )
        functionCtx.isUnitCoercionContext = signature.returnType == sema.types.unitType
        functionCtx.suspensionContext = SuspensionContext(function: symbol)
        if !signature.contextReceiverTypes.isEmpty {
            functionCtx = functionCtx.with(
                contextReceiverTypes: ctx.contextReceiverTypes + signature.contextReceiverTypes
            )
            let syntheticContextSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)
            var contextParameterIndex = 0
            for (index, contextReceiver) in function.contextReceivers.enumerated() {
                guard index < signature.contextReceiverTypes.count else {
                    continue
                }
                let parameterSymbol: SymbolID
                if contextReceiver.isContextParameter {
                    guard signature.contextParameterSymbols.indices.contains(contextParameterIndex) else {
                        continue
                    }
                    parameterSymbol = signature.contextParameterSymbols[contextParameterIndex]
                    contextParameterIndex += 1
                } else {
                    parameterSymbol = syntheticContextSymbol
                }
                guard let name = contextReceiver.name else { continue }
                locals[name] = (
                    signature.contextReceiverTypes[index],
                    parameterSymbol,
                    false,
                    true
                )
            }
        }
        // A member extension's dispatch receiver is distinct from bare `this`.
        // Keep its owner symbol on the tower so nested local nominals capture
        // the enclosing instance rather than the extension receiver.
        if function.receiverType != nil, let owner = ctx.enclosingClassSymbol {
            var outerReceivers = functionCtx.outerReceiverTypes
            for index in outerReceivers.indices where outerReceivers[index].symbol == nil {
                if driver.helpers.nominalSymbol(of: outerReceivers[index].type, types: sema.types) == owner {
                    outerReceivers[index].symbol = owner
                }
            }
            functionCtx = functionCtx.copying(outerReceiverTypes: outerReceivers)
        }
        // An extension function's name doubles as the label of its receiver:
        // `fun Buffer.snapshot() = build { this@snapshot.size }` refers to the
        // extension receiver from inside a lambda with its own receiver.
        if let extensionReceiverType = signature.receiverType {
            functionCtx = functionCtx.withOuterReceiver(
                label: function.name,
                type: extensionReceiverType,
                symbol: SyntheticSymbolScheme.receiverParameterSymbol(for: symbol)
            )
        }
        // Propagate suppression flag so that individual `return` statements inside
        // functions with inferred return types also skip the platform-type warning.
        functionCtx.suppressPlatformReturnWarning = (function.returnType == nil)

        typeCheckParameterDefaultValues(
            function.valueParams,
            signature: signature,
            ctx: functionCtx,
            solver: solver,
            diagnostics: diagnostics,
            baseLocals: baseLocals
        )

        // Bodyless declarations use .unit as their sentinel. Abstract and expect
        // functions declare a contract only, while runtime bridges lower to a
        // symbol outside the Kotlin body via their header metadata.
        let symbolFlags = sema.symbols.symbol(symbol)?.flags ?? []
        let isAbstract = function.body == .unit
            && symbolFlags.contains(.abstractType)
        if isAbstract { return }
        if function.body == .unit {
            // Members of an `expect` class / object / interface (including
            // companion and nested declarations) are contracts as well: the
            // `actual` counterpart supplies the bodies.
            if hasRuntimeBridge || symbolFlags.contains(.expectDeclaration)
                || isNestedInExpectDeclaration(ctx.enclosingClassSymbol, sema: sema)
            {
                return
            }
            diagnostics.error(
                "KSWIFTK-SEMA-0009",
                "Function '\(ctx.interner.resolve(function.name))' must have a body.",
                range: function.range
            )
            return
        }

        // With an inferred return type, `signature.returnType` is only the header
        // placeholder (`Any`, non-null). Using it as the expected type or as a subtype
        // bound would reject legitimately nullable bodies such as `fun g() = f()` where
        // `f(): Any?`, so the body is inferred without an expectation instead.
        let hasInferredReturnType: Bool = {
            guard function.returnType == nil, case .expr = function.body else { return false }
            return true
        }()
        let bodyType = inferFunctionBodyType(
            function.body,
            ctx: functionCtx,
            locals: &locals,
            expectedType: hasInferredReturnType ? nil : signature.returnType
        )
        let inferredBodyType: TypeID
        if hasInferredReturnType,
           case let .expr(bodyExprID, _) = function.body,
           let companionValueType = driver.helpers.retypeClassNameAsCompanionValue(
               bodyExprID,
               currentType: bodyType,
               ast: ctx.ast,
               sema: sema
           )
        {
            // An inferred function returning a bare classifier exposes the
            // companion value, matching local initializer inference.
            inferredBodyType = companionValueType
        } else {
            inferredBodyType = bodyType
        }
        // Expression bodies that are range expressions infer as the scalar element
        // type (the isRangeExpr duck-typing convention), so `fun f(): IntRange = a..b`
        // skips the nominal subtype check like the equivalent local declaration does —
        // but only when the body's actual element type matches IntRange's (KSWIFTK
        // range-element-type gap: `fun f(): LongRange = 1..10` must still be rejected).
        let bodyIsRangeExpr = {
            guard case let .expr(bodyExprID, _) = function.body else { return false }
            return driver.helpers.rangeExprMatchesDeclaredElementType(
                bodyExprID: bodyExprID,
                bodyType: bodyType,
                declaredType: signature.returnType,
                sema: sema,
                interner: ctx.interner
            )
        }()
        if !bodyIsRangeExpr, !hasInferredReturnType {
            driver.emitSubtypeConstraint(
                left: bodyType,
                right: signature.returnType,
                range: function.range,
                solver: solver,
                sema: sema,
                diagnostics: diagnostics,
                // Suppress platform warning when return type is inferred (not explicitly declared):
                // the placeholder anyType is not a user-declared non-null constraint.
                suppressPlatformWarning: function.returnType == nil
            )
        }

        updateInferredReturnType(
            function: function,
            symbol: symbol,
            bodyType: inferredBodyType,
            signature: signature,
            sema: sema,
            ctx: ctx
        )
        recordContractEffects(
            function: function,
            symbol: symbol,
            signature: signature,
            ast: ctx.ast,
            interner: ctx.interner,
            sema: sema,
            scope: functionScope
        )
        recordDirectInlineLambdaInvocation(
            function: function,
            symbol: symbol,
            signature: signature,
            ast: ctx.ast,
            sema: sema
        )
    }

    /// An inline declaration only guarantees that its lambda does not escape;
    /// it may still invoke the lambda zero or several times. Infer the stronger
    /// EXACTLY_ONCE effect only for a body consisting solely of a direct call to
    /// that parameter. Explicit contracts take precedence over this inference.
    private func recordDirectInlineLambdaInvocation(
        function: FunDecl,
        symbol: SymbolID,
        signature: FunctionSignature,
        ast: ASTModule,
        sema: SemaModule
    ) {
        guard function.isInline else { return }
        let bodyExprID: ExprID
        switch function.body {
        case let .expr(expr, _):
            bodyExprID = expr
        case let .block(exprs, _) where exprs.count == 1:
            bodyExprID = exprs[0]
        default:
            return
        }
        guard let bodyExpr = ast.arena.expr(bodyExprID) else { return }
        let invocationExprID: ExprID
        if case let .returnExpr(value?, _, _) = bodyExpr {
            invocationExprID = value
        } else {
            invocationExprID = bodyExprID
        }
        guard let invocation = ast.arena.expr(invocationExprID),
              case let .call(calleeID, _, args, _) = invocation,
              args.isEmpty,
              let callee = ast.arena.expr(calleeID),
              case let .nameRef(calleeName, _) = callee,
              let index = function.valueParams.firstIndex(where: {
                  $0.name == calleeName && !$0.isNoinline
              }),
              signature.valueParameterSymbols.indices.contains(index),
              !sema.symbols.contractCallsInPlaceEffects(for: symbol).contains(where: {
                  $0.parameterSymbol == signature.valueParameterSymbols[index]
              })
        else {
            return
        }
        sema.symbols.addContractCallsInPlaceEffect(
            ContractCallsInPlaceEffect(
                parameterSymbol: signature.valueParameterSymbols[index],
                kind: .exactlyOnce
            ),
            for: symbol
        )
    }

    private func updateInferredReturnType(
        function: FunDecl,
        symbol: SymbolID,
        bodyType: TypeID,
        signature: FunctionSignature,
        sema: SemaModule,
        ctx: TypeInferenceContext
    ) {
        let skipUpdate = if bodyType == sema.types.errorType {
            true
        } else if bodyType == sema.types.nothingType {
            switch function.body {
            case .block: true
            case .expr, .unit: false
            }
        } else {
            false
        }

        if function.returnType == nil, case .expr = function.body, !skipUpdate {
            sema.symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: signature.receiverType,
                    contextReceiverTypes: signature.contextReceiverTypes,
                    contextParameterSymbols: signature.contextParameterSymbols,
                    contextParameterTypes: signature.contextParameterTypes,
                    parameterTypes: signature.parameterTypes,
                    returnType: exposedAnonymousType(bodyType, symbol: symbol, range: function.range, ctx: ctx),
                    isSuspend: signature.isSuspend,
                    canThrow: signature.canThrow,
                    valueParameterSymbols: signature.valueParameterSymbols,
                    valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                    valueParameterIsVararg: signature.valueParameterIsVararg,
                    valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                    hasExplicitInlineParameterMetadata: signature.hasExplicitInlineParameterMetadata,
                    typeParameterSymbols: signature.typeParameterSymbols,
                    reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                    typeParameterUpperBounds: signature.typeParameterUpperBounds,
                    typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
                    classTypeParameterCount: signature.classTypeParameterCount
                ),
                for: symbol
            )
        }
    }

    func precollectContractEffects(function: FunDecl, symbol: SymbolID, ctx: TypeInferenceContext) {
        guard let signature = ctx.sema.symbols.functionSignature(for: symbol) else { return }
        let scope = FunctionScope(parent: ctx.scope, symbols: ctx.sema.symbols)
        for parameter in signature.typeParameterSymbols { scope.insert(parameter) }
        recordContractEffects(
            function: function, symbol: symbol, signature: signature, ast: ctx.ast,
            interner: ctx.interner, sema: ctx.sema, scope: scope
        )
    }

    private func recordContractEffects(
        function: FunDecl,
        symbol: SymbolID,
        signature: FunctionSignature,
        ast: ASTModule,
        interner: StringInterner,
        sema: SemaModule,
        scope: Scope
    ) {
        guard case let .block(expressions, _) = function.body,
              let firstExprID = expressions.first,
              let firstExpr = ast.arena.expr(firstExprID),
              case let .call(calleeExprID, _, args, _) = firstExpr,
              args.count == 1,
              let calleeExpr = ast.arena.expr(calleeExprID),
              case let .nameRef(calleeName, _) = calleeExpr,
              interner.resolve(calleeName) == "contract",
              let lambdaExpr = ast.arena.expr(args[0].expr)
        else {
            return
        }

        let lambdaBodyExprID: ExprID? = switch lambdaExpr {
        case let .lambdaLiteral(_, body, _, _):
            body
        default:
            nil
        }
        guard let lambdaBodyExprID,
              let lambdaBodyExpr = ast.arena.expr(lambdaBodyExprID)
        else {
            return
        }

        let effectExprIDs: [ExprID] = switch lambdaBodyExpr {
        case let .blockExpr(statements, trailingExpr, _):
            statements + (trailingExpr.map { [$0] } ?? [])
        default:
            [lambdaBodyExprID]
        }

        for effectExprID in effectExprIDs {
            recordSingleContractEffect(
                effectExprID: effectExprID,
                function: function,
                symbol: symbol,
                signature: signature,
                ast: ast,
                interner: interner,
                sema: sema,
                scope: scope
            )
        }
    }

    private func recordSingleContractEffect(
        effectExprID: ExprID,
        function: FunDecl,
        symbol: SymbolID,
        signature: FunctionSignature,
        ast: ASTModule,
        interner: StringInterner,
        sema: SemaModule,
        scope: Scope
    ) {
        guard let effectExpr = ast.arena.expr(effectExprID) else { return }

        if case let .memberCall(receiverExprID, impliesName, _, impliesArgs, _) = effectExpr,
           interner.resolve(impliesName) == "implies",
           impliesArgs.count == 1,
           let receiverExpr = ast.arena.expr(receiverExprID),
           case let .call(returnsCalleeExprID, _, returnsArgs, _) = receiverExpr,
           let returnsCalleeExpr = ast.arena.expr(returnsCalleeExprID),
           case let .nameRef(returnsName, _) = returnsCalleeExpr,
           ["returns", "returnsNotNull"].contains(interner.resolve(returnsName))
        {
            // Determine the returns constraint: nil = any return,
            // true/false = when the function returns that specific Boolean.
            let returnsValue: Bool?
            let returnCondition: ContractReturnCondition
            if interner.resolve(returnsName) == "returnsNotNull", returnsArgs.isEmpty {
                returnsValue = nil
                returnCondition = .returnsNotNull
            } else if interner.resolve(returnsName) == "returns", returnsArgs.isEmpty {
                returnsValue = nil
                returnCondition = .normally
                if sema.symbols.contractReturnsEffect(for: symbol) == nil {
                    sema.symbols.setContractReturnsEffect(
                        .returnsNormally,
                        for: symbol
                    )
                }
            } else if returnsArgs.count == 1,
                      let boolValue = extractBooleanLiteral(returnsArgs[0].expr, ast: ast, interner: interner)
            {
                returnsValue = boolValue
                returnCondition = boolValue ? .returnsTrue : .returnsFalse
            } else if returnsArgs.count == 1,
                      isNullLiteralExpr(returnsArgs[0].expr, ast: ast)
            {
                returnsValue = nil
                returnCondition = .returnsNull
            } else {
                return
            }
            recordReturnsImpliesEffect(
                impliesArgs: impliesArgs,
                returnsValue: returnsValue,
                returnCondition: returnCondition,
                function: function,
                symbol: symbol,
                signature: signature,
                ast: ast,
                interner: interner,
                sema: sema,
                scope: scope
            )
            return
        }

        if case let .call(returnsCalleeExprID, _, returnsArgs, _) = effectExpr,
           let returnsCalleeExpr = ast.arena.expr(returnsCalleeExprID),
           case let .nameRef(returnsName, _) = returnsCalleeExpr,
           interner.resolve(returnsName) == "returns"
        {
            if returnsArgs.isEmpty {
                // A more specific effect (e.g. `returns(true)`) should not be
                // overwritten by a bare `returns()` when multiple effects appear
                // in the same block.
                if sema.symbols.contractReturnsEffect(for: symbol) == nil {
                    sema.symbols.setContractReturnsEffect(
                        .returnsNormally,
                        for: symbol
                    )
                }
            } else if returnsArgs.count == 1 {
                // Only valid when the function's return type is Boolean; ignore
                // the effect for non-Boolean-returning functions to prevent
                // encoding an invalid contract.
                guard signature.returnType == sema.types.booleanType else { return }
                if let boolValue = extractBooleanLiteral(returnsArgs[0].expr, ast: ast, interner: interner) {
                    // Heuristic: find the first Boolean parameter for smart-cast binding.
                    let conditionIndex = signature.parameterTypes.firstIndex { typeID in
                        typeID == sema.types.booleanType
                    }
                    sema.symbols.setContractReturnsEffect(
                        .returnsBooleanValue(
                            expectedValue: boolValue,
                            conditionParameterIndex: conditionIndex
                        ),
                        for: symbol
                    )
                }
            }
            return
        }

        if case let .call(calleeExprID, _, callArgs, _) = effectExpr,
           let calleeExpr = ast.arena.expr(calleeExprID),
           case let .nameRef(calleeName, _) = calleeExpr,
           interner.resolve(calleeName) == "callsInPlace",
           callArgs.count >= 1, callArgs.count <= 2,
           let firstArgExpr = ast.arena.expr(callArgs[0].expr),
           case let .nameRef(lambdaParamName, _) = firstArgExpr
        {
            var invocationKind: InvocationKind = .unknown
            if callArgs.count == 2 {
                invocationKind = resolveInvocationKindArg(
                    callArgs[1].expr, ast: ast, interner: interner
                ) ?? .unknown
            }
            if let parameterIndex = function.valueParams.firstIndex(where: { $0.name == lambdaParamName }),
               parameterIndex < signature.valueParameterSymbols.count
            {
                sema.symbols.addContractCallsInPlaceEffect(
                    ContractCallsInPlaceEffect(
                        parameterSymbol: signature.valueParameterSymbols[parameterIndex],
                        kind: invocationKind
                    ),
                    for: symbol
                )
            }
            return
        }

        if case let .call(calleeExprID, _, returnNNArgs, _) = effectExpr,
           let calleeExpr = ast.arena.expr(calleeExprID),
           case let .nameRef(calleeName, _) = calleeExpr,
           interner.resolve(calleeName) == "returnsNotNull",
           returnNNArgs.isEmpty
        {
            sema.symbols.setContractReturnsNotNull(for: symbol)
            return
        }
    }

    private func recordReturnsImpliesEffect(
        impliesArgs: [CallArgument],
        returnsValue: Bool?,
        returnCondition: ContractReturnCondition,
        function: FunDecl,
        symbol: SymbolID,
        signature: FunctionSignature,
        ast: ASTModule,
        interner: StringInterner,
        sema: SemaModule,
        scope: Scope
    ) {
        guard let conditionExpr = ast.arena.expr(impliesArgs[0].expr) else {
            return
        }

        // Every conjunct is guaranteed by the same return condition. An OR
        // does not guarantee either operand independently.
        if case let .binary(.logicalAnd, lhs, rhs, _) = conditionExpr {
            for operand in [lhs, rhs] {
                recordReturnsImpliesEffect(
                    impliesArgs: [CallArgument(expr: operand)], returnsValue: returnsValue,
                    returnCondition: returnCondition, function: function, symbol: symbol,
                    signature: signature, ast: ast, interner: interner, sema: sema, scope: scope
                )
            }
            return
        }

        // Record the type in the declaration scope, not the caller's scope.
        if case let .isCheck(operand, typeRef, negated, _) = conditionExpr,
           !negated
        {
            let target: ContractImplicationTarget
            if case let .nameRef(name, _) = ast.arena.expr(operand),
               let index = function.valueParams.firstIndex(where: { $0.name == name })
            {
                target = .valueParameter(index)
            } else if case let .thisRef(label, _) = ast.arena.expr(operand),
                      label == function.name,
                      function.receiverType != nil,
                      signature.receiverType != nil
            {
                target = .extensionReceiver
            } else {
                return
            }
            let targetType = driver.helpers.resolveTypeRef(
                typeRef, ast: ast, sema: sema, interner: interner, scope: scope
            )
            guard targetType != sema.types.errorType else { return }
            sema.symbols.addContractImplicationEffect(
                ContractImplicationEffect(target: target, returnCondition: returnCondition,
                                          argumentCondition: .isType, targetType: targetType),
                for: symbol
            )
            return
        }

        if case let .binary(.notEqual, lhsExprID, rhsExprID, _) = conditionExpr {
            let parameterName: InternedString? = if let lhsExpr = ast.arena.expr(lhsExprID),
                                                    case let .nameRef(name, _) = lhsExpr,
                                                    isNullLiteralExpr(rhsExprID, ast: ast)
            {
                name
            } else if let rhsExpr = ast.arena.expr(rhsExprID),
                      case let .nameRef(name, _) = rhsExpr,
                      isNullLiteralExpr(lhsExprID, ast: ast)
            {
                name
            } else {
                nil
            }
            guard let parameterName,
                  let parameterIndex = function.valueParams.firstIndex(where: { $0.name == parameterName }),
                  parameterIndex < signature.valueParameterSymbols.count
            else {
                return
            }
            // For bare `returns() implies (param != null)`, also record the legacy
            // ContractNonNullEffect for backward compatibility.
            sema.symbols.addContractImplicationEffect(
                ContractImplicationEffect(parameterIndex: parameterIndex, returnCondition: returnCondition, argumentCondition: .nonNull),
                for: symbol
            )
            if returnCondition == .normally {
                sema.symbols.setContractNonNullEffect(
                    ContractNonNullEffect(
                        parameterSymbol: signature.valueParameterSymbols[parameterIndex],
                        appliesOnAnyReturn: true
                    ),
                    for: symbol
                )
            }
            return
        }

        // A negated Boolean parameter guarantees the argument's false branch.
        // The legacy ContractConditionEffect only represents true conditions.
        if case let .unaryExpr(.not, operandID, _) = conditionExpr,
           case let .nameRef(paramName, _) = ast.arena.expr(operandID),
           let parameterIndex = function.valueParams.firstIndex(where: { $0.name == paramName }),
           parameterIndex < signature.parameterTypes.count,
           signature.parameterTypes[parameterIndex] == sema.types.booleanType
        {
            sema.symbols.addContractImplicationEffect(
                ContractImplicationEffect(parameterIndex: parameterIndex, returnCondition: returnCondition, argumentCondition: .booleanFalse),
                for: symbol
            )
            return
        }

        // `returns() implies param` where param is Boolean.
        // This means the argument expression passed for this parameter is guaranteed
        // true after normal return, enabling smart casts on the call-site expression.
        if case let .nameRef(paramName, _) = conditionExpr,
           let parameterIndex = function.valueParams.firstIndex(where: { $0.name == paramName }),
           parameterIndex < signature.parameterTypes.count,
           signature.parameterTypes[parameterIndex] == sema.types.booleanType
        {
            sema.symbols.addContractImplicationEffect(
                ContractImplicationEffect(parameterIndex: parameterIndex, returnCondition: returnCondition, argumentCondition: .booleanTrue),
                for: symbol
            )
            guard returnCondition != .returnsNotNull, returnCondition != .returnsNull else { return }
            sema.symbols.setContractConditionEffect(
                ContractConditionEffect(
                    conditionParameterIndex: parameterIndex,
                    returnsValue: returnsValue
                ),
                for: symbol
            )
        }
    }

    /// The AST represents `InvocationKind.EXACTLY_ONCE` as a zero-arg `.memberCall` or
    /// as a plain `.nameRef` when already resolved.
    private func resolveInvocationKindArg(
        _ exprID: ExprID,
        ast: ASTModule,
        interner: StringInterner
    ) -> InvocationKind? {
        guard let expr = ast.arena.expr(exprID) else { return nil }
        if case let .memberCall(receiverExprID, memberName, _, memberArgs, _) = expr,
           memberArgs.isEmpty,
           let receiverExpr = ast.arena.expr(receiverExprID),
           case let .nameRef(receiverName, _) = receiverExpr,
           interner.resolve(receiverName) == "InvocationKind"
        {
            return InvocationKind(rawValue: interner.resolve(memberName))
        }
        if case let .nameRef(name, _) = expr {
            return InvocationKind(rawValue: interner.resolve(name))
        }
        return nil
    }

    private func extractBooleanLiteral(
        _ exprID: ExprID,
        ast: ASTModule,
        interner: StringInterner
    ) -> Bool? {
        guard let expr = ast.arena.expr(exprID) else { return nil }
        if case let .nameRef(name, _) = expr {
            let resolved = interner.resolve(name)
            if resolved == "true" { return true }
            if resolved == "false" { return false }
        }
        if case let .boolLiteral(value, _) = expr {
            return value
        }
        return nil
    }

    private func isNullLiteralExpr(
        _ exprID: ExprID,
        ast: ASTModule
    ) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }
        if case .nullLiteral = expr {
            return true
        }
        return false
    }

    /// A member declared without a body inside an `expect` class/object/interface
    /// is a contract, not a missing body — the `actual` counterpart supplies the
    /// implementation.
    private func isNestedInExpectDeclaration(_ classSymbol: SymbolID?, sema: SemaModule) -> Bool {
        var current: SymbolID? = classSymbol
        var guardCount = 0
        while let symbolID = current, guardCount < 64 {
            guardCount += 1
            if let symbol = sema.symbols.symbol(symbolID), symbol.flags.contains(.expectDeclaration) {
                return true
            }
            current = sema.symbols.parentSymbol(for: symbolID)
        }
        return false
    }
}
