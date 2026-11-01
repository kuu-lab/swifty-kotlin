
extension DataFlowSemaPhase {
    func analyzeBody(
        declID: DeclID,
        ast: ASTModule,
        symbols _: SymbolTable,
        types _: TypeSystem,
        bindings _: BindingTable,
        diagnostics: DiagnosticEngine,
        interner _: StringInterner
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        switch decl {
        case let .funDecl(funDecl):
            var seenNames: Set<InternedString> = []
            for valueParam in funDecl.valueParams {
                if seenNames.contains(valueParam.name) {
                    diagnostics.error(
                        "KSWIFTK-TYPE-0002",
                        "Duplicate function parameter name.",
                        range: funDecl.range
                    )
                }
                seenNames.insert(valueParam.name)
            }

        case .propertyDecl:
            break

        case .classDecl, .interfaceDecl, .objectDecl, .typeAliasDecl, .enumEntryDecl:
            break
        }
    }

    func resolveTypeRef(
        _ typeRefID: TypeRefID?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        sourceManager: SourceManager? = nil,
        localTypeParameters: [InternedString: SymbolID] = [:],
        relativeOwnerFQName: [InternedString]? = nil,
        currentPackageFQName: [InternedString]? = nil,
        imports: [ImportDecl] = [],
        diagnostics: DiagnosticEngine? = nil,
        recursionDepth: Int = 0,
        usageRange: SourceRange? = nil,
        expandTypeAlias: Bool = true
    ) -> TypeID? {
        guard recursionDepth <= DataFlowSemaPhase.maxStructuralRecursionDepth else {
            diagnostics?.error(
                "KSWIFTK-SEMA-TYPE-DEPTH",
                "Type nesting is too deep (exceeded maximum depth of \(DataFlowSemaPhase.maxStructuralRecursionDepth)).",
                range: nil
            )
            return types.errorType
        }
        guard let typeRefID, let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }

