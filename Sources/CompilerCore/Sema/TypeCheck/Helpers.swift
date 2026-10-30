
func nominalRangeElementType(
    for rangeType: TypeID,
    sema: SemaModule,
    interner: StringInterner
) -> TypeID? {
    let nonNullType = sema.types.makeNonNullable(rangeType)
    guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
        return nil
    }

    switch interner.resolve(symbol.name) {
    case "IntRange", "IntProgression":
        return sema.types.intType
    case "LongRange", "LongProgression":
        return sema.types.longType
    case "UIntRange", "UIntProgression":
        return sema.types.uintType
    case "ULongRange", "ULongProgression":
        return sema.types.ulongType
    case "CharRange", "CharProgression":
        return sema.types.charType
    default:
        return nil
    }
}

struct TypeCheckHelpers {
    /// The companion object's type when `exprID` is a bare `ClassName` value
    /// expression naming a class/interface/enum that has a companion object.
    ///
    /// Sema types such a name as the class's own nominal type so that
    /// `ClassName.member()` keeps resolving through the companion. In Kotlin,
    /// however, a bare class name used as a *value* denotes the companion object
    /// (`val f: Factory<Widget> = Widget`, `makeTwo(Widget)`), and the lowering
    /// already redirects it to the companion singleton. Value-position callers
    /// use this to give the expression the companion's type -- which carries the
    /// companion's supertypes -- and rebind the expression to it.
    func retypeClassNameAsCompanionValue(
        _ exprID: ExprID,
        currentType: TypeID,
        ast: ASTModule,
        sema: SemaModule
    ) -> TypeID? {
        guard case .nameRef = ast.arena.expr(exprID),
              let boundSymbol = sema.bindings.identifierSymbols[exprID],
              let boundInfo = sema.symbols.symbol(boundSymbol),
              boundInfo.kind == .class || boundInfo.kind == .interface || boundInfo.kind == .enumClass,
              let companionSymbol = sema.symbols.companionObjectSymbol(for: boundSymbol),
              case let .classType(currentClass) = sema.types.kind(of: currentType),
              currentClass.classSymbol == boundSymbol
        else {
            return nil
        }
        let companionType = sema.symbols.propertyType(for: companionSymbol)
            ?? sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))
        sema.bindings.bindExprType(exprID, type: companionType)
        return companionType
    }

    /// A control-flow branch (`try` body, `catch`, `if`/`else` arm, `when`
    /// branch) whose value-producing expression is a bare class name denotes
    /// the companion object, not a `ClassType(X)` instance. Without retyping,
    /// branch joins keep the nominal type and postfix member lookup cannot
    /// reach companion members (`try { ULong } finally { }.MAX_VALUE`,
    /// KUU-3232). Unwraps block bodies to their trailing expression.
    func retypeBranchClassObjectValue(
        _ exprID: ExprID,
        currentType: TypeID,
        ast: ASTModule,
        sema: SemaModule
    ) -> TypeID? {
        var candidate = exprID
        while case let .blockExpr(_, trailingExpr, _) = ast.arena.expr(candidate),
              let trailingExpr
        {
            candidate = trailingExpr
        }
        return retypeClassNameAsCompanionValue(
            candidate, currentType: currentType, ast: ast, sema: sema
        )
    }

    /// Per-compilation memoization for opt-in requirement derivation and
    /// annotation-class resolution (see `OptInResolutionCache`). A class, so
    /// copies of this struct and every `driver.helpers` call site share it.
    let optInResolutionCache = OptInResolutionCache()

    private func syntheticCoroutineNominalType(
        packageName: [InternedString],
        shortName: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let shortNameID = interner.intern(shortName)
        let candidates = sema.symbols.lookupAll(fqName: packageName + [shortNameID])
            .filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                switch symbol.kind {
                case .class, .interface, .object:
                    return true
                default:
                    return false
                }
            }
            .sorted { $0.rawValue < $1.rawValue }
        guard let symbolID = candidates.first else {
            return nil
        }
        // Source-backed Deferred is generic (`Deferred<out T>`). An empty
        // ClassType.args list is an arity mismatch and breaks `.await()`
        // member matching after KSP-1564 / #7485.
        let typeArguments: [TypeArg] = sema.types.nominalTypeParameterSymbols(for: symbolID).map { _ in
            .out(sema.types.anyType)
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbolID,
            args: typeArguments,
            nullability: .nonNull
        )))
    }

    func emitVisibilityError(
        for symbol: SemanticSymbol,
        name: String,
        range: SourceRange?,
        diagnostics: DiagnosticEngine
    ) {
        let visLabel: String
        let code: String
        switch symbol.visibility {
        case .private:
            visLabel = "private"
            code = "KSWIFTK-SEMA-0040"
        case .protected:
            visLabel = "protected"
            code = "KSWIFTK-SEMA-0041"
        case .internal:
            visLabel = "internal in the bundled stdlib module"
            code = "KSWIFTK-SEMA-0044"
        case .public:
            return
        }
        diagnostics.error(code, "Cannot access '\(name)': it is \(visLabel).", range: range)
    }

    func bindAndReturnErrorType(_ id: ExprID, sema: SemaModule) -> TypeID {
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    func isStableLocalSymbol(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        guard let symbol = sema.symbols.symbol(symbolID) else {
            // A symbol ID outside the registered table is either `.invalid`
            // (-1), a genuinely unknown/out-of-range ID, or one of the
            // synthetic per-binding schemes that deliberately never register
            // a table entry -- lambda parameters
            // (ExprTypeChecker+NameLambdaAndCallableRefInference's per-lambda
            // negative IDs) and the extension/implicit-receiver `this`
            // (SyntheticSymbolScheme.receiverParameterSymbol). Both schemes
            // stay well below -1 (SyntheticSymbolScheme documents its bands
            // as <= -10000; the lambda-parameter band starts past -1_000_000),
            // and both name bindings that Kotlin never allows reassigning, so
            // they are stable. Anything else (including -1 and other
            // out-of-range IDs) is treated conservatively as unstable.
            return symbolID.rawValue < -1
        }
        switch symbol.kind {
        case .valueParameter, .local:
            return !symbol.flags.contains(.mutable)
        default:
            return false
        }
    }

    func isRangeLikeType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        switch interner.resolve(symbol.name) {
        case "OpenEndRange", "ClosedRange", "ClosedFloatingPointRange",
             "IntRange", "IntProgression",
             "LongRange", "LongProgression",
             "UIntRange", "UIntProgression",
             "ULongRange", "ULongProgression",
             "CharRange", "CharProgression":
            return true
        default:
            return false
        }
    }

    /// Concrete classes such as `LongRange`/`CharProgression` have a fixed
    /// primitive element type. Generic interfaces (`OpenEndRange<T>`,
    /// `ClosedRange<T>`, `ClosedFloatingPointRange<T>`) are invariant in `T`,
    /// so their element type is read directly from the sole type argument.
    /// Returns `nil` when the element type cannot be determined (e.g. a
    /// star-projected type argument), in which case callers should not skip
    /// the nominal subtype check.
    func rangeLikeDeclaredElementType(
        for rangeType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        if let fixedElement = nominalRangeElementType(for: rangeType, sema: sema, interner: interner) {
            return fixedElement
        }
        guard let (classType, symbol) = resolveClassTypeSymbol(
            sema.types.makeNonNullable(rangeType), sema: sema
        ) else {
            return nil
        }
        switch interner.resolve(symbol.name) {
        case "OpenEndRange", "ClosedRange", "ClosedFloatingPointRange":
            switch classType.args.first {
            case let .invariant(inner), let .out(inner), let .in(inner):
                return sema.types.makeNonNullable(inner)
            case .star, nil:
                return nil
            }
        default:
            return nil
        }
    }

    /// A range literal's bound `bodyType` is usually the scalar element type
    /// itself (Int/Long/UInt/ULong), but two cases hide the true element type
    /// behind a side channel: Char ranges share Int's representation
    /// (STDLIB-290), and floating-point ranges are tracked separately
    /// (`floatingPointRangeElementType`) because the primary scalar inference
    /// in `ExprTypeChecker+BinaryAndFlowInference.swift` has no Double/Float
    /// branch. A range value produced by a resolved call (e.g.
    /// `IntProgression.fromClosedRange(...)`) instead binds `bodyType` to the
    /// real nominal class directly, so that case is unwrapped via
    /// `rangeLikeDeclaredElementType` too.
    func rangeExprActualElementType(
        for exprID: ExprID,
        bodyType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        if let floatElement = sema.bindings.floatingPointRangeElementType(forExpr: exprID) {
            return floatElement
        }
        if sema.bindings.isCharRangeExpr(exprID) {
            return sema.types.charType
        }
        if isRangeLikeType(bodyType, sema: sema, interner: interner),
           let nominalElement = rangeLikeDeclaredElementType(for: bodyType, sema: sema, interner: interner)
        {
            return nominalElement
        }
        return sema.types.makeNonNullable(bodyType)
    }

    /// Decides whether the nominal subtype check between a range-literal
    /// body/initializer and a range-like declared/expected type may be
    /// skipped under the isRangeExpr duck-typing convention.
    ///
    /// The skip is only valid when the body's actual element type matches
    /// the declared type's expected element type exactly: range element
    /// types are invariant type parameters, and primitives don't implicitly
    /// widen in Kotlin (e.g. an `Int` range literal is not an acceptable
    /// `LongRange`). When the element types don't match — or the expected
    /// element type can't be determined, e.g. a star-projected type
    /// argument — this returns `false` so the caller falls through to the
    /// normal subtype constraint, which correctly rejects the mismatch.
    func rangeExprMatchesDeclaredElementType(
        bodyExprID: ExprID,
        bodyType: TypeID,
        declaredType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard sema.bindings.isRangeExpr(bodyExprID),
              isRangeLikeType(declaredType, sema: sema, interner: interner),
              let expectedElement = rangeLikeDeclaredElementType(
                  for: declaredType, sema: sema, interner: interner
              )
        else {
            return false
        }
        let actualElement = rangeExprActualElementType(
            for: bodyExprID, bodyType: bodyType, sema: sema, interner: interner
        )
        return actualElement == expectedElement
    }

    /// A range expression uses its element type as the intermediate Sema type,
    /// so `LocalDeclTypeChecker` needs a narrow exemption for an explicitly
    /// annotated `Iterable<T>`. Concrete collection types and other iterable
    /// classes still require the normal subtype constraint.
    func isPlainIterableType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return symbol.fqName == [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
    }

    /// Deliberately reads the resolved nominal argument instead of asking
    /// `iterableElementType` to inspect the synthetic `iterator()` member. The
    /// latter can expose the declaration's unsubstituted `E` type parameter for
    /// the interface itself.
    func plainIterableElementType(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard isPlainIterableType(type, sema: sema, interner: interner),
              let (classType, _) = resolveClassTypeSymbol(type, sema: sema),
              let elementArgument = classType.args.first
        else {
            return nil
        }
        switch elementArgument {
        case let .invariant(element), let .out(element), let .in(element):
            return element
        case .star:
            return sema.types.anyType
        }
    }

    func isOpenEndRangeType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        return interner.resolve(symbol.name) == "OpenEndRange"
    }

    /// True when a resolved call's return type yields a heap-backed range
    /// object — the `ClosedRange`/`ClosedFloatingPointRange`/`OpenEndRange`
    /// interfaces or any user-defined class conforming to them — rather
    /// than the opaque runtime range-box handle that `isRangeExpr` and the
    /// floating-point range marks describe. Concrete built-in range and
    /// progression classes (`IntRange`, `CharProgression`, ...) *are*
    /// runtime boxes, so they are deliberately excluded (KUU-2941).
    func isRangeInterfaceType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (classType, symbol) = resolveClassTypeSymbol(
            sema.types.makeNonNullable(type), sema: sema
        ) else {
            return false
        }
        switch interner.resolve(symbol.name) {
        case "ClosedRange", "ClosedFloatingPointRange", "OpenEndRange":
            return true
        case "IntRange", "IntProgression",
             "LongRange", "LongProgression",
             "UIntRange", "UIntProgression",
             "ULongRange", "ULongProgression",
             "CharRange", "CharProgression":
            return false
        default:
            break
        }
        for interface in ["ClosedRange", "ClosedFloatingPointRange", "OpenEndRange"] {
            if let rangeSymbol = sema.symbols.lookup(
                fqName: ["kotlin", "ranges", interface].map(interner.intern)
            ), sema.types.isNominalSubtypeSymbol(classType.classSymbol, of: rangeSymbol) {
                return true
            }
        }
        return false
    }

    /// - Parameter isCharRangeExpr: true when the range expression's operands were Char
    ///   (STDLIB-290). Char ranges share Int's runtime/static representation (see the
    ///   `.rangeTo`/`.rangeUntil`/`.downTo` binary op inference), so this must be checked
    ///   before the plain Int case below to avoid mistyping the loop variable as Int.
    func iterableElementType(
        for iterableType: TypeID,
        isRangeExpr: Bool,
        isCharRangeExpr: Bool = false,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        // String is iterable over its Char elements; the loop variable still needs
        // the correct static Char type for member resolution and explicit typing.
        if sema.types.makeNonNullable(iterableType) == sema.types.stringType {
            return sema.types.charType
        }
        // Range/progression types (Int/Long/UInt/ULong) are iterable over their element type,
        // but only when the expression is actually a range operator.
        if isRangeExpr, isCharRangeExpr, iterableType == sema.types.intType {
            return sema.types.charType
        }
        if isRangeExpr, iterableType == sema.types.intType {
            return sema.types.intType
        }
        if isRangeExpr, iterableType == sema.types.longType {
            return sema.types.longType
        }
        if isRangeExpr, iterableType == sema.types.uintType {
            return sema.types.uintType
        }
        if isRangeExpr, iterableType == sema.types.ulongType {
            return sema.types.ulongType
        }
        if let (_, symbol) = resolveClassTypeSymbol(iterableType, sema: sema)
        {
            switch interner.resolve(symbol.name) {
            case "IntRange", "IntProgression":
                return sema.types.intType
            case "LongRange", "LongProgression":
                return sema.types.longType
            case "UIntRange", "UIntProgression":
                return sema.types.uintType
            case "ULongRange", "ULongProgression":
                return sema.types.ulongType
            case "CharRange", "CharProgression":
                return sema.types.charType
            default:
                break
            }
        }
        // Map/MutableMap iteration yields Map.Entry<K, V>, not the first type argument.
        if let entryType = mapEntryElementType(for: iterableType, sema: sema, interner: interner) {
            return entryType
        }
        if let arrayElement = arrayElementType(for: iterableType, sema: sema, interner: interner) {
            return arrayElement
        }
        if let customElement = customIteratorElementType(for: iterableType, sema: sema, interner: interner) {
            return customElement
        }
        // BUG-167: A class implementing `Iterable<T>` iterates over `T` even when
        // its `iterator()` override carries no `operator` flag of its own.
        if let supertypeElement = iterableSupertypeElementType(for: iterableType, sema: sema, interner: interner) {
            return supertypeElement
        }
        // `CharSequence.iterator()` is a `kotlin.text` package-level extension,
        // not an interface member, so the member-candidate walks above never see
        // it; every CharSequence subtype iterates `Char` through that extension.
        if isCharSequenceSubtype(iterableType, sema: sema, interner: interner) {
            return sema.types.charType
        }
        return nil
    }

    private func isCharSequenceSubtype(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let charSequenceSymbol = sema.symbols.lookupNominal(fqName: [
            interner.intern("kotlin"),
            interner.intern("CharSequence"),
        ]) else {
            return false
        }
        let charSequenceType = sema.types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        return sema.types.isSubtype(sema.types.makeNonNullable(type), charSequenceType)
    }

    func iterableSupertypeElementType(
        for iterableType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let (classType, _) = resolveClassTypeSymbol(
            sema.types.makeNonNullable(iterableType),
            sema: sema
        ),
            let iterableSymbol = sema.symbols.lookupNominal(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]),
            let args = sema.types.liftedNominalSupertypeArgs(
                from: classType.classSymbol,
                childArgs: classType.args,
                to: iterableSymbol
            ),
            let element = args.first
        else {
            return nil
        }
        return switch element {
        case let .invariant(type), let .out(type), let .in(type): type
        case .star: sema.types.anyType
        }
    }

    private func customIteratorElementType(
        for iterableType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let nonNullType = sema.types.makeNonNullable(iterableType)
        guard case .classType = sema.types.kind(of: nonNullType) else { return nil }

        let iteratorName = interner.intern("iterator")
        let candidates = collectMemberFunctionCandidates(
            named: iteratorName,
            receiverType: nonNullType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty
            else {
                return false
            }
            return true
        }

        guard let chosen = candidates.first,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }

        let returnType = signature.returnType
        if case let .classType(iteratorClassType) = sema.types.kind(of: returnType),
           !iteratorClassType.args.isEmpty
        {
            switch iteratorClassType.args[0] {
            case let .invariant(inner), let .out(inner), let .in(inner):
                return inner
            case .star:
                return sema.types.nullableAnyType
            }
        }
        let nextName = interner.intern("next")
        let nextCandidates = collectMemberFunctionCandidates(
            named: nextName,
            receiverType: returnType,
            sema: sema,
            interner: interner
        )
        if let nextCandidate = nextCandidates.first,
           let nextSignature = sema.symbols.functionSignature(for: nextCandidate)
        {
            return nextSignature.returnType
        }
        return sema.types.anyType
    }

    /// The inherited type arguments matter for classes such as TreeMap, which
    /// reaches MutableMap through several Java collection interfaces.
    func mapEntryElementType(
        for mapType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(mapType)) else {
            return nil
        }

        let kotlinCollectionsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("collections")]
        guard let mapSymbol = sema.symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("Map")]),
              let mutableMapSymbol = sema.symbols.lookup(
                  fqName: kotlinCollectionsPkg + [interner.intern("MutableMap")]
              )
        else {
            return nil
        }

        let isMutable: Bool
        let mapArgs: [TypeArg]
        if let mutableMapArgs = sema.types.liftedNominalSupertypeArgs(
            from: classType.classSymbol,
            childArgs: classType.args,
            to: mutableMapSymbol
        ), mutableMapArgs.count >= 2 {
            isMutable = true
            mapArgs = mutableMapArgs
        } else if let readOnlyMapArgs = sema.types.liftedNominalSupertypeArgs(
            from: classType.classSymbol,
            childArgs: classType.args,
            to: mapSymbol
        ), readOnlyMapArgs.count >= 2 {
            isMutable = false
            mapArgs = readOnlyMapArgs
        } else {
            return nil
        }

        // MutableMap.iterator() returns MutableMap.MutableEntry, while Map.iterator()
        // returns the read-only Map.Entry surface.
        let entryOwnerName = isMutable ? interner.intern("MutableMap") : interner.intern("Map")
        let entryName = isMutable ? interner.intern("MutableEntry") : interner.intern("Entry")
        let entryFQName = kotlinCollectionsPkg + [entryOwnerName, entryName]
        guard let entrySymbol = sema.symbols.lookup(fqName: entryFQName) else {
            return nil
        }

        // Mirror the actual `iterator().next()` element types: Map yields
        // `Map.Entry<K, V>` and MutableMap yields `MutableMap.MutableEntry<K, V>`,
        // so the map's own K/V arguments (including any use-site projections)
        // carry through unchanged. Wrapping them as `out` would mark V
        // write-forbidden on the invariant MutableEntry and wrongly reject
        // `e.setValue(...)` in `for (e in mutableMap)` loops.
        return sema.types.make(.classType(ClassType(
            classSymbol: entrySymbol,
            args: Array(mapArgs.prefix(2)),
            nullability: .nonNull
        )))
    }

    /// True when `candidate` is a function that shares an operator-convention
    /// name (get/set/componentN/...) but lacks the `operator` modifier —
    /// the shape kotlinc reports as "'operator' modifier is required".
    /// Property accessors share the short names `get`/`set` and are excluded
    /// via their property parent, matching the bundled-stdlib fallback's
    /// accessor guard.
    func isNonOperatorConventionFunction(_ candidate: SymbolID, sema: SemaModule) -> Bool {
        guard let symbol = sema.symbols.symbol(candidate),
              symbol.kind == .function,
              !symbol.flags.contains(.operatorFunction)
        else {
            return false
        }
        if let parent = sema.symbols.parentSymbol(for: candidate),
           sema.symbols.symbol(parent)?.kind == .property
        {
            return false
        }
        return true
    }

    /// Receiver display name for operator-convention diagnostics: the nominal
    /// class name when resolvable, else the full type display name.
    func conventionReceiverDisplayName(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> String {
        if let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) {
            return interner.resolve(symbol.name)
        }
        return sema.types.displayName(of: receiverType, symbols: sema.symbols, interner: interner)
    }

    func arrayElementType(
        for arrayType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (classType, symbol) = resolveClassTypeSymbol(arrayType, sema: sema) else {
            return nil
        }
        switch symbol.name {
        case knownNames.intArray:
            return sema.types.intType
        case knownNames.longArray:
            return sema.types.longType
        case knownNames.shortArray:
            return sema.types.shortType
        case knownNames.byteArray:
            return sema.types.byteType
        case knownNames.ubyteArray:
            return sema.types.ubyteType
        case knownNames.ushortArray:
            return sema.types.ushortType
        case knownNames.uintArray:
            return sema.types.uintType
        case knownNames.ulongArray:
            return sema.types.ulongType
        case knownNames.doubleArray:
            return sema.types.doubleType
        case knownNames.floatArray:
            return sema.types.floatType
        case knownNames.booleanArray:
            return sema.types.booleanType
        case knownNames.charArray:
            return sema.types.charType
        default:
            if !classType.args.isEmpty {
                switch classType.args[0] {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return inner
                case .star:
                    return sema.types.nullableAnyType
                }
            }
            return nil
        }
    }

    func kxMiniCoroutineBuiltinReturnType(
        calleeName: InternedString?,
        argumentCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let calleeName else {
            return nil
        }
        let knownNames = KnownCompilerNames(interner: interner)
        switch calleeName {
        case knownNames.runBlocking:
            guard argumentCount >= 1 else { return nil }
            return sema.types.anyType
        case knownNames.launch:
            guard argumentCount >= 1 else { return nil }
            return syntheticCoroutineNominalType(
                packageName: [interner.intern("kotlinx"), interner.intern("coroutines")],
                shortName: "Job",
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case knownNames.async:
            guard argumentCount >= 1 else { return nil }
            return syntheticCoroutineNominalType(
                packageName: [interner.intern("kotlinx"), interner.intern("coroutines")],
                shortName: "Deferred",
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case knownNames.produce:
            guard argumentCount >= 1 else { return nil }
            return syntheticCoroutineNominalType(
                packageName: [interner.intern("kotlinx"), interner.intern("coroutines"), interner.intern("channels")],
                shortName: "Channel",
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        case interner.intern("delay"):
            guard argumentCount == 1 else { return nil }
            return sema.types.unitType
        case interner.intern("kk_array_new"),
             knownNames.intArray,
             knownNames.longArray,
             knownNames.doubleArray,
             knownNames.floatArray,
             knownNames.booleanArray,
             knownNames.charArray:
            guard argumentCount == 1 else { return nil }
            return sema.types.anyType
        case interner.intern("kk_array_get"), interner.intern("__kk_list_get"):
            guard argumentCount == 2 else { return nil }
            return sema.types.anyType
        case interner.intern("kk_array_set"):
            guard argumentCount == 3 else { return nil }
            return sema.types.unitType
        // Flow (CORO-003): preserve `flow { ... }` fallback typing as Flow<Any>.
        // Member-like names such as `map`/`filter`/`take` stay conservative here
        // because this helper does not know whether the unresolved callee was
        // invoked on an actual Flow receiver.
        case knownNames.flow:
            guard argumentCount == 1 else { return nil }
            return makeFlowType(
                elementType: sema.types.anyType,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
        // KSP-674: flowOf / emptyFlow are Kotlin source now; they resolve
        // normally and no longer need unresolved-call fallback typing.
        case knownNames.emit:
            guard argumentCount == 1 else { return nil }
            return sema.types.unitType
        case interner.intern("collect"), interner.intern("collectLatest"):
            guard argumentCount >= 1 else { return nil }
            return sema.types.unitType
        case interner.intern("map"), interner.intern("filter"), interner.intern("take"),
             interner.intern("transform"), interner.intern("takeWhile"), interner.intern("dropWhile"),
             interner.intern("flatMapConcat"), interner.intern("flatMapMerge"), interner.intern("flatMapLatest"),
             interner.intern("buffer"), interner.intern("conflate"), interner.intern("flowOn"),
             interner.intern("debounce"), interner.intern("sample"),
             interner.intern("zip"), interner.intern("combine"), interner.intern("merge"):
            guard argumentCount == 1 || argumentCount == 2 else { return nil }
            return sema.types.nullableAnyType
        case interner.intern("toList"), interner.intern("first"), interner.intern("single"):
            guard argumentCount == 0 || argumentCount == 1 else { return nil }
            return sema.types.anyType
        default:
            return nil
        }
    }

    /// Returns `nil` when the symbol has not been registered (caller should
    /// fall back to `anyType`).
    func makeFlowType(
        elementType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let flowFQName: [InternedString] = [
            interner.intern("kotlinx"),
            interner.intern("coroutines"),
            interner.intern("flow"),
            interner.intern("Flow"),
        ]
        guard let symbolID = sema.symbols.lookup(fqName: flowFQName) else { return nil }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbolID,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
    }

    func resolveBuiltinTypeName(
        _ name: InternedString,
        nullability: Nullability = .nonNull,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID? {
        if let builtin = BuiltinTypeNames(interner: interner).resolveBuiltinType(name, nullability: nullability, types: types) {
            return builtin
        }
        return nil
    }

    func hasUserDeclaredClassifier(
        _ name: InternedString,
        scope: Scope,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let kotlinRoot = interner.intern("kotlin")
        return scope.lookupClassifier(name, matching: { id in
            guard let sym = sema.symbols.symbol(id) else { return false }
            switch sym.kind {
            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                return sym.fqName.first != kotlinRoot
            default:
                return false
            }
        }).isEmpty == false
    }

    func resolveTypeRef(
        _ typeRefID: TypeRefID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope? = nil,
        diagnostics: DiagnosticEngine? = nil,
        inferenceContext: TypeInferenceContext? = nil,
        usageRange: SourceRange? = nil,
        allowBareGenericTypeAliasProjection: Bool = false
    ) -> TypeID {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return sema.types.errorType
        }
        switch typeRef {
        case let .named(path, argRefs, nullable):
            guard let shortName = path.last else {
                return sema.types.errorType
            }
            let nullability: Nullability = nullable ? .nullable : .nonNull
            if let builtin = resolveBuiltinTypeName(shortName, nullability: nullability, types: sema.types, interner: interner),
               !(path.count == 1 && scope.map { hasUserDeclaredClassifier(shortName, scope: $0, sema: sema, interner: interner) } == true)
            {
                return builtin
            }
            if path.count == 1,
               let scope,
               let typeParameterSymbol = resolveTypeParameterSymbol(shortName, scope: scope, sema: sema)
            {
                return sema.types.make(.typeParam(TypeParamType(symbol: typeParameterSymbol, nullability: nullability)))
            }
            do {
                func isTypeLikeSymbol(_ symbolID: SymbolID) -> Bool {
                    guard let sym = sema.symbols.symbol(symbolID) else { return false }
                    switch sym.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                        return true
                    default:
                        return false
                    }
                }
                // A source declaration shadows an imported-library declaration
                // with the same FQ name (e.g. a module vendoring `kotlinx.io`
                // sources while the bundled stdlib exports the same types).
                // Sorting candidate lists by rawValue alone would put the
                // imported symbol first, since imported symbols occupy lower
                // IDs, so prefer non-imported candidates and use rawValue only
                // as the deterministic tie-break.
                let sourceFirstThenID: (SymbolID, SymbolID) -> Bool = { lhs, rhs in
                    let lhsImported = sema.symbols.symbol(lhs)?.flags.contains(.importedLibrary) == true
                    let rhsImported = sema.symbols.symbol(rhs)?.flags.contains(.importedLibrary) == true
                    if lhsImported != rhsImported {
                        return !lhsImported
                    }
                    return lhs.rawValue < rhs.rawValue
                }
                // Prefer the lexically-scoped candidate (which encodes import
                // priority: explicit imports > same-package declarations >
                // wildcard imports > default imports for classifiers, KUU-1423)
                // for unqualified references. Without this, an unrelated
                // same-named declaration from a non-imported package (e.g.
                // `kotlin.properties.Lazy` vs. the in-scope `kotlin.Lazy`)
                // could shadow the correct symbol merely by having a lower
                // internal ID, since the short-name fallback below has no
                // notion of scope.
                let scopeCandidates: [SymbolID] = if path.count == 1, let scope {
                    scope.lookupClassifier(shortName, matching: isTypeLikeSymbol).sorted(by: sourceFirstThenID)
                } else {
                    []
                }
                // A type imported by its outer declaration can be referenced by
                // a qualified nested name (for example, `Base64.Default`). The
                // full path is not globally qualified in that form, so walk the
                // imported outer symbol before falling back to short-name lookup.
                let qualifiedScopeCandidates: [SymbolID] = {
                    guard path.count > 1, let scope else { return [] }
                    var current = scope.lookupClassifier(path[0], matching: isTypeLikeSymbol)
                        .sorted(by: sourceFirstThenID)
                    for component in path.dropFirst() {
                        current = current.flatMap { ownerID -> [SymbolID] in
                            guard let owner = sema.symbols.symbol(ownerID) else { return [] }
                            return sema.symbols.lookupAll(fqName: owner.fqName + [component])
                                .filter(isTypeLikeSymbol)
                        }
                        .sorted(by: sourceFirstThenID)
                        if current.isEmpty {
                            break
                        }
                    }
                    return current
                }()
                let fqCandidates = sema.symbols.lookupAll(fqName: path).filter(isTypeLikeSymbol)
                    .sorted(by: sourceFirstThenID)
                // Resolve nested types through the imported or package-scoped
                // nominal root before falling back to the short name. This is
                // required when several nominal types expose the same nested
                // name, such as kotlin.time.Clock.Companion.
                let nestedCandidates: [SymbolID] = {
                    guard path.count > 1, let scope else {
                        return []
                    }
                    let rootCandidates = scope.lookupClassifier(path[0], matching: isTypeLikeSymbol)
                    return rootCandidates.flatMap { rootSymbol -> [SymbolID] in
                        guard let rootInfo = sema.symbols.symbol(rootSymbol) else {
                            return []
                        }
                        return sema.symbols.lookupAll(
                            fqName: rootInfo.fqName + Array(path.dropFirst())
                        ).filter(isTypeLikeSymbol)
                    }
                    .sorted(by: sourceFirstThenID)
                }()
                // KUU-3237: a typealias cannot qualify a nested-classifier
                // reference (`A2.Nested` is unresolved in Kotlin). The scoped
                // lookups above walk the alias's own fqName, which has no
                // children, so every qualified candidate list is empty here —
                // report the member instead of letting the short-name
                // fallback resolve `Nested` against an unrelated owner.
                if path.count > 1,
                   let scope,
                   qualifiedScopeCandidates.isEmpty,
                   fqCandidates.isEmpty,
                   nestedCandidates.isEmpty,
                   let qualifierID = scope.lookupClassifier(path[0], matching: isTypeLikeSymbol)
                       .sorted(by: sourceFirstThenID).first,
                   sema.symbols.symbol(qualifierID)?.kind == .typeAlias
                {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0025",
                        "Unresolved type '\(interner.resolve(shortName))'.",
                        range: usageRange
                    )
                    return sema.types.errorType
                }
                // Fall back to short-name lookup so that packaged types
                // (e.g. `package test; class Foo`) resolve when referenced
                // by simple name (`Foo`) during type checking.
                let kotlinReflectPackage = [interner.intern("kotlin"), interner.intern("reflect")]
                let shortNameCandidates = sema.symbols.lookupByShortName(shortName).filter { candidate in
                    guard isTypeLikeSymbol(candidate), let symbol = sema.symbols.symbol(candidate) else {
                        return false
                    }
                    guard !symbol.fqName.starts(with: kotlinReflectPackage) else { return false }
                    // A nested classifier is never reachable by its bare
                    // short name: Kotlin scopes it to the declaring
                    // classifier's body. Only package members (top-level
                    // declarations) may satisfy this recovery path, so a
                    // subtype's `Entry` cannot silently name
                    // `Contract.Entry` (KUU-3637, KUU-3636).
                    if let parent = sema.symbols.parentSymbol(for: candidate),
                       sema.symbols.symbol(parent)?.kind != .package
                    {
                        return false
                    }
                    // Local classes resolve only through their lexical scope,
                    // including self-references while collecting their headers.
                    if symbol.kind == .class, symbol.flags.contains(.synthetic),
                       let root = symbol.fqName.first,
                       interner.resolve(root).hasPrefix("__localdecl_")
                    {
                        return false
                    }
                    return true
                }
                    .sorted(by: sourceFirstThenID)
                let candidates: [SymbolID] = if !scopeCandidates.isEmpty {
                    scopeCandidates
                } else if !qualifiedScopeCandidates.isEmpty {
                    qualifiedScopeCandidates
                } else if !fqCandidates.isEmpty {
                    fqCandidates
                } else if !nestedCandidates.isEmpty {
                    nestedCandidates
                } else if !shortNameCandidates.isEmpty {
                    shortNameCandidates
                } else if let arity = sema.types.functionNInterfaceArity(named: path, interner: interner),
                          let functionN = DataFlowSemaPhase().ensureSyntheticFunctionInterface(
                              arity: arity,
                              symbols: sema.symbols,
                              types: sema.types,
                              interner: interner
                          )
                {
                    [functionN]
                } else {
                    // Preserve short-name recovery for legacy and generated
                    // type references, but require imports for kotlin.reflect.
                    []
                }
                if let symbolID = candidates.first {
                    if let symbol = sema.symbols.symbol(symbolID),
                       let inferenceContext,
                       !inferenceContext.visibilityChecker.isAccessible(
                           symbol,
                           fromFile: inferenceContext.currentFileID,
                           enclosingClass: inferenceContext.enclosingClassSymbol
                       ) {
                        if let diagnostics {
                            emitVisibilityError(
                                for: symbol,
                                name: interner.resolve(shortName),
                                range: usageRange,
                                diagnostics: diagnostics
                            )
                        }
                        return sema.types.errorType
                    }
                    if let inferenceContext, let diagnostics {
                        checkOptIn(
                            for: symbolID,
                            ctx: inferenceContext,
                            range: usageRange,
                            diagnostics: diagnostics
                        )
                    }
                    if let diagnostics {
                        checkDeprecation(
                            for: symbolID,
                            sema: sema,
                            interner: interner,
                            range: usageRange,
                            diagnostics: diagnostics
                        )
                    }
                    let resolvedArgs = resolveTypeArgRefsForTypeCheck(
                        argRefs, ast: ast, sema: sema, interner: interner,
                        scope: scope, diagnostics: diagnostics, inferenceContext: inferenceContext, usageRange: usageRange
                    )
                    if sema.symbols.symbol(symbolID)?.kind != .typeAlias {
                        TypeProjectionValidator(symbols: sema.symbols, types: sema.types,
                                                interner: interner, diagnostics: diagnostics, range: usageRange)
                            .validate(arguments: resolvedArgs, of: symbolID)
                    }
                    if let sym = sema.symbols.symbol(symbolID), sym.kind == .typeAlias {
                        let aliasTypeArgs: [TypeArg]
                        // Bare generic aliases erase their omitted parameters in runtime checks and casts.
                        // Other type-reference contexts keep the normal arity diagnostic.
                        if allowBareGenericTypeAliasProjection,
                           argRefs.isEmpty
                        {
                            let typeParameterCount = sema.symbols.typeAliasTypeParameters(for: symbolID).count
                            aliasTypeArgs = typeParameterCount == 0
                                ? resolvedArgs
                                : Array(repeating: .star, count: typeParameterCount)
                        } else {
                            aliasTypeArgs = resolvedArgs
                        }
                        if let expanded = expandTypeAlias(
                            symbolID,
                            typeArgs: aliasTypeArgs,
                            sema: sema,
                            visited: [],
                            depth: 0,
                            diagnostics: diagnostics,
                            projectionRange: usageRange
                        ) {
                            if nullability == .nullable {
                                return applyNullabilityForTypeCheck(expanded, types: sema.types)
                            }
                            return expanded
                        }
                        // Fall through to classType for error recovery
                    }
                    if let sym = sema.symbols.symbol(symbolID),
                       symbolID == sema.types.kClassInterfaceSymbol
                        || sym.fqName == [interner.intern("kotlin"), interner.intern("reflect"), interner.intern("KClass")]
                    {
                        // Preserve use-site projections: the dedicated KClass
                        // representation has an invariant argument.
                        if let firstArg = resolvedArgs.first {
                            switch firstArg {
                            case .star, .in, .out:
                                return sema.types.make(.classType(ClassType(
                                    classSymbol: symbolID,
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
                                sema.types.anyType
                            case let .out(t), let .in(t):
                                t
                            }
                        } else {
                            sema.types.anyType
                        }
                        return sema.types.makeKClassType(argument: argumentType, nullability: nullability)
                    }
                    // Qualified inner-class references (`Outer<V>.Inner`) supply the
                    // qualifier's arguments; route through the nominal split so they
                    // land in enclosingTypeArgs rather than the class's own args.
                    // A bare name supplies none, so the implicit enclosing instance
                    // fills those slots (`KeySet` inside `CIM<Value>` spells
                    // `CIM<Value>.KeySet`).
                    var nominalArgs = resolvedArgs
                    let enclosingCount = sema.types.enclosingTypeParameterSymbols(for: symbolID).count
                    if enclosingCount > 0 {
                        let implicitEnclosing = sema.types.implicitInnerClassEnclosingArgs(
                            for: symbolID,
                            enclosingInstanceTypes: inferenceContext?.implicitReceiverMemberLookupTypes() ?? []
                        )
                        if path.count == 1 {
                            nominalArgs = implicitEnclosing + resolvedArgs
                        } else if resolvedArgs.count < enclosingCount {
                            nominalArgs = Array(implicitEnclosing.prefix(enclosingCount - resolvedArgs.count)) + resolvedArgs
                        }
                    }
                    return sema.types.make(.classType(sema.types.classType(
                        for: symbolID,
                        arguments: nominalArgs,
                        nullability: nullability
                    )))
                }
                diagnostics?.error(
                    "KSWIFTK-SEMA-0025",
                    "Unresolved type '\(interner.resolve(shortName))'.",
                    range: usageRange
                )
                return sema.types.errorType
            }

        case let .functionType(contextReceiverRefIDs, receiverRefID, paramRefIDs, returnRefID, isSuspend, nullable):
            let nullability: Nullability = nullable ? .nullable : .nonNull
            let contextReceiverTypes = contextReceiverRefIDs.map {
                resolveTypeRef($0, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics, inferenceContext: inferenceContext, usageRange: usageRange)
            }
            let receiverType: TypeID? = receiverRefID.flatMap { resolveTypeRef($0, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics, inferenceContext: inferenceContext, usageRange: usageRange) }
            let paramTypes = paramRefIDs.map { resolveTypeRef($0, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics, inferenceContext: inferenceContext, usageRange: usageRange) }
            let returnType = resolveTypeRef(returnRefID, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics, inferenceContext: inferenceContext, usageRange: usageRange)
            return sema.types.make(.functionType(FunctionType(
                contextReceivers: contextReceiverTypes,
                receiver: receiverType,
                params: paramTypes,
                returnType: returnType,
                isSuspend: isSuspend,
                nullability: nullability
            )))

        case let .intersection(partRefs):
            let partTypes = partRefs.map { resolveTypeRef($0, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics, inferenceContext: inferenceContext, usageRange: usageRange) }
            return sema.types.make(.intersection(partTypes))

        case let .annotated(base, annotations):
            let baseType = resolveTypeRef(base, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics, inferenceContext: inferenceContext, usageRange: usageRange)
            return ExtensionFunctionTypeSupport.normalizeAnnotatedType(
                baseType: baseType,
                annotations: annotations,
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                diagnostics: diagnostics,
                range: usageRange
            )
        }
    }

    func resolveTypeArgRefsForTypeCheck(
        _ argRefs: [TypeArgRef],
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        scope: Scope? = nil,
        diagnostics: DiagnosticEngine? = nil,
        inferenceContext: TypeInferenceContext? = nil,
        usageRange: SourceRange? = nil
    ) -> [TypeArg] {
        argRefs.map { argRef in
            switch argRef {
            case let .invariant(innerRef):
                .invariant(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics, inferenceContext: inferenceContext, usageRange: usageRange))
            case let .out(innerRef):
                .out(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics, inferenceContext: inferenceContext, usageRange: usageRange))
            case let .in(innerRef):
                .in(resolveTypeRef(innerRef, ast: ast, sema: sema, interner: interner, scope: scope, diagnostics: diagnostics, inferenceContext: inferenceContext, usageRange: usageRange))
            case .star:
                .star
            }
        }
    }

    func resolveTypeParameterSymbol(
        _ name: InternedString,
        scope: Scope,
        sema: SemaModule
    ) -> SymbolID? {
        scope.lookup(name).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .typeParameter
        }
    }

    func throwableType(sema: SemaModule, interner: StringInterner) -> TypeID? {
        let throwableFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Throwable")]
        guard let throwableSymbol = sema.symbols.lookup(fqName: throwableFQName) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func recordMemberValInitializationSmartCast(
        property: SymbolID,
        declaredType: TypeID,
        valueType: TypeID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        guard ctx.allowsValPropertyInitialization,
              ctx.lambdaDepth == 0,
              let propSymbol = ctx.sema.symbols.symbol(property),
              propSymbol.kind == .property,
              !propSymbol.flags.contains(.mutable),
              ctx.sema.symbols.parentSymbol(for: property) == ctx.enclosingClassSymbol,
              ctx.dataFlow.isStableMemberProperty(property, ast: ctx.ast, sema: ctx.sema),
              valueType != ctx.sema.types.errorType,
              valueType != ctx.sema.types.nothingType,
              ctx.sema.types.isSubtype(valueType, declaredType),
              let thisLocal = locals[ctx.interner.intern("this")]
        else {
            return
        }
        let reference = DataFlowReference(root: thisLocal.symbol, properties: [property])
        let flowState = VariableFlowState(
            possibleTypes: [valueType],
            nullability: ctx.sema.types.nullability(of: valueType),
            isStable: true
        )
        locals.memberFlow[reference] = flowState
    }
}
