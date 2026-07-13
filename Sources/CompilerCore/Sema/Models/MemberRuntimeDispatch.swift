import RuntimeABI

enum MemberDispatchReceiverKind: String, Equatable, Hashable {
    case intRange
    case longRange
    case charRange
    case uintRange
    case ulongRange
    case intProgression
    case longProgression
    case charProgression
    case uintProgression
    case ulongProgression
    case iterable
    case list
    case set
    case collection
    case map
    case sequence
    case string
    case charSequence

    var isCharRangeLike: Bool {
        self == .charRange || self == .charProgression
    }

    var isLongRangeLike: Bool {
        self == .longRange || self == .longProgression
    }

    var isUIntRangeLike: Bool {
        self == .uintRange || self == .uintProgression
    }

    var isULongRangeLike: Bool {
        self == .ulongRange || self == .ulongProgression
    }
}

enum MemberDispatchLambdaShape: String, Equatable, Hashable {
    case none
    case hofLambda
}

enum MemberRuntimeArgumentMode: String, Equatable, Hashable {
    case lowered
    case normalized
}

enum MemberRuntimeThrownResultMode: String, Equatable, Hashable {
    case none
    case nullableAny
}

struct MemberRuntimeCallSpec: Equatable, Hashable {
    let runtimeLinkName: String
    let canThrow: Bool
    let argumentMode: MemberRuntimeArgumentMode
    let thrownResultMode: MemberRuntimeThrownResultMode

    init(
        runtimeLinkName: String,
        canThrow: Bool = false,
        argumentMode: MemberRuntimeArgumentMode = .lowered,
        thrownResultMode: MemberRuntimeThrownResultMode = .none
    ) {
        self.runtimeLinkName = runtimeLinkName
        self.canThrow = canThrow
        self.argumentMode = argumentMode
        self.thrownResultMode = thrownResultMode
    }
}

struct MemberDispatchKey: Equatable, Hashable, CustomStringConvertible {
    let receiverKind: MemberDispatchReceiverKind
    let memberName: String
    let arity: Int
    let lambdaShape: MemberDispatchLambdaShape

    init(
        receiverKind: MemberDispatchReceiverKind,
        memberName: String,
        arity: Int,
        lambdaShape: MemberDispatchLambdaShape = .none
    ) {
        self.receiverKind = receiverKind
        self.memberName = memberName
        self.arity = arity
        self.lambdaShape = lambdaShape
    }

    var description: String {
        return "\(receiverKind).\(memberName):\(arity) \(lambdaShape)"
    }
}

enum MemberRuntimeDispatch {
    static func rangeReceiverKind(
        receiverExpr: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> MemberDispatchReceiverKind? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        let nominalName: String? = {
            guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) else {
                return nil
            }
            return interner.resolve(symbol.name)
        }()

        switch nominalName {
        case "IntProgression":
            return .intProgression
        case "LongProgression":
            return .longProgression
        case "CharProgression":
            return .charProgression
        case "UIntProgression":
            return .uintProgression
        case "ULongProgression":
            return .ulongProgression
        case "IntRange":
            return .intRange
        case "LongRange":
            return .longRange
        case "CharRange":
            return .charRange
        case "UIntRange":
            return .uintRange
        case "ULongRange":
            return .ulongRange
        default:
            break
        }