        switch typeRef {
        case let .named(path, argRefs, nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull

            guard let shortName = path.last else {
                return nil
            }

            if path.count == 1, let typeParamSymbol = localTypeParameters[shortName] {
                return types.make(.typeParam(TypeParamType(symbol: typeParamSymbol, nullability: nullability)))
            }

            var builtinShadow: SemanticSymbol?
            if let builtinType = builtinTypeNames(interner: interner).resolveBuiltinType(
                shortName,
                nullability: nullability,
                types: types
            ) {
                let kotlinRoot = interner.intern("kotlin")
                let mayShadow = path.count == 1 && (
                    imports.contains { !$0.isWildcard && ($0.alias == shortName || $0.path.last == shortName) }
                        || symbols.lookupByShortName(shortName).contains { id in
                            guard let symbol = symbols.symbol(id) else { return false }
                            return isNominalTypeSymbol(symbol.kind) && symbol.fqName.first != kotlinRoot
                        }
                )
                if mayShadow {
                    func accessible(_ symbol: SemanticSymbol) -> Bool {
                        guard isNominalTypeSymbol(symbol.kind) else { return false }
                        if symbol.visibility == .private, let file = usageRange?.start.file,
                           let declarationFile = symbols.sourceFileID(for: symbol.id) ?? symbol.declSite?.start.file,
                           declarationFile != file
                        { return false }
                        return true
                    }
                    let relative = relativeOwnerFQName.map {
                        resolveRelativeNominalCandidates(named: shortName, relativeTo: $0,
                                                         currentPackageFQName: currentPackageFQName, symbols: symbols)
                    } ?? []
                    builtinShadow = relative.first(where: accessible)
                    let explicitImports = imports.filter {
                        !$0.isWildcard && ($0.alias == shortName || ($0.alias == nil && $0.path.last == shortName))
                    }
                    if builtinShadow == nil {
                        if explicitImports.contains(where: { $0.path == [kotlinRoot, shortName] }) {
                            return builtinType
                        }
                        builtinShadow = explicitImports.lazy.flatMap { declaration in
                            symbols.lookupAll(fqName: declaration.path).compactMap { symbols.symbol($0) }
                        }.first(where: accessible)
                    }
                    if builtinShadow == nil {
                        let package = currentPackageFQName ?? usageRange.flatMap { ast.file(for: $0.start.file)?.packageFQName } ?? []
                        builtinShadow = symbols.lookupAll(fqName: package + [shortName])
                            .compactMap { symbols.symbol($0) }.first(where: accessible)
                    }
                }
                // Named imports and same-package declarations can shadow a
                // builtin; wildcard imports and root fallbacks cannot.
                if builtinShadow == nil || builtinShadow?.fqName.first == kotlinRoot { return builtinType }
            }

            var candidates: [SemanticSymbol]
            if let builtinShadow {
                candidates = [builtinShadow]
            } else if let relativeOwnerFQName
            {
                // Resolve the lexical root before walking a qualified nested name.
                // For example, Slot.Task inside Ch refers to Ch.Slot.Task.
                // Qualified type annotations can start at a lexically enclosing
                // declaration, such as Slot.Closed inside the class owning Slot.
                let relativeRoots = resolveRelativeNominalCandidates(
                    named: path[0],
                    relativeTo: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    symbols: symbols
                )
                let relativeCandidates = path.count == 1 ? relativeRoots : relativeRoots.flatMap { root in
                    symbols.lookupAll(fqName: root.fqName + Array(path.dropFirst()))
                        .compactMap { symbols.symbol($0) }
                        .filter { isNominalTypeSymbol($0.kind) }
                }
                if !relativeCandidates.isEmpty {
                    candidates = relativeCandidates
                } else {
                    let fqCandidates = resolveNominalCandidates(
                        for: path,
                        currentPackageFQName: currentPackageFQName,
                        imports: imports,
                        symbols: symbols,
                        interner: interner
                    )
                    if !fqCandidates.isEmpty {
                        candidates = fqCandidates
                    } else if path.count == 1 {
                        candidates = unqualifiedFallbackNominals(
                            named: shortName,
                            currentPackageFQName: currentPackageFQName,
                            imports: imports,
                            usageRange: usageRange,
                            ast: ast,
                            symbols: symbols,
                            types: types,
                            sourceManager: sourceManager,
                            interner: interner,
                            relativeOwnerFQName: relativeOwnerFQName,
                            recursionDepth: recursionDepth
                        )
                    } else {
                        candidates = []
                    }
                }
            } else {
                let fqCandidates = resolveNominalCandidates(
                    for: path,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    symbols: symbols,
                    interner: interner
                )
                if !fqCandidates.isEmpty {
                    candidates = fqCandidates
                } else if path.count == 1 {
                    candidates = unqualifiedFallbackNominals(
                        named: shortName,
                        currentPackageFQName: currentPackageFQName,
                        imports: imports,
                        usageRange: usageRange,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        sourceManager: sourceManager,
                        interner: interner,
                        relativeOwnerFQName: relativeOwnerFQName,
                        recursionDepth: recursionDepth
                    )
                } else {
                    candidates = []
                }
            }
            if candidates.isEmpty,
               let arity = types.functionNInterfaceArity(named: path, interner: interner),
               let functionN = ensureSyntheticFunctionInterface(
                   arity: arity,
                   symbols: symbols,
                   types: types,
                   interner: interner
               ),
               let symbol = symbols.symbol(functionN)
            {
                // FunctionN has a compiler-internal FQN under kotlin.Function,
                // while source annotations use the default-imported kotlin name.
                candidates = [symbol]
            }
            if let resolved = candidates.first(where: { isNominalTypeSymbol($0.kind) }) {
                let isBundledDeclaration = (symbols.sourceFileID(for: resolved.id) ?? resolved.declSite?.start.file)
                    .map { sourceManager?.origin(of: $0)?.isBundledStdlib == true } == true
                // Header resolution has no enclosing-class context here. The
                // source-origin check enforces the stdlib's internal module
                // boundary; private/protected source access uses type checking.
                if resolved.flags.contains(.importedLibrary) || (isBundledDeclaration && resolved.visibility == .internal), let usageRange {
                    let fileID = usageRange.start.file
                    let suppressed = ast.file(for: fileID)?.annotations.contains { annotation in
                        KnownCompilerAnnotation.suppress.matches(annotation.name)
                            && annotation.arguments.contains { argument in
                                let code = argument.filter { $0 != "\"" && $0 != "'" }
                                return code == "INVISIBLE_MEMBER" || code == "INVISIBLE_REFERENCE"
                            }
                    } == true
                    let checker = VisibilityChecker(
                        symbols: symbols,
                        sourceManager: sourceManager,
                        interner: interner,
                        invisibleAccessFiles: suppressed ? [fileID.rawValue] : []
                    )
                    if !checker.isAccessible(resolved, fromFile: fileID, enclosingClass: nil) {
                        let label = resolved.visibility == .internal ? "internal" : "private"
                        diagnostics?.error(
                            resolved.visibility == .internal ? "KSWIFTK-SEMA-0044" : "KSWIFTK-SEMA-0040",
                            "Cannot access '\(interner.resolve(shortName))': it is \(label).",
                            range: usageRange
                        )
                        return types.errorType
                    }
                }
                if let diagnostics {
                    TypeCheckHelpers().checkDeprecation(
                        for: resolved.id,
                        symbols: symbols,
                        interner: interner,
                        range: usageRange,
                        diagnostics: diagnostics
                    )
                }
                let resolvedArgs = resolveTypeArgRefs(
                    argRefs,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    sourceManager: sourceManager,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth,
                    usageRange: usageRange
                )
                if resolved.kind != .typeAlias {
                    TypeProjectionValidator(symbols: symbols, types: types, interner: interner,
                                            diagnostics: diagnostics, range: usageRange)
                        .validate(arguments: resolvedArgs, of: resolved.id)
                }
                if resolved.kind == .typeAlias, expandTypeAlias {
                    if let underlying = resolveTypeAliasUnderlying(
                        resolved.id,
                        symbols: symbols,
                        types: types,
                        typeArgs: resolvedArgs,
                        visited: [],
                        recursionDepth: recursionDepth,
                        diagnostics: diagnostics,
                        projectionRange: usageRange,
                        interner: interner
                    ) {
                        // The alias may have been resolved before an alias it
                        // mentions (declared later) had an underlying type.
                        let underlying = expandNestedTypeAliases(
                            in: underlying, inProgress: [resolved.id], depth: 0, symbols: symbols, types: types
                        )
                        if nullability == .nullable {
                            return applyNullability(underlying, types: types)
                        }
                        return underlying
                    }
                    // Fall through to class-type path for error recovery when
                    // underlying type is not yet available (e.g. unresolved RHS,
                    // imported alias without signature metadata).
                }
                if resolved.id == types.kClassInterfaceSymbol
                    || resolved.fqName == [interner.intern("kotlin"), interner.intern("reflect"), interner.intern("KClass")]
                {
                    // KClass is invariant. Preserve every use-site projection
                    // in the nominal representation; the dedicated type only
                    // represents an invariant argument.
                    if let firstArg = resolvedArgs.first {
                        switch firstArg {
                        case .star, .in, .out:
                            return types.make(.classType(ClassType(
                                classSymbol: resolved.id,
                                args: resolvedArgs,
                                nullability: nullability
                            )))
                        case .invariant:
                            break
                        }
                    }
                    let argumentType: TypeID = if let firstArg = resolvedArgs.first {
                        switch firstArg {
                        case let .invariant(t):
                            t
                        case .star:
                            types.anyType
                        case let .out(t), let .in(t):
                            t
                        }
                    } else {
                        types.anyType
                    }
                    return types.makeKClassType(argument: argumentType, nullability: nullability)
                }
                // Qualified inner-class references (`Outer<V>.Inner`) supply
                // the qualifier's arguments; route through the nominal split so
                // they land in enclosingTypeArgs rather than the class's own args.
                // A bare name supplies none, so the implicit enclosing instance
                // fills those slots (`KeySet` inside `CIM<Value>` spells
                // `CIM<Value>.KeySet`).
                var nominalArgs = resolvedArgs
                let enclosingCount = types.enclosingTypeParameterSymbols(for: resolved.id).count
                if enclosingCount > 0 {
                    let implicitEnclosing = types.implicitInnerClassEnclosingArgs(
                        for: resolved.id,
                        enclosingInstanceTypes: lexicalOwnerSelfTypes(
                            relativeOwnerFQName: relativeOwnerFQName,
                            ast: ast,
                            symbols: symbols,
                            types: types,
                            interner: interner,
                            currentPackageFQName: currentPackageFQName,
                            imports: imports
                        )
                    )
                    if path.count == 1 {
                        nominalArgs = implicitEnclosing + resolvedArgs
                    } else if resolvedArgs.count < enclosingCount {
                        nominalArgs = Array(implicitEnclosing.prefix(enclosingCount - resolvedArgs.count)) + resolvedArgs
                    }
                }
                return types.make(.classType(types.classType(
                    for: resolved.id,
                    arguments: nominalArgs,
                    nullability: nullability
                )))
            }
            if candidates.isEmpty,
               let builtinNestedSymbol = resolveBuiltinClassNestedType(
                   path: path,
                   types: types,
                   symbols: symbols,
                   interner: interner
               ),
               isNominalTypeSymbol(builtinNestedSymbol.kind)
            {
                let resolvedArgs = resolveTypeArgRefs(
                    argRefs,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    sourceManager: sourceManager,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth
                )
                return types.make(.classType(ClassType(classSymbol: builtinNestedSymbol.id, args: resolvedArgs, nullability: nullability)))
            }
            diagnostics?.error(
                "KSWIFTK-SEMA-0025",
                "Unresolved type '\(interner.resolve(shortName))'.",
                range: usageRange
            )
            return types.errorType

        case let .functionType(contextReceiverRefIDs, receiverRefID, paramRefIDs, returnRefID, isSuspend, nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            var contextReceiverTypes: [TypeID] = []
            for contextReceiverRef in contextReceiverRefIDs {
                guard let contextReceiverType = resolveTypeRef(
                    contextReceiverRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    sourceManager: sourceManager,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
                ) else {
                    return nil
                }
                contextReceiverTypes.append(contextReceiverType)
            }
            var receiverType: TypeID?
            if let receiverRefID {
                receiverType = resolveTypeRef(
                    receiverRefID,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    sourceManager: sourceManager,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
                )
            }
            var paramTypes: [TypeID] = []
            for paramRef in paramRefIDs {
                guard let paramType = resolveTypeRef(
                    paramRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    sourceManager: sourceManager,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
                ) else {
                    return nil
                }
                paramTypes.append(paramType)
            }
            let returnType = resolveTypeRef(
                returnRefID,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                sourceManager: sourceManager,
                localTypeParameters: localTypeParameters,
                relativeOwnerFQName: relativeOwnerFQName,
                currentPackageFQName: currentPackageFQName,
                imports: imports,
                diagnostics: diagnostics,
                recursionDepth: recursionDepth + 1,
                usageRange: usageRange
            ) ?? types.unitType
            return types.make(.functionType(FunctionType(
                contextReceivers: contextReceiverTypes,
                receiver: receiverType,
                params: paramTypes,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: nullability
            )))

        case let .intersection(partRefs):
            let partTypes = partRefs.compactMap {
                resolveTypeRef(
                    $0,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    sourceManager: sourceManager,
                    localTypeParameters: localTypeParameters,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
                )
            }
            guard partTypes.count == partRefs.count else { return nil }
            return types.make(.intersection(partTypes))

        case let .annotated(base, annotations):
            guard let baseType = resolveTypeRef(
                base,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                sourceManager: sourceManager,
                localTypeParameters: localTypeParameters,
                relativeOwnerFQName: relativeOwnerFQName,
                currentPackageFQName: currentPackageFQName,
                imports: imports,
                diagnostics: diagnostics,
                recursionDepth: recursionDepth + 1,
                usageRange: usageRange
            ) else {
                return nil
            }
            return ExtensionFunctionTypeSupport.normalizeAnnotatedType(
                baseType: baseType,
                annotations: annotations,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: diagnostics,
                range: usageRange
            )
        }
    }

    private func unqualifiedFallbackNominals(
        named shortName: InternedString,
        currentPackageFQName: [InternedString]?,
        imports: [ImportDecl],
        usageRange: SourceRange?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        sourceManager: SourceManager?,
        interner: StringInterner,
        relativeOwnerFQName: [InternedString]? = nil,
        recursionDepth: Int = 0
    ) -> [SemanticSymbol] {
        let currentPackage = currentPackageFQName
            ?? usageRange.flatMap { ast.file(for: $0.start.file)?.packageFQName }
        let defaultImportPackages = Set(TypeCheckScopeBuilder().makeDefaultImportPackages(interner: interner))
        let kotlinReflectPackage = [interner.intern("kotlin"), interner.intern("reflect")]
        let enforcesWildcardImportVisibility =
            usageRange.flatMap { sourceManager?.origin(of: $0.start.file) } == .user
                && imports.contains(where: \.isWildcard)
        // A nested classifier's simple name is scoped to its declaring
        // classifier's body: the bare-name recovery may only re-bind it when
        // a lexical nominal owner inherits it through its superclass chain
        // (interfaces never contribute nested classifiers, KUU-3637/KUU-3636).
        // The owner path may name a member (`Child.value`), so every nominal
        // prefix contributes. Supertype edges are not bound yet at header
        // time, so the written supertype clauses are resolved instead; only
        // class-kind owners qualify, matching Kotlin's superclass-only rule.
        // The set is consulted only for candidates with a non-package parent,
        // so compute it lazily: a short name with no same-named nominal must
        // not pay for the transitive supertype walk at all (KUU-4013).
        var inheritedNestedParentIDsStorage: Set<SymbolID>?
        func inheritedNestedParentIDs() -> Set<SymbolID> {
            if let inheritedNestedParentIDsStorage { return inheritedNestedParentIDsStorage }
            let computed: Set<SymbolID> = {
                guard let relativeOwnerFQName,
                      recursionDepth < DataFlowSemaPhase.maxStructuralRecursionDepth
                else { return [] }
                var ownerPath = relativeOwnerFQName
                var result: Set<SymbolID> = []
                while !ownerPath.isEmpty {
                    defer { ownerPath.removeLast() }
                    guard let ownerID = symbols.lookupAll(fqName: ownerPath)
                        .compactMap({ symbols.symbol($0) })
                        .first(where: { isNominalTypeSymbol($0.kind) })?.id
                    else { continue }
                    for instanceType in declaredSupertypeInstanceTypes(
                        of: ownerID,
                        ownerFQName: ownerPath,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner,
                        currentPackageFQName: currentPackageFQName,
                        imports: imports,
                        visited: [ownerID],
                        depth: recursionDepth + 1
                    ) {
                        guard case let .classType(classType) = types.kind(of: types.makeNonNullable(instanceType)),
                              symbols.symbol(classType.classSymbol)?.kind == .class
                        else { continue }
                        result.insert(classType.classSymbol)
                    }
                }
                return result
            }()
            inheritedNestedParentIDsStorage = computed
            return computed
        }
        return symbols.lookupByShortName(shortName).compactMap { symbols.symbol($0) }.filter { symbol in
            guard isNominalTypeSymbol(symbol.kind) else { return false }
            // kotlin.reflect declarations require an explicit import.
            guard !symbol.fqName.starts(with: kotlinReflectPackage) else { return false }
            let parentID = symbols.parentSymbol(for: symbol.id)
            // The classifier legitimately visible through an enclosing
            // owner's superclass chain is in scope regardless of import
            // shape. Package parents can never be in the set (it holds only
            // class-kind symbols), so this also skips forcing the lazy
            // computation for package-parented candidates entirely.
            if let parentID, symbols.symbol(parentID)?.kind != .package {
                return inheritedNestedParentIDs().contains(parentID)
            }
            // Wildcard imports must not widen short-name recovery beyond the
            // current/default/imported package paths (KUU-3295). Other header
            // paths retain legacy recovery for top-level and forward
            // references.
            guard enforcesWildcardImportVisibility else { return true }
            let fqName = symbol.fqName
            if let currentPackage, fqName == currentPackage + [shortName] {
                return true
            }
            if defaultImportPackages.contains(where: { $0 + [shortName] == fqName }) {
                return true
            }
            if fqName == [shortName] {
                return true
            }
            if imports.contains(where: { importDecl in
                if importDecl.alias == shortName {
                    return importDecl.path == fqName
                }
                guard importDecl.alias == nil else { return false }
                if importDecl.path == fqName {
                    return true
                }
                if importDecl.isWildcard {
                    return importDecl.path + [shortName] == fqName
                }
                return symbols.importPathContributesMembers(
                    importDecl.path,
                    isWildcard: false
                ) && importDecl.path + [shortName] == fqName
            }) {
                return true
            }
            return false
        }
    }

    /// Self types of the lexical nominal owners enclosing a type reference,
    /// innermost first, together with each owner's inherited-instance views
    /// (`CIM<Int>` for `Sub : CIM<Int>`). An inner class reference resolves
    /// its implicit enclosing instance from this chain: inside `Sub` the
    /// instance is a `Sub` lifted through its declared `CIM<Int>` supertype.
    ///
    /// The chain mirrors the implicit receiver tower: a non-`inner` nested
    /// owner (class/object/interface) does not capture an enclosing instance,
    /// so the walk stops there; an `inner` class passes its parent's instance
    /// through.
    private func lexicalOwnerSelfTypes(
        relativeOwnerFQName: [InternedString]?,
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        currentPackageFQName: [InternedString]?,
        imports: [ImportDecl]
    ) -> [TypeID] {
        var ownerPath = relativeOwnerFQName ?? []
        var selfTypes: [TypeID] = []
        while !ownerPath.isEmpty {
            guard let ownerID = symbols.lookup(fqName: ownerPath),
                  let owner = symbols.symbol(ownerID),
                  isNominalTypeSymbol(owner.kind)
            else {
                ownerPath.removeLast()
                continue
            }
            selfTypes.append(contentsOf: lexicalOwnerInstanceTypes(
                forOwnerID: ownerID,
                ownerFQName: ownerPath,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                currentPackageFQName: currentPackageFQName,
                imports: imports
            ))
            ownerPath.removeLast()
            guard owner.flags.contains(.innerClass) else {
                break
            }
        }
        return selfTypes
    }

    /// The candidate enclosing-instance types one lexical owner contributes:
    /// its self type (e.g. `Sub` or `CIM<Value>`) followed by the types its
    /// declared supertype clause resolves to (`CIM<Int>` for `Sub : CIM<Int>`).
    func lexicalOwnerInstanceTypes(
        forOwnerID ownerID: SymbolID,
        ownerFQName: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        currentPackageFQName: [InternedString]?,
        imports: [ImportDecl]
    ) -> [TypeID] {
        let parameters = types.allTypeParameterSymbols(for: ownerID)
        let arguments = parameters.map { parameter in
            TypeArg.invariant(types.make(.typeParam(TypeParamType(symbol: parameter))))
        }
        return [types.make(.classType(types.classType(for: ownerID, arguments: arguments)))]
            + declaredSupertypeInstanceTypes(
                of: ownerID,
                ownerFQName: ownerFQName,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                currentPackageFQName: currentPackageFQName,
                imports: imports,
                visited: [ownerID]
            )
    }

    /// Nominal types an owner's declared supertype clause resolves to, with
    /// transitive supertypes flattened. Supertype-argument maps only exist
    /// after `bindInheritanceEdges` runs, so header-time resolution walks the
    /// written clauses instead: `Sub : CIM<Int>` supplies `CIM<Int>` directly.
    private func declaredSupertypeInstanceTypes(
        of ownerID: SymbolID,
        ownerFQName: [InternedString],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        currentPackageFQName: [InternedString]?,
        imports: [ImportDecl],
        visited: Set<SymbolID>,
        depth: Int = 0
    ) -> [TypeID] {
        guard depth < DataFlowSemaPhase.maxStructuralRecursionDepth,
              let declID = nominalDeclID(forFQName: ownerFQName, ast: ast),
              let decl = ast.arena.decl(declID)
        else {
            return []
        }
        var closureKey: HeaderSupertypeClosureKey?
        if visited == [ownerID] {
            // Fresh-start queries (the only shape the lexical-owner walks
            // issue) replay the same transitive closure. The memo must not
            // outlive the symbol-table state it was computed against, so the
            // monotonic symbol count is part of the key (KUU-4013).
            let key = HeaderSupertypeClosureKey(
                ownerID: ownerID,
                ownerFQName: ownerFQName,
                packageFQName: currentPackageFQName ?? [],
                imports: imports.map {
                    HeaderSupertypeClosureKey.ImportKey(
                        path: $0.path, alias: $0.alias, isWildcard: $0.isWildcard
                    )
                },
                symbolCount: symbols.count
            )
            if let memoized = declaredSupertypeClosureMemo[key] {
                return memoized
            }
            // An unresolved supertype clause name re-enters this owner's own
            // closure: unqualified-name recovery probes the owner chain for
            // inherited nested classifiers, which enumerates the same
            // supertypes again. Recursion depth only bounds the descent —
            // every level redoes the same enumeration, which is the
            // KUU-4013 exponential. A still-open closure is a cyclic
            // dependency: its contribution is empty by definition.
            guard declaredSupertypeClosuresInProgress.insert(key).inserted else {
                return []
            }
            closureKey = key
        }
        defer {
            if let closureKey {
                declaredSupertypeClosuresInProgress.remove(closureKey)
            }
        }
        let superTypeRefs: [TypeRefID]
        switch decl {
        case let .classDecl(classDecl):
            superTypeRefs = classDecl.superTypeEntries.map(\.typeRef)
        case let .interfaceDecl(interfaceDecl):
            superTypeRefs = interfaceDecl.superTypes
        case let .objectDecl(objectDecl):
            superTypeRefs = objectDecl.superTypes
        default:
            return []
        }
        var clauseTypeParameters: [InternedString: SymbolID] = [:]
        for parameter in types.allTypeParameterSymbols(for: ownerID) {
            if let name = symbols.symbol(parameter)?.name {
                clauseTypeParameters[name] = parameter
            }
        }
        var visited = visited
        var instanceTypes: [TypeID] = []
        for typeRefID in superTypeRefs {
            guard let resolved = resolveTypeRef(
                typeRefID,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                localTypeParameters: clauseTypeParameters,
                relativeOwnerFQName: ownerFQName,
                currentPackageFQName: currentPackageFQName,
                imports: imports,
                recursionDepth: depth + 1
            ), case let .classType(superClass) = types.kind(of: types.makeNonNullable(resolved))
            else {
                continue
            }
            instanceTypes.append(types.makeNonNullable(resolved))
            guard visited.insert(superClass.classSymbol).inserted else {
                continue
            }
            instanceTypes.append(contentsOf: declaredSupertypeInstanceTypes(
                of: superClass.classSymbol,
                ownerFQName: symbols.symbol(superClass.classSymbol)?.fqName ?? ownerFQName,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                currentPackageFQName: currentPackageFQName,
                imports: imports,
                visited: visited,
                depth: depth + 1
            ))
        }
        if let closureKey {
            declaredSupertypeClosureMemo[closureKey] = instanceTypes
        }
        return instanceTypes
    }

    /// The decl carrying `fqName`, located by walking the file's nested-type
    /// containers. Local declarations and synthetic members not reachable
    /// through the tree return nil, which simply skips the supertype lookup.
    private func nominalDeclID(
        forFQName fqName: [InternedString],
        ast: ASTModule
    ) -> DeclID? {
        for file in ast.sortedFiles {
            guard fqName.starts(with: file.packageFQName) else { continue }
            let segments = Array(fqName.dropFirst(file.packageFQName.count))
            guard !segments.isEmpty else { continue }
            var candidates = file.topLevelDecls
            for (index, segment) in segments.enumerated() {
                guard let match = candidates.first(where: { declID in
                    guard let decl = ast.arena.decl(declID) else { return false }
                    return nominalDeclName(of: decl) == segment
                }) else {
                    break
                }
                if index == segments.count - 1 {
                    return match
                }
                guard let decl = ast.arena.decl(match) else { break }
                candidates = nestedNominalDecls(of: decl)
            }
        }
        return nil
    }

    private func nominalDeclName(of decl: Decl) -> InternedString? {
        switch decl {
        case let .classDecl(classDecl): classDecl.name
        case let .interfaceDecl(interfaceDecl): interfaceDecl.name
        case let .objectDecl(objectDecl): objectDecl.name
        case let .enumEntryDecl(enumEntryDecl): enumEntryDecl.name
        case let .typeAliasDecl(typeAliasDecl): typeAliasDecl.name
        case .funDecl, .propertyDecl: nil
        }
    }

    private func nestedNominalDecls(of decl: Decl) -> [DeclID] {
        switch decl {
        case let .classDecl(classDecl):
            classDecl.nestedClasses + classDecl.nestedObjects + (classDecl.companionObject.map { [$0] } ?? [])
        case let .interfaceDecl(interfaceDecl):
            interfaceDecl.nestedClasses + interfaceDecl.nestedObjects + (interfaceDecl.companionObject.map { [$0] } ?? [])
        case let .objectDecl(objectDecl):
            objectDecl.nestedClasses + objectDecl.nestedObjects
        default:
            []
        }
    }

    private func resolveRelativeNominalCandidates(
        named shortName: InternedString,
        relativeTo ownerFQName: [InternedString],
        currentPackageFQName: [InternedString]?,
        symbols: SymbolTable
    ) -> [SemanticSymbol] {
        guard !ownerFQName.isEmpty else {
            return []
        }

        var candidates: [SemanticSymbol] = []
        var seen: Set<SymbolID> = []
        var current = ownerFQName
        while !current.isEmpty {
            // The package segment is not a lexical owner scope: names at that
            // tier rank below explicit imports (KUU-1423), so stop before it
            // and let the caller's import-aware candidate list order them.
            if let currentPackageFQName, current == currentPackageFQName {
                break
            }
            // Members of the enclosing declaration (nested types) are closer than
            // the enclosing declaration's own name, so `A.A` wins over `A` (KUU-2172).
            let nestedFQName = current + [shortName]
            for symbolID in symbols.lookupAll(fqName: nestedFQName) where seen.insert(symbolID).inserted {
                if let symbol = symbols.symbol(symbolID) {
                    candidates.append(symbol)
                }
            }

            if current.last == shortName {
                for symbolID in symbols.lookupAll(fqName: current) where seen.insert(symbolID).inserted {
                    if let symbol = symbols.symbol(symbolID) {
                        candidates.append(symbol)
                    }
                }
            }

            current.removeLast()
        }
        return candidates.filter { isNominalTypeSymbol($0.kind) }
    }

    private func resolveNominalCandidates(
        for path: [InternedString],
        currentPackageFQName: [InternedString]?,
        imports: [ImportDecl],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [SemanticSymbol] {
        guard !path.isEmpty else {
            return []
        }

        var candidatePaths: [[InternedString]] = {
            var paths: [[InternedString]] = []
            if path.count == 1 {
                if let shortName = path.first {
                    var wildcardPaths: [[InternedString]] = []
                    // Kotlin's classifier tier order puts explicit (single-type
                    // and alias) imports above same-package declarations, so
                    // they are expanded first here (KUU-1423).
                    for importDecl in imports {
                        if let alias = importDecl.alias, alias == shortName {
                            paths.append(importDecl.path)
                        } else if importDecl.alias == nil,
                                  importDecl.isWildcard
                        {
                            // `import pkg.*` exposes `pkg.Name` as `Name`;
                            // without this expansion a same-named root-package
                            // symbol (e.g. the CancellationException
                            // compatibility class, KSP-1150) shadows the
                            // wildcard-imported declaration.
                            wildcardPaths.append(importDecl.path + path)
                        } else if importDecl.alias == nil,
                                  importDecl.path.last == shortName
                        {
                            paths.append(importDecl.path)
                        }
                    }
                    if let currentPackageFQName,
                       !currentPackageFQName.isEmpty || symbols.lookupAll(fqName: path).contains(where: { symbolID in
                           guard let symbol = symbols.symbol(symbolID) else { return false }
                           return isNominalTypeSymbol(symbol.kind) && !symbol.flags.contains(.synthetic)
                       })
                    {
                        paths.append(currentPackageFQName + path)
                    }
                    // Wildcard imports rank below same-package and explicit
                    // imports, matching Kotlin's unqualified-name precedence.
                    paths.append(contentsOf: wildcardPaths)
                }
                // Header types are resolved before TypeCheck builds file scopes.
                // Expand star imports here as well; otherwise a same-named
                // stdlib class found by the short-name fallback can replace the
                // imported class in a function signature (KUU-916).
                if let shortName = path.first {
                    // Package-only paths (and `a.b.*` wildcards) contribute
                    // members; a path that also resolves to a declaration is
                    // a declaration import and must not leak its neighbours
                    // (KUU-1205).
                    for importDecl in imports where importDecl.alias == nil {
                        if symbols.importPathContributesMembers(importDecl.path, isWildcard: importDecl.isWildcard) {
                            paths.append(importDecl.path + [shortName])
                        }
                    }
                }
                for defaultPackage in TypeCheckScopeBuilder().makeDefaultImportPackages(interner: interner) {
                    paths.append(defaultPackage + path)
                }
                // An unqualified root symbol is the final fallback. This ordering
                // keeps an explicit import from being shadowed by a compatibility
                // alias with the same short name (KSP-1150).
                paths.append(path)
            } else {
                // The qualifier of a nested-type reference resolves like an
                // unqualified classifier name: explicit/alias imports outrank
                // same-package declarations, and both outrank wildcard and
                // root-package fallbacks (KUU-1423).
                var wildcardQualifiedPaths: [[InternedString]] = []
                for importDecl in imports {
                    let tail = Array(path.dropFirst())
                    if let alias = importDecl.alias, alias == path[0] {
                        paths.append(importDecl.path + tail)
                    } else if importDecl.alias == nil,
                              importDecl.isWildcard
                    {
                        wildcardQualifiedPaths.append(importDecl.path + path)
                    } else if importDecl.alias == nil,
                              importDecl.path.last == path[0]
                    {
                        paths.append(importDecl.path + tail)
                    }
                }
                if let currentPackageFQName, !currentPackageFQName.isEmpty {
                    paths.append(currentPackageFQName + path)
                }
                paths.append(path)
                paths.append(contentsOf: wildcardQualifiedPaths)
            }
            return paths
        }()

        if path.count > 1 {
            // Package-only paths (and `a.b.*` wildcards) contribute members,
            // e.g. `import kotlin.coroutines.*` + `CoroutineContext.Key`.
            for importDecl in imports where importDecl.alias == nil {
                if symbols.importPathContributesMembers(importDecl.path, isWildcard: importDecl.isWildcard) {
                    candidatePaths.append(importDecl.path + path)
                }
            }
            // A nested type can be rooted in a default-imported declaration,
            // such as Map.Entry. Header resolution must use the same import
            // packages as expression/type checking instead of requiring an
            // explicit import of the outer declaration.
            for defaultPackage in TypeCheckScopeBuilder().makeDefaultImportPackages(interner: interner) {
                candidatePaths.append(defaultPackage + path)
            }
        }

        var seenPaths: Set<[InternedString]> = []
        var result: [SemanticSymbol] = []
        for candidatePath in candidatePaths where seenPaths.insert(candidatePath).inserted {
            result.append(contentsOf: symbols.lookupAll(fqName: candidatePath).compactMap { symbols.symbol($0) }
                .filter { isNominalTypeSymbol($0.kind) })
        }
        return result
    }

    func resolveTypeArgRefs(
        _ argRefs: [TypeArgRef],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        sourceManager: SourceManager? = nil,
        localTypeParameters: [InternedString: SymbolID] = [:],
        relativeOwnerFQName: [InternedString]? = nil,
        currentPackageFQName: [InternedString]? = nil,
        imports: [ImportDecl] = [],
        diagnostics: DiagnosticEngine? = nil,
        recursionDepth: Int = 0,
        usageRange: SourceRange? = nil
    ) -> [TypeArg] {
        var result: [TypeArg] = []
        result.reserveCapacity(argRefs.count)
        for argRef in argRefs {
            switch argRef {
            case let .invariant(innerRef):
                let resolved = resolveTypeRef(
                    innerRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    sourceManager: sourceManager,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
                ) ?? types.errorType
                result.append(.invariant(resolved))
            case let .out(innerRef):
                let resolved = resolveTypeRef(
                    innerRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    sourceManager: sourceManager,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
                ) ?? types.errorType
                result.append(.out(resolved))
            case let .in(innerRef):
                let resolved = resolveTypeRef(
                    innerRef,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    sourceManager: sourceManager,
                    localTypeParameters: localTypeParameters,
                    relativeOwnerFQName: relativeOwnerFQName,
                    currentPackageFQName: currentPackageFQName,
                    imports: imports,
                    diagnostics: diagnostics,
                    recursionDepth: recursionDepth + 1,
                    usageRange: usageRange
                ) ?? types.errorType
                result.append(.in(resolved))
            case .star:
                result.append(.star)
            }
        }
        return result
    }

    func applyNullability(_ typeID: TypeID, types: TypeSystem) -> TypeID {
        switch types.kind(of: typeID) {
        case let .primitive(p, _):
            return types.make(.primitive(p, .nullable))
        case let .classType(ct):
            return types.make(.classType(ClassType(
                classSymbol: ct.classSymbol,
                args: ct.args,
                enclosingTypeArgs: ct.enclosingTypeArgs,
                nullability: .nullable
            )))
        case let .typeParam(tp):
            return types.make(.typeParam(TypeParamType(symbol: tp.symbol, nullability: .nullable, capture: tp.capture)))
        case let .functionType(ft):
            return types.make(.functionType(FunctionType(contextReceivers: ft.contextReceivers, receiver: ft.receiver, params: ft.params, returnType: ft.returnType, isSuspend: ft.isSuspend, isCallableReference: ft.isCallableReference, nullability: .nullable)))
        case let .kClassType(kc):
            return types.make(.kClassType(KClassType(argument: kc.argument, nullability: .nullable)))
        case .any, .unit, .nullableUnit, .platformUnit, .nothing:
            let nullable = types.makeNullable(typeID)
            // If makeNullable is a no-op: either the type is already nullable (keep it)
            // or makeNullable genuinely can't apply (e.g. an intersection) — fall back to Any?
            if nullable == typeID {
                return types.isSubtype(types.nullableNothingType, typeID) ? typeID : types.nullableAnyType
            }
            return nullable
        default:
            return types.nullableAnyType
        }
    }

    /// Maximum depth for recursive typealias expansion to prevent infinite loops.
    private static let maxAliasExpansionDepth = 32

    /// Maximum structural recursion depth for type resolution and substitution.
    /// Keep one parser level available so source at the semantic boundary can
    /// still be parsed and rejected by Sema with the semantic depth diagnostic.
    static let maxStructuralRecursionDepth = TypeRefParserCore.maxRecursionDepth - 1

    func resolveTypeAliasUnderlying(
        _ symbolID: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        typeArgs: [TypeArg] = [],
        visited: Set<SymbolID>,
        depth: Int = 0,
        recursionDepth: Int = 0,
        diagnostics: DiagnosticEngine? = nil,
        projectionRange: SourceRange? = nil,
        interner: StringInterner? = nil
    ) -> TypeID? {
        guard !visited.contains(symbolID) else {
            diagnostics?.error(
                "KSWIFTK-SEMA-ALIAS-CYCLE",
                "Cyclic typealias definition detected.",
                range: symbols.symbol(symbolID)?.declSite
            )
            return nil
        }
        guard depth < DataFlowSemaPhase.maxAliasExpansionDepth else {
            diagnostics?.error(
                "KSWIFTK-SEMA-ALIAS-DEPTH",
                "Typealias expansion exceeded maximum depth of \(DataFlowSemaPhase.maxAliasExpansionDepth).",
                range: symbols.symbol(symbolID)?.declSite
            )
            return nil
        }
        guard let underlying = symbols.typeAliasUnderlyingType(for: symbolID) else {
            return nil
        }
        TypeProjectionValidator(symbols: symbols, types: types,
                                interner: interner,
                                diagnostics: diagnostics,
                                range: projectionRange ?? symbols.symbol(symbolID)?.declSite)
            .validate(arguments: typeArgs, of: symbolID)
        let expanded = substituteTypeAliasParams(
            underlying,
            aliasSymbol: symbolID,
            typeArgs: typeArgs,
            symbols: symbols,
            types: types,
            recursionDepth: recursionDepth,
            diagnostics: diagnostics
        )
        if case let .classType(classType) = types.kind(of: expanded),
           let targetSymbol = symbols.symbol(classType.classSymbol),
           targetSymbol.kind == .typeAlias
        {
            var newVisited = visited
            newVisited.insert(symbolID)
            let chainArgs = classType.args
            if let resolved = resolveTypeAliasUnderlying(
                classType.classSymbol,
                symbols: symbols,
                types: types,
                typeArgs: chainArgs,
                visited: newVisited,
                depth: depth + 1,
                recursionDepth: recursionDepth,
                diagnostics: diagnostics,
                projectionRange: projectionRange,
                interner: interner
            ) {
                if classType.nullability == .nullable {
                    return applyNullability(resolved, types: types)
                }
                return resolved
            }
            return nil
        }
        return expanded
    }

    func substituteTypeAliasParams(
        _ typeID: TypeID,
        aliasSymbol: SymbolID,
        typeArgs: [TypeArg],
        symbols: SymbolTable,
        types: TypeSystem,
        recursionDepth: Int = 0,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        let typeParamSymbols = symbols.typeAliasTypeParameters(for: aliasSymbol)
        // Non-generic aliases may still carry fully-substituted underlying type arguments
        // through expected-type propagation, so there is nothing left to substitute here.
        if typeParamSymbols.isEmpty {
            return typeID
        }
        // Alias is generic. Emit a diagnostic whenever the argument count does not match,
        // even if we end up not performing any substitution.
        if !typeArgs.isEmpty && typeArgs.count != typeParamSymbols.count {
            diagnostics?.error(
                "KSWIFTK-SEMA-0062",
                "Type argument count mismatch: expected \(typeParamSymbols.count) but got \(typeArgs.count).",
                range: nil
            )
        }
        var argSubstitution: [SymbolID: TypeArg] = [:]
        for (index, paramSymbol) in typeParamSymbols.enumerated() {
            guard index < typeArgs.count else { break }
            argSubstitution[paramSymbol] = typeArgs[index]
        }
        guard !argSubstitution.isEmpty else {
            return typeID
        }
        return applySubstitution(
            typeID,
            argSubstitution: argSubstitution,
            types: types,
            symbols: symbols,
            recursionDepth: recursionDepth,
            diagnostics: diagnostics
        )
    }

    private func applySubstitution(
        _ typeID: TypeID,
        argSubstitution: [SymbolID: TypeArg],
        types: TypeSystem,
        symbols: SymbolTable,
        recursionDepth: Int = 0,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        guard recursionDepth <= DataFlowSemaPhase.maxStructuralRecursionDepth else {
            diagnostics?.error(
                "KSWIFTK-SEMA-TYPE-DEPTH",
                "Type substitution nesting is too deep (exceeded maximum depth of \(DataFlowSemaPhase.maxStructuralRecursionDepth)).",
                range: nil
            )
            return types.errorType
        }
        switch types.kind(of: typeID) {
        case let .typeParam(tp):
            if let replacement = argSubstitution[tp.symbol] {
                // In non-arg positions, extract the TypeID from the TypeArg.
                // For .star, expand to the wildcard upper bound (Any?) since
                // leaving the type parameter unsubstituted would create dangling references.
                let replacementType: TypeID = switch replacement {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    inner
                case .star:
                    types.nullableAnyType
                }
                if tp.nullability == .nullable {
                    return applyNullability(replacementType, types: types)
                }
                return replacementType
            }
            return typeID
        case let .classType(ct):
            let newArgs = ct.args.map { arg -> TypeArg in
                substituteArg(
                    arg,
                    argSubstitution: argSubstitution,
                    types: types,
                    symbols: symbols,
                    recursionDepth: recursionDepth + 1,
                    diagnostics: diagnostics
                )
            }
            let newEnclosingTypeArgs = ct.enclosingTypeArgs.map { arg in
                substituteArg(
                    arg,
                    argSubstitution: argSubstitution,
                    types: types,
                    symbols: symbols,
                    recursionDepth: recursionDepth + 1,
                    diagnostics: diagnostics
                )
            }
            return types.make(.classType(ClassType(
                classSymbol: ct.classSymbol,
                args: newArgs,
                enclosingTypeArgs: newEnclosingTypeArgs,
                nullability: ct.nullability
            )))
        case let .functionType(ft):
            let newContextReceivers = ft.contextReceivers.map {
                applySubstitution($0, argSubstitution: argSubstitution, types: types, symbols: symbols, recursionDepth: recursionDepth + 1, diagnostics: diagnostics)
            }
            let newReceiver = ft.receiver.map {
                applySubstitution($0, argSubstitution: argSubstitution, types: types, symbols: symbols, recursionDepth: recursionDepth + 1, diagnostics: diagnostics)
            }
            let newParams = ft.params.map {
                applySubstitution($0, argSubstitution: argSubstitution, types: types, symbols: symbols, recursionDepth: recursionDepth + 1, diagnostics: diagnostics)
            }
            let newReturn = applySubstitution(
                ft.returnType,
                argSubstitution: argSubstitution,
                types: types,
                symbols: symbols,
                recursionDepth: recursionDepth + 1,
                diagnostics: diagnostics
            )
            return types.make(.functionType(FunctionType(contextReceivers: newContextReceivers, receiver: newReceiver, params: newParams, returnType: newReturn, isSuspend: ft.isSuspend, isCallableReference: ft.isCallableReference, nullability: ft.nullability)))
        case let .kClassType(kc):
            let newArg = applySubstitution(
                kc.argument,
                argSubstitution: argSubstitution,
                types: types,
                symbols: symbols,
                recursionDepth: recursionDepth + 1,
                diagnostics: diagnostics
            )
            if newArg == kc.argument { return typeID }
            return types.make(.kClassType(KClassType(argument: newArg, nullability: kc.nullability)))
        case .stringStruct, .primitive, .any, .unit, .nullableUnit, .platformUnit, .nothing, .error:
            return typeID
        case let .intersection(parts):
            let newParts = parts.map {
                applySubstitution($0, argSubstitution: argSubstitution, types: types, symbols: symbols, recursionDepth: recursionDepth + 1, diagnostics: diagnostics)
            }
            return types.make(.intersection(newParts))
        }
    }

    /// Substitute a type argument, preserving use-site projections through expansion.
    /// - `.invariant(T)` in the RHS: replace with the full `TypeArg` from the use-site
    ///   (e.g., `Foo<out String>` expands `Box<T>` to `Box<out String>`)
    /// - `.out(T)` / `.in(T)` in the RHS: keep the declaration-site projection,
    ///   substitute inner type; `.star` substitution yields `.star`
    /// - `.star`: preserved as-is
    private func substituteArg(
        _ arg: TypeArg,
        argSubstitution: [SymbolID: TypeArg],
        types: TypeSystem,
        symbols: SymbolTable,
        recursionDepth: Int = 0,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeArg {
        switch arg {
        case let .invariant(inner):
            // If the inner type is a bare type parameter with a substitution,
            // replace the entire arg with the use-site TypeArg (preserving projection).
            if case let .typeParam(tp) = types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                if tp.nullability == .nullable {
                    return replacement.mapTypes { applyNullability($0, types: types) }
                }
                return replacement
            }
            return .invariant(applySubstitution(
                inner,
                argSubstitution: argSubstitution,
                types: types,
                symbols: symbols,
                recursionDepth: recursionDepth + 1,
                diagnostics: diagnostics
            ))
        case let .out(inner):
            if case let .typeParam(tp) = types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                // Declaration-site has `.out`; if use-site is `.star`, star wins.
                if case .star = replacement { return .star }
                let innerType = typeArgInnerType(replacement, types: types, diagnostics: diagnostics)
                let resolved = tp.nullability == .nullable ? applyNullability(innerType, types: types) : innerType
                return .out(resolved)
            }
            return .out(applySubstitution(
                inner,
                argSubstitution: argSubstitution,
                types: types,
                symbols: symbols,
                recursionDepth: recursionDepth + 1,
                diagnostics: diagnostics
            ))
        case let .in(inner):
            if case let .typeParam(tp) = types.kind(of: inner),
               let replacement = argSubstitution[tp.symbol]
            {
                if case .star = replacement { return .star }
                let innerType = typeArgInnerType(replacement, types: types, diagnostics: diagnostics)
                let resolved = tp.nullability == .nullable ? applyNullability(innerType, types: types) : innerType
                return .in(resolved)
            }
            return .in(applySubstitution(
                inner,
                argSubstitution: argSubstitution,
                types: types,
                symbols: symbols,
                recursionDepth: recursionDepth + 1,
                diagnostics: diagnostics
            ))
        case .star:
            return .star
        }
    }

    private func typeArgInnerType(
        _ arg: TypeArg,
        types: TypeSystem,
        diagnostics: DiagnosticEngine? = nil
    ) -> TypeID {
        switch arg {
        case let .invariant(inner), let .out(inner), let .in(inner):
            return inner
        case .star:
            diagnostics?.error(
                "KSWIFTK-SEMA-0063",
                "Cannot extract inner type from star projection '<*>'.",
                range: nil
            )
            return types.errorType
        }
    }

    /// Resolve a nested type reference (e.g. `Char.Companion`) inside a builtin
    /// type's synthetic class symbol when normal nominal lookup fails.
    private func resolveBuiltinClassNestedType(
        path: [InternedString],
        types: TypeSystem,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SemanticSymbol? {
        guard path.count > 1, let first = path.first else { return nil }

        let rootClassSymbol: SymbolID?
        if first == interner.intern("Char") {
            rootClassSymbol = types.charClassSymbol
        } else if first == interner.intern("String") {
            rootClassSymbol = types.stringClassSymbol
        } else if first == interner.intern("Any") {
            rootClassSymbol = types.anyClassSymbol
        } else if first == interner.intern("Byte")
            || first == interner.intern("Long")
            || first == interner.intern("Short")
        {
            let kotlinFQName = [interner.intern("kotlin"), first]
            rootClassSymbol = symbols.lookupAll(fqName: kotlinFQName).first(where: { symbolID in
                guard let symbol = symbols.symbol(symbolID) else { return false }
                return symbol.kind == .class
            })
        } else {
            rootClassSymbol = nil
        }

        guard let root = rootClassSymbol, let rootInfo = symbols.symbol(root) else {
            return nil
        }
        let nestedFQName = rootInfo.fqName + Array(path.dropFirst())
        guard let symbolID = symbols.lookupAll(fqName: nestedFQName).first else { return nil }
        return symbols.symbol(symbolID)
    }

}
