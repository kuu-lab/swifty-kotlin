
extension CallTypeChecker {
    /// KUU-3237: Kotlin does not resolve nested classifiers through a
    /// typealias qualifier (`A2.Inner`, `A2.Companion` are unresolved
    /// references), while companion members and enum entries remain
    /// reachable through the alias. Import aliases (`import C as A`)
    /// resolve to the class symbol directly and keep classifier access.
    /// The bound identifier is not enough: `expandTypeAliasValueTarget`
    /// rebinds the name to the target nominal when it has a companion,
    /// so the scope candidates for the written name decide.
    func receiverQualifierIsTypeAlias(
        receiverID: ExprID,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        if case let .nameRef(name, _) = ctx.ast.arena.expr(receiverID) {
            if let bound = sema.bindings.identifierSymbol(for: receiverID),
               let symbol = sema.symbols.symbol(bound) {
                switch symbol.kind {
                case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                    break
                default:
                    return false
                }
            }
            return ctx.valueScopeLookup(name).matches.contains {
                sema.symbols.symbol($0)?.kind == .typeAlias
            }
        }
        return sema.bindings.identifierSymbol(for: receiverID)
            .flatMap { sema.symbols.symbol($0) }?.kind == .typeAlias
    }

    func resolveClassNameMemberValue(
        ownerNominalSymbol: SymbolID,
        memberName: InternedString,
        sema: SemaModule
    ) -> (symbol: SymbolID, type: TypeID)? {
        guard let owner = sema.symbols.symbol(ownerNominalSymbol) else {
            return nil
        }
        let memberFQName = owner.fqName + [memberName]
        var candidates = sema.symbols.lookupAll(fqName: memberFQName).sorted(by: { $0.rawValue < $1.rawValue })
        if candidates.isEmpty {
            candidates = sema.symbols.lookupByShortName(memberName)
                .filter { candidate in
                    sema.symbols.parentSymbol(for: candidate) == ownerNominalSymbol
                }
                .sorted(by: { $0.rawValue < $1.rawValue })
        }
        for candidate in candidates {
            guard let candidateSymbol = sema.symbols.symbol(candidate) else {
                continue
            }
            switch candidateSymbol.kind {
            case .field:
                if let fieldType = sema.symbols.propertyType(for: candidate) {
                    return (candidate, fieldType)
                }
            case .property where candidateSymbol.flags.contains(.static):
                if let propertyType = sema.symbols.propertyType(for: candidate) {
                    return (candidate, propertyType)
                }
            case .object:
                let objectType = sema.types.make(.classType(ClassType(
                    classSymbol: candidate,
                    args: [],
                    nullability: .nonNull
                )))
                return (candidate, objectType)
            default:
                continue
            }
        }
        return nil
    }

