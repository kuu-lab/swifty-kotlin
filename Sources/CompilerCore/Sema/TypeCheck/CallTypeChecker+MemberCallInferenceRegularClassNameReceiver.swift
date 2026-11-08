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

        // KUU-3237: a typealias qualifier cannot reach nested classifiers
        // (`A2.Nested`, `A2.Inner`, `A2.Companion` are all unresolved in
        // Kotlin), but companion members and enum entries stay visible
        // through the alias, so only `.object` member values are skipped.
        let receiverViaTypeAlias = receiverQualifierIsTypeAlias(
            receiverID: request.receiverID, ctx: request.ctx
        )
        if isClassNameReceiver,
           request.args.isEmpty,
           let ownerSymbol = classNameReceiverNominalSymbol,
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: ownerSymbol,
               memberName: request.calleeName,
               sema: request.sema
           ),
           !(receiverViaTypeAlias
               && request.sema.symbols.symbol(staticMember.symbol)?.kind == .object),
           // An explicit `()` on a nested `object` is a function invocation,
           // not a value read — fall through so `invoke` can dispatch
           // (KUU-3662).
           !(request.ast.arena.isExplicitCall(request.id)
               && request.sema.symbols.symbol(staticMember.symbol)?.kind == .object)
        {
            if let memberSymbol = request.sema.symbols.symbol(staticMember.symbol),
               !request.ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: request.ctx.currentFileID,
                   enclosingClass: request.ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(for: memberSymbol, name: request.interner.resolve(request.calleeName), range: request.range, diagnostics: request.ctx.sema.diagnostics)
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
            request.sema.bindings.bindIdentifier(request.id, symbol: staticMember.symbol)
            request.sema.bindings.bindExprType(request.id, type: staticMember.type)
            return staticMember.type
        }

        if isClassNameReceiver,
           let ownerSymbol = classNameReceiverNominalSymbol,
           let owner = request.sema.symbols.symbol(ownerSymbol)
        {
            let staticMethodFQName = owner.fqName + [request.calleeName]
            var staticMethodCandidates = request.sema.symbols.lookupAll(fqName: staticMethodFQName).filter { candidate in
                guard let symbol = request.sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      request.sema.symbols.parentSymbol(for: candidate) == ownerSymbol,
                      let signature = request.sema.symbols.functionSignature(for: candidate)
                else {
                    return false
                }
                return signature.receiverType == nil
            }
            if staticMethodCandidates.isEmpty {
                staticMethodCandidates = request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                    guard let symbol = request.sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          request.sema.symbols.parentSymbol(for: candidate) == ownerSymbol,
                          let signature = request.sema.symbols.functionSignature(for: candidate)
                    else {
                        return false
                    }
                    return signature.receiverType == nil
                }
            }
            if !staticMethodCandidates.isEmpty {
                let (visibleStaticMethods, invisibleStaticMethods) = request.ctx.filterByVisibility(staticMethodCandidates)
                if let firstInvisible = invisibleStaticMethods.first {
                    driver.helpers.emitVisibilityError(
                        for: firstInvisible,
                        name: request.interner.resolve(request.calleeName),
                        range: request.range,
                        diagnostics: request.ctx.sema.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
                if !visibleStaticMethods.isEmpty {
                    let callArgs = zip(request.args, argTypes).map { arg, type in
                        CallArg.source(arg, type: type, callRange: request.range, ast: request.ctx.ast)
                    }
                    let call = CallExpr(
                        range: request.range,
                        calleeName: request.calleeName,
                        args: callArgs,
                        explicitTypeArgs: request.explicitTypeArgs
                    )
                    let resolved = request.ctx.resolver.resolveCall(
                        candidates: visibleStaticMethods,
                        call: call,
                        expectedType: request.expectedType,
                        ctx: request.sema
                    )
                    if let diagnostic = resolved.diagnostic {
                        request.ctx.sema.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                    }
                    if let chosen = resolved.chosenCallee,
                       let signature = request.sema.symbols.functionSignature(for: chosen)
                    {
                        bindResolvedFunctionValueSamArguments(request.id, chosen: chosen, resolved: resolved, sema: request.sema)
                        request.sema.bindings.bindCall(
                            request.id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: resolved.substitutedTypeArguments
                                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                    .map(\.value),
                                parameterMapping: resolved.parameterMapping
                            )
                        )
                        request.sema.bindings.bindCallableTarget(request.id, target: .symbol(chosen))
                        request.sema.bindings.bindIdentifier(request.id, symbol: chosen)
                        let typeVarBySymbol = request.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                        let resultType = request.sema.types.substituteTypeParameters(
                            in: signature.returnType,
                            substitution: resolved.substitutedTypeArguments,
                            typeVarBySymbol: typeVarBySymbol
                        )
                        request.sema.bindings.bindExprType(request.id, type: resultType)
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
                let ownerType = request.sema.types.make(.classType(ClassType(
                    classSymbol: ownerSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                if request.args.isEmpty,
                   request.sema.bundledIndex.contains(
                       ownerFQName: owner.fqName,
                       name: request.calleeName,
                       arity: 0
                   ),
                   let extensionPropertyType = resolveExtensionPropertyGetter(
                       id: request.id,
                       calleeName: request.calleeName,
                       range: request.range,
                       receiverType: ownerType,
                       expectedType: request.expectedType,
                       ctx: request.ctx
                   )
                {
                    request.sema.bindings.bindExprType(request.receiverID, type: ownerType)
                    request.sema.bindings.bindExprType(request.id, type: extensionPropertyType)
                    return extensionPropertyType
                }

                var ownerExtensionCandidates = request.ctx.cachedScopeLookup(request.calleeName).filter { candidate in
                    guard let symbol = request.sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          let signature = request.sema.symbols.functionSignature(for: candidate),
                          let receiver = signature.receiverType
                    else {
                        return false
                    }
                    guard request.sema.bundledIndex.contains(
                        ownerFQName: owner.fqName,
                        name: request.calleeName,
                        arity: signature.parameterTypes.count
                    ) else {
                        return false
                    }
                    return extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: ownerType,
                        declaredReceiver: receiver,
                        sema: request.sema
                    )
                }
                if ownerExtensionCandidates.isEmpty {
                    ownerExtensionCandidates = request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                        guard let symbol = request.sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              symbol.flags.contains(.synthetic),
                              let signature = request.sema.symbols.functionSignature(for: candidate),
                              let receiver = signature.receiverType
                        else {
                            return false
                        }
                        guard isUnsignedRandomExtensionVisible(symbol, named: request.calleeName, ctx: request.ctx) else {
                            return false
                        }
                        guard request.sema.bundledIndex.contains(
                            ownerFQName: owner.fqName,
                            name: request.calleeName,
                            arity: signature.parameterTypes.count
                        ) else {
                            return false
                        }
                        return extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: ownerType,
                            declaredReceiver: receiver,
                            sema: request.sema
                        )
                    }
                }
                let (visibleOwnerExtensions, invisibleOwnerExtensions) = request.ctx.filterByVisibility(ownerExtensionCandidates)
                if let firstInvisible = invisibleOwnerExtensions.first {
                    driver.helpers.emitVisibilityError(
                        for: firstInvisible,
                        name: request.interner.resolve(request.calleeName),
                        range: request.range,
                        diagnostics: request.ctx.sema.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
                if !visibleOwnerExtensions.isEmpty {
                    let callArgs = zip(request.args, argTypes).map { arg, type in
                        CallArg.source(arg, type: type, callRange: request.range, ast: request.ctx.ast)
                    }
                    let call = CallExpr(
                        range: request.range,
                        calleeName: request.calleeName,
                        args: callArgs,
                        explicitTypeArgs: request.explicitTypeArgs
                    )
                    let resolved = request.ctx.resolver.resolveCall(
                        candidates: visibleOwnerExtensions,
                        call: call,
                        expectedType: request.expectedType,
                        implicitReceiverType: ownerType,
                        ctx: request.sema
                    )
                    if let diagnostic = resolved.diagnostic {
                        request.ctx.sema.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                    }
                    if let chosen = resolved.chosenCallee,
                       let signature = request.sema.symbols.functionSignature(for: chosen)
                    {
                        request.sema.bindings.bindCall(
                            request.id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: resolved.substitutedTypeArguments
                                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                    .map(\.value),
                                parameterMapping: resolved.parameterMapping
                            )
                        )
                        request.sema.bindings.bindCallableTarget(request.id, target: .symbol(chosen))
                        request.sema.bindings.bindIdentifier(request.id, symbol: chosen)
                        let typeVarBySymbol = request.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                        let resultType = request.sema.types.substituteTypeParameters(
                            in: signature.returnType,
                            substitution: resolved.substitutedTypeArguments,
                            typeVarBySymbol: typeVarBySymbol
                        )
                        driver.helpers.checkDeprecation(
                            for: chosen,
                            sema: request.sema,
                            interner: request.interner,
                            range: request.range,
                            diagnostics: request.ctx.sema.diagnostics
                        )
                        driver.helpers.checkOptIn(
                            for: chosen,
                            ctx: request.ctx,
                            range: request.range,
                            diagnostics: request.ctx.sema.diagnostics
                        )
                        request.sema.bindings.bindExprType(request.receiverID, type: ownerType)
                        request.sema.bindings.bindExprType(request.id, type: resultType)
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
            switch request.ast.arena.expr(request.receiverID) {
            case .nameRef:
                break
            case .memberCall where !request.ast.arena.isExplicitCall(request.receiverID):
                break
            default:
                return nil
            }
            guard let symbolID = request.sema.bindings.identifierSymbol(for: request.receiverID),
                  request.sema.symbols.symbol(symbolID)?.kind == .object
            else {
                return nil
            }
            return symbolID
        }()
        if let ownerSymbol = nestedClassifierOwnerSymbol,
           let owner = request.sema.symbols.symbol(ownerSymbol)
        {
            let nestedOwnerFQName = owner.fqName + [request.calleeName]
            var nestedOwnerSymbols = request.sema.symbols.lookupAll(fqName: nestedOwnerFQName).filter { candidate in
                guard let symbol = request.sema.symbols.symbol(candidate) else {
                    return false
                }
                guard request.sema.symbols.parentSymbol(for: candidate) == ownerSymbol else {
                    return false
                }
                switch symbol.kind {
                case .class, .interface, .enumClass, .object, .annotationClass, .typeAlias:
                    return true
                default:
                    return false
                }
            }
            if nestedOwnerSymbols.isEmpty {
                let shortNameNestedOwners = request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                    guard let symbol = request.sema.symbols.symbol(candidate) else {
                        return false
                    }
                    guard request.sema.symbols.parentSymbol(for: candidate) == ownerSymbol else {
                        return false
                    }
                    switch symbol.kind {
                    case .class, .interface, .enumClass, .object, .annotationClass, .typeAlias:
                        return true
                    default:
                        return false
                    }
                }
                if shortNameNestedOwners.count == 1 {
                    nestedOwnerSymbols = shortNameNestedOwners
                }
            }
            // A nested typealias qualifier (`Owner.Alias`) resolves through
            // its expanded classifier: `Owner.Alias(...)` calls the
            // underlying constructor and a bare `Owner.Alias` is a
            // classifier reference to the expansion (KUU-3840).
            var nestedAliasContext: TypeAliasConstructorContext?
            var nestedAliasExpandedOwner: SymbolID?
            if let aliasSymbol = nestedOwnerSymbols.first(where: {
                request.sema.symbols.symbol($0)?.kind == .typeAlias
            }) {
                if let aliasSemantic = request.sema.symbols.symbol(aliasSymbol),
                   !request.ctx.visibilityChecker.isAccessible(
                       aliasSemantic,
                       fromFile: request.ctx.currentFileID,
                       enclosingClass: request.ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: aliasSemantic,
                        name: request.interner.resolve(request.calleeName),
                        range: request.range,
                        diagnostics: request.ctx.sema.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
                let aliasTypeParameters = request.sema.symbols.typeAliasTypeParameters(for: aliasSymbol)
                if !request.explicitTypeArgs.isEmpty, request.explicitTypeArgs.count != aliasTypeParameters.count {
                    request.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0062",
                        "Type argument count mismatch: expected \(aliasTypeParameters.count) but got \(request.explicitTypeArgs.count).",
                        range: request.range
                    )
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
                let aliasTypeArgs: [TypeArg] = if request.explicitTypeArgs.isEmpty {
                    aliasTypeParameters.map {
                        .invariant(request.sema.types.make(.typeParam(TypeParamType(
                            symbol: $0, nullability: .nonNull
                        ))))
                    }
                } else {
                    request.explicitTypeArgs.enumerated().map { index, type in
                        let resolved = type == TypeID.invalid
                            ? request.sema.types.make(.typeParam(TypeParamType(
                                symbol: aliasTypeParameters[index], nullability: .nonNull
                            )))
                            : type
                        return .invariant(resolved)
                    }
                }
                if let expanded = driver.helpers.expandTypeAlias(
                    aliasSymbol,
                    typeArgs: aliasTypeArgs,
                    sema: request.sema,
                    visited: [],
                    depth: 0,
                    diagnostics: request.sema.diagnostics
                ), case let .classType(aliasTarget) = request.sema.types.kind(of: expanded) {
                    let expandedOwner = request.sema.symbols.actualSymbol(for: aliasTarget.classSymbol)
                        ?? aliasTarget.classSymbol
                    nestedAliasExpandedOwner = expandedOwner
                    if request.args.isEmpty, !request.ast.arena.isExplicitCall(request.id) {
                        // Bind the expanded classifier, not the alias:
                        // lowering treats the qualifier exactly like a
                        // direct `Owner.Nested` spelling (KUU-3840).
                        request.sema.bindings.bindIdentifier(request.id, symbol: expandedOwner)
                        request.sema.bindings.bindExprType(request.id, type: expanded)
                        return expanded
                    }
                    if request.sema.symbols.symbol(expandedOwner)?.flags.contains(.innerClass) == true {
                        // `Owner.Alias()` cannot supply the enclosing
                        // instance an inner-class constructor needs — the
                        // same error Kotlin reports for `Owner.Inner()`.
                        let innerName = request.sema.symbols.symbol(expandedOwner)
                            .map { request.interner.resolve($0.name) } ?? request.interner.resolve(request.calleeName)
                        request.ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-0437",
                            "constructor of the inner class '\(innerName)' can only be called with a receiver of the containing class.",
                            range: request.range
                        )
                        return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                    }
                    // `typeAliasConstructorSignature` reads the combined
                    // argument list from `args`, so keep the enclosing +
                    // own arguments flattened there (KUU-3840).
                    let constructorType = request.sema.types.make(.classType(ClassType(
                        classSymbol: expandedOwner,
                        args: request.sema.types.allTypeArguments(for: aliasTarget),
                        nullability: .nonNull
                    )))
                    nestedAliasContext = TypeAliasConstructorContext(
                        typeParameterSymbols: aliasTypeParameters,
                        expandedType: constructorType,
                        typeAliasSymbol: aliasSymbol
                    )
                }
            }
            if let nestedOwner = nestedOwnerSymbols.first,
               let samType = inferQualifiedNestedClassifierSamConstruction(
                   request.id,
                   calleeName: request.calleeName,
                   classifierSymbol: nestedAliasExpandedOwner ?? nestedOwner,
                   args: request.args,
                   argTypes: argTypes,
                   ctx: request.ctx,
                   locals: &locals,
                   expectedType: request.expectedType,
                   explicitTypeArgs: request.explicitTypeArgs
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
            if request.args.isEmpty, let nestedOwner = nestedOwnerSymbols.first,
               let nestedOwnerKind = request.sema.symbols.symbol(nestedOwner)?.kind,
               nestedOwnerKind == .enumClass
                   || ((nestedOwnerKind == .class || nestedOwnerKind == .object
                        || nestedOwnerKind == .interface || nestedOwnerKind == .annotationClass)
                       && !request.ast.arena.isExplicitCall(request.id))
            {
                if let nestedSymbol = request.sema.symbols.symbol(nestedOwner),
                   !request.ctx.visibilityChecker.isAccessible(
                       nestedSymbol,
                       fromFile: request.ctx.currentFileID,
                       enclosingClass: request.ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: nestedSymbol, name: request.interner.resolve(request.calleeName),
                        range: request.range, diagnostics: request.ctx.sema.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
                let nestedType = request.sema.types.make(.classType(ClassType(
                    classSymbol: nestedOwner,
                    args: [],
                    nullability: .nonNull
                )))
                request.sema.bindings.bindIdentifier(request.id, symbol: nestedOwner)
                request.sema.bindings.bindExprType(request.id, type: nestedType)
                return nestedType
            }
            // `Outer.I()` reaches here as a classifier qualifier — there is
            // no containing-class instance on the receiver side, so an inner
            // class constructor cannot be called this way. Object qualifiers
            // only reach this path through the value binding above and are
            // already instances.
            if isClassNameReceiver,
               let nestedOwner = nestedOwnerSymbols.first,
               request.sema.symbols.symbol(nestedOwner)?.flags.contains(.innerClass) == true
            {
                let innerName = request.sema.symbols.symbol(nestedOwner)
                    .map { request.interner.resolve($0.name) } ?? request.interner.resolve(request.calleeName)
                request.ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0437",
                    "constructor of the inner class '\(innerName)' can only be called with a receiver of the containing class.",
                    range: request.range
                )
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
            let nestedCtorFQName = owner.fqName + [request.calleeName, request.knownNames.initName]
            var nestedCtorCandidates = request.sema.symbols.lookupAll(fqName: nestedCtorFQName).filter { candidate in
                guard let symbol = request.sema.symbols.symbol(candidate) else {
                    return false
                }
                return symbol.kind == .constructor
            }
            if nestedCtorCandidates.isEmpty {
                if !nestedOwnerSymbols.isEmpty {
                    let initName = request.knownNames.initName
                    nestedCtorCandidates = request.sema.symbols.lookupByShortName(initName).filter { candidate in
                        guard let symbol = request.sema.symbols.symbol(candidate),
                              symbol.kind == .constructor
                        else {
                            return false
                        }
                        guard let parent = request.sema.symbols.parentSymbol(for: candidate) else {
                            return false
                        }
                        return nestedOwnerSymbols.contains(parent)
                    }
                }
            }
            if nestedCtorCandidates.isEmpty,
               let expandedOwner = nestedAliasExpandedOwner,
               let expandedOwnerSymbol = request.sema.symbols.symbol(expandedOwner)
            {
                // `Owner.Alias(...)` calls the expanded classifier's
                // constructors, stored under the underlying FQ name rather
                // than the alias's (KUU-3840).
                nestedCtorCandidates = request.sema.symbols.lookupAll(
                    fqName: expandedOwnerSymbol.fqName + [request.knownNames.initName]
                ).filter { candidate in
                    request.sema.symbols.symbol(candidate)?.kind == .constructor
                        && request.sema.symbols.parentSymbol(for: candidate) == expandedOwner
                }
            }
            if !nestedCtorCandidates.isEmpty {
                let hasFactoryFunctionCandidates: Bool = {
                    let factoryOwner = owner.kind == .object
                        ? ownerSymbol : request.sema.symbols.companionObjectSymbol(for: ownerSymbol)
                    guard let factoryOwner else {
                        return false
                    }
                    let factoryType = request.sema.types.make(.classType(ClassType(
                        classSymbol: factoryOwner,
                        args: [],
                        nullability: .nonNull
                    )))
                    if !driver.helpers.collectMemberFunctionCandidates(
                        named: request.calleeName,
                        receiverType: factoryType,
                        sema: request.sema,
                        interner: request.interner
                    ).isEmpty {
                        return true
                    }
                    // Mirror ordinary object/companion lookup's scoped and
                    // imported-library extension fallbacks.
                    let extensionCandidates = request.ctx.cachedScopeLookup(request.calleeName)
                        + request.sema.symbols.lookupByShortName(request.calleeName).filter {
                            request.sema.symbols.symbol($0)?.flags.contains(.synthetic) == true
                        }
                    return extensionCandidates.contains { candidate in
                        guard request.sema.symbols.symbol(candidate)?.kind == .function,
                              let receiver = request.sema.symbols.functionSignature(for: candidate)?.receiverType
                        else {
                            return false
                        }
                        return extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: factoryType,
                            declaredReceiver: receiver,
                            sema: request.sema
                        )
                    }
                }()
                let (visibleNested, invisibleNested) = request.ctx.filterByVisibility(nestedCtorCandidates)
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
                           classifierSymbol: nestedAliasExpandedOwner ?? nestedOwner,
                           argTypes: argTypes,
                           locals: &locals
                       )
                    {
                        return invokeType
                    }
                    driver.helpers.emitVisibilityError(for: firstInvisible, name: request.interner.resolve(request.calleeName), range: request.range, diagnostics: request.ctx.sema.diagnostics)
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
                if !visibleNested.isEmpty {
                    if request.args.isEmpty, request.explicitTypeArgs.isEmpty {
                        let zeroArgNested = visibleNested.first { candidate in
                            guard let signature = request.sema.symbols.functionSignature(for: candidate) else {
                                return false
                            }
                            return signature.parameterTypes.isEmpty && signature.typeParameterSymbols.isEmpty
                        }
                        if let zeroArgNested,
                           let signature = request.sema.symbols.functionSignature(for: zeroArgNested)
                        {
                            request.sema.bindings.bindCall(
                                request.id,
                                binding: CallBinding(
                                    chosenCallee: zeroArgNested,
                                    substitutedTypeArguments: [],
                                    parameterMapping: [:]
                                )
                            )
                            let resultType = signature.returnType
                            if request.ast.arena.isExplicitCall(request.id),
                               let nestedOwner = request.sema.symbols.parentSymbol(for: zeroArgNested),
                               let nestedOwnerSymbol = request.sema.symbols.symbol(nestedOwner),
                               (nestedOwnerSymbol.kind == .class || nestedOwnerSymbol.kind == .annotationClass),
                               !nestedOwnerSymbol.flags.contains(.innerClass)
                            {
                                request.sema.bindings.markTypeQualifiedConstructorCallExpr(request.id)
                            }
                            request.sema.bindings.bindExprType(request.id, type: resultType)
                            return resultType
                        }
                    }
                    // Nested constructors return before ordinary member-call
                    // preparation, so infer lambdas and callable references
                    // against their constructor parameter types here too.
                    var cachedNonLambdaArgTypes: [Int: TypeID] = [:]
                    for (index, argument) in request.args.enumerated() {
                        if request.ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                            continue
                        }
                        cachedNonLambdaArgTypes[index] = argTypes[index]
                    }
                    var expectedTypeOverrides: [Int: TypeID] = [:]
                    var lambdaContextOverrides: [Int: TypeInferenceContext] = [:]
                    let argumentDiagnosticsCheckpoint = request.sema.diagnostics.checkpoint()
                    let originalArgumentLocals = locals
                    let expectedTypeHintIndices = prepareCallExprArgumentContexts(
                        args: request.args,
                        callRange: request.range,
                        ctx: request.ctx,
                        expectedType: request.expectedType,
                        explicitTypeArgs: request.explicitTypeArgs,
                        calleeName: request.calleeName,
                        candidates: visibleNested,
                        locals: locals,
                        withContextExpectedLambdaType: nil,
                        expectedTypeOverrides: &expectedTypeOverrides,
                        lambdaContextOverrides: &lambdaContextOverrides
                    )
                    let preparedArgs = prepareCallArguments(
                        args: request.args,
                        callRange: request.range,
                        candidates: visibleNested,
                        preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
                        expectedTypeOverrides: expectedTypeOverrides,
                        expectedTypeHintIndices: expectedTypeHintIndices,
                        contextualCallResultType: request.ctx.isCallResultDiscarded && request.ctx.isUnitCoercionContext
                            ? request.sema.types.unitType : request.expectedType,
                        explicitTypeArgs: request.explicitTypeArgs,
                        lambdaContextOverrides: lambdaContextOverrides,
                        ctx: request.ctx,
                        locals: &locals
                    )
                    let resolved = resolveCallRespectingLambdaReturnType(
                        candidates: visibleNested,
                        args: request.args,
                        argTypes: preparedArgs.argTypes,
                        range: request.range,
                        calleeName: request.calleeName,
                        explicitTypeArgs: request.explicitTypeArgs,
                        typeAliasConstructor: nestedAliasContext,
                        expectedType: request.expectedType,
                        implicitReceiverType: nil,
                        lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                        inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                        blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                        hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                        ctx: request.ctx
                    )
                    if let diagnostic = resolved.diagnostic {
                        if request.ctx.allowsLiftedCallExpectedTypeHints, !expectedTypeHintIndices.isEmpty {
                            request.sema.diagnostics.rollback(to: argumentDiagnosticsCheckpoint)
                            locals = originalArgumentLocals
                            var retryContext = request.ctx
                            retryContext.allowsLiftedCallExpectedTypeHints = false
                            // Member calls reuse already-bound argument types.
                            // Refresh speculative arguments before the retry
                            // so Box<Any> cannot survive a natural Box<Int> pass.
                            for index in expectedTypeHintIndices.sorted() {
                                guard isInferableNestedCallExpr(request.args[index].expr, ast: request.ast) else { continue }
                                _ = driver.inferExpr(request.args[index].expr, ctx: retryContext, locals: &locals)
                            }
                            return driver.inferExpr(request.id, ctx: retryContext, locals: &locals, expectedType: request.expectedType)
                        }
                        // Kotlin gives applicable nested constructors priority
                        // for Owner.Name(...), but retries object/companion functions
                        // when no constructor is applicable. Keep constructor
                        // ambiguity instead of silently choosing a factory.
                        // A result-type mismatch does not make an otherwise
                        // applicable constructor yield to a companion function.
                        let ctorInapplicable = diagnostic.code != "KSWIFTK-SEMA-0003"
                            && (request.expectedType == nil || request.ctx.resolver.probeCall(
                                candidates: visibleNested,
                                call: CallExpr(
                                    range: request.range,
                                    calleeName: request.calleeName,
                                    args: zip(request.args, preparedArgs.argTypes).map { argument, type in
                                        CallArg(
                                            label: argument.label,
                                            isSpread: argument.isSpread,
                                            type: type,
                                            isTrailingLambda: argument.isTrailingLambda
                                        )
                                    },
                                    explicitTypeArgs: request.explicitTypeArgs,
                                    typeAliasConstructor: nestedAliasContext
                                ),
                                expectedType: nil,
                                ctx: request.sema
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
                                   classifierSymbol: nestedAliasExpandedOwner ?? nestedOwner,
                                   argTypes: argTypes,
                                   locals: &locals
                               )
                            {
                                return invokeType
                            }
                        }
                        request.ctx.sema.diagnostics.emit(diagnostic)
                        return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                    }
                    if let chosen = resolved.chosenCallee,
                       let signature = request.sema.symbols.functionSignature(for: chosen)
                    {
                        contextualizeResolvedIntegerArguments(args: request.args, resolved: resolved, ctx: request.ctx, locals: &locals)
                        request.sema.bindings.bindCall(
                            request.id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: resolved.substitutedTypeArguments
                                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                    .map(\.value),
                                parameterMapping: resolved.parameterMapping
                            )
                        )
                        let typeVarBySymbol = request.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                        let resultType = request.sema.types.substituteTypeParameters(
                            in: signature.returnType,
                            substitution: resolved.substitutedTypeArguments,
                            typeVarBySymbol: typeVarBySymbol
                        )
                        if request.ast.arena.isExplicitCall(request.id),
                           let nestedOwner = request.sema.symbols.parentSymbol(for: chosen),
                           let nestedOwnerSymbol = request.sema.symbols.symbol(nestedOwner),
                           (nestedOwnerSymbol.kind == .class || nestedOwnerSymbol.kind == .annotationClass),
                           !nestedOwnerSymbol.flags.contains(.innerClass)
                        {
                            request.sema.bindings.markTypeQualifiedConstructorCallExpr(request.id)
                        }
                        request.sema.bindings.bindExprType(request.id, type: resultType)
                        return resultType
                    }
                }
            }
            if nestedCtorCandidates.isEmpty,
               let nestedOwner = nestedOwnerSymbols.first,
               let companionInvokeType = inferQualifiedNestedClassifierCompanionInvoke(
                   request,
                   classifierSymbol: nestedAliasExpandedOwner ?? nestedOwner,
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
