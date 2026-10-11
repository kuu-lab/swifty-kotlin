
extension ExprTypeChecker {
    func inferNameRefExpr(
        _ id: ExprID,
        name: InternedString,
        nameRange: SourceRange?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        isQualifier: Bool = false
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        if name == knownNames.thisName,
           let receiverType = ctx.implicitReceiverType
        {
            sema.bindings.bindExprType(id, type: receiverType)
            return receiverType
        }
        if let local = locals[name],
           !isQualifier || sema.symbols.symbol(local.symbol)?.kind != .function
        {
            if !local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(name))' must be initialized before use.",
                    range: nameRange
                )
            }
            sema.bindings.bindIdentifier(id, symbol: local.symbol)
            // Propagate collection marks through variable references (P5-84).
            if sema.bindings.isCollectionSymbol(local.symbol) {
                sema.bindings.markCollectionExpr(id)
            }
            if sema.bindings.isRangeSymbol(local.symbol) {
                sema.bindings.markRangeExpr(id)
            }
            if sema.bindings.isCharRangeSymbol(local.symbol) {
                sema.bindings.markCharRangeExpr(id)
            }
            if sema.bindings.isUIntRangeSymbol(local.symbol) {
                sema.bindings.markUIntRangeExpr(id)
            }
            if sema.bindings.isULongRangeSymbol(local.symbol) {
                sema.bindings.markULongRangeExpr(id)
            }
            if sema.bindings.isFloatingPointRangeSymbol(local.symbol) {
                sema.bindings.markFloatingPointRangeExpr(id)
                if let elementType = sema.bindings.floatingPointRangeElementType(forSymbol: local.symbol) {
                    sema.bindings.bindFloatingPointRangeElementType(
                        elementType, forExpr: id,
                        endExclusive: sema.bindings.isOpenFloatingPointRangeSymbol(local.symbol)
                    )
                }
            }
            if sema.bindings.isFlowSymbol(local.symbol) {
                sema.bindings.markFlowExpr(id)
                if let flowElementType = sema.bindings.flowElementType(forSymbol: local.symbol) {
                    sema.bindings.bindFlowElementType(flowElementType, forExpr: id)
                }
            }
            sema.bindings.bindExprType(id, type: local.type)
            return local.type
        }
        // An uninvoked function is not a qualified receiver. Keep values in
        // the lookup so properties still shadow imported classifiers.
        let allCandidateIDs: [SymbolID] = if isQualifier {
            ctx.scope.lookup(name, matching: { symbolID in
                guard let symbol = ctx.cachedSymbol(symbolID) else { return false }
                return symbol.kind != .function && symbol.kind != .constructor
            })
        } else {
            ctx.cachedScopeLookup(name)
        }
        // @DslMarker restriction: filter out candidates from outer receivers
        // that share a DslMarker annotation with the current implicit receiver.
        let dslBlockedIDs = allCandidateIDs.filter { ctx.isCandidateBlockedByDslMarker($0) }
        let dslFilteredIDs = allCandidateIDs.filter { !ctx.isCandidateBlockedByDslMarker($0) }
        let (visibleIDs, initialInvisibleSyms) = ctx.filterByVisibility(dslFilteredIDs)
        var invisibleSyms = initialInvisibleSyms
        var candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        if candidates.isEmpty {
            let nominalFallbackIDs = sema.symbols.lookupByShortName(name).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                switch symbol.kind {
                case .object, .class, .interface, .enumClass, .annotationClass, .typeAlias:
                    return true
                default:
                    return false
                }
            }
            let (visibleFallbackIDs, invisibleFallbackSyms) = ctx.filterByVisibility(nominalFallbackIDs)
            if !visibleFallbackIDs.isEmpty {
                candidates = visibleFallbackIDs.compactMap { ctx.cachedSymbol($0) }
            } else if invisibleSyms.isEmpty, !invisibleFallbackSyms.isEmpty {
                invisibleSyms = invisibleFallbackSyms
            }
        }

        // Implicit receiver member lookup walks the whole receiver tower
        // (extension receiver, enclosing lambda receivers, `this@Owner`
        // dispatch receivers, enclosing class) — a member extension body's
        // `this` is the extension receiver, but the dispatch owner's members,
        // inherited ones included, still resolve unqualified.
        let implicitReceiverLookupEntries = ctx.implicitReceiverMemberLookupEntries()
        if !implicitReceiverLookupEntries.isEmpty {
            var memberType: TypeID?
            for (index, receiver) in implicitReceiverLookupEntries.enumerated() {
                memberType = resolveImplicitReceiverMember(
                    id: id,
                    name: name,
                    receiverType: receiver.type,
                    ctx: ctx,
                    sema: sema,
                    interner: interner,
                    nameRange: nameRange,
                    emitDiagnosticOnFailure: index == implicitReceiverLookupEntries.count - 1
                        && candidates.isEmpty && invisibleSyms.isEmpty && dslBlockedIDs.isEmpty
                )
                if memberType != nil {
                    if memberType != sema.types.errorType, let receiverSymbol = receiver.symbol {
                        sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: receiverSymbol)
                    }
                    break
                }
            }
            if let memberType, memberType != sema.types.errorType {
                if let reference = ctx.dataFlow.resolveStableReference(
                    id, locals: locals, ast: ctx.ast, sema: sema, interner: interner
                ), reference.isStable,
                   let narrowedType = ctx.dataFlow.resolvedTypeFromFlowState(
                       ctx.flowState.includingMembers(from: locals), reference: reference.symbol
                   )
                {
                    sema.bindings.bindExprType(id, type: narrowedType)
                    return narrowedType
                }
                return memberType
            }
            if candidates.isEmpty, memberType == sema.types.errorType {
                return sema.types.errorType
            }
        }
        if candidates.isEmpty, !dslBlockedIDs.isEmpty {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-DSLMARKER",
                "'@DslMarker' implicit access to '\(interner.resolve(name))' from outer receiver is restricted. Use explicit receiver.",
                range: nameRange
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        candidates.removeAll { candidate in
            guard let declaredReceiver = sema.symbols.extensionPropertyReceiverType(for: candidate.id) else {
                return false
            }
            guard let receiverType = ctx.implicitReceiverType else {
                // Package-scope extension properties remain in import scopes
                // so `receiver.property` can resolve them, but a bare name in
                // a receiver-free context must not bind as a global property.
                return implicitReceiverLookupEntries.isEmpty
            }
            return !sema.types.isSubtype(
                sema.types.makeNonNullable(receiverType),
                sema.types.makeNonNullable(declaredReceiver)
            )
        }
        if candidates.isEmpty {
            var implicitMemberResult: (symbol: SymbolID, type: TypeID)?
            for receiver in implicitReceiverLookupEntries {
                if let result = driver.helpers.lookupMemberProperty(
                    named: name,
                    receiverType: sema.types.makeNonNullable(receiver.type),
                    sema: sema
                ) {
                    if let receiverSymbol = receiver.symbol {
                        sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: receiverSymbol)
                    }
                    implicitMemberResult = result
                    break
                }
            }
            if let result = implicitMemberResult {
                sema.bindings.markImplicitReceiverMember(id, name: name)
                sema.bindings.bindIdentifier(id, symbol: result.symbol)
                driver.helpers.checkDeprecation(
                    for: result.symbol,
                    sema: sema,
                    interner: interner,
                    range: nameRange,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                driver.helpers.checkOptIn(
                    for: result.symbol,
                    ctx: ctx,
                    range: nameRange,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                sema.bindings.bindExprType(id, type: result.type)
                return result.type
            } else if let firstInvisible = invisibleSyms.first {
                driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(name), range: nameRange, diagnostics: ctx.semaCtx.diagnostics)
            } else if name == knownNames.field {
                // Kotlin's `field` identifier is only valid inside property
                // getter/setter bodies where it refers to the backing field.
                // Emit a targeted diagnostic instead of the generic
                // "Unresolved reference" error.
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-FIELD",
                    "'field' can only be used inside a property getter or setter body.",
                    range: nameRange
                )
            } else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0022",
                    "Unresolved reference '\(interner.resolve(name))'.",
                    range: nameRange
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let preferredCandidate = candidates.first(where: { symbol in
            switch symbol.kind {
            case .property, .field, .backingField, .object, .class, .interface, .enumClass:
                true
            default:
                false
            }
        }) ?? candidates.first
        if let preferredCandidate {
            sema.bindings.bindIdentifier(id, symbol: preferredCandidate.id)
            if ctx.implicitReceiverType != nil,
               sema.symbols.extensionPropertyReceiverType(for: preferredCandidate.id) != nil
            {
                sema.bindings.markImplicitReceiverMember(id, name: name)
            }
            // ANNO-001: Check for @Deprecated annotation on the resolved symbol.
            driver.helpers.checkDeprecation(
                for: preferredCandidate.id,
                sema: sema,
                interner: interner,
                range: nameRange,
                diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: preferredCandidate.id,
                ctx: ctx,
                range: nameRange,
                diagnostics: ctx.semaCtx.diagnostics
            )
            // DEBT-SEMA-003: a property's initializer referencing the property's
            // own symbol reads it before it has ever been assigned a value.
            if let initializingPropertySymbol = ctx.initializingPropertySymbol,
               preferredCandidate.id == initializingPropertySymbol
            {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(name))' must be initialized before use.",
                    range: nameRange
                )
            }
        }
        let resolvedType = preferredCandidate.flatMap {
            resolveTypeForCandidate($0, sema: sema)
        } ?? sema.types.anyType
        // Propagate compile-time constant value for `const val` references
        // so downstream passes can fold without re-querying the symbol table.
        if let preferredCandidate, preferredCandidate.flags.contains(.constValue),
           let constKind = sema.symbols.constValueExprKind(for: preferredCandidate.id)
        {
            sema.bindings.bindConstExprValue(id, value: constKind)
        }
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    private func resolveImplicitReceiverMember(
        id: ExprID,
        name: InternedString,
        receiverType: TypeID,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        interner: StringInterner,
        nameRange: SourceRange?,
        emitDiagnosticOnFailure: Bool = true
    ) -> TypeID? {
        // STDLIB-004: Inside receiver lambdas (run/apply/with), bare name
        // references resolve as properties on the implicit receiver (this).
        let knownNames = KnownCompilerNames(interner: interner)
        let resolvedName = interner.resolve(name)
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        var implicitMemberType: TypeID?
        if sema.types.isSubtype(nonNullReceiver, sema.types.stringType), resolvedName == "length" {
            implicitMemberType = sema.types.intType
        }
        if nonNullReceiver == sema.types.charType, resolvedName == "code" {
            implicitMemberType = sema.types.intType
        }
        if implicitMemberType == nil, name == knownNames.size || name == knownNames.isEmpty,
           let (_, symbol) = resolveClassTypeSymbol(nonNullReceiver, sema: sema),
           knownNames.collectionKind(of: symbol) != nil
        {
            implicitMemberType = name == knownNames.size
                ? sema.types.intType
                : sema.types.make(.primitive(.boolean, .nonNull))
        }
        if implicitMemberType == nil,
           let result = driver.helpers.lookupMemberProperty(named: name, receiverType: nonNullReceiver, sema: sema)
        {
            sema.bindings.markImplicitReceiverMember(id, name: name)
            sema.bindings.bindIdentifier(id, symbol: result.symbol)
            driver.helpers.checkDeprecation(
                for: result.symbol, sema: sema, interner: interner,
                range: nameRange, diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: result.symbol,
                ctx: ctx,
                range: nameRange,
                diagnostics: ctx.semaCtx.diagnostics
            )
            sema.bindings.bindExprType(id, type: result.type)
            return result.type
        }
        // KUU-1451: the bundled stdlib models generic extension *properties*
        // (`List.lastIndex`, `List.indices`, `Array.lastIndex`, ...) as
        // zero-argument extension functions — see the note in
        // Stdlib/kotlin/collections/Collections.kt. `lookupMemberProperty`
        // only walks `.property` symbols, so a bare read on an implicit
        // receiver (`l.run { lastIndex }`) otherwise binds the raw function
        // symbol and KIR emits a `symbolRef` of the callee instead of calling
        // it on `this`. Resolve the receiver-matching zero-argument extension
        // overload here and record it as a call so lowering materializes the
        // implicit receiver as the callee's first argument — the same shape
        // the explicit `this.lastIndex` member-call form produces.
        //
        // The property-style facade is a bundled-stdlib convention for the
        // upstream extension *properties* the bundled parser cannot declare
        // on generic receivers. The bundled source models exactly three
        // names this way today — `List/Array/Collection.lastIndex`,
        // `List/Array/Collection.indices` (Stdlib/kotlin/collections/) and
        // `Any.javaClass` (Stdlib/kotlin/JavaClass.kt) — so the candidate
        // set is confined to those names on bundled declarations (source or
        // imported stdlib artifact). Ordinary functions (`first`, `count`,
        // member `c.run { m }`, user extensions) keep Kotlin's invocation
        // syntax requirement and are excluded; the explicit `c.m`
        // acceptance is a separate pre-existing deviation (KUU-1453).
        if implicitMemberType == nil {
            let propertyFacadeNames: Set<InternedString> = [
                ctx.interner.intern("lastIndex"),
                ctx.interner.intern("indices"),
                ctx.interner.intern("javaClass"),
            ]
            var seenPropertyStyleCandidates: Set<SymbolID> = []
            let scopedIDs = ctx.cachedScopeLookup(name) + sema.symbols.lookupByShortName(name)
            let (visibleIDs, _) = ctx.filterByVisibility(scopedIDs)
            let propertyStyleFunctions = visibleIDs.filter { candidate in
                guard seenPropertyStyleCandidates.insert(candidate).inserted,
                      let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      propertyFacadeNames.contains(symbol.name),
                      sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.isEmpty,
                      !signature.isSuspend,
                      let declaredReceiver = signature.receiverType
                else {
                    return false
                }
                if let parentID = sema.symbols.parentSymbol(for: candidate),
                   let parent = sema.symbols.symbol(parentID)
                {
                    // Getter/setter helpers share their property's name; they
                    // are not callable member candidates.
                    if parent.kind == .property {
                        return false
                    }
                    // A genuine member is declared under its nominal owner;
                    // a package-level extension keeps its package FQName even
                    // when member lookup attaches it to the nominal.
                    if parent.kind != .package,
                       symbol.fqName == parent.fqName + [symbol.name]
                    {
                        return false
                    }
                }
                // Only bundled stdlib declarations (bundled sources, or the
                // imported stdlib artifact merged into the index) model
                // extension properties as zero-argument functions.
                guard let memberKey = BundledDeclarationIndex.memberKey(
                    for: symbol,
                    symbolID: candidate,
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: ctx.interner
                ) else {
                    return false
                }
                let declaredOwnerKey = BundledMemberKey(
                    ownerFQName: Array(symbol.fqName.dropLast()),
                    name: symbol.name,
                    arity: signature.parameterTypes.count
                )
                guard sema.bundledIndex.contains(memberKey)
                    || sema.bundledIndex.contains(declaredOwnerKey)
                else {
                    return false
                }
                return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiver,
                    declaredReceiver: declaredReceiver,
                    sema: sema
                )
            }
            if !propertyStyleFunctions.isEmpty,
               let callRange = nameRange ?? ctx.ast.arena.exprRange(id)
            {
                let resolved = ctx.resolver.resolveCall(
                    candidates: propertyStyleFunctions,
                    call: CallExpr(
                        range: callRange,
                        calleeName: name,
                        args: [],
                        explicitTypeArgs: [],
                        dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
                    ),
                    expectedType: nil,
                    implicitReceiverType: nonNullReceiver,
                    ctx: ctx.semaCtx
                )
                if resolved.diagnostic == nil, let chosen = resolved.chosenCallee {
                    let memberType = driver.callChecker.bindCallAndResolveReturnType(
                        id, chosen: chosen, resolved: resolved, sema: sema
                    )
                    sema.bindings.markImplicitReceiverMember(id, name: name)
                    sema.bindings.bindExprType(id, type: memberType)
                    return memberType
                }
            }
        }
        if let memberType = implicitMemberType {
            sema.bindings.markImplicitReceiverMember(id, name: name)
            sema.bindings.bindExprType(id, type: memberType)
            return memberType
        }
        if emitDiagnosticOnFailure {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Unresolved reference '\(resolvedName)'.",
                range: nameRange
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        return nil
    }

    private func resolveTypeForCandidate(_ symbol: SemanticSymbol, sema: SemaModule) -> TypeID? {
        if let signature = sema.symbols.functionSignature(for: symbol.id) {
            return signature.returnType
        }
        if symbol.kind == .property || symbol.kind == .field {
            return sema.symbols.propertyType(for: symbol.id)
        }
        // Objects are singletons – always resolve to their nominal type so
        // that `ObjectName.member()` works.
        if symbol.kind == .object {
            // Unit keeps its builtin value representation while retaining a
            // source-backed object symbol for member dispatch.
            if symbol.id == sema.types.unitClassSymbol {
                return sema.types.unitType
            }
            if let objectType = sema.symbols.propertyType(for: symbol.id) {
                return objectType
            }
            return sema.types.make(.classType(ClassType(classSymbol: symbol.id, args: [], nullability: .nonNull)))
        }
        // For class/interface/enum symbols, only resolve to nominal type when
        // they have a companion object so that `ClassName.companionMember()`
        // can resolve.  Without a companion, keep the previous anyType
        // fallback so that `ClassName.instanceMethod()` correctly errors.
        if symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass,
           sema.symbols.companionObjectSymbol(for: symbol.id) != nil
        {
            return sema.types.make(.classType(ClassType(classSymbol: symbol.id, args: [], nullability: .nonNull)))
        }
        return nil
    }
}
