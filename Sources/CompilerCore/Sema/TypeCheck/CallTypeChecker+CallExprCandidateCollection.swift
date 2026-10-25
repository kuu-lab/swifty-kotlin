// swiftlint:disable file_length function_body_length cyclomatic_complexity

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
        constructorTypeAlias: inout SymbolID?,
        typeAliasConstructor: inout TypeAliasConstructorContext?,
        implicitReceiverScopeCandidates: inout [SymbolID],
        callImplicitReceiverType: inout TypeID?,
        memberExtensionReceiverMarks: inout [SymbolID: SymbolID],
        mergedImplicitReceiverMembers: inout [SymbolID],
        callInvisible: inout [SemanticSymbol],
        knownApplicableImplicitMembers: inout Set<SymbolID>,
        typeNameCompanionInvokeCandidates: inout Set<SymbolID>,
        typeNameCompanionInvokeReceiverType: inout TypeID?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        if let calleeName {
            let scopeSelection = scopeCallCandidatesAfterInapplicableMembers(
                named: calleeName, args: args, range: range,
                explicitTypeArgs: explicitTypeArgs, ctx: ctx, locals: locals
            )
            knownApplicableImplicitMembers = scopeSelection.knownApplicableMembers
            let allCallCandidates = scopeSelection.candidates.filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            if let receiverEntry = ctx.implicitReceiverMemberLookupEntries().first(where: { entry in
                allCallCandidates.contains { candidate in
                    guard let declaredReceiver = sema.symbols.functionSignature(for: candidate)?.receiverType else {
                        return false
                    }
                    if sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil {
                        return implicitMemberExtensionReceiverMatches(entry.type, declared: declaredReceiver, sema: sema)
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
            let dslBlockedCandidates = allCallCandidates.filter { ctx.isCandidateBlockedByDslMarker($0) }
            let dslFiltered = allCallCandidates.filter { !ctx.isCandidateBlockedByDslMarker($0) }
            let (vis, invis) = ctx.filterByVisibility(dslFiltered)
            candidates = vis
            implicitReceiverScopeCandidates = vis
            callInvisible = invis
            if candidates.isEmpty, !invis.isEmpty {
                // A scope tier that only offers inaccessible declarations must
                // not stop the call tower — keep looking in outer tiers so a
                // bundled-internal `maxOf` cannot hide `kotlin.math.maxOf`.
                // Restrict the retry to plain callables; receiver-bearing
                // candidates need the implicit-receiver matching done above.
                let blocked = Set(allCallCandidates).union(invis.map(\.id))
                let outerTierCandidates = ctx.scope.lookup(calleeName, matching: { candidate in
                    guard !blocked.contains(candidate),
                          let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return (symbol.kind == .function || symbol.kind == .constructor)
                        && sema.symbols.functionSignature(for: candidate)?.receiverType == nil
                }).filter { !ctx.isCandidateBlockedByDslMarker($0) }
                let outerVisible = ctx.filterByVisibility(outerTierCandidates).visible
                if !outerVisible.isEmpty {
                    candidates = outerVisible
                    implicitReceiverScopeCandidates = outerVisible
                    callInvisible = []
                }
            }
            if locals[calleeName] == nil,
               let receiverType = ctx.implicitReceiverType
            {
                var memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName, receiverType: receiverType, sema: sema, interner: interner
                )
                if memberCandidates.isEmpty {
                    memberCandidates = collectWorkerExecuteMemberCandidates(
                        named: calleeName, receiverType: receiverType, sema: sema, interner: interner
                    )
                }
                // Imported library declarations also carry the synthetic flag.
                // Include them before argument inference so receiver lambdas on
                // members such as HexFormat.Builder.bytes get their expected type.
                let sourceMembers = memberCandidates.filter {
                    !scopeSelection.excludedMembers.contains($0)
                        && (sema.symbols.isSourceBackedSymbol($0)
                            || sema.symbols.symbol($0)?.flags.contains(.synthetic) == false)
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
                                  implicitMemberExtensionReceiverMatches(entry.type, declared: declaredReceiver, sema: sema)
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
                    let visibleOuterCandidates = outerContext.filterByVisibility(
                        outerCandidates.filter { !scopeSelection.excludedMembers.contains($0) }
                    ).visible
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
                                  implicitMemberExtensionReceiverMatches(entry.type, declared: declaredReceiver, sema: sema)
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
            if candidates.isEmpty, !dslBlockedCandidates.isEmpty {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-DSLMARKER",
                    "'@DslMarker' implicit access to '\(interner.resolve(calleeName))' from outer receiver is restricted. Use explicit receiver.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            var resolvedFromLocalShadow = false
            var localFunctionCandidates = ctx.scope.lookup(calleeName, matching: { candidate in
                guard ctx.cachedSymbol(candidate)?.flags.contains(.localFunction) == true else {
                    return false
                }
                // A local extension function without an implicit receiver is
                // not callable in this position. Let a same-named local
                // function value (for example, `val label = receiver::label`)
                // reach callable-value invocation instead.
                guard sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
                      let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType
                else {
                    return true
                }
                return ctx.implicitReceiverMemberLookupEntries().contains { entry in
                    extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: entry.type,
                        declaredReceiver: receiver,
                        sema: sema
                    )
                }
            })
            // A parameter declared by the local function itself shadows the
            // function's own name for every reference inside the body —
            // `fun f(f: () -> R) = f()` invokes the parameter, not the
            // function (KUU-3210). Same-block `val`/`fun` pairs keep the
            // KUU-2193 call/value namespace split, so only the owning
            // function's candidate is dropped.
            if let shadowingParameter = locals[calleeName]?.symbol {
                localFunctionCandidates.removeAll { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate) else {
                        return false
                    }
                    return signature.valueParameterSymbols.contains(shadowingParameter)
                        || signature.contextParameterSymbols.contains(shadowingParameter)
                }
            }
            if !localFunctionCandidates.isEmpty {
                let localReceiverFunctionValueIsApplicable: Bool = {
                    guard explicitTypeArgs.isEmpty,
                          args.isEmpty,
                          localFunctionCandidates.allSatisfy({
                              sema.symbols.functionSignature(for: $0)?.receiverType != nil
                          }),
                          let local = locals[calleeName],
                          ctx.cachedSymbol(local.symbol)?.kind != .function,
                          ctx.cachedSymbol(local.symbol)?.kind != .class,
                          case let .functionType(function) = sema.types.kind(of: local.type),
                          function.nullability == .nonNull,
                          function.params.isEmpty,
                          let declaredReceiver = function.receiver
                    else {
                        return false
                    }
                    return ctx.implicitReceiverMemberLookupEntries().contains { entry in
                        implicitMemberExtensionReceiverMatches(
                            entry.type,
                            declared: declaredReceiver,
                            sema: sema
                        )
                    }
                }()
                if localReceiverFunctionValueIsApplicable {
                    // A same-named local `T.() -> R` value is invoked with the
                    // matching implicit receiver and shadows local extensions
                    // in this call form (KUU-2921).
                    candidates = []
                } else {
                    // Call-position lookup keeps every same-scope local overload,
                    // even when a value with the same name occupies the value namespace.
                    candidates = localFunctionCandidates
                }
                resolvedFromLocalShadow = true
            }
            // Lambda parameters carry synthetic (negative) symbol IDs with no
            // symbol-table entry, so a missing symbol must not skip the shadow
            // check: such a local is still a value that hides same-named functions.
            if localFunctionCandidates.isEmpty, let local = locals[calleeName] {
                let localSymbolKind = ctx.cachedSymbol(local.symbol)?.kind
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
                let localCallableCannotAcceptFunctionalArgument: Bool = {
                    guard !candidates.isEmpty,
                          localSymbolKind != .function,
                          case let .functionType(functionType) = sema.types.kind(
                              of: sema.types.makeNonNullable(local.type)
                          ),
                          functionType.receiver == nil,
                          functionType.contextReceivers.isEmpty,
                          args.count == functionType.params.count,
                          !args.contains(where: { $0.label != nil || $0.isSpread })
                    else { return false }

                    for (index, argument) in args.enumerated()
                        where isLambdaOrCallableRefArg(argument.expr, ast: ctx.ast)
                    {
                        let parameterType = functionType.params[index]
                        if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(parameterType)) {
                            continue
                        }
                        if driver.helpers.samFunctionType(for: parameterType, sema: sema) != nil {
                            continue
                        }
                        // A lambda or callable reference cannot satisfy a plain
                        // value parameter of a local function value. Keep the
                        // visible function candidates so a same-named extension
                        // can accept the functional argument instead.
                        return true
                    }
                    return false
                }()
                if localSymbolKind == .function
                    || (localSymbolKind != .class && localIsCallableValue)
                    || local.type == sema.types.errorType
                {
                    // Callable local declarations shadow imported and top-level
                    // callables of the same name. Non-callable values do not:
                    // `val emptyList = emptyList<Int>()` must not hide a later
                    // `emptyList<String>()` call. A `.class`-kind local
                    // (KUU-555 named local class) is likewise not a callable
                    // value — `Local(...)` must reach its constructor through
                    // the KSP-CAP-006 merge below.
                    if !localCallableCannotAcceptFunctionalArgument {
                        candidates = localSymbolKind == .function ? [local.symbol] : []
                        resolvedFromLocalShadow = true
                    }
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
                // namespaces. Prefer lexical classifiers (including local
                // declarations), then inherited nested classifiers, before
                // file-level imports and package declarations. Constructors
                // still go through normal visibility and hidden-deprecation
                // handling below.
                let scopedClassSymbols = ctx.scope.lookupClassifier(calleeName, matching: { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass
                        || symbol.kind == .annotationClass || symbol.kind == .object
                }).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate),
                          symbol.flags.contains(.expectDeclaration)
                    else { return true }
                    return sema.symbols.actualSymbol(for: candidate) == nil
                }
                let inheritedClassSymbols = inheritedNestedClassifiers(named: calleeName, in: ctx)
                let localClassSymbol = locals[calleeName].flatMap { local -> SymbolID? in
                    guard let symbol = ctx.cachedSymbol(local.symbol),
                          symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass
                            || symbol.kind == .annotationClass || symbol.kind == .object
                    else { return nil }
                    return local.symbol
                }
                let classSym = localClassSymbol
                    ?? scopedClassSymbols.first(where: { isLexicallyDeclaredClassifier($0, in: ctx) })
                    ?? inheritedClassSymbols.first
                    ?? scopedClassSymbols.first
                if let classSym, let classSymbol = ctx.cachedSymbol(classSym) {
                    if let companionSymbol = sema.symbols.companionObjectSymbol(for: classSym) {
                        let companionType = sema.symbols.propertyType(for: companionSymbol)
                            ?? sema.types.make(.classType(ClassType(
                                classSymbol: companionSymbol,
                                args: [],
                                nullability: .nonNull
                            )))
                        let invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
                            named: interner.intern("invoke"),
                            receiverType: companionType,
                            sema: sema,
                            interner: interner
                        ).filter { candidate in
                            sema.symbols.symbol(candidate)?.flags.contains(.operatorFunction) == true
                        }
                        let (visibleInvokes, invisibleInvokes) = ctx.filterByVisibility(invokeCandidates)
                        candidates.append(contentsOf: visibleInvokes)
                        callInvisible.append(contentsOf: invisibleInvokes)
                        typeNameCompanionInvokeCandidates.formUnion(visibleInvokes)
                        if !visibleInvokes.isEmpty {
                            typeNameCompanionInvokeReceiverType = companionType
                        }
                    }

                    if classSymbol.kind == .interface {
                        // Interfaces have no constructors; any call candidate
                        // added above must come from the companion object.
                    } else if classSymbol.flags.contains(.abstractType) {
                        // P5-112: Prohibit direct instantiation of abstract classes,
                        // but only when there is no other viable candidate (e.g. a
                        // coexisting top-level factory function): an abstract
                        // class's own constructor is never itself a usable call
                        // target, so it must not blot out a real candidate.
                        if candidates.isEmpty, callInvisible.isEmpty {
                            let className = classSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                            ctx.sema.diagnostics.error(
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
                                    // A same-signature companion `invoke` is a
                                    // distinct call target: Kotlin prefers the
                                    // constructor when applicable, then falls
                                    // back to `invoke` when it is not.
                                    !typeNameCompanionInvokeCandidates.contains(existingID)
                                        && sema.symbols.functionSignature(for: existingID)?.parameterTypes
                                        == ctorSignature.parameterTypes
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
            // An actual typealias paired with an expect class must replace that
            // expect class's constructor candidate, which otherwise wins scope
            // lookup but has no platform implementation.
            var aliasSymbols = ctx.cachedScopeLookup(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .typeAlias
            }
            for candidate in ctx.scope.lookupClassifier(calleeName, matching: { aliasID in
                guard let symbol = ctx.cachedSymbol(aliasID) else { return false }
                return symbol.kind == .typeAlias
            }) where !aliasSymbols.contains(candidate) {
                aliasSymbols.append(candidate)
            }
            let calleeClassifierID: SymbolID? = if case let .call(calleeExpr, _, _, _) = ctx.ast.arena.expr(id) {
                sema.bindings.identifierSymbol(for: calleeExpr)
            } else {
                nil
            }
            let aliasLinkedFromCallee = calleeClassifierID.flatMap { candidate -> SymbolID? in
                guard ctx.cachedSymbol(candidate)?.kind == .typeAlias,
                      ctx.cachedSymbol(candidate)?.flags.contains(.actualDeclaration) == true
                else {
                    return nil
                }
                return candidate
            }
            var expectClassCandidates = calleeClassifierID.map { [$0] } ?? []
            expectClassCandidates.append(contentsOf: ctx.scope.lookupClassifier(calleeName, matching: { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .class && symbol.flags.contains(.expectDeclaration)
            }))
            let aliasLinkedFromExpect = expectClassCandidates.first { expectID in
                guard let actualID = sema.symbols.actualSymbol(for: expectID) else { return false }
                return ctx.cachedSymbol(expectID)?.kind == .class
                    && ctx.cachedSymbol(expectID)?.flags.contains(.expectDeclaration) == true
                    && ctx.cachedSymbol(actualID)?.kind == .typeAlias
            }.flatMap { sema.symbols.actualSymbol(for: $0) }
            let pairedAliasID = aliasLinkedFromCallee ?? aliasLinkedFromExpect
            let pairedExpectClass: SymbolID? = pairedAliasID.flatMap { aliasID -> SymbolID? in
                guard let alias = ctx.cachedSymbol(aliasID) else { return nil }
                return sema.symbols.lookupAll(fqName: alias.fqName).first { expectID in
                    ctx.cachedSymbol(expectID)?.kind == .class
                        && ctx.cachedSymbol(expectID)?.flags.contains(.expectDeclaration) == true
                        && sema.symbols.actualSymbol(for: expectID) == aliasID
                }
            }
            let aliasToExpand = pairedAliasID ?? (candidates.isEmpty ? aliasSymbols.first : nil)
            if let aliasSym = aliasToExpand {
                let aliasTypeParameters = sema.symbols.typeAliasTypeParameters(for: aliasSym)
                if !explicitTypeArgs.isEmpty, explicitTypeArgs.count != aliasTypeParameters.count {
                    sema.diagnostics.error(
                        "KSWIFTK-SEMA-0062",
                        "Type argument count mismatch: expected \(aliasTypeParameters.count) but got \(explicitTypeArgs.count).",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                let aliasTypeArgs: [TypeArg] = if explicitTypeArgs.isEmpty {
                    aliasTypeParameters.map {
                        .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))))
                    }
                } else {
                    explicitTypeArgs.enumerated().map { index, type in
                        let resolved = type == TypeID.invalid
                            ? sema.types.make(.typeParam(TypeParamType(symbol: aliasTypeParameters[index], nullability: .nonNull)))
                            : type
                        return .invariant(resolved)
                    }
                }
                if let expanded = driver.helpers.expandTypeAlias(
                    aliasSym,
                    typeArgs: aliasTypeArgs,
                    sema: sema,
                    visited: [],
                    depth: 0,
                    diagnostics: ctx.sema.diagnostics
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
                            var existingCandidates = candidates
                            if let pairedExpectClass {
                                existingCandidates.removeAll { candidate in
                                    sema.symbols.symbol(candidate)?.kind == .constructor
                                        && sema.symbols.parentSymbol(for: candidate) == pairedExpectClass
                                }
                            }
                            let constructorParameterTypes = vis.compactMap {
                                sema.symbols.functionSignature(for: $0)?.parameterTypes
                            }
                            existingCandidates.removeAll { existingID in
                                guard isHiddenByDeprecatedAnnotation(existingID, symbols: sema.symbols),
                                      let signature = sema.symbols.functionSignature(for: existingID)
                                else {
                                    return false
                                }
                                return constructorParameterTypes.contains(signature.parameterTypes)
                            }
                            let newCtorVis = vis.filter { ctorID in
                                guard let ctorSignature = sema.symbols.functionSignature(for: ctorID) else {
                                    return true
                                }
                                return !existingCandidates.contains { existingID in
                                    sema.symbols.functionSignature(for: existingID)?.parameterTypes == ctorSignature.parameterTypes
                                }
                            }
                            candidates = existingCandidates + newCtorVis
                            constructorTypeAlias = aliasSym
                            let aliasResultType = pairedExpectClass.map { expectID in
                                sema.types.make(.classType(ClassType(
                                    classSymbol: expectID,
                                    args: aliasTypeArgs,
                                    nullability: .nonNull
                                )))
                            }
                            let expandedConstructorType = sema.types.make(.classType(ClassType(
                                classSymbol: constructorOwner,
                                args: classType.args,
                                enclosingTypeArgs: classType.enclosingTypeArgs,
                                nullability: .nonNull
                            )))
                            let innerOuterReceiverType = ctx.implicitReceiverMemberLookupEntries().lazy
                                .compactMap { receiver in
                                    self.driver.helpers.innerClassOuterReceiverType(
                                        for: expandedConstructorType,
                                        receiverType: receiver.type,
                                        sema: sema
                                    )
                                }
                                .first
                            let outerTypeParameterSymbols = sema.symbols.symbol(constructorOwner)?.flags
                                .contains(.innerClass) == true
                                ? driver.helpers.innerTypeAliasOuterTypeParameters(of: aliasSym, sema: sema)
                                : []
                            typeAliasConstructor = TypeAliasConstructorContext(
                                typeParameterSymbols: aliasTypeParameters,
                                expandedType: expandedConstructorType,
                                resultType: aliasResultType,
                                typeAliasSymbol: aliasSym,
                                innerOuterReceiverType: innerOuterReceiverType,
                                outerTypeParameterSymbols: outerTypeParameterSymbols
                            )
                            callInvisible.append(contentsOf: invis)
                        }
                    }
                }
            }
        } else if let calleePath, calleePath.count > 1 {
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
        candidates = preferKotlinStringConstructorFactories(
            candidates,
            calleeName: calleeName,
            calleePath: calleePath,
            ctx: ctx
        )
        return nil
    }

    private func preferKotlinStringConstructorFactories(
        _ candidates: [SymbolID],
        calleeName: InternedString?,
        calleePath: [InternedString]?,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let interner = ctx.interner
        guard calleePath.map({ $0.count <= 1 }) ?? true,
              calleeName == interner.intern("String")
        else {
            return candidates
        }

        let kotlinStringFQName = [interner.intern("kotlin"), interner.intern("String")]
        let kotlinTextStringFQName = [
            interner.intern("kotlin"), interner.intern("text"), interner.intern("String"),
        ]
        let preferredParameterTypes = Set(candidates.compactMap { candidate -> [TypeID]? in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  symbol.fqName == kotlinStringFQName
            else {
                return nil
            }
            return ctx.sema.symbols.functionSignature(for: candidate)?.parameterTypes
        })
        guard !preferredParameterTypes.isEmpty else {
            return candidates
        }

        return candidates.filter { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  symbol.fqName == kotlinTextStringFQName,
                  let signature = ctx.sema.symbols.functionSignature(for: candidate)
            else {
                return true
            }
            return !preferredParameterTypes.contains(signature.parameterTypes)
        }
    }

    func aliasConstructorArgumentContextTypes(
        _ alias: TypeAliasConstructorContext,
        explicitTypeArgs: [TypeID],
        sema: SemaModule
    ) -> [TypeID] {
        guard !explicitTypeArgs.isEmpty || alias.typeParameterSymbols.isEmpty,
              case let .classType(owner) = sema.types.kind(of: alias.expandedType)
        else { return [] }
        let variables = sema.types.makeTypeVarBySymbol(alias.typeParameterSymbols)
        let substitution = Dictionary(uniqueKeysWithValues: zip(alias.typeParameterSymbols, explicitTypeArgs).compactMap {
            symbol, type -> (TypeVarID, TypeID)? in
            guard type != TypeID.invalid else { return nil }
            return variables[symbol].map { ($0, type) }
        })
        return owner.args.compactMap { argument in
            switch argument {
            case let .invariant(type), let .out(type), let .in(type):
                sema.types.substituteTypeParameters(in: type, substitution: substitution, typeVarBySymbol: variables)
            case .star: nil
            }
        }
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
