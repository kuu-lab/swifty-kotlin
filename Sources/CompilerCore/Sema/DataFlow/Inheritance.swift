
extension DataFlowSemaPhase {
    func bindInheritanceEdges(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine = DiagnosticEngine(),
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                bindInheritanceEdges(
                    declID: declID,
                    currentPackage: file.packageFQName,
                    imports: file.imports,
                    enclosingTypeParameters: [:],
                    enclosingClassScopes: [],
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        }
    }

    private func bindInheritanceEdges(
        declID: DeclID,
        currentPackage: [InternedString],
        imports: [ImportDecl],
        enclosingTypeParameters: [InternedString: SymbolID],
        enclosingClassScopes: [[InternedString]],
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let symbol = bindings.declSymbols[declID],
              let decl = ast.arena.decl(declID)
        else {
            return
        }

        let superTypeRefs: [TypeRefID]
        let nestedDecls: [DeclID]
        switch decl {
        case let .classDecl(classDecl):
            superTypeRefs = classDecl.superTypeEntries.map(\.typeRef)
            nestedDecls = classDecl.nestedClasses + classDecl.nestedObjects
                + (classDecl.companionObject.map { [$0] } ?? [])
        case let .interfaceDecl(interfaceDecl):
            superTypeRefs = interfaceDecl.superTypes
            nestedDecls = interfaceDecl.nestedClasses + interfaceDecl.nestedObjects
                + (interfaceDecl.companionObject.map { [$0] } ?? [])
        case let .objectDecl(objectDecl):
            superTypeRefs = objectDecl.superTypes
            nestedDecls = objectDecl.nestedClasses + objectDecl.nestedObjects
        default:
            return
        }

        // Type parameters declared on the current nominal type are in scope for
        // its supertype type arguments (e.g. `AbstractIterator<T> : Iterator<T>`).
        // Without this, a supertype argument that names an own type parameter fails
        // to resolve and the supertype is recorded with no type arguments, which
        // breaks override covariance and polymorphic subtyping for the subclass.
        var mergedEnclosingTypeParameters: [InternedString: SymbolID] = [:]
        if case let .classDecl(classDecl) = decl, classDecl.isInner {
            mergedEnclosingTypeParameters = enclosingTypeParameters
        }
        for (name, paramSymbol) in buildTypeParameterMap(for: symbol, types: types, symbols: symbols) {
            mergedEnclosingTypeParameters[name] = paramSymbol
        }

        var superSymbols: [SymbolID] = []
        for superTypeRef in superTypeRefs {
            if let resolved = resolveNominalSymbolAndTypeArgs(
                superTypeRef,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: mergedEnclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) {
                if let imported = symbols.symbol(resolved.symbol),
                   imported.flags.contains(.importedLibrary),
                   let fileID = symbols.sourceFileID(for: symbol)
                       ?? symbols.symbol(symbol)?.declSite?.start.file {
                    let suppressed = ast.file(for: fileID)?.annotations.contains { annotation in
                        KnownCompilerAnnotation.suppress.matches(annotation.name)
                            && annotation.arguments.contains { argument in
                                let code = argument.filter { $0 != "\"" && $0 != "'" }
                                return code == "INVISIBLE_MEMBER" || code == "INVISIBLE_REFERENCE"
                            }
                    } == true
                    let checker = VisibilityChecker(
                        symbols: symbols,
                        invisibleAccessFiles: suppressed ? [fileID.rawValue] : []
                    )
                    if !checker.isAccessible(imported, fromFile: fileID, enclosingClass: nil) {
                        let name = imported.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        diagnostics.error(
                            imported.visibility == .internal ? "KSWIFTK-SEMA-0044" : "KSWIFTK-SEMA-0040",
                            "Cannot inherit from '\(name)': it is not visible in this module.",
                            range: symbols.symbol(symbol)?.declSite
                        )
                        continue
                    }
                }
                superSymbols.append(resolved.symbol)
                if !resolved.typeArgs.isEmpty {
                    symbols.setSupertypeTypeArgs(resolved.typeArgs, for: symbol, supertype: resolved.symbol)
                    types.setNominalSupertypeTypeArgs(resolved.typeArgs, for: symbol, supertype: resolved.symbol)
                }
            }
        }

        // Annotation classes ALWAYS implicitly extend kotlin.Annotation,
        // regardless of other explicit supertypes (e.g. interfaces).
        // Classes/objects/enums without an explicit class supertype get kotlin.Any.
        let annotationFQName = [interner.intern("kotlin"), interner.intern("Annotation")]
        let anyFQName = [interner.intern("kotlin"), interner.intern("Any")]
        if let symbolInfo = symbols.symbol(symbol) {
            if symbolInfo.kind == .annotationClass,
               let annotationSymbol = types.annotationInterfaceSymbol ?? symbols.lookup(fqName: annotationFQName),
               symbol != annotationSymbol,
               !superSymbols.contains(annotationSymbol)
            {
                superSymbols.append(annotationSymbol)
            }
            // Enum classes implicitly extend `kotlin.Enum<ThisEnum>`. The
            // generated enum lowering registers the runtime edge later, but
            // source-backed Comparable member lookup must see this conformance
            // during Sema as well (e.g. `Direction.NORTH.compareTo(...)`).
            if symbolInfo.kind == .enumClass,
               let enumBaseSymbol = symbols.lookup(fqName: [
                   interner.intern("kotlin"),
                   interner.intern("Enum"),
               ]),
               symbol != enumBaseSymbol,
               !superSymbols.contains(enumBaseSymbol)
            {
                let enumType = types.make(.classType(ClassType(
                    classSymbol: symbol,
                    args: [],
                    nullability: .nonNull
                )))
                let enumTypeArg: [TypeArg] = [.invariant(enumType)]
                symbols.setSupertypeTypeArgs(enumTypeArg, for: symbol, supertype: enumBaseSymbol)
                types.setNominalSupertypeTypeArgs(enumTypeArg, for: symbol, supertype: enumBaseSymbol)
                superSymbols.append(enumBaseSymbol)
            }
            // Add implicit kotlin.Any for classes/objects/enums that have no
            // class supertype yet (they may still implement interfaces).
            if symbolInfo.kind == .class || symbolInfo.kind == .object
                || symbolInfo.kind == .enumClass || symbolInfo.kind == .annotationClass
            {
                let hasClassSupertype = superSymbols.contains { superSym in
                    guard let info = symbols.symbol(superSym) else { return false }
                    return info.kind == .class || info.kind == .enumClass || info.kind == .annotationClass
                }
                if !hasClassSupertype,
                   let anySymbol = symbols.lookup(fqName: anyFQName),
                   symbol != anySymbol,
                   !superSymbols.contains(anySymbol)
                {
                    superSymbols.append(anySymbol)
                }
            }
        }

        let uniqueSuperSymbols = Array(Set(superSymbols)).sorted(by: { $0.rawValue < $1.rawValue })
        symbols.setDirectSupertypes(uniqueSuperSymbols, for: symbol)
        types.setNominalDirectSupertypes(uniqueSuperSymbols, for: symbol)

        // The current nominal's fqName joins the scope chain so nested
        // declarations resolve sibling classifiers (e.g. `Inner` inside
        // `Container` -> `Container.Inner`) per Kotlin's scope nesting.
        var nestedScopes = enclosingClassScopes
        if let ownerFQName = symbols.symbol(symbol)?.fqName {
            nestedScopes.append(ownerFQName)
        }
        for nestedDeclID in nestedDecls {
            bindInheritanceEdges(
                declID: nestedDeclID,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: mergedEnclosingTypeParameters,
                enclosingClassScopes: nestedScopes,
                ast: ast,
                symbols: symbols,
                bindings: bindings,
                types: types,
                diagnostics: diagnostics,
                interner: interner
            )
        }
    }

