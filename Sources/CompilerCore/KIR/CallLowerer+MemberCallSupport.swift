
struct MemberCallReceiver {
    let expr: ExprID
    let loweredID: KIRExprID
}

/// Tag scheme shared by every `kk_any_to_string`/`kk_any_hashCode`/`kk_any_equals`
/// call site (Any-fallback member calls, string concatenation/interpolation,
/// data class `toString()` synthesis, `println(dataClass)` rewriting, ...):
/// 1=default (Int/Long/erased Any), 2=Boolean, 3=String, 4=Char, 5=Float,
/// 6=Double, 7=ULong. ULong spans the full 64 bits, so kk_any_to_string must
/// reinterpret it as unsigned (tag 1 would print the signed reinterpretation,
/// or even "null" for values whose bit pattern equals Int.min). UInt/UByte/
/// UShort stay on the default tag: they are always zero-extended into this
/// container, so tag 1's signed decimal rendering already matches their
/// unsigned value. This is a free function (not a `CallLowerer` method) so
/// every lowering pass that stringifies an arbitrary Any-typed value can
/// share the exact same tag computation instead of drifting out of sync.
func computeAnyFallbackTag(for type: TypeID, sema: SemaModule) -> Int64 {
    switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
    case .primitive(.boolean, _):
        2
    case .stringStruct:
        3
    case .primitive(.char, _):
        4
    case .primitive(.float, _):
        5
    case .primitive(.double, _):
        6
    case .primitive(.ulong, _):
        7
    default:
        1
    }
}

extension CallLowerer {
    static let unresolvedCoroutineHandleMemberNames: Set<String> = [
        "await", "join", "awaitCompletion",
        "cancel", "complete", "completeExceptionally",
        "isActive", "isCompleted", "isCancelled"
    ]
    // KSP-678: close / isClosedForReceive / isClosedForSend migrated to bundled
    // Kotlin source; only the suspension core send / receive remain here.
    static let unresolvedChannelMemberNames: Set<String> = ["send", "receive"]
    // Flow operators beyond map/filter/take/collect (already covered by
    // unresolvedCollectionMemberNames because those names also exist on
    // collections). These names are Flow-specific, so a Flow receiver with an
    // unresolved chosenCallee still needs its receiver argument inserted here.
    static let unresolvedFlowMemberNames: Set<String> = [
        "buffer", "conflate", "collectLatest", "debounce", "sample", "delayEach", "flowOn",
        "transform", "dropWhile", "flatMapConcat", "flatMapMerge", "flatMapLatest",
        "catch", "retry", "retryWhen", "onErrorReturn", "onErrorResume", "single",
    ]

    enum PrimitiveCompareABIKind: Int32 {
        case int = 0
        case long = 1
        case uint = 2
        case ulong = 3
        case boolean = 4
        case char = 5
        case float = 6
        case double = 7
    }

