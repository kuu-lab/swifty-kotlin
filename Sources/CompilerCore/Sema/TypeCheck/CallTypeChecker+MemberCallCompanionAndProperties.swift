
extension CallTypeChecker {
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
        requireInScope: Bool = false,
        invocationCandidateFilter: ((SymbolID) -> Bool)? = nil
    ) -> TypeID? {
        let sema = ctx.sema
        let scopedCandidates = invocationCandidateFilter == nil
            ? ctx.cachedScopeLookup(calleeName) : ctx.scope.lookupMergingChain(calleeName)
        let visible = ctx.filterByVisibility(scopedCandidates).visible
        var getterCandidates: [SymbolID] = []
        var propertyForGetter: [SymbolID: SymbolID] = [:]
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
            var receiverTypes = ctx.outerReceiverTypes.map(\.type)
            if let implicitReceiverType = ctx.implicitReceiverType {
                receiverTypes.append(implicitReceiverType)
            }
            if let enclosingClass = ctx.enclosingClassSymbol {
                receiverTypes.append(sema.types.make(.classType(ClassType(
                    classSymbol: enclosingClass, args: [], nullability: .nonNull
                ))))
            }
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
                  !requireSynthetic || symbol.flags.contains(.synthetic),
                  hasDispatchReceiverOrImport(for: candidate),
                  isInInvocationScope(candidate),
                  invocationCandidateFilter?(candidate) ?? true,
                  preferredSourcePackage == nil || isUserSourceDeclaration(candidate)
                      || Array(symbol.fqName.dropLast()) == preferredSourcePackage,
                  let receiver = sema.symbols.extensionPropertyReceiverType(for: candidate),
                  extensionSyntheticFallbackReceiverMatches(
                      callSiteReceiver: receiverType,
                      declaredReceiver: receiver,
                      sema: sema
                  ),
                  let getterAccessor = sema.symbols.extensionPropertyGetterAccessor(for: candidate)
            else {
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
        // STDLIB-JVM-PROP-003: Fallback to short-name lookup for JVM reflection
        // properties (e.g. KClass<T>.java). Restricted to known JVM property names
        // to avoid accidentally resolving unrelated experimental APIs.
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
                guard bindCall else {
                    sema.bindings.bindIdentifier(id, symbol: firstInvisible)
                    return sema.symbols.propertyType(for: firstInvisible)
                        ?? sema.types.errorType
                }
                driver.helpers.emitVisibilityError(
                    for: invisibleSymbol,
                    name: ctx.interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
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
        var resolved = ctx.resolver.resolveCall(
            candidates: getterCandidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: [],
                dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
            ),
            expectedType: expectedType,
            implicitReceiverType: receiverType,
            ctx: ctx.semaCtx
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
                implicitReceiverType: receiverType,
                ctx: ctx.semaCtx
            )
        }
        if resolved.diagnostic != nil {
            return nil
        }
        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        validateReifiedPropertyArguments(chosen, arguments: resolved.substitutedTypeArguments, range: range, ctx: ctx)

        sema.bindings.bindExtensionPropertyGetterCall(id, binding: CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: resolved.substitutedTypeArguments.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value),
            parameterMapping: resolved.parameterMapping
        ))
        if bindCall {
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
        }
        let deprecationCheckTarget: SymbolID
        // Compound assignment (`bindCall == false`) reads the selected property
        // directly, so its l-value needs the parent-property identifier binding.
        // Plain reads keep the accessor-owner-only behaviour so lowering still
        // dispatches through the getter call binding.
        let ownerProperty = sema.symbols.accessorOwnerProperty(for: chosen)
            ?? (bindCall ? nil : propertyForGetter[chosen] ?? sema.symbols.parentSymbol(for: chosen))
        if let ownerProperty, sema.symbols.symbol(ownerProperty)?.kind == .property {
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
            diagnostics: ctx.semaCtx.diagnostics
        )
        driver.helpers.checkOptIn(
            for: deprecationCheckTarget,
            ctx: ctx,
            range: range,
            diagnostics: ctx.semaCtx.diagnostics
        )
        if let property = propertyForGetter[chosen], property != deprecationCheckTarget {
            driver.helpers.checkOptIn(
                for: property,
                ctx: ctx,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
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
        valueType: TypeID,
        ctx: TypeInferenceContext
    ) -> SymbolID? {
        let sema = ctx.sema
        var setterCandidates: [SymbolID] = []
        var propertyForSetter: [SymbolID: SymbolID] = [:]
        var invisibleProperties: [SymbolID] = []
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
            if !setterCandidates.contains(setterAccessor) {
                setterCandidates.append(setterAccessor)
                propertyForSetter[setterAccessor] = candidate
            }
        }
        for candidate in ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible {
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
        guard !setterCandidates.isEmpty else {
            if let firstInvisible = invisibleProperties.first,
               let invisibleSymbol = sema.symbols.symbol(firstInvisible)
            {
                driver.helpers.emitVisibilityError(
                    for: invisibleSymbol,
                    name: ctx.interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            return nil
        }

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
            ctx: ctx.semaCtx
        )
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            return nil
        }
        guard let chosen = resolved.chosenCallee,
              let propertySymbol = propertyForSetter[chosen]
                  ?? sema.symbols.accessorOwnerProperty(for: chosen)
        else {
            return nil
        }

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
        validateReifiedPropertyArguments(chosen, arguments: resolved.substitutedTypeArguments, range: range, ctx: ctx)
        sema.bindings.bindIdentifier(id, symbol: propertySymbol)
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        driver.helpers.checkDeprecation(
            for: propertySymbol,
            sema: sema,
            interner: ctx.interner,
            range: range,
            diagnostics: ctx.semaCtx.diagnostics
        )
        driver.helpers.checkOptIn(
            for: propertySymbol,
            ctx: ctx,
            range: range,
            diagnostics: ctx.semaCtx.diagnostics
        )
        return propertySymbol
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
                ctx.semaCtx.diagnostics.error("KSWIFTK-SEMA-0020", "This type cannot be used as a reified property type argument.", range: range)
            }
        }
    }
}