        guard sema.bindings.isRangeExpr(receiverExpr) else {
            return nil
        }
        if sema.bindings.isCharRangeExpr(receiverExpr) {
            return .charRange
        }
        if sema.bindings.isULongRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.ulongType {
            return .ulongRange
        }
        if sema.bindings.isUIntRangeExpr(receiverExpr) || nonNullReceiverType == sema.types.uintType {
            return .uintRange
        }
        if nonNullReceiverType == sema.types.longType {
            return .longRange
        }
        return .intRange
    }

    static func collectionReceiverKind(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> MemberDispatchReceiverKind? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) else {
            return nil
        }

        let knownNames = KnownCompilerNames(interner: interner)
        switch knownNames.collectionKind(of: symbol) {
        case .map?:
            return .map
        case .set?:
            return .set
        case .list?:
            return .list
        case .collection?:
            return .collection
        case .sequence?:
            return .sequence
        case .array?, nil:
            break
        }

        if symbol.name == interner.intern("Iterable")
            || symbol.fqName == [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern("Iterable"),
            ]
        {
            return .iterable
        }
        return nil
    }

    static func stringReceiverKind(
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> MemberDispatchReceiverKind? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if sema.types.isSubtype(nonNullReceiverType, sema.types.stringType) {
            return .string
        }
        if let charSequenceSymbol = sema.types.charSequenceInterfaceSymbol,
           case let .classType(classType) = sema.types.kind(of: nonNullReceiverType),
           classType.classSymbol == charSequenceSymbol
        {
            return .charSequence
        }
        return nil
    }

    static func rangeRuntimeLinkName(for key: MemberDispatchKey) -> String? {
        let kind = key.receiverKind
        let hasArgument = key.arity > 0

        switch key.memberName {
        case "random":
            if hasArgument {
                if kind.isCharRangeLike { return "kk_char_range_random_random" }
                return rangeRuntimeName(kind: kind, member: "random_random", longMember: "random_random")
            }
            return rangeRuntimeName(kind: kind, member: "random", longMember: "random")
        case "randomOrNull":
            if kind == .charRange {
                return hasArgument ? "kk_char_range_randomOrNull_random" : "kk_char_range_randomOrNull"
            }
            return rangeRuntimeName(
                kind: kind,
                member: hasArgument ? "randomOrNull_random" : "randomOrNull",
                longMember: hasArgument ? "randomOrNull_random" : "randomOrNull"
            )
        case "contains":
            if kind.isULongRangeLike { return "kk_ulong_range_contains" }
            if kind.isUIntRangeLike { return "kk_uint_range_contains" }
            if kind.isLongRangeLike { return "kk_long_range_contains" }
            return "kk_op_contains"
        case "isEmpty":
            return rangeRuntimeName(
                kind: kind,
                member: "isEmpty",
                longMember: "isEmpty",
                charMember: "isEmpty",
                charProgressionUsesChar: true
            )
        case "endExclusive":
            return "kk_range_endExclusive"
        case "sum":
            if kind.isUIntRangeLike { return "kk_uint_range_sum" }
            return "kk_range_sum"
        case "count":
            return rangeRuntimeName(kind: kind, member: "count", longMember: "count")
        case "toList":
            return rangeRuntimeName(
                kind: kind,
                member: "toList",
                longMember: "toList",
                charMember: "toList",
                charProgressionUsesChar: true
            )
        case "toUIntArray":
            return "kk_uint_range_toUIntArray"
        case "toULongArray":
            return "kk_ulong_range_toULongArray"
        case "toLongArray":
            return "kk_long_range_toLongArray"
        case "iterator":
            return rangeRuntimeName(kind: kind, member: "iterator", longMember: "iterator")
        case "forEach":
            return rangeRuntimeName(kind: kind, member: "forEach", longMember: "forEach")
        case "map":
            return rangeRuntimeName(kind: kind, member: "map", longMember: "map")
        case "mapIndexed":
            return rangeRuntimeName(kind: kind, member: "mapIndexed")
        case "mapNotNull":
            return rangeRuntimeName(kind: kind, member: "mapNotNull")
        case "filter":
            return rangeRuntimeName(kind: kind, member: "filter")
        case "filterIndexed":
            return rangeRuntimeName(kind: kind, member: "filterIndexed")
        case "filterNot":
            return rangeRuntimeName(kind: kind, member: "filterNot")
        case "reduce":
            return rangeRuntimeName(kind: kind, member: "reduce")
        case "reduceIndexed":
            return rangeRuntimeName(kind: kind, member: "reduceIndexed")
        case "fold":
            return rangeRuntimeName(kind: kind, member: "fold")
        case "foldIndexed":
            return rangeRuntimeName(kind: kind, member: "foldIndexed")
        case "find":
            return rangeRuntimeName(kind: kind, member: "find")
        case "findLast":
            return rangeRuntimeName(kind: kind, member: "findLast")
        case "first":
            if key.arity > 0 {
                return rangeRuntimeName(kind: kind, member: "first_predicate")
            }
            return rangeRuntimeName(kind: kind, member: "first", longMember: "first")
        case "start":
            return rangeRuntimeName(kind: kind, member: "first", longMember: "first")
        case "firstOrNull":
            if key.arity == 0 {
                return rangeRuntimeName(kind: kind, member: "firstOrNull", longMember: "firstOrNull")
            }
            return rangeRuntimeName(kind: kind, member: "firstOrNull_predicate")
        case "last":
            if key.arity > 0 {
                return rangeRuntimeName(kind: kind, member: "last_predicate")
            }
            return rangeRuntimeName(kind: kind, member: "last", longMember: "last")
        case "end":
            return rangeRuntimeName(kind: kind, member: "last", longMember: "last")
        case "lastOrNull":
            if key.arity == 0 {
                return rangeRuntimeName(kind: kind, member: "lastOrNull", longMember: "lastOrNull")
            }
            return rangeRuntimeName(kind: kind, member: "lastOrNull_predicate")
        case "any":
            return rangeRuntimeName(kind: kind, member: "any")
        case "all":
            return rangeRuntimeName(kind: kind, member: "all")
        case "none":
            return rangeRuntimeName(kind: kind, member: "none")
        case "chunked":
            return rangeRuntimeName(kind: kind, member: "chunked")
        case "windowed":
            return rangeRuntimeName(kind: kind, member: "windowed")
        case "take":
            return rangeRuntimeName(kind: kind, member: "take", longMember: "take", charMember: "take")
        case "drop":
            return rangeRuntimeName(kind: kind, member: "drop", longMember: "drop", charMember: "drop")
        case "average":
            return rangeRuntimeName(kind: kind, member: "average", longMember: "average")
        case "sorted":
            return rangeRuntimeName(kind: kind, member: "sorted", longMember: "sorted", charMember: "sorted")
        case "reversed":
            return rangeRuntimeName(kind: kind, member: "reversed", longMember: "reversed")
        case "step":
            if key.arity == 0 {
                return rangeRuntimeName(
                    kind: kind,
                    member: "step",
                    longMember: "step",
                    charMember: "step",
                    charProgressionUsesChar: true
                )
            }
            if kind.isULongRangeLike { return "kk_ulong_step" }
            if kind.isUIntRangeLike { return "kk_uint_step" }
            if kind.isCharRangeLike { return "kk_char_range_step" }
            return "kk_op_step"
        default:
            return nil
        }
    }

    static func collectionRuntimeLinkName(for key: MemberDispatchKey) -> String? {
        guard let ownerKind = stdlibSurfaceOwnerKind(for: key.receiverKind) else {
            return nil
        }
        return StdlibSurfaceSpec.collectionHOFMember(
            ownerKind: ownerKind,
            memberName: key.memberName,
            arity: key.arity
        )?.runtimeLinkName
    }

    static func stringRuntimeCall(for key: MemberDispatchKey) -> MemberRuntimeCallSpec? {
        guard key.receiverKind == .string else {
            return nil
        }

        switch (key.memberName, key.arity) {
        case ("lowercase", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_lowercase_flat")
        case ("uppercase", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_uppercase_flat")
        case ("toInt", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_toInt_flat", canThrow: true)
        case ("toIntOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_toIntOrNull_flat")
        case ("toDouble", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toDouble_flat", canThrow: true)
        case ("toDoubleOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toDoubleOrNull_flat")
        case ("toFloatOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toFloatOrNull_flat")
        case ("toList", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_toList_flat")
        case ("toMutableList", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_toMutableList")
        case ("toSortedSet", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_toSortedSet_flat")
        case ("asIterable", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_asIterable_flat")
        case ("toCharArray", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_toCharArray_flat")
        case ("toRegex", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_toRegex_flat")
        case ("lines", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_lines_flat")
        case ("lineSequence", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_lineSequence_flat")
        case ("firstOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_firstOrNull_flat")
        case ("lastOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_lastOrNull_flat")
        case ("zipWithNext", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_zipWithNext_flat")
        case ("asSequence", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_asSequence_flat")
        case ("withIndex", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_withIndex_flat")
        case ("trimIndent", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_trimIndent_flat")
        case ("trimMargin", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_trimMargin_default_flat")
        case ("prependIndent", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_prependIndent_default_flat")
        case ("replaceIndent", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_replaceIndent_default_flat")
        case ("toInt", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_toInt_radix_flat", canThrow: true)
        case ("windowed", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_windowed_default_flat")
        case ("startsWith", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_startsWith_flat")
        case ("endsWith", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_endsWith_flat")
        case ("lastIndexOf", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_lastIndexOf_flat")
        case ("get", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_get_flat")
        case ("compareTo", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_compareTo_flat")
        case ("matches", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_matches_regex_flat")
        case ("mapIndexed", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_mapIndexed_flat", argumentMode: .normalized)
        case ("mapNotNull", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_mapNotNull_flat", argumentMode: .normalized)
        case ("filterIndexed", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_filterIndexed_flat", argumentMode: .normalized)
        case ("filterNot", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_filterNot_flat", argumentMode: .normalized)
        case ("count", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_count_flat", argumentMode: .normalized)
        case ("any", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_any_flat", argumentMode: .normalized)
        case ("all", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_all_flat", argumentMode: .normalized)
        case ("none", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_none_flat", argumentMode: .normalized)
        case ("indexOfFirst", 1):
            return MemberRuntimeCallSpec(
                runtimeLinkName: "kk_string_indexOfFirst_flat",
                canThrow: true,
                argumentMode: .normalized
            )
        case ("indexOfLast", 1):
            return MemberRuntimeCallSpec(
                runtimeLinkName: "kk_string_indexOfLast_flat",
                canThrow: true,
                argumentMode: .normalized
            )
        case ("takeWhile", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_takeWhile_flat", argumentMode: .normalized)
        case ("takeLastWhile", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_takeLastWhile_flat", argumentMode: .normalized)
        case ("dropWhile", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_dropWhile_flat", argumentMode: .normalized)
        case ("find", 1):
            return MemberRuntimeCallSpec(
                runtimeLinkName: "kk_string_find_flat",
                canThrow: true,
                argumentMode: .normalized
            )
        case ("findLast", 1):
            return MemberRuntimeCallSpec(
                runtimeLinkName: "kk_string_findLast_flat",
                canThrow: true,
                argumentMode: .normalized
            )
        case ("partition", 1):
            return MemberRuntimeCallSpec(
                runtimeLinkName: "kk_string_partition_flat",
                canThrow: true,
                argumentMode: .normalized,
                thrownResultMode: .nullableAny
            )
        case ("chunked", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_chunked_flat")
        case ("chunkedSequence", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_chunked_sequence_flat")
        case ("encodeToByteArray", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_encodeToByteArray_charset_flat")
        case ("toByteArray", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toByteArray_charset_flat")
        case ("removePrefix", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_removePrefix_flat")
        case ("removeSuffix", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_removeSuffix_flat")
        case ("removeSurrounding", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_removeSurrounding_flat")
        case ("trimMargin", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_trimMargin_flat")
        case ("prependIndent", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_prependIndent_flat")
        case ("replaceIndent", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_replaceIndent_flat")
        case ("take", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_take_flat", canThrow: true)
        case ("drop", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_drop_flat", canThrow: true)
        case ("takeLast", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_takeLast_flat", canThrow: true)
        case ("dropLast", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_dropLast_flat", canThrow: true)
        case ("removeRange", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_removeRange_range_flat", canThrow: true)
        case ("toCollection", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_toCollection_flat")

        case ("subSequence", 2):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_subSequence_flat", canThrow: true)
        case ("windowed", 2):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_windowed_flat")
        case ("compareTo", 2):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_compareToIgnoreCase_flat")
        case ("replaceIndentByMargin", 2):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_replaceIndentByMargin_flat")
        case ("removeSurrounding", 2):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_removeSurrounding_pair_flat")
        case ("removeRange", 2):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_removeRange_flat", canThrow: true)
        case ("replaceRange", 2):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_replaceRange_flat", canThrow: true)

        case ("windowed", 3):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_windowed_partial_flat")
        case ("windowedSequence", 3):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_windowedSequence_partial_flat")
        default:
            return nil
        }
    }

    private static func rangeRuntimeName(
        kind: MemberDispatchReceiverKind,
        member: String,
        longMember: String? = nil,
        charMember: String? = nil,
        charProgressionUsesChar: Bool = false
    ) -> String {
        if kind == .charRange || (kind == .charProgression && charProgressionUsesChar), let charMember {
            return "kk_char_range_\(charMember)"
        }
        if kind.isULongRangeLike {
            return "kk_ulong_range_\(member)"
        }
        if kind.isUIntRangeLike {
            return "kk_uint_range_\(member)"
        }
        if kind.isLongRangeLike, let longMember {
            return "kk_long_range_\(longMember)"
        }
        return "kk_range_\(member)"
    }

    private static func stdlibSurfaceOwnerKind(
        for receiverKind: MemberDispatchReceiverKind
    ) -> StdlibSurfaceOwnerKind? {
        switch receiverKind {
        case .map:
            return .map
        case .sequence:
            return .sequence
        case .iterable, .list, .set, .collection:
            return .list
        default:
            return nil
        }
    }
}