    func primitiveCompareABIKind(for type: TypeID, sema: SemaModule) -> PrimitiveCompareABIKind? {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .primitive(.int, _), .primitive(.ubyte, _), .primitive(.ushort, _):
            return .int
        case .primitive(.long, _):
            return .long
        case .primitive(.uint, _):
            return .uint
        case .primitive(.ulong, _):
            return .ulong
        case .primitive(.boolean, _):
            return .boolean
        case .primitive(.char, _):
            return .char
        case .primitive(.float, _):
            return .float
        case .primitive(.double, _):
            return .double
        default:
            return nil
        }
    }

    func anyFallbackTag(for type: TypeID, sema: SemaModule) -> Int64 {
        computeAnyFallbackTag(for: type, sema: sema)
    }

    /// Target kind for `kk_number_to_primitive` (KSP-1540). Mirrors the
    /// Runtime-side `RuntimeNumberConversionTargetKind` by raw value — the two
    /// enums live in separate modules linked only through the C ABI, so they
    /// must be kept in sync manually.
    enum NumberConversionTargetKind: Int32 {
        case double = 0
        case float = 1
        case long = 2
        case int = 3
        case short = 4
        case byte = 5
    }

    func numberConversionTargetKind(for calleeName: InternedString, interner: StringInterner) -> NumberConversionTargetKind? {
        switch interner.resolve(calleeName) {
        case "toDouble": return .double
        case "toFloat": return .float
        case "toLong": return .long
        case "toInt": return .int
        case "toShort": return .short
        case "toByte": return .byte
        default: return nil
        }
    }

    /// The `$enumOrdinalToName$<encodedFqName>(ordinal): String` helper for `type`,
    /// when `type` is a non-null enum class that has one.
    ///
    /// `.synthetic` enum classes (Platform.OsFamily, RegexOption, …) are
    /// header-only symbols with no source declSite, so
    /// DataEnumSealedSynthesisPass never synthesizes their helper — see
    /// `emitBoxCallWithValueClassTag`, which skips them for the same reason.
    /// A nullable enum is excluded too: its null sentinel would be fed to the
    /// helper as an ordinal.
    func enumOrdinalToNameCallee(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> (callee: InternedString, symbol: SymbolID?)? {
        guard case let .classType(classType) = sema.types.kind(of: type),
              classType.nullability == .nonNull,
              let symbol = sema.symbols.symbol(classType.classSymbol),
              symbol.kind == .enumClass,
              !symbol.flags.contains(.synthetic)
        else {
            return nil
        }
        let helperName = NameMangler.enumOrdinalToNameHelperName(for: symbol, interner: interner)
        let helperSymbol = sema.symbols.lookupAll(fqName: symbol.fqName + [helperName]).first { id in
            sema.symbols.symbol(id).map { $0.kind == .function } ?? false
        }
        return (helperName, helperSymbol)
    }

    /// The class's own `toString(): String` -- source-declared or synthesized
    /// (e.g. a data class's member-wise `toString()`) -- when `type` is a
    /// `class` (not `object`/`interface`/`enumClass` -- enums are handled by
    /// `enumOrdinalToNameCallee` above). Mirrors
    /// `ConsolePrintLoweringPass.classToStringExpression`'s resolution
    /// (including its exact synthetic-symbol filter: reject only the
    /// `kotlin.Any.toString` fallback, not every `.synthetic`-flagged
    /// symbol -- a data class's toString is `.synthetic` too, but Sema
    /// registers its signature at header-collection time, well before this
    /// BuildKIR-time funnel runs, and `DataEnumSealedSynthesisPass` reliably
    /// gives it a body before codegen ever needs one, the same guarantee
    /// `println`/`print` already rely on for a data class argument) so `+`/
    /// string-template stringification of a class value calls the same
    /// override `println`/explicit `.toString()` already do, instead of
    /// falling through to `kk_any_to_string`'s generic "<object 0x...>"
    /// rendering. `lookupAll` is an exact-fqName lookup (not inheritance-
    /// aware), so this only matches a class whose own static type directly
    /// declares (or has synthesized for it) a `toString`; a class that only
    /// inherits one from a base class, referenced at its own (sub)type
    /// rather than the declaring base type, still falls through to the
    /// generic path (BUG-219).
    func classToStringCallee(
        for type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> (callee: InternedString, symbol: SymbolID)? {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let classSymbol = sema.symbols.symbol(classType.classSymbol),
              classSymbol.kind == .class
        else {
            return nil
        }
        let toStringName = interner.intern("toString")
        let toStringFQName = classSymbol.fqName + [toStringName]
        let toStringSymbol: SymbolID? = sema.symbols.lookupAll(fqName: toStringFQName).first { id in
            guard let sym = sema.symbols.symbol(id), sym.kind == .function else { return false }
            let sig = sema.symbols.functionSignature(for: id)
            return sig?.parameterTypes.isEmpty ?? true
        }
        guard let toStringSym = toStringSymbol,
              let toStringFnSymbol = sema.symbols.symbol(toStringSym),
              !(toStringFnSymbol.flags.contains(.synthetic) && toStringFnSymbol.fqName == [
                  interner.intern("kotlin"), interner.intern("Any"), toStringName,
              ])
        else {
            return nil
        }
        let externalLinkName = sema.symbols.externalLinkName(for: toStringSym)
        let callee: InternedString = if let externalLinkName, !externalLinkName.isEmpty {
            interner.intern(externalLinkName)
        } else {
            toStringName
        }
        return (callee, toStringSym)
    }

    /// Converts `valueID` (of static type `valueType`) to a `String` via
    /// `kk_any_to_string`, using `anyFallbackTag`'s tag for `valueType` and
    /// guarding against the null-sentinel collision for nullable
    /// Float?/Double?/ULong? (tags 5/6/7): their null-sentinel bit pattern
    /// (Int.min) coincides with a legitimate in-range value (-0.0, or a
    /// ULong of exactly 2^63), and kk_any_to_string decodes those tags
    /// *before* checking for the sentinel, so an actually-null value must be
    /// intercepted here first or it renders as that in-range value instead of
    /// "null". Every call site that stringifies an arbitrary Any-typed value
    /// for concatenation/interpolation should route through this helper
    /// rather than calling kk_any_to_string directly, so a future tag needing
    /// the same guard only has to be added in one place.
    func emitAnyToStringWithNullGuard(
        valueID: KIRExprID,
        valueType: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let stringType = sema.types.stringType
        let isNullable = sema.types.makeNonNullable(valueType) != valueType
        // A statically enum-typed value is represented as its bare ordinal, so
        // `kk_any_to_string` would render the number. The enum class's
        // `$enumOrdinalToName$<encodedFqName>` helper maps it back to the entry name —
        // the same helper `emitBoxCallWithValueClassTag` uses when an enum crosses
        // an Any-erased boundary.
        if let nameHelper = enumOrdinalToNameCallee(for: valueType, sema: sema, interner: interner) {
            let name = arena.appendTemporary(type: stringType)
            instructions.append(.call(
                symbol: nameHelper.symbol,
                callee: nameHelper.callee,
                arguments: [valueID],
                result: name,
                canThrow: false,
                thrownResult: nil
            ))
            return name
        }
        // Classes with their own overridden toString() need the same override
        // dispatch that `+`/string-template stringification should use;
        // kk_any_to_string's generic fallback has no notion of user-defined
        // toString() and would otherwise render the raw handle
        // ("<object 0x...>"). Route through the override (virtually, when the
        // receiver's declared toString is overridable) instead, matching what
        // ConsolePrintLoweringPass already does for println/print. A class
        // that only inherits toString from a base class (no direct override)
        // still falls through to the generic path below.
        if let classCallee = classToStringCallee(for: valueType, sema: sema, interner: interner) {
            let converted = arena.appendTemporary(type: stringType)
            func emitToStringCall(into result: KIRExprID) -> KIRInstruction {
                tryEmitVirtualDispatch(
                    chosenCallee: classCallee.symbol,
                    calleeName: classCallee.callee,
                    receiverExpr: nil,
                    loweredReceiverID: valueID,
                    isSuperCall: false,
                    finalArguments: [],
                    result: result,
                    sema: sema,
                    arena: arena,
                    interner: interner
                ) ?? .call(
                    symbol: classCallee.symbol,
                    callee: classCallee.callee,
                    arguments: [valueID],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                )
            }
            guard isNullable else {
                instructions.append(emitToStringCall(into: converted))
                return converted
            }
            let nonNullLabel = driver.ctx.makeLoopLabel()
            let endLabel = driver.ctx.makeLoopLabel()
            let nullStr = interner.intern("null")
            let nullStrID = arena.appendExpr(.stringLiteral(nullStr), type: stringType)
            instructions.append(.constValue(result: nullStrID, value: .stringLiteral(nullStr)))
            instructions.append(.jumpIfNotNull(value: valueID, target: nonNullLabel))
            instructions.append(.copy(from: nullStrID, to: converted))
            instructions.append(.jump(endLabel))
            instructions.append(.label(nonNullLabel))
            let innerConverted = arena.appendTemporary(type: stringType)
            instructions.append(emitToStringCall(into: innerConverted))
            instructions.append(.copy(from: innerConverted, to: converted))
            instructions.append(.label(endLabel))
            return converted
        }
        let tag = anyFallbackTag(for: valueType, sema: sema)
        let tagID = arena.appendExpr(.intLiteral(tag), type: intType)
        instructions.append(.constValue(result: tagID, value: .intLiteral(tag)))
        let converted = arena.appendTemporary(type: stringType)
        guard isNullable, tag == 5 || tag == 6 || tag == 7 else {
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_any_to_string"),
                arguments: [valueID, tagID],
                result: converted,
                canThrow: false,
                thrownResult: nil
            ))
            return converted
        }
        let nonNullLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        let nullStr = interner.intern("null")
        let nullStrID = arena.appendExpr(.stringLiteral(nullStr), type: stringType)
        instructions.append(.constValue(result: nullStrID, value: .stringLiteral(nullStr)))
        instructions.append(.jumpIfNotNull(value: valueID, target: nonNullLabel))
        instructions.append(.copy(from: nullStrID, to: converted))
        instructions.append(.jump(endLabel))
        instructions.append(.label(nonNullLabel))
        let innerConverted = arena.appendTemporary(type: stringType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_any_to_string"),
            arguments: [valueID, tagID],
            result: innerConverted,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.copy(from: innerConverted, to: converted))
        instructions.append(.label(endLabel))
        return converted
    }

    func isCoroutineHandleReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        return knownNames.isCoroutineHandleSymbol(symbol)
    }

    func isChannelReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        return knownNames.isChannelSymbol(symbol)
    }

    func isFlowReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (classType, _) = resolveClassTypeSymbol(receiverType, sema: sema),
              let flowSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("kotlinx"), interner.intern("coroutines"),
                  interner.intern("flow"), interner.intern("Flow"),
              ])
        else {
            return false
        }
        return classType.classSymbol == flowSymbol
    }

    func isCoroutineContextReceiverType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        guard interner.resolve(symbol.name) == "CoroutineContext" else {
            return false
        }
        let kotlinxCoroutinesPkg: [InternedString] = [
            interner.intern("kotlinx"),
            interner.intern("coroutines"),
        ]
        let kotlinCoroutinesPkg: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
        ]
        return symbol.fqName.starts(with: kotlinxCoroutinesPkg)
            || symbol.fqName.starts(with: kotlinCoroutinesPkg)
    }
    static let unresolvedCollectionMemberNames: Set<String> = [
        "size", "get", "contains", "containsAll", "containsKey", "containsValue",
        "isEmpty", "first", "last", "indexOf", "lastIndexOf", "indexOfFirst", "indexOfLast",
        "count", "iterator",
        "map", "filter", "filterNot", "mapNotNull", "mapIndexedNotNullTo", "flatMapIndexedTo", "flatMapIndexed", "firstNotNullOf", "firstNotNullOfOrNull", "filterNotNull", "requireNoNulls", "forEach", "flatMap",
        "map", "filter", "filterNot", "mapNotNull", "mapIndexedNotNullTo", "flatMapTo", "firstNotNullOf", "firstNotNullOfOrNull", "filterNotNull", "requireNoNulls", "forEach", "flatMap",
        "any", "none", "all",
        "fold", "foldIndexed", "foldRight", "foldRightIndexed",
        "reduce", "reduceRight", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "reduceIndexed", "reduceIndexedOrNull",
        "scan", "scanIndexed", "scanReduce", "runningFold", "runningFoldIndexed",
        "runningReduce", "runningReduceIndexed",
        "groupBy", "groupByTo", "groupingBy", "sortedBy", "find", "findLast", "associateBy", "associateByTo", "associateWith", "associateWithTo", "associate", "associateTo", "zip", "zipWithNext", "unzip",
        "eachCount", "eachCountTo", "aggregate", "aggregateTo",
        "withIndex", "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed", "mapValues", "mapValuesTo", "mapKeys", "mapKeysTo", "filterKeys", "filterValues",
        "getValue", "getOrDefault", "getOrElse", "getOrPut", "getOrNull", "elementAtOrNull", "elementAt", "elementAtOrElse",
        "putAll", "addAll",
        "maxBy", "minBy", "max", "min", "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull", "maxOrNull", "minOrNull",
        "plus", "plusElement", "minus", "minusElement",
        "asSequence", "asIterable", "toList", "toSet", "toMap", "toCollection", "toMutableList", "toMutableSet", "toSortedSet", "toTypedArray",
        // Kept for non-List receivers (Set / Iterable): List receivers are
        // source-backed since KSP-628 and no longer reach this path.
        "toBooleanArray", "toCharArray", "toShortArray", "toDoubleArray", "toFloatArray", "toIntArray", "toLongArray", "toByteArray", "toUByteArray", "toUShortArray", "toUIntArray", "toULongArray",
        "take", "takeWhile", "takeLast", "drop", "reversed", "asReversed", "sorted", "distinct", "flatten", "chunked", "windowed", "collect", "subList",
        "sortedDescending", "sortedByDescending", "sortedWith", "partition",
        "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
        "maxOf", "minOf",
        "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
        "sort", "sortWith", "sortBy", "sortByDescending",
        "onEach", "onEachIndexed",
        "copyOf", "copyOfRange", "fill",
        "firstOrNull", "lastOrNull", "singleOrNull",
        "addAll", "removeAll", "retainAll",
        "intersect", "union", "subtract",
        "toHashSet",
        "containsAll", "binarySearch", "average",
        "addFirst", "addLast",
        "sum", "sumOf", "sumBy", "sumByDouble",
    ]

}
