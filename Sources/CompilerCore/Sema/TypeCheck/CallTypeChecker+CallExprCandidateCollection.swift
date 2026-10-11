// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Candidate collection for `inferCallExpr`: scope lookup merged with
/// implicit-receiver member candidates (visibility- and DslMarker-filtered),
/// classifier-as-callable handling, and fully-qualified-name calls, plus the
/// candidate-list preference passes that follow collection.
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
extension CallTypeChecker {
    func collectCallExprCandidates(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        calleePath: [InternedString]?,
        candidates: inout [SymbolID],
        implicitReceiverScopeCandidates: inout [SymbolID],
        callImplicitReceiverType: inout TypeID?,
        memberExtensionReceiverMarks: inout [SymbolID: SymbolID],
        mergedImplicitReceiverMembers: inout [SymbolID],
        callInvisible: inout [SemanticSymbol]
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        if let calleeName {
            let allCallCandidates = scopeCallCandidatesConsideringImplicitReceivers(named: calleeName, ctx: ctx).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            if let receiverEntry = ctx.implicitReceiverMemberLookupEntries().first(where: { entry in
                allCallCandidates.contains { candidate in
                    guard let declaredReceiver = sema.symbols.functionSignature(for: candidate)?.receiverType else {
                        return false
                    }
                    return extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: entry.type,
                        declaredReceiver: declaredReceiver,
                        sema: sema
                    )
                }
            }) {
                callImplicitReceiverType = receiverEntry.type
            }
            // @DslMarker restriction: filter out candidates that belong to an
            // outer receiver class that shares a DslMarker annotation with the
            // current implicit receiver.
            let dslBlockedCandidates = allCallCandidates.filter { ctx.isCandidateBlockedByDslMarker($0) }
            let dslFiltered = allCallCandidates.filter { !ctx.isCandidateBlockedByDslMarker($0) }
            let (vis, invis) = ctx.filterByVisibility(dslFiltered)
            candidates = vis
            implicitReceiverScopeCandidates = vis
            callInvisible = invis
            if locals[calleeName] == nil,
               let receiverType = ctx.implicitReceiverType
            {
                let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName, receiverType: receiverType, sema: sema, interner: interner
                )
                // Imported library declarations also carry the synthetic flag.
                // Include them before argument inference so receiver lambdas on
                // members such as HexFormat.Builder.bytes get their expected type.
                let sourceMembers = memberCandidates.filter {
                    sema.symbols.isSourceBackedSymbol($0)
                        || sema.symbols.symbol($0)?.flags.contains(.synthetic) == false
                }
                let visibleMembers = ctx.filterByVisibility(sourceMembers).visible
                if !visibleMembers.isEmpty {
                    let scopeProvidedNoCandidates = candidates.isEmpty
                    // Member-extension members surface under the dispatch
                    // receiver type but must resolve against the implicit
                    // receiver tower entry picked for the extension receiver.
                    var regularMembers: [SymbolID] = []
                    var memberExtensionCandidates: [(symbol: SymbolID, receiverType: TypeID)] = []
                    for candidate in visibleMembers {
                        guard let signature = sema.symbols.functionSignature(for: candidate),
                              sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil,
                              let declaredReceiver = signature.receiverType,
                              let picked = ctx.implicitReceiverMemberLookupEntries().first(where: { entry in
                                  sema.types.isSubtype(
                                      sema.types.makeNonNullable(entry.type),
                                      sema.types.makeNonNullable(declaredReceiver)
                                  )
                              })
                        else {
                            regularMembers.append(candidate)
                            continue
                        }
                        memberExtensionCandidates.append((candidate, picked.type))
                        if let pickedSymbol = picked.symbol {
                            memberExtensionReceiverMarks[candidate] = pickedSymbol
                        }
                    }
                    if !regularMembers.isEmpty {
                        candidates = regularMembers
                        if scopeProvidedNoCandidates {
                            mergedImplicitReceiverMembers = regularMembers
                        }
                    } else if let extensionReceiverType = memberExtensionCandidates.first?.receiverType {
                        candidates = memberExtensionCandidates
                            .filter { $0.receiverType == extensionReceiverType }
                            .map(\.symbol)
                        callImplicitReceiverType = extensionReceiverType
                    }
                }
            }
            if candidates.isEmpty,
               locals[calleeName] == nil,
               let activeReceiverType = ctx.implicitReceiverType,
               driver.helpers.collectMemberFunctionCandidates(
                   named: calleeName,
                   receiverType: sema.types.makeNonNullable(activeReceiverType),
                   sema: sema,
                   interner: interner
               ).isEmpty
            {
                // The scope chain can contain an enclosing class's private
                // method, but an anonymous object's symbol is not itself a
                // member of that class for visibility checks. Resolve the
                // method against the lexical receiver that owns it.
                for lexicalReceiverType in ctx.outerReceiverTypes.reversed().map(\.type) {
                    let outerType = sema.types.makeNonNullable(lexicalReceiverType)
                    guard let outerClassSymbol = driver.helpers.nominalSymbol(
                        of: outerType,
                        types: sema.types
                    ) else {
                        continue
                    }
                    let outerCandidates = driver.helpers.collectMemberFunctionCandidates(
                        named: calleeName,
                        receiverType: outerType,
                        sema: sema,
                        interner: interner
                    )
                    let outerContext = ctx.copying(enclosingClassSymbol: outerClassSymbol)
                    let visibleOuterCandidates = outerContext.filterByVisibility(outerCandidates).visible
                    guard !visibleOuterCandidates.isEmpty else {
                        continue
                    }
                    // Member extensions consume two implicit receivers — the
                    // tower entry that owns the declaration (dispatch) and an
                    // implicit receiver matching the declared extension
                    // receiver — so they resolve under a different
                    // `callImplicitReceiverType` than ordinary members, which
                    // check the dispatch receiver itself.
                    var memberExtensionCandidates: [(symbol: SymbolID, receiverType: TypeID)] = []
                    var regularCandidates: [SymbolID] = []
                    for candidate in visibleOuterCandidates {
                        guard sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil else {
                            regularCandidates.append(candidate)
                            continue
                        }
                        // Kotlin allows any implicit receiver in the tower
                        // whose type satisfies the declared extension
                        // receiver — innermost first. The picked entry's
                        // symbol is recorded so KIR lowering materializes
                        // that exact value (e.g. the enclosing Int receiver
                        // captured past a `with("s")` lambda receiver).
                        guard let signature = sema.symbols.functionSignature(for: candidate),
                              let declaredReceiver = signature.receiverType,
                              let picked = ctx.implicitReceiverMemberLookupEntries().first(where: { entry in
                                  sema.types.isSubtype(
                                      sema.types.makeNonNullable(entry.type),
                                      sema.types.makeNonNullable(declaredReceiver)
                                  )
                              })
                        else { continue }
                        memberExtensionCandidates.append((candidate, picked.type))
                        if let pickedSymbol = picked.symbol {
                            memberExtensionReceiverMarks[candidate] = pickedSymbol
                        }
                    }
                    if !regularCandidates.isEmpty {
                        candidates = regularCandidates
                        callImplicitReceiverType = outerType
                    } else if let extensionReceiverType = memberExtensionCandidates.first?.receiverType {
                        candidates = memberExtensionCandidates
                            .filter { $0.receiverType == extensionReceiverType }
                            .map(\.symbol)
                        callImplicitReceiverType = extensionReceiverType
                    }
                    guard !candidates.isEmpty else {
                        continue
                    }
                    callInvisible = []
                    break
                }
            }
            if calleeName == knownNames.toList,
               let implicitReceiverType = ctx.implicitReceiverType
            {
                candidates = preferCollectionToListCandidates(
                    candidates,
                    receiverType: implicitReceiverType,
                    sema: sema,
                    interner: interner
                )
            }
            // If all candidates were blocked by DslMarker, emit a specific diagnostic.
            if candidates.isEmpty, !dslBlockedCandidates.isEmpty {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-DSLMARKER",
                    "'@DslMarker' implicit access to '\(interner.resolve(calleeName))' from outer receiver is restricted. Use explicit receiver.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            var resolvedFromLocalShadow = false
            if let local = locals[calleeName],
               let sym = ctx.cachedSymbol(local.symbol)
            {
                let localIsCallableValue: Bool = {
                    if case .functionType = sema.types.kind(of: local.type) {
                        return true
                    }
                    let invokeName = interner.intern("invoke")
                    if driver.helpers.collectMemberFunctionCandidates(
                        named: invokeName,
                        receiverType: local.type,
                        sema: sema,
                        interner: interner
                    ).contains(where: { candidateID in
                        sema.symbols.symbol(candidateID)?.flags.contains(.operatorFunction) == true
                    }) {
                        return true
                    }
                    return collectDispatchReceiverMemberExtensionCandidates(
                        named: invokeName,
                        extensionReceiverType: sema.types.makeNonNullable(local.type),
                        ctx: ctx
                    ).contains { candidateID in
                        sema.symbols.symbol(candidateID)?.flags.contains(.operatorFunction) == true
                    }
                }()
                if sym.kind == .function
                    || (sym.kind != .class && localIsCallableValue)
                    || local.type == sema.types.errorType
                {
                    // Callable local declarations shadow imported and top-level
                    // callables of the same name. Non-callable values do not:
                    // `val emptyList = emptyList<Int>()` must not hide a later
                    // `emptyList<String>()` call. A `.class`-kind local
                    // (KUU-555 named local class) is likewise not a callable
                    // value — `Local(...)` must reach its constructor through
                    // the KSP-CAP-006 merge below.
                    candidates = sym.kind == .function ? [local.symbol] : []
                    resolvedFromLocalShadow = true
                }
            }
            // KSP-CAP-006: a class/enum/annotation-class/object may coexist
            // with a top-level function of the same name (e.g. `class Random`
            // + top-level `fun Random(seed: Long): Random`, the real
            // kotlin-stdlib factory-function idiom). Merge that type's
            // constructors into the candidate set instead of only using them
            // as an empty-candidates fallback, so overload resolution can
            // choose between the function(s) and the constructor(s) by
            // argument type -- the same way it already does between two
            // overloaded functions of the same name. Skipped when a local
            // variable already shadows the name (resolvedFromLocalShadow).
            if !resolvedFromLocalShadow {
                // Ordinary scope lookup stops at the first scope containing
                // any binding of this name. A companion function can therefore
                // hide its enclosing class's nested classifier even though
                // Kotlin keeps callable and classifier lookup in separate
                // namespaces. Recover only the nearest lexical classifier;
                // constructors still go through the normal visibility and
                // hidden-deprecation handling below.
                let classSymbols = ctx.scope.lookupClassifier(calleeName, matching: { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .class || symbol.kind == .enumClass || symbol.kind == .annotationClass || symbol.kind == .object
                }).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate),
                          symbol.flags.contains(.expectDeclaration)
                    else { return true }
                    return sema.symbols.actualSymbol(for: candidate) == nil
                }
                if let classSym = classSymbols.first, let classSymbol = ctx.cachedSymbol(classSym) {
                    if classSymbol.flags.contains(.abstractType) {
                        // P5-112: Prohibit direct instantiation of abstract classes,
                        // but only when there is no other viable candidate (e.g. a
                        // coexisting top-level factory function): an abstract
                        // class's own constructor is never itself a usable call
                        // target, so it must not blot out a real candidate.
                        if candidates.isEmpty {
                            let className = classSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                            ctx.semaCtx.diagnostics.error(
                                "KSWIFTK-SEMA-ABSTRACT",
                                "Cannot create an instance of abstract class '\(className)'.",
                                range: range
                            )
                            sema.bindings.bindExprType(id, type: sema.types.errorType)
                            return sema.types.errorType
                        }
                    } else {
                        let initName = interner.intern("<init>")
                        let ctorFQName = classSymbol.fqName + [initName]
                        // Constructors share an FQName across expect/actual
                        // classes, but only the selected classifier owns the
                        // constructor candidates for this call.
                        let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName).filter {
                            sema.symbols.parentSymbol(for: $0) == classSym
                        }
                        if !ctorSymbols.isEmpty {
                            let (ctorVis, ctorInvis) = ctx.filterByVisibility(ctorSymbols)
                            // Some synthetic stdlib types register a class
                            // constructor whose signature exactly duplicates a
                            // coexisting top-level factory function's signature
                            // (e.g. kotlin.io.path.Path's synthetic
                            // `<init>(String)` alongside the top-level `fun
                            // Path(pathString: String): Path`). Without this
                            // filter the duplicate becomes a second,
                            // indistinguishable overload candidate and every
                            // call to that name falsely resolves as ambiguous.
                            // Hidden compatibility factories are present in
                            // metadata but must not suppress an identically shaped
                            // constructor. They are intentionally retained by
                            // filterByVisibility when no other function overload
                            // exists so a direct call to a removed function still
                            // receives the deprecation diagnostic; constructors are
                            // merged only here, so discard the hidden duplicate now.
                            let constructorParameterTypes = ctorVis.compactMap {
                                sema.symbols.functionSignature(for: $0)?.parameterTypes
                            }
                            candidates.removeAll { existingID in
                                guard isHiddenByDeprecatedAnnotation(existingID, symbols: sema.symbols),
                                      let signature = sema.symbols.functionSignature(for: existingID)
                                else {
                                    return false
                                }
                                return constructorParameterTypes.contains(signature.parameterTypes)
                            }
                            let newCtorVis = ctorVis.filter { ctorID in
                                guard let ctorSignature = sema.symbols.functionSignature(for: ctorID) else {
                                    return true
                                }
                                return !candidates.contains { existingID in
                                    sema.symbols.functionSignature(for: existingID)?.parameterTypes == ctorSignature.parameterTypes
                                }
                            }
                            candidates.append(contentsOf: newCtorVis)
                            callInvisible.append(contentsOf: ctorInvis)
                        }
                    }
                }
            }
            if candidates.isEmpty,
               calleeName == knownNames.suspendCoroutine,
               let suspendCoroutineSymbol = sema.symbols.lookup(fqName: knownNames.kotlinSuspendCoroutineFQName) {
                candidates = [suspendCoroutineSymbol]
            }
            if candidates.isEmpty,
               calleeName == knownNames.runBlocking,
               let runBlockingSymbol = sema.symbols.lookup(fqName: knownNames.kotlinxCoroutinesRunBlockingFQName) {
                candidates = [runBlockingSymbol]
            }
            // --- Typealias constructor calls ---
            // If the callee is a typealias (e.g. `typealias IntPair = Pair<Int, Int>`),
            // expand it to the underlying class and resolve its constructor.
            if candidates.isEmpty {
                let aliasSymbols = ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .typeAlias
                }
                if let aliasSym = aliasSymbols.first {
                    let aliasTypeParameters = sema.symbols.typeAliasTypeParameters(for: aliasSym)
                    let aliasTypeArgs: [TypeArg] = if !explicitTypeArgs.isEmpty {
                        explicitTypeArgs.map { TypeArg.invariant($0) }
                    } else if !aliasTypeParameters.isEmpty,
                              let expectedType,
                              case let .classType(expectedClassType) = sema.types.kind(of: expectedType)
                    {
                        Array(expectedClassType.args.prefix(aliasTypeParameters.count))
                    } else if !aliasTypeParameters.isEmpty {
                        Array(repeating: TypeArg.invariant(sema.types.anyType), count: aliasTypeParameters.count)
                    } else {
                        []
                    }
                    if let expanded = driver.helpers.expandTypeAlias(
                        aliasSym,
                        typeArgs: aliasTypeArgs,
                        sema: sema,
                        visited: [],
                        depth: 0,
                        diagnostics: ctx.semaCtx.diagnostics
                    ),
                       case let .classType(classType) = sema.types.kind(of: expanded)
                    {
                        let constructorOwner = sema.symbols.actualSymbol(for: classType.classSymbol)
                            ?? classType.classSymbol
                        if let underlyingSymbol = ctx.cachedSymbol(constructorOwner) {
                            let initName = interner.intern("<init>")
                            let ctorFQName = underlyingSymbol.fqName + [initName]
                            let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName).filter {
                                sema.symbols.parentSymbol(for: $0) == constructorOwner
                            }
                            if !ctorSymbols.isEmpty {
                                let (vis, invis) = ctx.filterByVisibility(ctorSymbols)
                                candidates = vis
                                callInvisible.append(contentsOf: invis)
                            }
                        }
                    }
                }
            }
        } else if let calleePath, calleePath.count > 1 {
            // FQN call: e.g. kotlin.math.abs(x) — look up directly by fully qualified name
            let fqnCandidates = sema.symbols.lookupAll(fqName: calleePath).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            let (vis, invis) = ctx.filterByVisibility(fqnCandidates)
            candidates = vis
            callInvisible.append(contentsOf: invis)
        } else {
            candidates = []
        }
        return nil
    }

    func applyImplicitReceiverPredicateCandidatePreference(
        args: [CallArgument],
        ctx: TypeInferenceContext,
        calleeName: InternedString?,
        candidates: inout [SymbolID],
        implicitReceiverScopeCandidates: [SymbolID]
    ) {
        let ast = ctx.ast
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        if let calleeName,
           let implicitReceiverType = ctx.implicitReceiverType,
           calleeName == knownNames.removeAll || calleeName == knownNames.retainAll,
           args.contains(where: { ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true })
        {
            let preferredCandidates = preferImplicitReceiverPredicateCandidates(
                candidates,
                fallbackCandidates: implicitReceiverScopeCandidates,
                args: args,
                receiverType: implicitReceiverType,
                ctx: ctx
            )
            if !preferredCandidates.isEmpty {
                candidates = preferredCandidates
            }
        }
    }

    func applyIndexOfReceiverPreference(
        ctx: TypeInferenceContext,
        calleeName: InternedString?,
        candidates: inout [SymbolID]
    ) {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        // KSP-979: an implicit receiver call must keep the most-specific
        // source-backed owner for the Iterable index family. Existing bundled
        // List bodies use an unqualified indexOf call in contains(); once the
        // generic Iterable overload is added, resolve this owner before the
        // ordinary top-level overload resolver reports an ambiguity.
        if let calleeName,
           let implicitReceiverType = ctx.implicitReceiverType,
           calleeName == knownNames.indexOf || calleeName == knownNames.indexOfFirst || calleeName == knownNames.indexOfLast
        {
            let receiverClassifier = ReceiverClassifier(sema: sema, interner: interner)
            let nonNullReceiver = sema.types.makeNonNullable(implicitReceiverType)
            let preferListReceiver: Bool? = if receiverClassifier.isConcreteListLikeType(nonNullReceiver) {
                true
            } else if !receiverClassifier.isCollectionLikeType(nonNullReceiver),
                      receiverClassifier.isNominalIterableType(nonNullReceiver)
            {
                false
            } else {
                nil
            }
            if let preferListReceiver {
                let preferredCandidates = candidates.filter { candidate in
                    guard sema.symbols.isSourceBackedSymbol(candidate),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType
                    else {
                        return false
                    }
                    if preferListReceiver {
                        return receiverClassifier.isConcreteListLikeType(declaredReceiver)
                    }
                    return !receiverClassifier.isCollectionLikeType(declaredReceiver)
                        && receiverClassifier.isNominalIterableType(declaredReceiver)
                }
                if !preferredCandidates.isEmpty {
                    candidates = preferredCandidates
                }
            }
        }
    }
}