    private func buildTypeParameterMap(
        for owner: SymbolID,
        types: TypeSystem,
        symbols: SymbolTable
    ) -> [InternedString: SymbolID] {
        var map: [InternedString: SymbolID] = [:]
        for typeParam in types.nominalTypeParameterSymbols(for: owner) {
            guard let paramSym = symbols.symbol(typeParam) else { continue }
            map[paramSym.name] = typeParam
        }
        return map
    }

    private struct ResolvedSupertype {
        let symbol: SymbolID
        let typeArgs: [TypeArg]
    }

    /// Builds the candidate FQNs used by inheritance resolution for a type
    /// reference. Inheritance is bound before file scopes are built, so this
    /// mirrors the relevant file-scope lookup rules explicitly instead of
    /// falling back to the global short-name index.
    private func inheritanceCandidatePaths(
        for path: [InternedString],
        currentPackage: [InternedString],
        imports: [ImportDecl],
        enclosingClassScopes: [[InternedString]] = [],
        symbols: SymbolTable
    ) -> [[InternedString]] {
        guard !path.isEmpty else {
            return []
        }

        var candidates: [[InternedString]] = []
        var seen: Set<[InternedString]> = []
        func append(_ candidate: [InternedString]) {
            guard seen.insert(candidate).inserted else {
                return
            }
            candidates.append(candidate)
        }

        // Enclosing class scopes resolve sibling nested classifiers before
        // package-level lookups, matching Kotlin's scope nesting (innermost
        // scope first).
        for scope in enclosingClassScopes.reversed() {
            append(scope + path)
        }

        if path.count == 1 {
            // Kotlin ranks explicit (single-type and alias) imports above
            // same-package declarations in the classifier namespace, so they
            // are expanded before the package path (KUU-1423). Wildcard and
            // member-contributing imports stay below the package tier.
            let simpleName = path[0]
            for importDecl in imports {
                if let alias = importDecl.alias {
                    if alias == simpleName {
                        append(importDecl.path)
                    }
                } else if !importDecl.isWildcard, importDecl.path.last == simpleName {
                    append(importDecl.path)
                }
            }

            if !currentPackage.isEmpty {
                append(currentPackage + path)
            }

            // `extractQualifiedPath` removes the `*` from wildcard imports.
            // Package-only paths (and `a.b.*` wildcards) contribute members;
            // a path also resolving to a declaration does not — the synthetic
            // package record sharing a class's FQ name must not leak the
            // class's neighbours into bare-name supertype lookup (KUU-1205).
            for importDecl in imports where importDecl.alias == nil {
                if symbols.importPathContributesMembers(importDecl.path, isWildcard: importDecl.isWildcard) {
                    append(importDecl.path + path)
                }
            }

            // A root-package declaration is not a file-scoped import. Keep it
            // as a fallback for compatibility with root-package source files,
            // but never let it shadow an explicit import above.
            append(path)
        } else {
            // An imported classifier (including an alias) may qualify a nested
            // supertype, e.g. CoroutineContext.Key<E>. Resolve that prefix before
            // looking for a root-qualified path so the inheritance edge is kept.
            for importDecl in imports where !importDecl.isWildcard {
                let importedName = importDecl.alias ?? importDecl.path.last
                if importedName == path.first {
                    append(importDecl.path + path.dropFirst())
                }
            }
            append(path)
            if !currentPackage.isEmpty {
                // Allow nested/package-relative supertypes such as
                // `TimeSource.WithComparableMarks` inside `kotlin.time`.
                append(currentPackage + path)
            }

            // A qualified supertype like `CoroutineContext.Key` resolves its
            // first segment through imports the same way simple names do:
            // `import kotlin.coroutines.CoroutineContext` contributes the
            // candidate `kotlin.coroutines.CoroutineContext.Key`. Without
            // this, user files outside the imported package silently drop
            // the supertype and fall back to kotlin.Any.
            let rootSegment = path[0]
            let remainder = Array(path.dropFirst())
            for importDecl in imports {
                if let alias = importDecl.alias {
                    if alias == rootSegment {
                        append(importDecl.path + remainder)
                    }
                } else if importDecl.path.last == rootSegment {
                    append(importDecl.path + remainder)
                }
            }

            // Wildcard/package imports contribute the whole qualified path,
            // e.g. `import kotlin.coroutines.*` + `CoroutineContext.Key`.
            for importDecl in imports where importDecl.alias == nil {
                if symbols.importPathContributesMembers(importDecl.path, isWildcard: importDecl.isWildcard) {
                    append(importDecl.path + path)
                }
            }
        }

        return candidates
    }

