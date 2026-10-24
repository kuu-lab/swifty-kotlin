
import Foundation

extension DataFlowSemaPhase {
    func bindInheritanceEdges(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        types: TypeSystem,
        diagnostics: DiagnosticEngine = DiagnosticEngine(),
        sourceManager: SourceManager? = nil,
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
                    sourceManager: sourceManager,
                    interner: interner
                )
            }
        }
    }

    func bindInheritanceEdges(
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
        sourceManager: SourceManager? = nil,
        interner: StringInterner
    ) {
        guard let symbol = bindings.declSymbols[declID],
              let decl = ast.arena.decl(declID)
        else {
            return
        }

        let superTypeRefs: [TypeRefID]
        let superTypeEntries: [SuperTypeEntry]
        let nestedDecls: [DeclID]
        switch decl {
        case let .classDecl(classDecl):
            superTypeRefs = classDecl.superTypeEntries.map(\.typeRef)
            superTypeEntries = classDecl.superTypeEntries
            nestedDecls = classDecl.nestedClasses + classDecl.nestedObjects
                + (classDecl.companionObject.map { [$0] } ?? [])
        case let .interfaceDecl(interfaceDecl):
            superTypeRefs = interfaceDecl.superTypes
            superTypeEntries = []
            nestedDecls = interfaceDecl.nestedClasses + interfaceDecl.nestedObjects
                + (interfaceDecl.companionObject.map { [$0] } ?? [])
        case let .objectDecl(objectDecl):
            superTypeRefs = objectDecl.superTypes
            superTypeEntries = objectDecl.superTypeEntries
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

        // Unresolved supertypes must not be dropped silently: report the
        // written name on user sources only — bundled/residual stdlib
        // declarations may reference profile-conditional types (KUU-3250).
        let declSite = symbols.symbol(symbol)?.declSite
        let reportUnresolved: ((InternedString) -> Void)? = {
            guard let fileID = symbols.sourceFileID(for: symbol) ?? declSite?.start.file,
                  sourceManager?.origin(of: fileID) == .user
            else { return nil }
            let isBundledStdlibSource = { (fileID: FileID) -> Bool in
                guard let resourcePath = Bundle.module.resourcePath else { return false }
                let stdlibPath = URL(fileURLWithPath: resourcePath).appendingPathComponent("Stdlib").path
                return sourceManager?.path(of: fileID).hasPrefix(stdlibPath + "/") == true
            }(fileID)
            guard !isBundledStdlibSource else { return nil }
            return { name in
                diagnostics.error(
                    "KSWIFTK-SEMA-0025",
                    "Unresolved type '\(interner.resolve(name))'.",
                    range: declSite
                )
            }
        }()

        var superSymbols: [SymbolID] = []
        let declFileID = symbols.sourceFileID(for: symbol)
            ?? symbols.symbol(symbol)?.declSite?.start.file
        let isBundledStdlibDecl = declFileID
            .flatMap { sourceManager?.origin(of: $0)?.isBundledStdlib } == true
        for (index, superTypeRef) in superTypeRefs.enumerated() {
            if let resolved = resolveNominalSymbolAndTypeArgs(
                superTypeRef,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: mergedEnclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                reportUnresolved: reportUnresolved
            ) {
                if superSymbols.contains(resolved.symbol) {
                    diagnostics.error(
                        "KSWIFTK-SEMA-0440",
                        "A supertype appears twice.",
                        range: (index < superTypeEntries.count ? superTypeEntries[index].range : nil)
                            ?? symbols.symbol(symbol)?.declSite
                    )
                    continue
                }
                if index < superTypeEntries.count {
                    let entry = superTypeEntries[index]
                    if !entry.hasConstructorCallSyntax,
                       entry.delegateExpression == nil,
                       symbols.symbol(resolved.symbol)?.kind == .class,
                       !isBundledStdlibDecl
                    {
                        diagnostics.error(
                            "KSWIFTK-SEMA-0436",
                            "this type has a constructor, so it must be initialized here.",
                            range: entry.range ?? symbols.symbol(symbol)?.declSite
                        )
                    }
                }
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
                TypeCheckHelpers().checkDeprecation(
                    for: resolved.symbol,
                    symbols: symbols,
                    interner: interner,
                    range: symbols.symbol(symbol)?.declSite,
                    diagnostics: diagnostics
                )
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

                // JVM preparation uses a synthetic kotlin.Enum shell because
                // it does not load the common Enum.kt source. In that mode the
                // shell has no Comparable<T> edge, so expose the conformance on
                // each user enum type for member lookup and operator binding.
                let comparableFQName = [interner.intern("kotlin"), interner.intern("Comparable")]
                let sourceFileID = symbols.sourceFileID(for: symbol) ?? symbols.symbol(symbol)?.declSite?.start.file
                let isBundledStdlibSource = sourceFileID.map { fileID in
                    guard let sourceManager, let resourcePath = Bundle.module.resourcePath else { return false }
                    let stdlibPath = URL(fileURLWithPath: resourcePath).appendingPathComponent("Stdlib").path
                    return sourceManager.path(of: fileID).hasPrefix(stdlibPath + "/")
                } ?? false
                if sourceFileID.flatMap({ sourceManager?.origin(of: $0) }) == .user,
                   !isBundledStdlibSource,
                   let comparableSymbol = types.comparableInterfaceSymbol ?? symbols.lookup(fqName: comparableFQName),
                   !types.isNominalSubtypeSymbol(enumBaseSymbol, of: comparableSymbol) {
                    let comparableTypeArg: [TypeArg] = [.invariant(enumType)]
                    symbols.setSupertypeTypeArgs(comparableTypeArg, for: symbol, supertype: comparableSymbol)
                    types.setNominalSupertypeTypeArgs(comparableTypeArg, for: symbol, supertype: comparableSymbol)
                    superSymbols.append(comparableSymbol)
                }
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

        // Deduplicate while preserving declaration order: the order in which a
        // class lists its supertypes is semantically significant in Kotlin
        // (overridden-descriptor order, hence inherited default-argument and
        // member resolution; KUU-2950). Object-literal and local-class paths
        // already record declaration order.
        var seenSuperSymbols: Set<SymbolID> = []
        let uniqueSuperSymbols = superSymbols.filter { seenSuperSymbols.insert($0).inserted }
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
                sourceManager: sourceManager,
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
        interner: StringInterner,
        reportUnresolved: ((InternedString) -> Void)? = nil
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
            // Suspend function types use the corresponding
            // kotlin.coroutines.SuspendFunction{N} interface, whose invoke
            // signature retains the suspend modifier. Context-receiver
            // function types still have no nominal equivalent here.
            guard contextReceiverRefIDs.isEmpty else {
                return nil
            }
            var paramTypes: [TypeID] = []
            if let receiverRefID {
                guard let receiverType = resolveTypeRefForInheritance(
                    receiverRefID, currentPackage: currentPackage,
                    imports: imports,
                    enclosingTypeParameters: enclosingTypeParameters,
                    enclosingClassScopes: enclosingClassScopes,
                    ast: ast,
                    symbols: symbols, types: types, interner: interner
                ) else { return nil }
                paramTypes.append(receiverType)
            }
            for paramRef in paramRefIDs {
                guard let paramType = resolveTypeRefForInheritance(
                    paramRef, currentPackage: currentPackage,
                    imports: imports,
                    enclosingTypeParameters: enclosingTypeParameters,
                    enclosingClassScopes: enclosingClassScopes,
                    ast: ast,
                    symbols: symbols, types: types, interner: interner
                ) else { return nil }
                paramTypes.append(paramType)
            }
            guard let returnType = resolveTypeRefForInheritance(
                returnRefID, currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                ast: ast,
                symbols: symbols, types: types, interner: interner
            ) else { return nil }
            let functionSymbol: SymbolID?
            if isSuspend {
                functionSymbol = types.suspendFunctionNInterfaceSymbols[paramTypes.count]
            } else {
                let functionFQName = [
                    interner.intern("kotlin"), interner.intern("Function"),
                    interner.intern("Function\(paramTypes.count)"),
                ]
                functionSymbol = symbols.lookupAll(fqName: functionFQName)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { isNominalTypeSymbol($0.kind) })?.id
            }
            guard let functionSymbol
            else {
                return nil
            }
            // KUU-1084: FunctionN declares its type params in Kotlin order
            // [P1..PN, R], so the supertype args carry params then return type.
            let functionArgs: [TypeArg] = paramTypes.map { .in($0) } + [.out(returnType)]
            return ResolvedSupertype(symbol: functionSymbol, typeArgs: functionArgs)
        case .intersection:
            return nil
        case let .annotated(baseRef, _):
            // Type-use annotations (`class C : @Anno Base()`) do not change
            // the inherited nominal; resolve the underlying ref instead of
            // silently dropping the edge (KUU-3250).
            return resolveNominalSymbolAndTypeArgs(
                baseRef,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                reportUnresolved: reportUnresolved
            )
        }
        guard !path.isEmpty else {
            return nil
        }

        let resolvedSupertype: (SymbolID) -> ResolvedSupertype = { symbol in
            let resolvedArgs = self.resolveTypeArgRefsForInheritance(
                argRefs,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                reportUnresolved: reportUnresolved
            )
            let nominal = self.resolveTypeAliasSupertype(symbol, symbols: symbols, types: types) ?? symbol
            let runtimeNominal = self.resolveActualNominalSupertype(nominal, symbols: symbols)
            return ResolvedSupertype(
                symbol: runtimeNominal,
                typeArgs: self.expandTypeAliasSupertypeArgs(symbol, writtenArgs: resolvedArgs, symbols: symbols, types: types)
            )
        }

        // Enclosing class scopes also contribute member classifiers
        // inherited through their supertypes: `I` inside `Sub.M` names
        // `Outer.I`, which no `scope + path` child lookup can express
        // (KUU-3250). Innermost scope first, matching the candidate tier
        // order below.
        let scopeCandidatePaths = Set(enclosingClassScopes.map { $0 + path })
        for scope in enclosingClassScopes.reversed() {
            if let symbol = symbols.lookupAll(fqName: scope + path)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id {
                return resolvedSupertype(symbol)
            }
            if let scopeSymbol = symbols.lookupAll(fqName: scope)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id,
               let member = inheritedMemberClassifierSymbol(
                   path: path,
                   owner: scopeSymbol,
                   symbols: symbols
               ) {
                return resolvedSupertype(member)
            }
        }

        let candidatePaths = inheritanceCandidatePaths(
            for: path,
            currentPackage: currentPackage,
            imports: imports,
            enclosingClassScopes: enclosingClassScopes,
            symbols: symbols
        )

        for candidatePath in candidatePaths where !scopeCandidatePaths.contains(candidatePath) {
            if let symbol = symbols.lookupAll(fqName: candidatePath)
                .compactMap({ symbols.symbol($0) })
                .first(where: { isNominalTypeSymbol($0.kind) })?.id
            {
                return resolvedSupertype(symbol)
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
                    return resolvedSupertype(symbol)
                }
            }
        }
        // A lone type parameter as the supertype head (`class C<T> : T()`)
        // resolves to the parameter — kotlinc rejects it as "supertype is
        // not a class or interface" rather than an unresolved name, so the
        // unresolved-name report stays silent for that shape (KUU-3250).
        if !(path.count == 1 && enclosingTypeParameters[path[0]] != nil) {
            reportUnresolved?(unresolvedSupertypeSegment(
                path: path,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                symbols: symbols
            ))
        }
        return nil
    }

    /// kotlinc names the first path segment that fails to resolve
    /// (`unresolved reference 'NotExist'` for `NotExist.Nested`, `'Missing'`
    /// for `Outer.Missing`, and `'NotExist'` for `kotlin.NotExist` where the
    /// `kotlin` package itself resolves), so the reported segment walks the
    /// prefixes in order (KUU-3250).
    private func unresolvedSupertypeSegment(
        path: [InternedString],
        currentPackage: [InternedString],
        imports: [ImportDecl],
        enclosingTypeParameters: [InternedString: SymbolID],
        enclosingClassScopes: [[InternedString]],
        symbols: SymbolTable
    ) -> InternedString {
        guard path.count > 1 else { return path[0] }
        let segmentResolves: ([InternedString]) -> Bool = { prefixPath in
            if prefixPath.count == 1, enclosingTypeParameters[prefixPath[0]] != nil {
                return true
            }
            let symbolResolves = self.inheritanceCandidatePaths(
                for: prefixPath,
                currentPackage: currentPackage,
                imports: imports,
                enclosingClassScopes: enclosingClassScopes,
                symbols: symbols
            ).contains { candidatePath in
                symbols.lookupAll(fqName: candidatePath)
                    .compactMap({ symbols.symbol($0) })
                    .contains(where: { $0.kind == .package || self.isNominalTypeSymbol($0.kind) })
            }
            if symbolResolves { return true }
            return enclosingClassScopes.contains { scope in
                guard let scopeSymbol = symbols.lookupAll(fqName: scope)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { self.isNominalTypeSymbol($0.kind) })?.id
                else { return false }
                return self.inheritedMemberClassifierSymbol(
                    path: prefixPath, owner: scopeSymbol, symbols: symbols
                ) != nil
            }
        }
        for index in path.indices.dropLast() where !segmentResolves(Array(path[...index])) {
            return path[index]
        }
        return path[path.count - 1]
    }

    /// Member classifier lookup through `owner`'s supertype chain: inside
    /// `Sub.M` the simple name `I` resolves to `Outer.I` because member
    /// types are inherited like other members (KUU-3250). The owner's own
    /// children are already covered by the `scope + path` fqName lookup,
    /// so only supertypes are walked, closest first.
    private func inheritedMemberClassifierSymbol(
        path: [InternedString],
        owner: SymbolID,
        symbols: SymbolTable
    ) -> SymbolID? {
        var seen: Set<SymbolID> = [owner]
        var queue = symbols.directSupertypes(for: owner)
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            for child in symbols.children(of: current) {
                guard let info = symbols.symbol(child), info.name == path[0],
                      isNominalTypeSymbol(info.kind)
                else { continue }
                var resolved = child
                var resolvedOK = true
                for component in path.dropFirst() {
                    guard let next = symbols.children(of: resolved).first(where: {
                        guard let nextInfo = symbols.symbol($0) else { return false }
                        return nextInfo.name == component && isNominalTypeSymbol(nextInfo.kind)
                    }) else {
                        resolvedOK = false
                        break
                    }
                    resolved = next
                }
                if resolvedOK { return resolved }
            }
            for superSymbol in symbols.directSupertypes(for: current)
                where seen.insert(superSymbol).inserted {
                queue.append(superSymbol)
            }
        }
        return nil
    }

    /// A fixed type argument of an alias target (`typealias Base = Box<String>`) is part
    /// of the supertype even though the header spells no arguments; expand the alias so
    /// the inheritance edge keeps `Box<String>` instead of an argument-less `Box`.
    private func expandTypeAliasSupertypeArgs(
        _ symbol: SymbolID,
        writtenArgs: [TypeArg],
        symbols: SymbolTable,
        types: TypeSystem
    ) -> [TypeArg] {
        guard symbols.symbol(symbol)?.kind == .typeAlias,
              let underlying = symbols.typeAliasUnderlyingType(for: symbol)
        else {
            return writtenArgs
        }
        let expanded = substituteTypeAliasParams(
            underlying,
            aliasSymbol: symbol,
            typeArgs: writtenArgs,
            symbols: symbols,
            types: types
        )
        guard case let .classType(classType) = types.kind(of: expanded) else {
            return writtenArgs
        }
        if symbols.symbol(classType.classSymbol)?.kind == .typeAlias, classType.classSymbol != symbol {
            return expandTypeAliasSupertypeArgs(
                classType.classSymbol, writtenArgs: classType.args, symbols: symbols, types: types
            )
        }
        return classType.args
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

    /// Inheritance needs the platform declaration's body-bearing layout when a
    /// source expect class has a matching actual declaration in the same module.
    /// Keep the expect symbol when no actual nominal is available, as with a
    /// common-only declaration that will be linked by a later compilation.
    private func resolveActualNominalSupertype(_ symbol: SymbolID, symbols: SymbolTable) -> SymbolID {
        guard let expect = symbols.symbol(symbol),
              expect.flags.contains(.expectDeclaration),
              isNominalTypeSymbol(expect.kind)
        else {
            return symbol
        }

        return symbols.lookupAll(fqName: expect.fqName)
            .compactMap { symbols.symbol($0) }
            .filter { $0.flags.contains(.actualDeclaration) && $0.kind == expect.kind }
            .sorted(by: { $0.id.rawValue < $1.id.rawValue })
            .first?.id ?? symbol
    }

    /// Resolve type arguments through the enclosing classifier scopes as well
    /// as package/import scopes, so nested self types such as `Hand` in
    /// `Comparable<Hand>` keep their nominal identity.
    private func resolveTypeArgRefsForInheritance(
        _ argRefs: [TypeArgRef],
        currentPackage: [InternedString],
        imports: [ImportDecl],
        enclosingTypeParameters: [InternedString: SymbolID],
        enclosingClassScopes: [[InternedString]],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        reportUnresolved: ((InternedString) -> Void)? = nil
    ) -> [TypeArg] {
        // Use all-or-nothing semantics: if any type arg fails to resolve,
        // return an empty array to preserve positional integrity.
        var result: [TypeArg] = []
        result.reserveCapacity(argRefs.count)
        for argRef in argRefs {
            switch argRef {
            case let .invariant(innerRef):
                guard let resolved = resolveTypeRefForInheritance(
                    innerRef,
                    currentPackage: currentPackage,
                    imports: imports,
                    enclosingTypeParameters: enclosingTypeParameters,
                    enclosingClassScopes: enclosingClassScopes,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    reportUnresolved: reportUnresolved
                ) else {
                    return []
                }
                result.append(.invariant(resolved))
            case let .out(innerRef):
                guard let resolved = resolveTypeRefForInheritance(
                    innerRef,
                    currentPackage: currentPackage,
                    imports: imports,
                    enclosingTypeParameters: enclosingTypeParameters,
                    enclosingClassScopes: enclosingClassScopes,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    reportUnresolved: reportUnresolved
                ) else {
                    return []
                }
                result.append(.out(resolved))
            case let .in(innerRef):
                guard let resolved = resolveTypeRefForInheritance(
                    innerRef,
                    currentPackage: currentPackage,
                    imports: imports,
                    enclosingTypeParameters: enclosingTypeParameters,
                    enclosingClassScopes: enclosingClassScopes,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    reportUnresolved: reportUnresolved
                ) else {
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
        enclosingClassScopes: [[InternedString]],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        reportUnresolved: ((InternedString) -> Void)? = nil
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
               let builtinType = BuiltinTypeNames(interner: interner).resolveBuiltinType(
                   path[1], nullability: nullability, types: types
               )
            {
                return builtinType
            }
            let resolvedType: (SymbolID) -> TypeID = { nominalSymbol in
                let resolvedArgs = self.resolveTypeArgRefsForInheritance(
                    argRefs,
                    currentPackage: currentPackage,
                    imports: imports,
                    enclosingTypeParameters: enclosingTypeParameters,
                    enclosingClassScopes: enclosingClassScopes,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    reportUnresolved: reportUnresolved
                )
                return types.make(.classType(ClassType(classSymbol: nominalSymbol, args: resolvedArgs, nullability: nullability)))
            }
            // Enclosing class scopes also contribute member classifiers
            // inherited through their supertypes (e.g. `I` -> `Outer.I`
            // inside `Sub.M`); see resolveNominalSymbolAndTypeArgs (KUU-3250).
            let scopeCandidatePaths = Set(enclosingClassScopes.map { $0 + path })
            for scope in enclosingClassScopes.reversed() {
                if let nominalSymbol = symbols.lookupAll(fqName: scope + path)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { isNominalTypeSymbol($0.kind) })
                {
                    return resolvedType(nominalSymbol.id)
                }
                if let scopeSymbol = symbols.lookupAll(fqName: scope)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { isNominalTypeSymbol($0.kind) })?.id,
                   let member = inheritedMemberClassifierSymbol(
                       path: path,
                       owner: scopeSymbol,
                       symbols: symbols
                   ) {
                    return resolvedType(member)
                }
            }
            let candidatePaths = inheritanceCandidatePaths(
                for: path,
                currentPackage: currentPackage,
                imports: imports,
                enclosingClassScopes: enclosingClassScopes,
                symbols: symbols
            )
            for candidatePath in candidatePaths where !scopeCandidatePaths.contains(candidatePath) {
                if let nominalSymbol = symbols.lookupAll(fqName: candidatePath)
                    .compactMap({ symbols.symbol($0) })
                    .first(where: { isNominalTypeSymbol($0.kind) })
                {
                    return resolvedType(nominalSymbol.id)
                }
            }
            // Resolve built-in/primitive type names first so they take precedence
            // over the default-import packages (e.g. `Int` is the primitive Int,
            // not any class named `Int` that might exist under `kotlin`).
            if path.count == 1 {
                if let builtinType = BuiltinTypeNames(interner: interner).resolveBuiltinType(
                    path[0],
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
                        return resolvedType(nominalSymbol.id)
                    }
                }
            }
            reportUnresolved?(unresolvedSupertypeSegment(
                path: path,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                symbols: symbols
            ))
            return nil
        case let .functionType(contextReceiverRefIDs, receiverRefID, paramRefIDs, returnRefID, isSuspend, nullable):
            return resolveFunctionTypeForInheritance(
                contextReceiverRefIDs: contextReceiverRefIDs,
                receiverRefID: receiverRefID, paramRefIDs: paramRefIDs, returnRefID: returnRefID, isSuspend: isSuspend, nullable: nullable,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            )
        case let .intersection(partRefs):
            let partTypes = partRefs.compactMap {
                resolveTypeRefForInheritance(
                    $0,
                    currentPackage: currentPackage,
                    imports: imports,
                    enclosingTypeParameters: enclosingTypeParameters,
                    enclosingClassScopes: enclosingClassScopes,
                    ast: ast,
                    symbols: symbols,
                    types: types,
                    interner: interner,
                    reportUnresolved: reportUnresolved
                )
            }
            guard partTypes.count == partRefs.count else { return nil }
            return types.make(.intersection(partTypes))
        case let .annotated(base, annotations):
            guard let baseType = resolveTypeRefForInheritance(
                base,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner,
                reportUnresolved: reportUnresolved
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
        enclosingClassScopes: [[InternedString]],
        ast: ASTModule,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID? {
        let nullability: Nullability = nullable ? .nullable : .nonNull
        var contextReceiverTypes: [TypeID] = []
        for contextReceiverRef in contextReceiverRefIDs {
            guard let contextReceiverType = resolveTypeRefForInheritance(
                contextReceiverRef,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) else { return nil }
            contextReceiverTypes.append(contextReceiverType)
        }
        var receiverType: TypeID?
        if let receiverRefID {
            guard let resolved = resolveTypeRefForInheritance(
                receiverRefID,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) else { return nil }
            receiverType = resolved
        }
        var paramTypes: [TypeID] = []
        for paramRef in paramRefIDs {
            guard let paramType = resolveTypeRefForInheritance(
                paramRef,
                currentPackage: currentPackage,
                imports: imports,
                enclosingTypeParameters: enclosingTypeParameters,
                enclosingClassScopes: enclosingClassScopes,
                ast: ast,
                symbols: symbols,
                types: types,
                interner: interner
            ) else { return nil }
            paramTypes.append(paramType)
        }
        guard let returnType = resolveTypeRefForInheritance(
            returnRefID,
            currentPackage: currentPackage,
            imports: imports,
            enclosingTypeParameters: enclosingTypeParameters,
            enclosingClassScopes: enclosingClassScopes,
            ast: ast,
            symbols: symbols,
            types: types,
            interner: interner
        ) else { return nil }
        return types.make(.functionType(FunctionType(
            contextReceivers: contextReceiverTypes,
            receiver: receiverType, params: paramTypes, returnType: returnType, isSuspend: isSuspend, nullability: nullability
        )))
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
                validateFunInterfaceContract(
                    declID: declID,
                    ast: ast,
                    symbols: symbols,
                    bindings: bindings,
                    diagnostics: diagnostics
                )
                validateAbstractOverridesForDecl(
                    declID: declID,
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

    /// A `fun interface` must end up with exactly one effective abstract function
    /// after own and inherited members have been collected.
    private func validateFunInterfaceContract(
        declID: DeclID,
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine
    ) {
        guard let decl = ast.arena.decl(declID),
              case let .interfaceDecl(interfaceDecl) = decl,
              interfaceDecl.isFunInterface,
              let symbol = bindings.declSymbols[declID],
              TypeCheckHelpers().effectiveSamAbstractMethod(for: symbol, symbols: symbols) == nil
        else {
            return
        }
        diagnostics.error(
            "KSWIFTK-SEMA-0406",
            "functional interface must have exactly one abstract function.",
            range: interfaceDecl.range
        )
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
        // Member-extension overloads may differ only by their extension receiver.
        let extensionReceiverType: TypeID?
        let parameterTypes: [TypeID]
        let methodTypeParameters: [SymbolID]
        let methodUpperBounds: [[TypeID]]
        let isSuspend: Bool

        func matches(_ other: DelegationDispatchKey, types: TypeSystem) -> Bool {
            guard name == other.name, isSuspend == other.isSuspend,
                  parameterTypes.count == other.parameterTypes.count,
                  methodTypeParameters.count == other.methodTypeParameters.count
            else { return false }
            func aligned(_ type: TypeID) -> TypeID {
                alphaAlignedMethodType(type, sourceParameters: methodTypeParameters,
                                       targetParameters: other.methodTypeParameters, types: types)
            }
            let extensionReceiversMatch: Bool
            if let extensionReceiverType, let otherReceiverType = other.extensionReceiverType {
                extensionReceiversMatch = methodIdentityParameterTypesMatch(
                    candidateParameterTypes: [otherReceiverType],
                    interfaceParameterTypes: [aligned(extensionReceiverType)],
                    types: types
                )
            } else {
                extensionReceiversMatch = extensionReceiverType == nil && other.extensionReceiverType == nil
            }
            guard extensionReceiversMatch else { return false }
            return methodIdentityParameterTypesMatch(candidateParameterTypes: other.parameterTypes,
                                                     interfaceParameterTypes: parameterTypes.map(aligned), types: types)
                && methodUpperBoundSetsMatch(methodUpperBounds.map { $0.map(aligned) }, other.methodUpperBounds, types: types)
        }
    }

    private func delegationDispatchKey(
        for method: SemanticSymbol,
        signature: FunctionSignature,
        extensionReceiverType: TypeID?,
        parameterTypes: [TypeID]? = nil,
        methodUpperBounds: [[TypeID]]
    ) -> DelegationDispatchKey {
        return DelegationDispatchKey(
            name: method.name,
            extensionReceiverType: extensionReceiverType,
            parameterTypes: parameterTypes ?? signature.parameterTypes,
            methodTypeParameters: Array(signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)),
            methodUpperBounds: methodUpperBounds,
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
            classMethodKeys.append(delegationDispatchKey(for: method, signature: signature,
                                                         extensionReceiverType: symbols.memberExtensionOwnerSymbol(for: funSymbol) == nil
                                                             ? nil : signature.receiverType,
                                                         methodUpperBounds: methodTypeParameterBounds(signature, types: types)))
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
                            extensionReceiverType: symbols.memberExtensionOwnerSymbol(for: memberSym.id) == nil
                                ? nil
                                : ifaceSig.receiverType.map {
                                    substituteDelegationType(
                                        $0, substitution: substitution, typeVarBySymbol: typeVarBySymbol, types: types
                                    )
                                },
                            parameterTypes: ifaceSig.parameterTypes.map {
                                substituteDelegationType(
                                    $0, substitution: substitution, typeVarBySymbol: typeVarBySymbol, types: types
                                )
                            },
                            methodUpperBounds: methodTypeParameterBounds(ifaceSig, types: types).map { bounds in
                                bounds.map {
                                    substituteDelegationType(
                                        $0, substitution: substitution, typeVarBySymbol: typeVarBySymbol, types: types
                                    )
                                }
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
        let isMemberExtension = symbols.memberExtensionOwnerSymbol(for: methodSym.id) != nil
        var forwardingFlags: SymbolFlags = [.synthetic, .overrideMember]
        if isMemberExtension {
            forwardingFlags.insert(.memberExtension)
        }
        let forwardingSymbol = symbols.define(
            kind: .function,
            name: methodName,
            fqName: forwardingFQName,
            declSite: range,
            visibility: methodSym.visibility,
            flags: forwardingFlags
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

        // Class parameters come from the delegating receiver; method parameters
        // need fresh binders owned by this forwarder, including in their bounds.
        let interfaceMethodParameters = Array(ifaceSig.typeParameterSymbols.dropFirst(ifaceSig.classTypeParameterCount))
        let localNamespace = forwardingFQName + [interner.intern("$\(forwardingSymbol.rawValue)")]
        let methodParameters = interfaceMethodParameters.map { original in
            let name = symbols.symbol(original)?.name ?? interner.intern("T\(original.rawValue)")
            let parameter = symbols.define(
                kind: .typeParameter,
                name: name,
                fqName: localNamespace + [name],
                declSite: range,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(forwardingSymbol, for: parameter)
            symbols.setAnnotations(symbols.annotations(for: original), for: parameter)
            return parameter
        }
        var forwardingSubstitution = substitution
        var forwardingTypeVars = typeVarBySymbol
        for (original, parameter) in zip(interfaceMethodParameters, methodParameters) {
            let typeVar = TypeVarID(rawValue: Int32(forwardingTypeVars.count))
            forwardingTypeVars[original] = typeVar
            forwardingSubstitution[typeVar] = types.make(.typeParam(TypeParamType(
                symbol: parameter, nullability: .nonNull
            )))
        }
        func substitute(_ type: TypeID) -> TypeID {
            substituteDelegationType(
                type, substitution: forwardingSubstitution, typeVarBySymbol: forwardingTypeVars, types: types
            )
        }
        let methodBounds = interfaceMethodParameters.enumerated().map { index, original in
            let signatureIndex = ifaceSig.classTypeParameterCount + index
            let bounds = signatureIndex < ifaceSig.typeParameterUpperBoundsList.count
                ? ifaceSig.typeParameterUpperBoundsList[signatureIndex]
                : symbols.typeParameterUpperBounds(for: original)
            let substitutedBounds = bounds.map(substitute)
            symbols.setTypeParameterUpperBounds(substitutedBounds, for: methodParameters[index])
            return substitutedBounds
        }

        let parameterTypes = ifaceSig.parameterTypes.map {
            substitute($0)
        }
        let receiverType = if isMemberExtension, let interfaceReceiverType = ifaceSig.receiverType {
            substitute(interfaceReceiverType)
        } else {
            classType
        }
        let returnType = substitute(ifaceSig.returnType)

        var paramSymbols: [SymbolID] = []
        for (index, paramType) in parameterTypes.enumerated() {
            let paramName = index < ifaceSig.valueParameterSymbols.count
                ? symbols.symbol(ifaceSig.valueParameterSymbols[index])?.name ?? interner.intern("p\(index)")
                : interner.intern("p\(index)")
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
            receiverType: receiverType,
            parameterTypes: parameterTypes,
            returnType: returnType,
            isSuspend: ifaceSig.isSuspend,
            valueParameterSymbols: paramSymbols,
            valueParameterHasDefaultValues: Array(repeating: false, count: paramSymbols.count),
            valueParameterIsVararg: Array(repeating: false, count: paramSymbols.count),
            typeParameterSymbols: classTypeParameterSymbols + methodParameters,
            typeParameterUpperBoundsList: classTypeParameterSymbols.map {
                symbols.typeParameterUpperBounds(for: $0)
            } + methodBounds,
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

        guard symbolInfo.kind == .class || symbolInfo.kind == .object,
              !symbolInfo.flags.contains(.abstractType),
              !symbolInfo.flags.contains(.expectDeclaration)
        else {
            return
        }

        // An expect declaration describes the common API but does not provide
        // the platform implementation. Check inherited abstract obligations
        // on its actual declaration, where the implementation is available.
        // Every inherited abstract member this class still owes an
        // implementation for. CLASS-008: members from an interface satisfied
        // through `by` delegation are excluded.
        var overriddenNames = collectOverriddenMemberNames(
            for: symbol,
            decl: decl,
            ast: ast,
            symbols: symbols
        )
        // A data object synthesizes `toString()` unless a final inherited implementation wins.
        if symbolInfo.kind == .object,
           symbolInfo.flags.contains(.dataType),
           let toStringName = symbols.children(ofFQName: symbolInfo.fqName).compactMap({ memberID -> InternedString? in
               guard let member = symbols.symbol(memberID),
                     member.kind == .function,
                     member.name == interner.intern("toString"),
                     member.flags.contains(.synthetic)
               else {
                   return nil
               }
               return member.name
           }).first {
            overriddenNames.insert(toStringName)
        }
        let missingMembers = unimplementedAbstractMembers(
            for: symbol,
            overriddenNames: overriddenNames,
            delegatedInterfaces: symbols.delegatedInterfaces(forClass: symbol),
            symbols: symbols,
            types: types,
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

    // P5-78: Validate the package and module boundary of sealed hierarchies.
    func validateSealedHierarchy(
        ast: ASTModule,
        symbols: SymbolTable,
        bindings: BindingTable,
        diagnostics: DiagnosticEngine,
        interner: StringInterner,
        sourceManager: SourceManager
    ) {
        func package(of symbol: SemanticSymbol) -> [InternedString] {
            var root = symbol
            while let parent = symbols.parentSymbol(for: root.id),
                  let owner = symbols.symbol(parent), owner.kind != .package {
                root = owner
            }
            return Array(root.fqName.dropLast())
        }
        for file in ast.sortedFiles {
            var declarations = file.topLevelDecls
            var index = 0
            while index < declarations.count {
                let declID = declarations[index]
                index += 1
                guard let decl = ast.arena.decl(declID) else { continue }
                switch decl {
                case let .classDecl(value):
                    declarations += value.nestedClasses + value.nestedObjects
                    if let companion = value.companionObject { declarations.append(companion) }
                case let .interfaceDecl(value):
                    declarations += value.nestedClasses + value.nestedObjects
                    if let companion = value.companionObject { declarations.append(companion) }
                case let .objectDecl(value):
                    declarations += value.nestedClasses + value.nestedObjects
                default:
                    break
                }
                guard let symbol = bindings.declSymbols[declID],
                      let symbolInfo = symbols.symbol(symbol)
                else {
                    continue
                }
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
                    let subclassIsBundled = symbolInfo.declSite.map {
                        sourceManager.origin(of: $0.start.file)?.isBundledStdlib == true
                    } ?? false
                    let superclassIsBundled = supertypeSymbol.declSite.map {
                        sourceManager.origin(of: $0.start.file)?.isBundledStdlib == true
                    } ?? false
                    let boundary: String?
                    if supertypeSymbol.flags.contains(.importedLibrary) || (superclassIsBundled && !subclassIsBundled) {
                        boundary = "module"
                    } else if package(of: symbolInfo) != package(of: supertypeSymbol) {
                        boundary = "package"
                    } else {
                        boundary = nil
                    }
                    if let boundary {
                        let subtypeName = symbolInfo.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        let supertypeName = supertypeSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                        diagnostics.error(
                            "KSWIFTK-SEMA-0070",
                            "'\(subtypeName)' cannot inherit from sealed type '\(supertypeName)': sealed subclasses must be in the same \(boundary).",
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
