/// Split out from `CollectionLiteralLoweringPass+CallRewrite.swift` to
/// keep the giant `rewriteCalls` body file scoped only to the rewrite
/// dispatcher.
extension CollectionLiteralLoweringSupport {
    /// Resolved constructor ownership or result types take precedence over
    /// legacy bare collection names, including for source-defined user classes.
    func isStdlibCollectionConstructor(
        symbol: SymbolID?,
        className: InternedString,
        result: KIRExprID?,
        arena: KIRArena,
        sema: SemaModule?,
        interner: StringInterner
    ) -> Bool {
        guard let sema else { return true }
        let expectedFQName = [interner.intern("kotlin"), interner.intern("collections"), className]
        func matchesCollectionClass(_ info: SemanticSymbol) -> Bool {
            info.fqName == expectedFQName || (info.fqName.isEmpty && info.name == className)
        }
        func matchesCollectionSymbol(_ symbolID: SymbolID, visited: Set<SymbolID>) -> Bool {
            guard !visited.contains(symbolID),
                  let info = sema.symbols.symbol(symbolID) else {
                return false
            }
            if matchesCollectionClass(info) { return true }
            guard info.kind == .typeAlias,
                  let underlying = sema.symbols.typeAliasUnderlyingType(for: symbolID),
                  case let .classType(target) = sema.types.kind(of: underlying)
            else {
                return false
            }
            var nextVisited = visited
            nextVisited.insert(symbolID)
            return matchesCollectionSymbol(target.classSymbol, visited: nextVisited)
        }
        if let symbol, let resolved = sema.symbols.symbol(symbol) {
            if resolved.kind == .constructor,
               let owner = sema.symbols.parentSymbol(for: symbol) {
                return matchesCollectionSymbol(owner, visited: [])
            }
            return matchesCollectionClass(resolved)
                || resolved.fqName == expectedFQName + [interner.intern("<init>")]
        }
        if let result,
           let resultType = arena.exprType(result),
           let resultClass = resolveClassType(resultType, sema: sema),
           sema.symbols.symbol(resultClass.classSymbol) != nil {
            return matchesCollectionSymbol(resultClass.classSymbol, visited: [])
        }
        // Keep the legacy fallback only when neither symbol nor type is available.
        return true
    }

    func isStdlibCollectionConstructor(
        symbol: SymbolID?,
        className: InternedString,
        result: KIRExprID?,
        module: KIRModule,
        ctx: KIRContext
    ) -> Bool {
        isStdlibCollectionConstructor(
            symbol: symbol, className: className, result: result,
            arena: module.arena, sema: ctx.sema, interner: ctx.interner
        )
    }

    /// Source-backed constructors may carry a mangled callee name in KIR.
    func stdlibMutableMapConstructorName(
        symbol: SymbolID?,
        callee: InternedString,
        result: KIRExprID?,
        lookup: CollectionLiteralLookupTables,
        arena: KIRArena,
        sema: SemaModule?,
        interner: StringInterner
    ) -> InternedString? {
        if lookup.mutableMapConstructorNames.contains(callee) {
            return isStdlibCollectionConstructor(
                symbol: symbol, className: callee, result: result,
                arena: arena, sema: sema, interner: interner
            ) ? callee : nil
        }
        guard let sema, let symbol,
              sema.symbols.symbol(symbol)?.kind == .constructor else {
            return nil
        }
        for className in [lookup.hashMapName, lookup.linkedHashMapName]
        where isStdlibCollectionConstructor(
            symbol: symbol, className: className, result: result,
            arena: arena, sema: sema, interner: interner
        ) {
            return className
        }
        return nil
    }

}

extension CollectionLiteralConstructionLoweringPass {

    func isHashSetConstructor(
        callee: InternedString,
        symbol: SymbolID?,
        arguments: [KIRExprID],
        result: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        // Delegated `super(...)` / `this(...)` calls initialize an existing
        // receiver. Their source constructor bodies must run; a factory would
        // allocate a different set and count `this` as a value argument.
        if callee == ctx.interner.intern("<init>"),
           let symbol,
           let signature = ctx.sema?.symbols.functionSignature(for: symbol),
           arguments.count == signature.parameterTypes.count + 1
        {
            return false
        }
        if callee == lookup.hashSetName {
            return isStdlibCollectionConstructor(
                symbol: symbol, className: lookup.hashSetName,
                result: result, module: module, ctx: ctx
            )
        }
        guard let sema = ctx.sema else { return false }
        let expectedFQName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("collections"),
            lookup.hashSetName,
        ]
        if let symbol,
           sema.symbols.symbol(symbol)?.kind == .constructor,
           let owner = sema.symbols.parentSymbol(for: symbol),
           let ownerInfo = sema.symbols.symbol(owner),
           ownerInfo.fqName == expectedFQName
        {
            return true
        }