    private func resolveNominalSymbolAndTypeArgs(
        _ typeRefID: TypeRefID,
        currentPackage: [InternedString],
        imports: [ImportDecl],
        enclosingTypeParameters: [InternedString: SymbolID],
        enclosingClassScopes: [[InternedString]] = [],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> ResolvedSupertype? {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }
        let path: [InternedString]
        let argRefs: [TypeArgRef]
        switch typeRef {
        case let .named(refPath, refs, _):
            path = refPath
            argRefs = refs
        case let .functionType(contextReceiverRefIDs, receiverRefID, paramRefIDs, returnRefID, isSuspend, _):
            // KSP-682 / KSP-CAP-009: a function-type supertype such as
            // `KProperty0<V> : () -> V` resolves to the kotlin.Function{N}
            // nominal interface so property references inherit invoke(...).
            // Suspend and context-receiver function types have no nominal
            // Function{N} equivalent here, so they are left unbound.
            guard !isSuspend, contextReceiverRefIDs.isEmpty else {
                return nil
            }
            var paramTypes: [TypeID] = []
            if let receiverRefID {
                guard let receiverType = resolveTypeRefForInheritance(
                    receiverRefID, currentPackage: currentPackage,
                    imports: imports,
                    enclosingTypeParameters: enclosingTypeParameters, ast: ast,
                    symbols: symbols, types: types, interner: interner
                ) else { return nil }
                paramTypes.append(receiverType)
            }
            for paramRef in paramRefIDs {
                guard let paramType = resolveTypeRefForInheritance(
                    paramRef, currentPackage: currentPackage,
                    imports: imports,
                    enclosingTypeParameters: enclosingTypeParameters, ast: ast,
                    symbols: symbols, types: types, interner: interner
                ) else { return nil }
                paramTypes.append(paramType)
            }
            guard let returnType = resolveTypeRefForInheritance(
                returnRefID, currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters, ast: ast,
                symbols: symbols, types: types, interner: interner
            ) else { return nil }
            let functionFQName = [
                interner.intern("kotlin"), interner.intern("Function"),
                interner.intern("Function\(paramTypes.count)"),
            ]
            guard let functionSymbol = symbols.lookupAll(fqName: functionFQName)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id
            else {
                return nil
            }
            // KUU-1084: FunctionN declares its type params in Kotlin order
            // [P1..PN, R], so the supertype args carry params then return type.
            let functionArgs: [TypeArg] = paramTypes.map { .in($0) } + [.out(returnType)]
            return ResolvedSupertype(symbol: functionSymbol, typeArgs: functionArgs)
        case .intersection, .annotated:
            return nil
        }
        guard !path.isEmpty else {
            return nil
        }

        let candidatePaths = inheritanceCandidatePaths(
            for: path,
            currentPackage: currentPackage,
            imports: imports,
            enclosingClassScopes: enclosingClassScopes,
            symbols: symbols
        )

        for candidatePath in candidatePaths {
            if let symbol = symbols.lookupAll(fqName: candidatePath)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id
            {
                let resolvedArgs = resolveTypeArgRefsForInheritance(
                    argRefs,
                    currentPackage: currentPackage,
                    imports: imports,
                    enclosingTypeParameters: enclosingTypeParameters,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner
                )
                let nominal = resolveTypeAliasSupertype(symbol, symbols: symbols, types: types) ?? symbol
                return ResolvedSupertype(symbol: nominal, typeArgs: resolvedArgs)
            }
        }

        // Kotlin default imports are considered after primitive/builtin names
        // in resolveTypeRefForInheritance. Supertype roots have no primitive
        // representation, so they can use the default-import packages here.
        do {
            for defaultPackage in TypeCheckScopeBuilder().makeDefaultImportPackages(interner: interner) {
                let candidatePath = defaultPackage + path
                if let symbol = symbols.lookupAll(fqName: candidatePath)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { isNominalTypeSymbol($0.kind) })?.id
                {
                    let resolvedArgs = resolveTypeArgRefsForInheritance(
                        argRefs,
                        currentPackage: currentPackage,
                        imports: imports,
                        enclosingTypeParameters: enclosingTypeParameters,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner
                    )
                    let nominal = resolveTypeAliasSupertype(symbol, symbols: symbols, types: types) ?? symbol
                    return ResolvedSupertype(symbol: nominal, typeArgs: resolvedArgs)
                }
            }
        }
        return nil
    }

    /// A supertype written through a type alias (e.g. `class R : AutoCloseable`, where
    /// `kotlin.AutoCloseable` aliases `kotlin.io.Closeable`) must record the aliased
    /// nominal type: the alias symbol itself is neither open nor an interface, and it
    /// carries no layout, so leaving it in the inheritance edge suppresses both the
    /// subclassability check and vtable/itable synthesis for the implementer.
    private func resolveTypeAliasSupertype(
        _ symbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> SymbolID? {
        guard symbols.symbol(symbol)?.kind == .typeAlias,
              let underlying = symbols.typeAliasUnderlyingType(for: symbol),
              case let .classType(classType) = types.kind(of: underlying),
              classType.classSymbol != symbol
        else {
            return nil
        }
        return resolveTypeAliasSupertype(classType.classSymbol, symbols: symbols, types: types)
            ?? classType.classSymbol
    }

    private func resolveTypeArgRefsForInheritance(
        _ argRefs: [TypeArgRef],
        currentPackage: [InternedString],
        imports: [ImportDecl],
        enclosingTypeParameters: [InternedString: SymbolID],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> [TypeArg] {
        // Use all-or-nothing semantics: if any type arg fails to resolve,
        // return an empty array to preserve positional integrity.
        var result: [TypeArg] = []
        result.reserveCapacity(argRefs.count)
        for argRef in argRefs {
            switch argRef {
            case let .invariant(innerRef):
                guard let resolved = resolveTypeRefForInheritance(innerRef, currentPackage: currentPackage, imports: imports, enclosingTypeParameters: enclosingTypeParameters, ast: ast, symbols: symbols, types: types, interner: interner) else {
                    return []
                }
                result.append(.invariant(resolved))
            case let .out(innerRef):
                guard let resolved = resolveTypeRefForInheritance(innerRef, currentPackage: currentPackage, imports: imports, enclosingTypeParameters: enclosingTypeParameters, ast: ast, symbols: symbols, types: types, interner: interner) else {
                    return []
                }
                result.append(.out(resolved))
            case let .in(innerRef):
                guard let resolved = resolveTypeRefForInheritance(innerRef, currentPackage: currentPackage, imports: imports, enclosingTypeParameters: enclosingTypeParameters, ast: ast, symbols: symbols, types: types, interner: interner) else {
                    return []
                }
                result.append(.in(resolved))
            case .star:
                result.append(.star)
            }
        }
        return result
    }

    private func resolveTypeRefForInheritance(
        _ typeRefID: TypeRefID,
        currentPackage: [InternedString],
        imports: [ImportDecl],
        enclosingTypeParameters: [InternedString: SymbolID],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID? {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return nil
        }
        switch typeRef {
        case let .named(path, argRefs, nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            guard !path.isEmpty else {
                return nil
            }
            // A single-component name that matches an enclosing type parameter
            // resolves to that type parameter (it shadows any same-named type).
            if path.count == 1, let typeParamSymbol = enclosingTypeParameters[path[0]] {
                return types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbol,
                    nullability: nullability
                )))
            }
            // Qualified Kotlin builtins use the same representation as their
            // unqualified names, including inside inherited type arguments.
            // Looking up kotlin.Boolean as a nominal class here would record
            // ArgType<Class#Boolean> instead of ArgType<Boolean>.
            if path.count == 2, path[0] == interner.intern("kotlin"),
               let builtinType = resolveBuiltinTypeNameForInheritance(
                   path[1], interner: interner, nullability: nullability, types: types
               )
            {
                return builtinType
            }
            let candidatePaths = inheritanceCandidatePaths(
                for: path,
                currentPackage: currentPackage,
                imports: imports,
                symbols: symbols
            )
            for candidatePath in candidatePaths {
                if let nominalSymbol = symbols.lookupAll(fqName: candidatePath)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { isNominalTypeSymbol($0.kind) })
                {
                    let resolvedArgs = resolveTypeArgRefsForInheritance(argRefs, currentPackage: currentPackage, imports: imports, enclosingTypeParameters: enclosingTypeParameters, ast: ast, symbols: symbols, types: types, interner: interner)
                    return types.make(.classType(ClassType(classSymbol: nominalSymbol.id, args: resolvedArgs, nullability: nullability)))
                }
            }
            // Resolve built-in/primitive type names first so they take precedence
            // over the default-import packages (e.g. `Int` is the primitive Int,
            // not any class named `Int` that might exist under `kotlin`).
            if path.count == 1 {
                if let builtinType = resolveBuiltinTypeNameForInheritance(
                    path[0],
                    interner: interner,
                    nullability: nullability,
                    types: types
                ) {
                    return builtinType
                }
            }
            // Kotlin default imports also apply to type arguments (e.g.
            // class X : Comparable<Int>), so search the standard default-import packages.
            do {
                for defaultPackage in TypeCheckScopeBuilder().makeDefaultImportPackages(interner: interner) {
                    let candidatePath = defaultPackage + path
                    if let nominalSymbol = symbols.lookupAll(fqName: candidatePath)
                        .compactMap({ symbols.symbol($0) })
                        .first(where: { isNominalTypeSymbol($0.kind) })
                    {
                        let resolvedArgs = resolveTypeArgRefsForInheritance(argRefs, currentPackage: currentPackage, imports: imports, enclosingTypeParameters: enclosingTypeParameters, ast: ast, symbols: symbols, types: types, interner: interner)
                        return types.make(.classType(ClassType(classSymbol: nominalSymbol.id, args: resolvedArgs, nullability: nullability)))
                    }
                }
            }
            return nil
        case let .functionType(contextReceiverRefIDs, receiverRefID, paramRefIDs, returnRefID, isSuspend, nullable):
            return resolveFunctionTypeForInheritance(
                contextReceiverRefIDs: contextReceiverRefIDs,
                receiverRefID: receiverRefID, paramRefIDs: paramRefIDs, returnRefID: returnRefID, isSuspend: isSuspend, nullable: nullable,
                currentPackage: currentPackage, imports: imports, enclosingTypeParameters: enclosingTypeParameters, ast: ast, symbols: symbols, types: types, interner: interner
            )
        case let .intersection(partRefs):
            let partTypes = partRefs.compactMap { resolveTypeRefForInheritance($0, currentPackage: currentPackage, imports: imports, enclosingTypeParameters: enclosingTypeParameters, ast: ast, symbols: symbols, types: types, interner: interner) }
            guard partTypes.count == partRefs.count else { return nil }
            return types.make(.intersection(partTypes))
        case let .annotated(base, annotations):
            guard let baseType = resolveTypeRefForInheritance(
                base,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) else {
                return nil
            }
            return ExtensionFunctionTypeSupport.normalizeAnnotatedType(
                baseType: baseType,
                annotations: annotations,
                symbols: symbols,
                types: types,
                interner: interner,
                diagnostics: nil
            )
        }
    }

    private func resolveFunctionTypeForInheritance(
        contextReceiverRefIDs: [TypeRefID],
        receiverRefID: TypeRefID?,
        paramRefIDs: [TypeRefID],
        returnRefID: TypeRefID,
        isSuspend: Bool,
        nullable: Bool,
        currentPackage: [InternedString],
        imports: [ImportDecl],
        enclosingTypeParameters: [InternedString: SymbolID],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID? {
        let nullability: Nullability = nullable ? .nullable : .nonNull
        var contextReceiverTypes: [TypeID] = []
        for contextReceiverRef in contextReceiverRefIDs {
            guard let contextReceiverType = resolveTypeRefForInheritance(
                contextReceiverRef, currentPackage: currentPackage, imports: imports, enclosingTypeParameters: enclosingTypeParameters, ast: ast, symbols: symbols, types: types, interner: interner
            ) else { return nil }
            contextReceiverTypes.append(contextReceiverType)
        }
        var receiverType: TypeID?
        if let receiverRefID {
            guard let resolved = resolveTypeRefForInheritance(
                receiverRefID, currentPackage: currentPackage, imports: imports, enclosingTypeParameters: enclosingTypeParameters, ast: ast, symbols: symbols, types: types, interner: interner
            ) else { return nil }
            receiverType = resolved
        }
        var paramTypes: [TypeID] = []
        for paramRef in paramRefIDs {
            guard let paramType = resolveTypeRefForInheritance(
                paramRef, currentPackage: currentPackage, imports: imports, enclosingTypeParameters: enclosingTypeParameters, ast: ast, symbols: symbols, types: types, interner: interner
            ) else { return nil }
            paramTypes.append(paramType)
        }
        guard let returnType = resolveTypeRefForInheritance(
            returnRefID, currentPackage: currentPackage, imports: imports, enclosingTypeParameters: enclosingTypeParameters, ast: ast, symbols: symbols, types: types, interner: interner
        ) else { return nil }
        return types.make(.functionType(FunctionType(
            contextReceivers: contextReceiverTypes,
            receiver: receiverType, params: paramTypes, returnType: returnType, isSuspend: isSuspend, nullability: nullability
        )))
    }

    private func resolveBuiltinTypeNameForInheritance(
        _ name: InternedString,
        interner: StringInterner,
        nullability: Nullability,
        types: TypeSystem
    ) -> TypeID? {
        if let builtinType = BuiltinTypeNames(interner: interner).resolveBuiltinType(name, nullability: nullability, types: types) {
            return builtinType
        }
        if name == interner.intern("Byte") || name == interner.intern("Short") {
            return types.make(.primitive(.int, nullability))
        }
        return nil
    }

    func isNominalTypeSymbol(_ kind: SymbolKind) -> Bool {
        switch kind {
        case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
            true
        default:
            false
        }
    }

    // P5-112: Validate that concrete subclasses of abstract classes override all abstract members.
    func validateAbstractOverrides(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in nominalDeclarationIDs(in: file, ast: ast) {
                validateAbstractOverridesForDecl(
                    declID: declID,
                    file: file,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    types: types,
                    diagnostics: diagnostics,
                    interner: interner
                )
            }
        }
    }

    /// CLASS-008: Validate class delegation (`: Interface by expr`).
    /// Ensures delegated supertypes are interfaces (not classes) and records them for abstract override exemption.
    func validateClassDelegation(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in nominalDeclarationIDs(in: file, ast: ast) {
                guard let decl = ast.arena.decl(declID),
                      let classSymbol = bindings.declSymbols[declID]
                else {
                    continue
                }
                let entries: [SuperTypeEntry]
                let range: SourceRange
                switch decl {
                case let .classDecl(classDecl):
                    entries = classDecl.superTypeEntries
                    range = classDecl.range
                case let .objectDecl(objectDecl):
                    entries = objectDecl.superTypeEntries
                    range = objectDecl.range
                default:
                    continue
                }
                var enclosingTypeParameters = buildTypeParameterMap(for: classSymbol, types: types, symbols: symbols)
                var enclosingClassScopes: [[InternedString]] = []
                var parent = symbols.parentSymbol(for: classSymbol)
                while let owner = parent, let ownerSym = symbols.symbol(owner) {
                    enclosingClassScopes.append(ownerSym.fqName)
                    enclosingTypeParameters.merge(buildTypeParameterMap(for: owner, types: types, symbols: symbols)) {
                        current, _ in current
                    }
                    parent = symbols.parentSymbol(for: owner)
                }
                for entry in entries where entry.delegateExpression != nil {
                    guard let resolved = resolveNominalSymbolAndTypeArgs(
                        entry.typeRef,
                        currentPackage: file.packageFQName,
                        imports: file.imports,
                        enclosingTypeParameters: enclosingTypeParameters,
                        enclosingClassScopes: enclosingClassScopes,
                        ast: ast,
                        symbols: symbols,
                        types: types,
                        interner: interner
                    ) else {
                        continue
                    }
                    if let delegateExpr = entry.delegateExpression {
                        let interfaceType = types.make(.classType(ClassType(
                            classSymbol: resolved.symbol,
                            args: resolved.typeArgs,
                            nullability: .nonNull
                        )))
                        registerClassDelegation(
                            delegateExpression: delegateExpr,
                            interfaceType: interfaceType,
                            classSymbol: classSymbol,
                            range: range,
                            symbols: symbols,
                            types: types,
                            diagnostics: diagnostics,
                            interner: interner
                        )
                    }
                }
            }
        }
    }

    /// Records the same delegation storage for header-time named nominals and
    /// anonymous objects discovered later during body type checking.
    @discardableResult
    func registerClassDelegation(
        delegateExpression: ExprID,
        interfaceType: TypeID,
        classSymbol: SymbolID,
        range: SourceRange,
        symbols: SymbolTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) -> SymbolID? {
        guard case let .classType(delegatedType) = types.kind(of: interfaceType),
              let interfaceSymbol = symbols.symbol(delegatedType.classSymbol),
              let classInfo = symbols.symbol(classSymbol)
        else { return nil }
        guard interfaceSymbol.kind == .interface else {
            let name = interfaceSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
            diagnostics.error(
                "KSWIFTK-SEMA-DELEGATE",
                "Class delegation is only supported for interfaces, not '\(name)'.",
                range: range
            )
            return nil
        }
        symbols.addDelegatedInterface(interfaceSymbol.id, forClass: classSymbol)
        symbols.setClassDelegationExpr(delegateExpression, forClass: classSymbol, interface: interfaceSymbol.id)
        let interfaceName = interner.resolve(interfaceSymbol.fqName.last ?? interner.intern(""))
        let fieldName = interner.intern("$delegate_\(interfaceName)")
        let fieldSymbol = symbols.define(
            kind: .field,
            name: fieldName,
            fqName: classInfo.fqName + [fieldName],
            declSite: range,
            visibility: .private,
            flags: []
        )
        symbols.setParentSymbol(classSymbol, for: fieldSymbol)
        symbols.setPropertyType(interfaceType, for: fieldSymbol)
        symbols.setClassDelegationField(fieldSymbol, forClass: classSymbol, interface: interfaceSymbol.id)
        return fieldSymbol
    }

    private func nominalDeclarationIDs(in file: ASTFile, ast: ASTModule) -> [DeclID] {
        var result: [DeclID] = []
        var queue = file.topLevelDecls
        while let declID = queue.popLast() {
            guard let decl = ast.arena.decl(declID) else { continue }
            switch decl {
            case let .classDecl(classDecl):
                queue.append(contentsOf: classDecl.nestedClasses + classDecl.nestedObjects)
                if let companion = classDecl.companionObject { queue.append(companion) }
            case let .interfaceDecl(interfaceDecl):
                queue.append(contentsOf: interfaceDecl.nestedClasses + interfaceDecl.nestedObjects)
                if let companion = interfaceDecl.companionObject { queue.append(companion) }
            case let .objectDecl(objectDecl):
                queue.append(contentsOf: objectDecl.nestedClasses + objectDecl.nestedObjects)
            default:
                continue
            }
            result.append(declID)
        }
        return result
    }

    /// CLASS-008: Create synthetic method symbols for delegated interface methods
    /// that the class does not override. These are used for itable layout and KIR lowering.
    private struct DelegationDispatchKey {
        let name: InternedString
        let parameterTypes: [TypeID]
        let methodTypeParameters: [SymbolID]
        let isSuspend: Bool

        func matches(_ other: DelegationDispatchKey, types: TypeSystem) -> Bool {
            guard name == other.name, isSuspend == other.isSuspend,
                  parameterTypes.count == other.parameterTypes.count,
                  methodTypeParameters.count == other.methodTypeParameters.count
            else { return false }
            // Compare alpha-equivalent method parameters after the interface's
            // class parameters have been substituted. Arity alone loses overloads.
            let typeVarBySymbol = types.makeTypeVarBySymbol(methodTypeParameters)
            var substitution: [TypeVarID: TypeID] = [:]
            for (parameter, otherParameter) in zip(methodTypeParameters, other.methodTypeParameters) {
                guard let typeVar = typeVarBySymbol[parameter] else { continue }
                substitution[typeVar] = types.make(.typeParam(TypeParamType(
                    symbol: otherParameter, nullability: .nonNull
                )))
            }
            return parameterTypes.map {
                types.substituteTypeParameters(in: $0, substitution: substitution, typeVarBySymbol: typeVarBySymbol)
            } == other.parameterTypes
        }
    }

    private func delegationDispatchKey(
        for method: SemanticSymbol,
        signature: FunctionSignature,
        parameterTypes: [TypeID]? = nil
    ) -> DelegationDispatchKey {
        return DelegationDispatchKey(
            name: method.name,
            parameterTypes: parameterTypes ?? signature.parameterTypes,
            methodTypeParameters: Array(signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)),
            isSuspend: signature.isSuspend
        )
    }

    func synthesizeClassDelegationForwardingMethodSymbols(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in nominalDeclarationIDs(in: file, ast: ast) {
                guard let decl = ast.arena.decl(declID),
                      let classSymbol = bindings.declSymbols[declID],
                      let classSym = symbols.symbol(classSymbol)
                else {
                    continue
                }
                let range: SourceRange
                let memberFunctions: [DeclID]
                let memberProperties: [DeclID]
                switch decl {
                case let .classDecl(classDecl):
                    range = classDecl.range
                    memberFunctions = classDecl.memberFunctions
                    memberProperties = classDecl.memberProperties
                case let .objectDecl(objectDecl):
                    range = objectDecl.range
                    memberFunctions = objectDecl.memberFunctions
                    memberProperties = objectDecl.memberProperties
                default:
                    continue
                }
                synthesizeDelegationForwardingForClass(
                    range: range, memberFunctions: memberFunctions, memberProperties: memberProperties,
                    classSymbol: classSymbol, classFQName: classSym.fqName,
                    symbols: symbols, bindings: bindings, types: types, interner: interner
                )
            }
        }
    }

    func synthesizeDelegationForwardingForClass(
        range: SourceRange,
        memberFunctions: [DeclID],
        memberProperties: [DeclID],
        classSymbol: SymbolID,
        classFQName: [InternedString],
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        var classMethodKeys: [DelegationDispatchKey] = []
        for funDeclID in memberFunctions {
            guard let funSymbol = bindings.declSymbols[funDeclID],
                  let method = symbols.symbol(funSymbol),
                  let signature = symbols.functionSignature(for: funSymbol)
            else { continue }
            classMethodKeys.append(delegationDispatchKey(for: method, signature: signature))
        }
        var classPropertyNames: Set<InternedString> = []
        for propDeclID in memberProperties {
            guard let propSymbol = bindings.declSymbols[propDeclID],
                  let propSym = symbols.symbol(propSymbol)
            else { continue }
            classPropertyNames.insert(propSym.name)
        }
        let classTypeParameterSymbols = types.nominalTypeParameterSymbols(for: classSymbol)

        for interfaceSymbol in symbols.delegatedInterfaces(forClass: classSymbol) {
            guard let fieldSymbol = symbols.classDelegationField(forClass: classSymbol, interface: interfaceSymbol)
            else {
                continue
            }
            let delegatedTypeArgs = delegationFieldTypeArgs(
                fieldSymbol: fieldSymbol,
                symbols: symbols,
                types: types
            )

            // Walk the delegated interface plus its inherited interfaces so
            // members declared on a super-interface (e.g. `Map.isEmpty` for a
            // `MutableMap` delegate) are forwarded too. Nearest declaration wins.
            var ownerQueue: [SymbolID] = [interfaceSymbol]
            var visitedOwners: Set<SymbolID> = []
            var seenMethodKeys = classMethodKeys
            var seenPropertyNames = classPropertyNames
            while !ownerQueue.isEmpty {
                let ownerInterface = ownerQueue.removeFirst()
                guard visitedOwners.insert(ownerInterface).inserted,
                      let ownerSym = symbols.symbol(ownerInterface)
                else {
                    continue
                }
                for supertype in symbols.directSupertypes(for: ownerInterface) {
                    if symbols.symbol(supertype)?.kind == .interface {
                        ownerQueue.append(supertype)
                    }
                }

                let (substitution, typeVarBySymbol) = delegationSubstitution(
                    for: ownerInterface,
                    delegatedInterface: interfaceSymbol,
                    delegatedTypeArgs: delegatedTypeArgs,
                    types: types
                )
                let interfaceMembers = symbols.children(ofFQName: ownerSym.fqName)
                    .compactMap { symbols.symbol($0) }
                    .filter { symbols.parentSymbol(for: $0.id) == ownerInterface }
                    // Extension member aliases (KSP-443) are lookup shims, not
                    // interface members — delegation must not forward to them.
                    .filter { !$0.flags.contains(.extensionMemberAlias) }

                for memberSym in interfaceMembers {
                    switch memberSym.kind {
                    case .function:
                        guard let ifaceSig = symbols.functionSignature(for: memberSym.id) else { continue }
                        let key = delegationDispatchKey(
                            for: memberSym, signature: ifaceSig,
                            parameterTypes: ifaceSig.parameterTypes.map {
                                substituteDelegationType(
                                    $0, substitution: substitution, typeVarBySymbol: typeVarBySymbol, types: types
                                )
                            }
                        )
                        guard !seenMethodKeys.contains(where: { key.matches($0, types: types) }) else { continue }
                        seenMethodKeys.append(key)
                        synthesizeForwardingMethod(
                            methodSym: memberSym, ifaceSig: ifaceSig,
                            range: range, classSymbol: classSymbol, classFQName: classFQName,
                            interfaceSymbol: ownerInterface, fieldSymbol: fieldSymbol,
                            substitution: substitution, typeVarBySymbol: typeVarBySymbol,
                            classTypeParameterSymbols: classTypeParameterSymbols,
                            symbols: symbols, types: types, interner: interner
                        )
                    case .property:
                        guard seenPropertyNames.insert(memberSym.name).inserted,
                              let propertyType = symbols.propertyType(for: memberSym.id)
                        else { continue }
                        synthesizeForwardingProperty(
                            propertySym: memberSym, propertyType: propertyType,
                            range: range, classSymbol: classSymbol, classFQName: classFQName,
                            interfaceSymbol: ownerInterface, fieldSymbol: fieldSymbol,
                            substitution: substitution, typeVarBySymbol: typeVarBySymbol,
                            symbols: symbols, types: types, interner: interner
                        )
                    default:
                        continue
                    }
                }
            }
        }
    }

    /// The concrete type arguments the delegated supertype applies to the
    /// interface, e.g. `[String, Int]` for `by mapOf(...)` on `Map<String, Int>`
    /// — the delegate field's declared type carries them.
    private func delegationFieldTypeArgs(
        fieldSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem
    ) -> [TypeArg] {
        guard let fieldType = symbols.propertyType(for: fieldSymbol),
              case let .classType(classType) = types.kind(of: types.makeNonNullable(fieldType))
        else {
            return []
        }
        return classType.args
    }

    /// Maps `ownerInterface`'s type parameters to the concrete arguments the
    /// delegation declaration supplies — e.g. `Map` gets `[String, Int]` when
    /// the class delegates `MutableMap<String, Int>`.
    private func delegationSubstitution(
        for ownerInterface: SymbolID,
        delegatedInterface: SymbolID,
        delegatedTypeArgs: [TypeArg],
        types: TypeSystem
    ) -> (substitution: [TypeVarID: TypeID], typeVarBySymbol: [SymbolID: TypeVarID]) {
        let ownerTypeParams = types.nominalTypeParameterSymbols(for: ownerInterface)
        guard !ownerTypeParams.isEmpty else {
            return ([:], [:])
        }
        let ownerArgs: [TypeArg] = if ownerInterface == delegatedInterface {
            delegatedTypeArgs
        } else {
            types.liftedNominalSupertypeArgs(
                from: delegatedInterface,
                childArgs: delegatedTypeArgs,
                to: ownerInterface
            ) ?? []
        }
        let typeVarBySymbol = types.makeTypeVarBySymbol(ownerTypeParams)
        var substitution: [TypeVarID: TypeID] = [:]
        for (index, typeParamSymbol) in ownerTypeParams.enumerated() {
            guard index < ownerArgs.count,
                  let typeVar = typeVarBySymbol[typeParamSymbol]
            else {
                continue
            }
            switch ownerArgs[index] {
            case let .invariant(inner), let .out(inner), let .in(inner):
                substitution[typeVar] = inner
            case .star:
                substitution[typeVar] = types.nullableAnyType
            }
        }
        return (substitution, typeVarBySymbol)
    }

    private func substituteDelegationType(
        _ type: TypeID,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        types: TypeSystem
    ) -> TypeID {
        guard !substitution.isEmpty else { return type }
        return types.substituteTypeParameters(
            in: type,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    private func synthesizeForwardingMethod(
        methodSym: SemanticSymbol,
        ifaceSig: FunctionSignature,
        range: SourceRange,
        classSymbol: SymbolID,
        classFQName: [InternedString],
        interfaceSymbol: SymbolID,
        fieldSymbol: SymbolID,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        classTypeParameterSymbols: [SymbolID],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let methodName = methodSym.name
        let forwardingFQName = classFQName + [methodName]
        let forwardingSymbol = symbols.define(
            kind: .function,
            name: methodName,
            fqName: forwardingFQName,
            declSite: range,
            visibility: methodSym.visibility,
            flags: [.synthetic, .overrideMember]
        )
        symbols.setParentSymbol(classSymbol, for: forwardingSymbol)

        let classTypeArgs = classTypeParameterSymbols.map {
            TypeArg.invariant(types.make(.typeParam(TypeParamType(
                symbol: $0, nullability: .nonNull
            ))))
        }
        let classType = types.make(.classType(ClassType(
            classSymbol: classSymbol, args: classTypeArgs, nullability: .nonNull
        )))

        let parameterTypes = ifaceSig.parameterTypes.map {
            substituteDelegationType(
                $0, substitution: substitution, typeVarBySymbol: typeVarBySymbol, types: types
            )
        }
        let returnType = substituteDelegationType(
            ifaceSig.returnType, substitution: substitution,
            typeVarBySymbol: typeVarBySymbol, types: types
        )

        var paramSymbols: [SymbolID] = []
        for (index, paramType) in parameterTypes.enumerated() {
            let paramName = interner.intern("p\(index)")
            let paramFQName = forwardingFQName + [paramName]
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramName,
                fqName: paramFQName,
                declSite: range,
                visibility: .private,
                flags: []
            )
            symbols.setParentSymbol(forwardingSymbol, for: paramSymbol)
            symbols.setPropertyType(paramType, for: paramSymbol)
            paramSymbols.append(paramSymbol)
        }

        let forwardingSig = FunctionSignature(
            receiverType: classType,
            parameterTypes: parameterTypes,
            returnType: returnType,
            isSuspend: ifaceSig.isSuspend,
            valueParameterSymbols: paramSymbols,
            valueParameterHasDefaultValues: Array(repeating: false, count: paramSymbols.count),
            valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count),
            typeParameterSymbols: classTypeParameterSymbols,
            classTypeParameterCount: classTypeParameterSymbols.count
        )
        symbols.setFunctionSignature(forwardingSig, for: forwardingSymbol)

        symbols.addClassDelegationForwardingMethod(
            forwardingSymbol,
            forClass: classSymbol,
            interface: interfaceSymbol,
            interfaceMethod: methodSym.id,
            field: fieldSymbol
        )
    }

    /// Mirrors `synthesizeForwardingMethod` for a delegated interface
    /// property: gives the class its own `val`/`var` symbol (so member
    /// lookup on the class stops at this property instead of falling
    /// through to the interface's own abstract declaration) that KIR
    /// lowering later gives a real getter/setter body reading through the
    /// delegate field.
    private func synthesizeForwardingProperty(
        propertySym: SemanticSymbol,
        propertyType: TypeID,
        range: SourceRange,
        classSymbol: SymbolID,
        classFQName: [InternedString],
        interfaceSymbol: SymbolID,
        fieldSymbol: SymbolID,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        symbols: SymbolTable,
        types: TypeSystem,
        interner _: StringInterner
    ) {
        var flags: SymbolFlags = [.synthetic, .overrideMember]
        if propertySym.flags.contains(.mutable) {
            flags.insert(.mutable)
        }
        let forwardingSymbol = symbols.define(
            kind: .property,
            name: propertySym.name,
            fqName: classFQName + [propertySym.name],
            declSite: range,
            visibility: propertySym.visibility,
            flags: flags
        )
        symbols.setParentSymbol(classSymbol, for: forwardingSymbol)
        symbols.setPropertyType(
            substituteDelegationType(
                propertyType, substitution: substitution,
                typeVarBySymbol: typeVarBySymbol, types: types
            ),
            for: forwardingSymbol
        )
        symbols.setPropertyHasCustomGetter(true, for: forwardingSymbol)

        symbols.addClassDelegationForwardingProperty(
            forwardingSymbol,
            forClass: classSymbol,
            interface: interfaceSymbol,
            interfaceProperty: propertySym.id,
            field: fieldSymbol
        )
    }


    private func validateAbstractOverridesForDecl(
        declID: DeclID,
        file: ASTFile,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        guard let symbol = bindings.declSymbols[declID],
              let decl = ast.arena.decl(declID),
              let symbolInfo = symbols.symbol(symbol)
        else {
            return
        }

        // Only check concrete class/object declarations (not abstract, not interface)
        guard symbolInfo.kind == .class || symbolInfo.kind == .object,
              !symbolInfo.flags.contains(.abstractType)
        else {
            return
        }

        // Every inherited abstract member this class still owes an
        // implementation for. CLASS-008: members from an interface satisfied
        // through `by` delegation are excluded.
        let missingMembers = unimplementedAbstractMembers(
            for: symbol,
            overriddenNames: collectOverriddenMemberNames(
                for: symbol,
                decl: decl,
                ast: ast,
                symbols: symbols
            ),
            delegatedInterfaces: symbols.delegatedInterfaces(forClass: symbol),
            symbols: symbols,
            interner: interner
        )
        guard !missingMembers.isEmpty else { return }

        let className = symbolInfo.fqName.map { interner.resolve($0) }.joined(separator: ".")
        let declRange: SourceRange? = switch decl {
        case let .classDecl(cd): cd.range
        case let .objectDecl(od): od.range
        default: nil
        }
        for abstractMember in missingMembers {
            guard let abstractSym = symbols.symbol(abstractMember) else { continue }
            diagnostics.error(
                "KSWIFTK-SEMA-ABSTRACT",
                "Class '\(className)' must override abstract member "
                    + "'\(interner.resolve(abstractSym.name))' or be declared abstract.",
                range: declRange
            )
        }
    }

    /// Collects the set of member names that this class provides via `override`.
    func collectOverriddenMemberNames(
        for _: SymbolID,
        decl: Decl,
        ast: ASTModule,
        symbols _: SymbolTable
    ) -> Set<InternedString> {
        var overriddenNames: Set<InternedString> = []

        let memberFunctions: [DeclID]
        let memberProperties: [DeclID]
        switch decl {
        case let .classDecl(classDecl):
            memberFunctions = classDecl.memberFunctions
            memberProperties = classDecl.memberProperties
        case let .objectDecl(objectDecl):
            memberFunctions = objectDecl.memberFunctions
            memberProperties = objectDecl.memberProperties
        default:
            return overriddenNames
        }

        for memberDeclID in memberFunctions {
            guard let memberDecl = ast.arena.decl(memberDeclID),
                  case let .funDecl(funDecl) = memberDecl else { continue }
            if funDecl.modifiers.contains(.override) {
                overriddenNames.insert(funDecl.name)
            }
        }

        for memberDeclID in memberProperties {
            guard let memberDecl = ast.arena.decl(memberDeclID),
                  case let .propertyDecl(propertyDecl) = memberDecl else { continue }
            if propertyDecl.modifiers.contains(.override) {
                overriddenNames.insert(propertyDecl.name)
            }
        }

        return overriddenNames
    }

    // P5-78: Validate that direct subclasses of sealed types are in the same package.
    func validateSealedHierarchy(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner
    ) {
        for file in ast.sortedFiles {
            for declID in file.topLevelDecls {
                guard let symbol = bindings.declSymbols[declID],
                      let decl = ast.arena.decl(declID),
                      let symbolInfo = symbols.symbol(symbol)
                else {
                    continue
                }
                // Only check class and interface declarations that have supertypes
                let hasSuperTypes: Bool
                switch decl {
                case let .classDecl(classDecl):
                    hasSuperTypes = !classDecl.superTypeEntries.isEmpty
                case let .interfaceDecl(interfaceDecl):
                    hasSuperTypes = !interfaceDecl.superTypes.isEmpty
                case let .objectDecl(objectDecl):
                    hasSuperTypes = !objectDecl.superTypes.isEmpty
                default:
                    continue
                }
                guard hasSuperTypes else { continue }

                let supertypes = symbols.directSupertypes(for: symbol)
                for supertypeID in supertypes {
                    guard let supertypeSymbol = symbols.symbol(supertypeID),
                          supertypeSymbol.flags.contains(.sealedType)
                    else {
                        continue
                    }
                    // Check same-package: compare package prefixes
                    let subtypePackage = Array(symbolInfo.fqName.dropLast())
                    let supertypePackage = Array(supertypeSymbol.fqName.dropLast())
                    if subtypePackage != supertypePackage {
                        let subtypeName = symbolInfo.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        let supertypeName = supertypeSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        diagnostics.error(
                            "KSWIFTK-SEMA-0070",
                            "'\(subtypeName)' cannot inherit from sealed type '\(supertypeName)': sealed subclasses must be in the same package.",
                            range: ast.arena.decl(declID).flatMap { d -> SourceRange? in
                                switch d {
                                case let .classDecl(cd): return cd.range
                                case let .interfaceDecl(id): return id.range
                                case let .objectDecl(od): return od.range
                                default: return nil
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}
