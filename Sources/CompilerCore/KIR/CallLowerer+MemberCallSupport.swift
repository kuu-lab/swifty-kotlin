
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
    static let unresolvedChannelMemberNames: Set<String> = ["send", "receive", "close", "isClosedForReceive", "isClosedForSend"]

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
        "toBooleanArray", "toCharArray", "toShortArray", "toDoubleArray", "toFloatArray", "toIntArray", "toLongArray", "toByteArray", "toUByteArray", "toUShortArray", "toUIntArray", "toULongArray",
        "take", "takeWhile", "takeLast", "drop", "reversed", "asReversed", "sorted", "distinct", "flatten", "chunked", "windowed", "collect", "subList",
        "sortedDescending", "sortedByDescending", "sortedWith", "partition",
        "sortedArrayWith",
        "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
        "maxOf", "minOf",
        "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
        "sort", "sortWith", "sortBy", "sortByDescending",
        "onEach", "onEachIndexed",
        "copyOf", "copyOfRange", "fill", "replaceAll", "removeIf",
        "firstOrNull", "lastOrNull", "singleOrNull",
        "addAll", "removeAll", "retainAll",
        "intersect", "union", "subtract",
        "toHashSet",
        "containsAll", "binarySearch", "average",
        "addFirst", "addLast",
        "sum", "sumOf", "sumBy", "sumByDouble",
        "to", // FUNC-002
    ]

}