        // Source-backed implicit constructors can lose their constructor
        // symbol while the call is converted to KIR. Recover the owner from
        // the resolved result type before falling back to the generic `<init>`
        // callee.
        guard callee == ctx.interner.intern("<init>"),
              let result,
              let resultType = module.arena.exprType(result),
              let resultClass = resolveClassType(resultType, sema: sema),
              let resultInfo = sema.symbols.symbol(resultClass.classSymbol)
        else {
            return false
        }
        return resultInfo.fqName == expectedFQName
    }

    /// KUU-1361: `java.util.TreeSet`/`java.util.TreeMap` constructors are
    /// recognized strictly by owner FQName — unlike `isHashSetConstructor`
    /// there is no bare-name match, so user classes that happen to share the
    /// `TreeSet`/`TreeMap` simple name keep their own semantics.
    private func isJavaUtilSortedConstructor(
        callee: InternedString,
        symbol: SymbolID?,
        result: KIRExprID?,
        module: KIRModule,
        className: InternedString,
        ctx: KIRContext
    ) -> Bool {
        guard let sema = ctx.sema else { return false }
        let expectedFQName = [
            ctx.interner.intern("java"),
            ctx.interner.intern("util"),
            className,
        ]
        if let symbol,
           sema.symbols.symbol(symbol)?.kind == .constructor,
           let owner = sema.symbols.parentSymbol(for: symbol),
           let ownerInfo = sema.symbols.symbol(owner),
           ownerInfo.fqName == expectedFQName
        {
            return true
        }
        guard callee == ctx.interner.intern("<init>"),
              let result,
              let resultType = module.arena.exprType(result),
              let resultClass = resolveClassType(resultType, sema: sema),
              let resultInfo = sema.symbols.symbol(resultClass.classSymbol)
        else {
            return false
        }
        return resultInfo.fqName == expectedFQName
    }

    func isTreeSetConstructor(
        callee: InternedString,
        symbol: SymbolID?,
        result: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        isJavaUtilSortedConstructor(
            callee: callee, symbol: symbol, result: result, module: module,
            className: lookup.treeSetName, ctx: ctx
        )
    }

    func isTreeMapConstructor(
        callee: InternedString,
        symbol: SymbolID?,
        result: KIRExprID?,
        module: KIRModule,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        isJavaUtilSortedConstructor(
            callee: callee, symbol: symbol, result: result, module: module,
            className: lookup.treeMapName, ctx: ctx
        )
    }

    enum TreeSetConstructorKind {
        case emptyOrComparator
        case collection
        case sortedSet
    }

    enum TreeMapConstructorKind {
        case emptyOrComparator
        case map
        case sortedMap
    }

    /// Discriminates the single-argument sorted constructors by the resolved
    /// constructor's declared parameter FQName first, then by the argument's
    /// static type FQName — mirroring the JVM overload split between
    /// `Comparator`, `Collection`/`SortedSet`, and `Map`/`SortedMap`.
    private func sortedConstructorArgumentKind(
        symbol: SymbolID?,
        argument: KIRExprID,
        sortedSimpleNames: Set<String>,
        collectionSimpleNames: Set<String>,
        module: KIRModule,
        ctx: KIRContext
    ) -> String? {
        guard let sema = ctx.sema else { return nil }
        var candidates: [SemanticSymbol?] = []
        if let symbol,
           let paramType = sema.symbols.functionSignature(for: symbol)?.parameterTypes.first
        {
            candidates.append(resolveClassTypeSymbol(paramType, sema: sema)?.symbol)
        }
        candidates.append(nil)
        if let argumentType = module.arena.exprType(argument) {
            candidates[1] = resolveClassTypeSymbol(argumentType, sema: sema)?.symbol
        }
        for candidate in candidates {
            guard let candidate else { continue }
            let simpleName = ctx.interner.resolve(candidate.fqName.last ?? candidate.name)
            if sortedSimpleNames.contains(simpleName) {
                return "sorted"
            }
            if simpleName == "Comparator" {
                return "comparator"
            }
            if collectionSimpleNames.contains(simpleName) {
                return "collection"
            }
        }
        return nil
    }

    func treeSetConstructorKind(
        symbol: SymbolID?,
        arguments: [KIRExprID],
        module: KIRModule,
        state: CollectionRewriteState,
        ctx: KIRContext
    ) -> TreeSetConstructorKind {
        // Constructor calls carry the freshly allocated `this` as
        // `arguments[0]` (kk_object_new); the declared parameters follow.
        guard arguments.count >= 2, let argument = arguments.last else {
            return .emptyOrComparator
        }
        let kind = sortedConstructorArgumentKind(
            symbol: symbol,
            argument: argument,
            sortedSimpleNames: ["SortedSet", "NavigableSet", "TreeSet"],
            collectionSimpleNames: [
                "Collection", "MutableCollection", "Iterable", "MutableIterable",
                "Set", "MutableSet", "HashSet", "LinkedHashSet",
                "AbstractSet", "AbstractMutableSet",
                "List", "MutableList", "ArrayList", "AbstractList", "AbstractMutableList",
                "Sequence",
            ],
            module: module,
            ctx: ctx
        )
        switch kind {
        case "sorted":
            return .sortedSet
        case "collection":
            return .collection
        case "comparator":
            return .emptyOrComparator
        default:
            // Tracked collection expressions with no resolvable class type
            // still take the Collection overload.
            if state.setExprIDs.contains(argument.rawValue)
                || state.listExprIDs.contains(argument.rawValue)
                || state.arrayExprIDs.contains(argument.rawValue)
            {
                return .collection
            }
            return .emptyOrComparator
        }
    }

    func treeMapConstructorKind(
        symbol: SymbolID?,
        arguments: [KIRExprID],
        module: KIRModule,
        state: CollectionRewriteState,
        ctx: KIRContext
    ) -> TreeMapConstructorKind {
        guard arguments.count >= 2, let argument = arguments.last else {
            return .emptyOrComparator
        }
        let kind = sortedConstructorArgumentKind(
            symbol: symbol,
            argument: argument,
            sortedSimpleNames: ["SortedMap", "NavigableMap", "TreeMap"],
            collectionSimpleNames: [
                "Map", "MutableMap", "HashMap", "LinkedHashMap",
                "AbstractMap", "AbstractMutableMap",
            ],
            module: module,
            ctx: ctx
        )
        switch kind {
        case "sorted":
            return .sortedMap
        case "collection":
            return .map
        case "comparator":
            return .emptyOrComparator
        default:
            if state.mapExprIDs.contains(argument.rawValue) {
                return .map
            }
            return .emptyOrComparator
        }
    }

    /// Looks up the primitive boxing callee for `type`, resolving a value
    /// class to its underlying primitive first (see `resolveValueClassKind`)
    /// so `Meters` boxes exactly like the `Int` it wraps — matching
    /// `ABILoweringPass`'s typeParam boxing boundary
    /// (`typeParamBoxingBoundaryCallees`), which every other reference-type
    /// boxing boundary in this pass is documented to mirror. A value class
    /// implementing an interface stays boxed instead (see
    /// `effectiveValueClassUnderlyingType`), so it never reaches this path.
    func primitiveBoxCalleeName(
        for type: TypeID,
        types: TypeSystem,
        symbols: SymbolTable? = nil,
        interner: StringInterner
    ) -> InternedString? {
        let kind = resolveValueClassKind(types.kind(of: type), types: types, symbols: symbols)
        return BoxingCalleeTable(interner: interner).boxCallee(for: kind, requireNonNull: false)
    }

    /// When the symbol is nil (unresolved) we conservatively allow the rewrite –
    /// the name check already passed and unresolved symbols are common for
    /// synthetic stubs that have no KIR-level symbol entry.
    func isStdlibCollectionFactory(
        symbol: SymbolID?,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        guard let sym = symbol,
              let resolved = ctx.sema?.symbols.symbol(sym)
        else {
            // No symbol info available – fall through to name-only rewrite
            // (backwards compatible with pre-symbol resolution passes).
            return true
        }
        let fqName = resolved.fqName
        return fqName == lookup.emptyListFQName
            || fqName == lookup.emptyArrayFQName
            || fqName == lookup.listOfFQName
            || fqName == lookup.mutableListOfFQName
            || fqName == lookup.arrayListOfFQName
            || fqName == lookup.listOfNotNullFQName
            || fqName == lookup.emptySetFQName
            || fqName == lookup.setOfFQName
            || fqName == lookup.setOfNotNullFQName
            || fqName == lookup.mutableSetOfFQName
            || fqName == lookup.linkedSetOfFQName
            || fqName == lookup.hashSetOfFQName
            || fqName == lookup.emptyMapFQName
            || fqName == lookup.mapOfFQName
            || fqName == lookup.mutableMapOfFQName
            || fqName == lookup.hashMapOfFQName
            || fqName == lookup.linkedMapOfFQName
    }

    /// Source-backed concrete classes lower through the same runtime bridge as
    /// the historical name-based constructor path. The resolved callee is
    /// `<init>` once ArrayList is a real class, so the owner FQName is the
    /// authoritative discriminator.
    func isStdlibArrayListConstructor(
        symbol: SymbolID?,
        callee: InternedString,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        if lookup.mutableListConstructorNames.contains(callee) {
            return true
        }
        guard let symbol,
              let resolved = ctx.sema?.symbols.symbol(symbol),
              resolved.kind == .constructor
        else {
            return false
        }
        return resolved.fqName == [
            lookup.kotlinName,
            ctx.interner.intern("collections"),
            lookup.arrayListName,
            lookup.initName,
        ]
    }

    func isStdlibArrayFactoryCall(
        symbol: SymbolID?,
        callee: InternedString,
        lookup: CollectionLiteralLookupTables,
        ctx: KIRContext
    ) -> Bool {
        if lookup.arrayOfFactoryNames.contains(callee),
           isStdlibCollectionFactory(symbol: symbol, lookup: lookup, ctx: ctx)
        {
            return true
        }
        return isSourceBackedPrimitiveArrayFactory(
            symbol,
            sema: ctx.sema,
            interner: ctx.interner
        )
    }

    func isCollectionCopyConstructorArgument(
        _ argument: KIRExprID,
        module: KIRModule,
        ctx: KIRContext
    ) -> Bool {
        guard let sema = ctx.sema,
              let argumentType = module.arena.exprType(argument)
        else {
            return false
        }

        let nonNullType = sema.types.makeNonNullable(argumentType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return false
        }

        let kotlinCollectionsFQName = [ctx.interner.intern("kotlin"), ctx.interner.intern("collections")]
        let javaUtilFQName = [ctx.interner.intern("java"), ctx.interner.intern("util")]
        let packageFQName = Array(symbol.fqName.dropLast())
        guard symbol.fqName.count >= 3,
              packageFQName == kotlinCollectionsFQName || packageFQName == javaUtilFQName
        else {
            return false
        }

        let simpleName = symbol.fqName.last ?? symbol.name
        switch ctx.interner.resolve(simpleName) {
        case "List", "MutableList", "ArrayList",
             "AbstractList", "AbstractMutableList",
             "Set", "MutableSet", "HashSet", "LinkedHashSet",
             "AbstractSet", "AbstractMutableSet",
             "Collection", "MutableCollection",
             "AbstractCollection", "AbstractMutableCollection",
             "SortedSet", "NavigableSet", "TreeSet":
            return true
        default:
            return false
        }
    }

    /// True when the resolved callee is a bundled Kotlin source declaration
    /// or an imported library symbol, meaning the lowering pass should not
    /// rewrite it to a `kk_*` runtime helper.
    func isSourceBacked(
        symbol: SymbolID?,
        ctx: KIRContext
    ) -> Bool {
        guard let symbol,
              let sema = ctx.sema,
              sema.symbols.symbol(symbol) != nil
        else {
            return false
        }
        return sema.symbols.isSourceBackedSymbol(symbol)
    }

    /// The simple name of a resolved `kotlin.sequences`/`kotlin.collections`
    /// function declaration, or `nil` when the callee is unresolved or belongs
    /// to any other package (KUU-3850).
    ///
    /// kklib-imported stdlib callees reach this pass under `kk_fn_*` link
    /// names, so a plain `callee == "take"`-style comparison can never see
    /// them; matching on the resolved declaration keeps working in both
    /// stdlib modes. `kotlin.collections` is included because this bundled
    /// stdlib declares some `Sequence` extensions (e.g. `count`) in that
    /// package; the call-site runtime-box receiver check still discriminates
    /// same-named `Iterable`/`List` overloads.
    func sequenceExtensionSimpleName(
        symbol: SymbolID?,
        sema: SemaModule?,
        interner: StringInterner
    ) -> InternedString? {
        guard let symbol,
              let sema,
              let decl = sema.symbols.symbol(symbol),
              decl.kind == .function,
              decl.fqName.count == 3,
              decl.fqName[0] == interner.intern("kotlin")
        else {
            return nil
        }
        let sequencesPackage = interner.intern("sequences")
        let collectionsPackage = interner.intern("collections")
        guard decl.fqName[1] == sequencesPackage || decl.fqName[1] == collectionsPackage else {
            return nil
        }
        return decl.fqName[2]
    }

}