    func resolveExtensionPropertyGetter(
        id: ExprID,
        calleeName: InternedString,
        range: SourceRange,
        receiverType: TypeID,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        preferredSourcePackage: [InternedString]? = nil,
        bindCall: Bool = true,
        bindExpression: Bool = true,
        requireInScope: Bool = false,
        invocationCandidateFilter: ((SymbolID) -> Bool)? = nil,
        onResolved: ((SymbolID, CallBinding) -> Void)? = nil
    ) -> TypeID? {
        let sema = ctx.sema
        let scopedCandidates = invocationCandidateFilter == nil
            ? ctx.cachedScopeLookup(calleeName) : ctx.scope.lookupMergingChain(calleeName)
        let visible = ctx.filterByVisibility(scopedCandidates).visible
        var getterCandidates: [SymbolID] = []
        var propertyForGetter: [SymbolID: SymbolID] = [:]
        var deferredReceiverConstraints: [SymbolID: [VariableConstraint]] = [:]
        var invisibleProperties: [SymbolID] = []
        func isUserSourceDeclaration(_ candidate: SymbolID) -> Bool {
            guard let sourceFileID = sema.symbols.sourceFileID(for: candidate)
                    ?? sema.symbols.symbol(candidate)?.declSite?.start.file
            else {
                return false
            }
            return driver.sourceManager?.origin(of: sourceFileID) == .user
        }
        func hasDispatchReceiverOrImport(for candidate: SymbolID) -> Bool {
            guard let owner = sema.symbols.parentSymbol(for: candidate),
                  let ownerSymbol = sema.symbols.symbol(owner),
                  ownerSymbol.kind == .class || ownerSymbol.kind == .interface
                      || ownerSymbol.kind == .object
            else {
                return true
            }
            if visible.contains(candidate) {
                return true
            }
            let ownerType = sema.types.make(.classType(ClassType(
                classSymbol: owner, args: [], nullability: .nonNull
            )))
            let receiverTypes = ctx.implicitReceiverMemberLookupEntries().map(\.type)
            return receiverTypes.contains { receiver in
                if sema.types.isSubtype(receiver, ownerType) { return true }
                guard case let .classType(type) = sema.types.kind(of: sema.types.makeNonNullable(receiver)) else { return false }
                return sema.types.isNominalSubtypeSymbol(type.classSymbol, of: owner)
            }
        }
        func isInInvocationScope(_ candidate: SymbolID) -> Bool {
            guard requireInScope else { return true }
            if visible.contains(candidate) { return true }
            guard let symbol = sema.symbols.symbol(candidate) else { return false }
            if let owner = sema.symbols.parentSymbol(for: candidate),
               let ownerInfo = sema.symbols.symbol(owner),
               ownerInfo.kind == .class || ownerInfo.kind == .interface || ownerInfo.kind == .object {
                return hasDispatchReceiverOrImport(for: candidate)
            }
            guard let file = ctx.currentASTFile else { return false }
            let package = Array(symbol.fqName.dropLast())
            if file.packageFQName == package { return true }
            return file.imports.contains { item in
                if item.isWildcard { return item.path == package }
                return item.path == symbol.fqName && (item.alias == nil || item.alias == calleeName)
            }
        }
        func collectGetterCandidate(from candidate: SymbolID, requireSynthetic: Bool) {
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .property,
                  !ctx.isCandidateBlockedByDslMarker(candidate),
                  !requireSynthetic || symbol.flags.contains(.synthetic),
                  hasDispatchReceiverOrImport(for: candidate),
                  isInInvocationScope(candidate),
                  invocationCandidateFilter?(candidate) ?? true,
                  preferredSourcePackage == nil || isUserSourceDeclaration(candidate)
                      || Array(symbol.fqName.dropLast()) == preferredSourcePackage,
                  let receiver = sema.symbols.extensionPropertyReceiverType(for: candidate)
            else {
                return
            }
            let receiverConstraints: [VariableConstraint]?
            if extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: receiverType,
                declaredReceiver: receiver,
                sema: sema
            ) {
                receiverConstraints = nil
            } else if let deferred = deferredBuilderReceiverConstraints(
                callSiteReceiver: receiverType,
                declaredReceiver: receiver,
                ctx: ctx,
                blameRange: range
            ) {
                receiverConstraints = deferred
            } else {
                return
            }
            guard let getterAccessor = sema.symbols.extensionPropertyGetterAccessor(for: candidate) else {
                return
            }
            guard ctx.visibilityChecker.isAccessible(
                symbol,
                fromFile: ctx.currentFileID,
                enclosingClass: ctx.enclosingClassSymbol
            ) else {
                if !invisibleProperties.contains(candidate) {
                    invisibleProperties.append(candidate)
                }
                return
            }
            if !getterCandidates.contains(getterAccessor) {
                getterCandidates.append(getterAccessor)
                propertyForGetter[getterAccessor] = candidate
            }
            if let receiverConstraints {
                deferredReceiverConstraints[candidate] = receiverConstraints
            }
        }
        var implicitMemberExtensionProperties: Set<SymbolID> = []
        for dispatchReceiver in ctx.implicitReceiverMemberLookupEntries() {
            let receiverRoots = driver.helpers.allNominalSymbols(
                of: dispatchReceiver.type,
                types: sema.types,
                symbols: sema.symbols,
                interner: ctx.interner
            )
            for candidate in sema.symbols.lookupByShortName(calleeName) {
                guard !ctx.isCandidateBlockedByDslMarker(candidate),
                      let owner = sema.symbols.memberExtensionOwnerSymbol(for: candidate),
                      receiverRoots.contains(where: { root in
                          root == owner || sema.types.isNominalSubtypeSymbol(root, of: owner)
                      }),
                      let receiver = sema.symbols.extensionPropertyReceiverType(for: candidate),
                      extensionSyntheticFallbackReceiverMatches(
                          callSiteReceiver: receiverType,
                          declaredReceiver: receiver,
                          sema: sema
                      )
                else {
                    continue
                }
                implicitMemberExtensionProperties.insert(candidate)
                collectGetterCandidate(from: candidate, requireSynthetic: false)
            }
        }
        let overridingMemberExtensionProperties = implicitMemberExtensionProperties.filter { property in
            sema.symbols.symbol(property)?.flags.contains(.overrideMember) == true
        }
        if !overridingMemberExtensionProperties.isEmpty {
            getterCandidates.removeAll { getter in
                guard let property = propertyForGetter[getter],
                      let propertyOwner = sema.symbols.memberExtensionOwnerSymbol(for: property),
                      let propertyReceiver = sema.symbols.extensionPropertyReceiverType(for: property)
                else {
                    return false
                }
                return overridingMemberExtensionProperties.contains { overridingProperty in
                    guard overridingProperty != property,
                          let overridingOwner = sema.symbols.memberExtensionOwnerSymbol(for: overridingProperty),
                          overridingOwner != propertyOwner,
                          sema.types.isNominalSubtypeSymbol(overridingOwner, of: propertyOwner),
                          let overridingReceiver = sema.symbols.extensionPropertyReceiverType(for: overridingProperty)
                    else {
                        return false
                    }
                    return sema.types.isSubtype(overridingReceiver, propertyReceiver)
                        && sema.types.isSubtype(propertyReceiver, overridingReceiver)
                }
            }
            propertyForGetter = propertyForGetter.filter { getter, _ in getterCandidates.contains(getter) }
        }
        func isUnavailableKotlinMathProperty(_ candidate: SymbolID) -> Bool {
            guard let symbol = sema.symbols.symbol(candidate) else {
                return false
            }
            let kotlinMathPackage = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("math"),
            ]
            guard Array(symbol.fqName.dropLast()) == kotlinMathPackage else {
                return false
            }
            guard let sourceFile = ctx.currentASTFile else {
                return true
            }
            if sourceFile.packageFQName == kotlinMathPackage {
                return false
            }
            return !sourceFile.imports.contains { importDecl in
                importDecl.path == kotlinMathPackage
                    || importDecl.path == symbol.fqName
            }
        }
        // Canonical and legacy atomic aliases expand to the same runtime class,
        // so a source-backed extension property must be selected by the package
        // imported at the call site rather than by nominal type alone.
        if let preferredSourcePackage {
            let sourceCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .property,
                      Array(symbol.fqName.dropLast()) == preferredSourcePackage
                          || isUserSourceDeclaration(candidate)
                else {
                    return false
                }
                return true
            }
            for candidate in sourceCandidates {
                collectGetterCandidate(from: candidate, requireSynthetic: false)
            }
        }
        for candidate in visible {
            collectGetterCandidate(from: candidate, requireSynthetic: false)
        }
        let implicitMemberExtensionGetters = Set(getterCandidates.filter { getter in
            guard let property = propertyForGetter[getter] else { return false }
            return implicitMemberExtensionProperties.contains(property)
        })
        if !implicitMemberExtensionGetters.isEmpty {
            getterCandidates = getterCandidates.filter(implicitMemberExtensionGetters.contains)
            propertyForGetter = propertyForGetter.filter { implicitMemberExtensionGetters.contains($0.key) }
        }
        // Short-name fallback, restricted to known JVM property names to avoid
        // accidentally resolving unrelated experimental APIs.
        let knownJvmPropertyNames: Set<String> = ["java", "javaObjectType", "javaPrimitiveType", "kotlin", "declaringJavaClass"]
        if getterCandidates.isEmpty,
           knownJvmPropertyNames.contains(ctx.interner.resolve(calleeName))
        {
            for candidate in sema.symbols.lookupByShortName(calleeName) {
                collectGetterCandidate(from: candidate, requireSynthetic: true)
            }
        }
        // Imported library extension properties are intentionally omitted from
        // file scopes and are resolved through member lookup instead. Recover
        // their synthetic accessors by short name when scope lookup found none;
        // the receiver check keeps this fallback type-directed.
        if getterCandidates.isEmpty {
            for candidate in sema.symbols.lookupByShortName(calleeName)
                where !isUnavailableKotlinMathProperty(candidate)
            {
                collectGetterCandidate(from: candidate, requireSynthetic: true)
            }
        }
        // Bundled stdlib source extension properties are not necessarily in the
        // consumer file scope. Recover their accessors by short name as well;
        // the receiver check above keeps this fallback type-directed.
        if getterCandidates.isEmpty {
            for candidate in sema.symbols.lookupByShortName(calleeName)
                where sema.symbols.isSourceBackedSymbol(candidate)
                    && !isUnavailableKotlinMathProperty(candidate)
            {
                collectGetterCandidate(from: candidate, requireSynthetic: false)
            }
        }
        guard !getterCandidates.isEmpty else {
            if let firstInvisible = invisibleProperties.first,
               let invisibleSymbol = sema.symbols.symbol(firstInvisible)
            {
                // Compound-assignment reads bind the property identifier rather
                // than a call; the caller re-checks accessibility on that bound
                // symbol, so surface the invisible declaration instead of
                // emitting a duplicate diagnostic here.
                guard bindCall, bindExpression else {
                    if !bindExpression {
                        driver.helpers.emitVisibilityError(
                            for: invisibleSymbol,
                            name: ctx.interner.resolve(calleeName),
                            range: range,
                            diagnostics: ctx.sema.diagnostics
                        )
                        return sema.types.errorType
                    }
                    sema.bindings.bindIdentifier(id, symbol: firstInvisible)
                    return sema.symbols.propertyType(for: firstInvisible)
                        ?? sema.types.errorType
                }
                driver.helpers.emitVisibilityError(
                    for: invisibleSymbol,
                    name: ctx.interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.sema.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            return nil
        }

        if invocationCandidateFilter != nil,
           let priority = getterCandidates.compactMap({ propertyForGetter[$0] }).map({
               callableInvocationScopePriority($0, named: calleeName, ctx: ctx)
           }).min() {
            getterCandidates.removeAll { getter in
                guard let property = propertyForGetter[getter] else { return true }
                return callableInvocationScopePriority(property, named: calleeName, ctx: ctx) != priority
            }
        }
        getterCandidates = preferMostSpecificMemberReceiverCandidates(
            getterCandidates,
            receiverType: resolvedBuilderInferenceType(receiverType, ctx: ctx),
            sema: sema,
            interner: ctx.interner
        )
        propertyForGetter = propertyForGetter.filter { getter, _ in getterCandidates.contains(getter) }
        if getterCandidates.count == 1,
           let getter = getterCandidates.first,
           let property = propertyForGetter[getter],
           let constraints = deferredReceiverConstraints[property]
        {
            ctx.builderInference?.constraints.append(contentsOf: constraints)
        }
        let resolvedReceiverType = resolvedBuilderInferenceType(receiverType, ctx: ctx)
        var resolved = ctx.resolver.resolveCall(
            candidates: getterCandidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: [],
                dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
            ),
            expectedType: expectedType,
            implicitReceiverType: resolvedReceiverType,
            ctx: ctx.sema
        )
        // A property can be used where a contravariant generic type is
        // expected (for example Comparator<String> passed to sortedWith's
        // Comparator<in String> parameter).  The callable resolver's
        // expected-return-type check is stricter than Kotlin's variance rule;
        // retry without that contextual constraint after receiver filtering so
        // the unique source-backed getter still resolves.
        if resolved.chosenCallee == nil, expectedType != nil {
            resolved = ctx.resolver.resolveCall(
                candidates: getterCandidates,
                call: CallExpr(
                    range: range,
                    calleeName: calleeName,
                    args: [],
                    dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
                ),
                expectedType: nil,
                implicitReceiverType: resolvedReceiverType,
                ctx: ctx.sema
            )
        }
        if resolved.diagnostic != nil {
            return nil
        }
        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        validateReifiedPropertyArguments(chosen, arguments: resolved.substitutedTypeArguments, range: range, ctx: ctx)

        let importedDispatchReceiver = importedObjectDispatchReceiverOwners(
            named: calleeName,
            candidates: [chosen],
            ctx: ctx
        )[chosen]
        let memberExtensionDispatchReceiver = sema.symbols.memberExtensionOwnerSymbol(for: chosen).flatMap { owner in
            ctx.implicitReceiverMemberLookupEntries().first { entry in
                let roots = driver.helpers.allNominalSymbols(
                    of: entry.type,
                    types: sema.types,
                    symbols: sema.symbols,
                    interner: ctx.interner
                )
                return roots.contains { root in
                    root == owner || sema.types.isNominalSubtypeSymbol(root, of: owner)
                }
            }?.symbol
        }
        let dispatchReceiver = importedDispatchReceiver ?? memberExtensionDispatchReceiver

        let getterBinding = CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: resolved.substitutedTypeArguments.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value),
            parameterMapping: resolved.parameterMapping,
            dispatchReceiverSymbol: dispatchReceiver,
            contextParameterReceiverSymbols: contextParameterReceiverSymbols(
                for: chosen,
                substitution: resolved.substitutedTypeArguments,
                ctx: ctx
            )
        )
        if bindExpression {
            sema.bindings.bindExtensionPropertyGetterCall(id, binding: getterBinding)
        } else if let property = propertyForGetter[chosen] ?? sema.symbols.accessorOwnerProperty(for: chosen) {
            onResolved?(property, getterBinding)
        }
        if bindExpression && bindCall {
            sema.bindings.bindCall(
                id,
                binding: getterBinding
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        }
        let deprecationCheckTarget: SymbolID
        // Compound assignment (`bindCall == false`) reads the selected property
        // directly, so its l-value needs the parent-property identifier binding.
        // Plain reads keep the accessor-owner-only behaviour so lowering still
        // dispatches through the getter call binding.
        let ownerProperty = sema.symbols.accessorOwnerProperty(for: chosen)
            ?? (bindCall ? nil : propertyForGetter[chosen] ?? sema.symbols.parentSymbol(for: chosen))
        if bindExpression, let ownerProperty, sema.symbols.symbol(ownerProperty)?.kind == .property {
            sema.bindings.bindIdentifier(id, symbol: ownerProperty)
            deprecationCheckTarget = ownerProperty
        } else {
            deprecationCheckTarget = chosen
        }
        driver.helpers.checkDeprecation(
            for: deprecationCheckTarget,
            sema: sema,
            interner: ctx.interner,
            range: range,
            diagnostics: ctx.sema.diagnostics
        )
        driver.helpers.checkOptIn(
            for: deprecationCheckTarget,
            ctx: ctx,
            range: range,
            diagnostics: ctx.sema.diagnostics
        )
        if let property = propertyForGetter[chosen], property != deprecationCheckTarget {
            driver.helpers.checkOptIn(
                for: property,
                ctx: ctx,
                range: range,
                diagnostics: ctx.sema.diagnostics
            )
        }
        guard let signature = sema.symbols.functionSignature(for: chosen) else {
            return sema.types.anyType
        }
        // Source getters may retain an erased header return type. Callable
        // property invocation needs the declared property function type, with
        // the same inferred type arguments as its selected getter.
        var returnType = propertyForGetter[chosen].flatMap { sema.symbols.propertyType(for: $0) } ?? signature.returnType
        if let property = propertyForGetter[chosen],
           let owner = sema.symbols.parentSymbol(for: property),
           let info = sema.symbols.symbol(owner),
           info.kind == .class || info.kind == .interface || info.kind == .object {
            let ownerType = sema.types.make(.classType(ClassType(classSymbol: owner, args: [], nullability: .nonNull)))
            let dispatchTypes = ctx.implicitReceiverMemberLookupEntries().map(\.type)
            if let dispatchType = dispatchTypes.first(where: { receiver in
                if sema.types.isSubtype(receiver, ownerType) { return true }
                guard case let .classType(type) = sema.types.kind(of: sema.types.makeNonNullable(receiver)) else { return false }
                return sema.types.isNominalSubtypeSymbol(type.classSymbol, of: owner)
            }) {
                returnType = driver.helpers.resolveMemberPropertyType(
                    returnType, receiverType: dispatchType, ownerSymbol: owner, sema: sema
                )
            }
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        return sema.types.substituteTypeParameters(
            in: returnType,
            substitution: resolved.substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    /// Setter counterpart of `resolveExtensionPropertyGetter`: an extension
    /// `var` written through an explicit receiver (`a.value = x`) is not found
    /// by `lookupMemberProperty` — its symbol lives at package scope — so
    /// `memberAssign` never bound it and KIR fell back to a call named after
    /// the property, which failed to link. Resolves the property through the
    /// same candidate sources the getter uses and binds it (plus the setter
    /// accessor as the call target) so lowering can route the write through
    /// the registered setter accessor.
    func resolveExtensionPropertySetter(
        id: ExprID,
        calleeName: InternedString,
        range: SourceRange,
        receiverType: TypeID,
        value: ExprID,
        locals: inout LocalBindings,
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        let sema = ctx.sema
        var setterCandidates: [SymbolID] = []
        var propertyForSetter: [SymbolID: SymbolID] = [:]
        var invisibleProperties: [SemanticSymbol] = []
        var lexicalClassOwners: [SymbolID] = []
        var lexicalScope: Scope? = ctx.scope
        while let scope = lexicalScope as? BaseScope {
            if let memberScope = scope as? ClassMemberScope {
                lexicalClassOwners.append(memberScope.owner)
            }
            lexicalScope = scope.parent
        }
        func isAccessibleFromLexicalScope(_ symbol: SemanticSymbol) -> Bool {
            ctx.visibilityChecker.isAccessible(
                symbol,
                fromFile: ctx.currentFileID,
                enclosingClass: ctx.enclosingClassSymbol
            ) || lexicalClassOwners.contains {
                ctx.visibilityChecker.isAccessible(
                    symbol,
                    fromFile: ctx.currentFileID,
                    enclosingClass: $0
                )
            }
        }
        func collectSetterCandidate(from candidate: SymbolID, requireSynthetic: Bool) {
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .property,
                  !requireSynthetic || symbol.flags.contains(.synthetic),
                  let receiver = sema.symbols.extensionPropertyReceiverType(for: candidate),
                  extensionSyntheticFallbackReceiverMatches(
                      callSiteReceiver: receiverType,
                      declaredReceiver: receiver,
                      sema: sema
                  ),
                  let setterAccessor = sema.symbols.extensionPropertySetterAccessor(for: candidate)
            else {
                return
            }
            if let owner = sema.symbols.memberExtensionOwnerSymbol(for: candidate) {
                let hasReceiver = ctx.implicitReceiverMemberLookupEntries().contains { entry in
                    driver.helpers.allNominalSymbols(
                        of: entry.type, types: sema.types, symbols: sema.symbols, interner: ctx.interner
                    ).contains { root in
                        root == owner || sema.types.isNominalSubtypeSymbol(root, of: owner)
                    }
                }
                let hasImportedReceiver = importedObjectDispatchReceiverOwners(
                    named: calleeName, candidates: [setterAccessor], ctx: ctx
                )[setterAccessor] != nil
                guard hasReceiver || hasImportedReceiver else { return }
            }
            guard isAccessibleFromLexicalScope(symbol) else {
                if !invisibleProperties.contains(where: { $0.id == symbol.id }) {
                    invisibleProperties.append(symbol)
                }
                return
            }
            if let setterVisibility = sema.symbols.propertySetterVisibility(for: candidate) {
                let setter = SemanticSymbol(
                    id: symbol.id,
                    kind: symbol.kind,
                    name: symbol.name,
                    fqName: symbol.fqName,
                    declSite: symbol.declSite,
                    visibility: setterVisibility,
                    flags: symbol.flags
                )
                guard isAccessibleFromLexicalScope(setter) else {
                    if !invisibleProperties.contains(where: { $0.id == setter.id }) {
                        invisibleProperties.append(setter)
                    }
                    return
                }
            }
            if !setterCandidates.contains(setterAccessor) {
                setterCandidates.append(setterAccessor)
                propertyForSetter[setterAccessor] = candidate
            }
        }
        for candidate in ctx.cachedScopeLookup(calleeName) {
            collectSetterCandidate(from: candidate, requireSynthetic: false)
        }
        // Bundled stdlib source extension properties are not necessarily in the
        // consumer file scope; recover them by short name, mirroring the
        // getter-side fallbacks (imported/synthetic props last).
        if setterCandidates.isEmpty {
            for candidate in sema.symbols.lookupByShortName(calleeName)
                where sema.symbols.isSourceBackedSymbol(candidate)
            {
                collectSetterCandidate(from: candidate, requireSynthetic: false)
            }
        }
        if setterCandidates.isEmpty {
            for candidate in sema.symbols.lookupByShortName(calleeName) {
                collectSetterCandidate(from: candidate, requireSynthetic: true)
            }
        }
        func hasMoreSpecificReceiver(_ lhs: SymbolID, than rhs: SymbolID) -> Bool {
            guard let lhsReceiver = sema.symbols.extensionPropertyReceiverType(for: lhs),
                  let rhsReceiver = sema.symbols.extensionPropertyReceiverType(for: rhs),
                  !typeMentionsTypeParameter(lhsReceiver, sema: sema),
                  !typeMentionsTypeParameter(rhsReceiver, sema: sema)
            else { return false }
            return sema.types.isSubtype(lhsReceiver, rhsReceiver)
                && !sema.types.isSubtype(rhsReceiver, lhsReceiver)
        }
        if !setterCandidates.isEmpty,
           let inaccessible = invisibleProperties.first(where: { hidden in
               setterCandidates.allSatisfy { candidate in
                   guard let property = propertyForSetter[candidate] else { return false }
                   return hasMoreSpecificReceiver(hidden.id, than: property)
               }
           })
        {
            _ = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
            driver.helpers.emitVisibilityError(
                for: inaccessible, name: ctx.interner.resolve(calleeName),
                range: range, diagnostics: sema.diagnostics
            )
            return nil
        }
        guard !setterCandidates.isEmpty else {
            let errorsBeforeValue = sema.diagnostics.errorCount
            _ = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
            if let invisibleSymbol = invisibleProperties.first {
                driver.helpers.emitVisibilityError(
                    for: invisibleSymbol,
                    name: ctx.interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.sema.diagnostics
                )
            } else if let privateMember = driver.helpers.inaccessiblePrivateQualifiedMember(
                named: calleeName,
                probeReceiverTypes: [sema.types.makeNonNullable(receiverType)],
                ctx: ctx
            ) {
                // Inherited `private` members never enter the write lookup
                // (they are not inherited), but a qualified assignment still
                // resolves the name — report it as inaccessible rather than
                // unresolved, matching kotlinc (KUU-3762). A class-name
                // receiver was already retyped to its companion object type.
                driver.helpers.emitVisibilityError(
                    for: privateMember,
                    name: ctx.interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.sema.diagnostics
                )
            } else if sema.diagnostics.errorCount == errorsBeforeValue {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0022", "Unresolved reference '\(ctx.interner.resolve(calleeName))'.", range: range
                )
            }
            return nil
        }

        let expectedValueType: TypeID?
        if case .lambdaLiteral = ctx.ast.arena.expr(value) {
            expectedValueType = lambdaLiteralExpectedType(
                at: 0,
                args: [CallArgument(expr: value)],
                callRange: range,
                candidates: setterCandidates,
                receiverType: receiverType,
                resolver: ctx.resolver,
                sema: sema,
                ctx: ctx
            ).type
        } else if isInferableNestedCallExpr(value, ast: ctx.ast) {
            // Extension properties are selected by receiver specificity. Do not
            // let a less-specific receiver hide the selected setter's context.
            let contextualCandidates = setterCandidates.filter { candidate in
                guard let property = propertyForSetter[candidate] else { return true }
                return !setterCandidates.contains { other in
                    guard other != candidate,
                          let otherProperty = propertyForSetter[other]
                    else { return false }
                    return hasMoreSpecificReceiver(otherProperty, than: property)
                }
            }
            let inaccessibleMayCompete = invisibleProperties.contains { hidden in
                !contextualCandidates.contains { candidate in
                    guard let property = propertyForSetter[candidate] else { return false }
                    return hasMoreSpecificReceiver(property, than: hidden.id)
                }
            }
            expectedValueType = inaccessibleMayCompete ? nil : contextualExtensionSetterValueType(
                candidates: contextualCandidates, receiverType: receiverType, ctx: ctx
            )
        } else {
            expectedValueType = nil
        }
        let valueType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: expectedValueType)

        let resolved = ctx.resolver.resolveCall(
            candidates: setterCandidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: [CallArg(type: valueType)],
                dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
            ),
            expectedType: nil,
            implicitReceiverType: receiverType,
            ctx: ctx.sema
        )
        if let diagnostic = resolved.diagnostic {
            ctx.sema.diagnostics.emit(diagnostic)
            return nil
        }
        guard let chosen = resolved.chosenCallee,
              let propertySymbol = propertyForSetter[chosen]
                  ?? sema.symbols.accessorOwnerProperty(for: chosen)
        else {
            return nil
        }

        let importedDispatchReceiver = importedObjectDispatchReceiverOwners(
            named: calleeName, candidates: [chosen], ctx: ctx
        )[chosen]
        let dispatchReceiverSymbol = importedDispatchReceiver ?? sema.symbols.memberExtensionOwnerSymbol(for: chosen).flatMap { owner in
            ctx.implicitReceiverMemberLookupEntries().first { entry in
                guard case let .classType(receiverClass) = sema.types.kind(
                    of: sema.types.makeNonNullable(entry.type)
                ) else {
                    return false
                }
                return sema.types.isNominalSubtypeSymbol(receiverClass.classSymbol, of: owner)
            }?.symbol
        }

        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map(\.value),
                parameterMapping: resolved.parameterMapping,
                dispatchReceiverSymbol: dispatchReceiverSymbol,
                contextParameterReceiverSymbols: contextParameterReceiverSymbols(
                    for: chosen,
                    substitution: resolved.substitutedTypeArguments,
                    ctx: ctx
                )
            )
        )
        validateReifiedPropertyArguments(chosen, arguments: resolved.substitutedTypeArguments, range: range, ctx: ctx)
        sema.bindings.bindIdentifier(id, symbol: propertySymbol)
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        driver.helpers.checkDeprecation(
            for: propertySymbol,
            sema: sema,
            interner: ctx.interner,
            range: range,
            diagnostics: ctx.sema.diagnostics
        )
        driver.helpers.checkOptIn(
            for: propertySymbol,
            ctx: ctx,
            range: range,
            diagnostics: ctx.sema.diagnostics
        )
        return propertySymbol
    }

    private func contextualExtensionSetterValueType(
        candidates: [SymbolID], receiverType: TypeID, ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        var commonType: TypeID?
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1
            else { return nil }
            let owner = sema.symbols.memberExtensionOwnerSymbol(for: candidate)
            let property = sema.symbols.accessorOwnerProperty(for: candidate)
                ?? sema.symbols.parentSymbol(for: candidate)
            let dispatchReceiver = owner.flatMap { owner in
                ctx.implicitReceiverMemberLookupEntries().first { entry in
                    driver.helpers.allNominalSymbols(
                        of: entry.type, types: sema.types, symbols: sema.symbols, interner: ctx.interner
                    ).contains { root in
                        root == owner || sema.types.isNominalSubtypeSymbol(root, of: owner)
                    }
                }?.type
            }
            let dispatchSubstituted: TypeID
            if owner != nil, let property {
                dispatchSubstituted = applyDispatchReceiverClassTypeArgs(
                    to: signature.parameterTypes[0], signature: signature, candidate: property, ctx: ctx
                )
            } else {
                dispatchSubstituted = signature.parameterTypes[0]
            }
            let classSubstituted = applyReceiverClassTypeArgs(
                to: dispatchSubstituted, signature: signature,
                candidate: candidate, receiverType: receiverType, sema: sema
            )
            let parameterType = applyFunctionReceiverTypeArgs(
                to: classSubstituted, signature: signature, receiverType: receiverType, sema: sema
            )
            let unresolvedSymbols: [SymbolID] = signature.typeParameterSymbols.enumerated().compactMap { index, symbol in
                if index < signature.classTypeParameterCount, let dispatchReceiver,
                   sema.types.typeContainsTypeParam(dispatchReceiver, symbol: symbol) {
                    return nil
                }
                return symbol
            }
            let typeVars = sema.types.makeTypeVarBySymbol(unresolvedSymbols)
            guard !ctx.resolver.containsTypeVariable(
                parameterType, typeVarBySymbol: typeVars, typeSystem: sema.types
            ) else { return nil }
            if let commonType, commonType != parameterType { return nil }
            commonType = parameterType
        }
        return commonType
    }

    private func validateReifiedPropertyArguments(
        _ accessor: SymbolID, arguments: [TypeVarID: TypeID], range: SourceRange, ctx: TypeInferenceContext
    ) {
        guard let signature = ctx.sema.symbols.functionSignature(for: accessor) else { return }
        let typeVariables = ctx.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        func cannotBeReified(_ type: TypeID) -> Bool {
            switch ctx.sema.types.kind(of: type) {
            case let .typeParam(parameter):
                return ctx.sema.symbols.symbol(parameter.symbol)?.flags.contains(.reifiedTypeParameter) != true
            default:
                return false
            }
        }
        for index in signature.reifiedTypeParameterIndices where index < signature.typeParameterSymbols.count {
            guard let variable = typeVariables[signature.typeParameterSymbols[index]],
                  let argument = arguments[variable] else { continue }
            if cannotBeReified(argument) {
                ctx.sema.diagnostics.error("KSWIFTK-SEMA-0020", "This type cannot be used as a reified property type argument.", range: range)
            }
        }
    }
}
