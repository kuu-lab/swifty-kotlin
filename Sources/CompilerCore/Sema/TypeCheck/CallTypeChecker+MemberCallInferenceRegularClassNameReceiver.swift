// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// Class-name (`Owner.member`) receiver resolution, extracted verbatim from
    /// `inferRegularMemberCall`. Handles static member values and functions,
    /// enum-owned source extensions, nested classifiers and nested constructors
    /// before ordinary member/extension lookup runs.
    /// Returns nil when no class-name receiver path applies.
    func tryInferRegularMemberCallClassNameReceiver(
        _ request: MemberCallInferenceRequest,
        isClassNameReceiver: Bool,
        classNameReceiverNominalSymbol: SymbolID?,
        argTypes: [TypeID]
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

        return nil
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
