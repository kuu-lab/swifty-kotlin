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
    /// The nominal-name half of `rangeReceiverKind`, usable when only the
    /// static receiver *type* is known (e.g. virtual-dispatch resolution in
    /// KIR, where no source ExprID survives).
    static func rangeReceiverKind(
        for receiverType: TypeID,
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
            return nil
        }
    }

    static func rangeReceiverKind(
        receiverExpr: ExprID,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> MemberDispatchReceiverKind? {
        if let nominalKind = rangeReceiverKind(for: receiverType, sema: sema, interner: interner) {
            return nominalKind
        }
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
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

        // KSP-457: range random APIs are bundled Kotlin source wrappers. Their
        // private __kk_* calls are lowered from the source bodies, not from the
        // legacy member-dispatch table.
        if key.memberName == "random" || key.memberName == "randomOrNull" {
            return nil
        }

        switch key.memberName {
        case "contains":
            // KSP-1524: ULong membership is source-backed. The signed runtime
            // bridge cannot compare values whose high bit is set.
            if kind.isULongRangeLike { return nil }
            // KSP-1523: UIntRange used to special-case its own bridge here,
            // but this is never reached for UInt — `contains`/`isEmpty` are
            // intercepted earlier by `closedRangeInterfaceRuntimeName` in
            // CallLowerer+MemberCallDefaultsAndResolution.swift, which
            // already sends UInt through `__kk_range_contains` (confirmed by
            // marker probe).
            return "__kk_range_contains"
        case "isEmpty":
            return rangeRuntimeName(kind: kind, member: "isEmpty")
        case "endExclusive":
            return "__kk_range_endExclusive"
        case "sum":
            // KSP-1523: UInt's `sum()` is a bundled, source-backed Kotlin
            // declaration (RangeHOF.kt); `chosenCallee`'s isSourceBackedSymbol
            // check short-circuits before this is ever consulted for UInt
            // (confirmed by marker probe on both receiver shapes).
            return kind.isULongRangeLike ? nil : "__kk_range_sum"
        case "count":
            return rangeRuntimeName(kind: kind, member: "count")
        case "toList":
            return rangeRuntimeName(
                kind: kind,
                member: "toList",
                longMember: "toList",
                charMember: "toList",
                charProgressionUsesChar: true
            )
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
            // KSP-1523/KSP-1529: `MemberDispatchKey` has no notion of
            // "property read" vs. "explicit call" — only the
            // isExplicitCall check in CallLowerer+LegacyMemberLikeCalls.swift
            // can tell them apart, and it intercepts `.first()` before this
            // dispatch table is ever consulted. Keep routing arity-0 `first`
            // through the same source-backed-aware lookup as `start` so this
            // never reconstructs a `kk_uint_range_first`/`_orThrow` name for
            // a receiver kind whose HOF surface is source-backed.
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
            // See the "first" case above: same source-backed-aware lookup,
            // same reason.
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
            return rangeRuntimeName(kind: kind, member: "reversed")
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
            if kind.isULongRangeLike { return nil }
            if kind.isUIntRangeLike { return nil }
            if kind.isCharRangeLike { return "__kk_char_range_step" }
            return "__kk_op_step"
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
        case ("toDouble", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toDouble_flat", canThrow: true)
        case ("toDoubleOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toDoubleOrNull_flat")
        case ("toFloatOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toFloatOrNull_flat")
        case ("toRegex", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toRegex_flat")
        case ("firstOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_firstOrNull_flat")
        case ("lastOrNull", 0):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_lastOrNull_flat")
        case ("get", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_get_flat")
        case ("compareTo", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "kk_string_compareTo_flat")
        case ("matches", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_matches_regex_flat")
        case ("encodeToByteArray", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_encodeToByteArray_charset_flat")
        case ("toByteArray", 1):
            return MemberRuntimeCallSpec(runtimeLinkName: "__kk_string_toByteArray_charset_flat")

        default:
            return nil
        }
    }

    /// Members with bundled `RangeHOF.kt` definitions on `UIntRange` /
    /// `ULongRange` — the two types share the same source-backed HOF
    /// surface (KSP-1525 / KSP-1527 / KSP-1528).
    private static let unsignedRangeSourceBackedHOFs: Set<String> = [
        "iterator", "chunked", "windowed", "take", "drop",
        "map", "mapIndexed", "mapNotNull",
        "filter", "filterIndexed", "filterNot",
        "forEach",
        "reduce", "reduceIndexed", "fold", "foldIndexed",
        "find", "findLast",
        "first_predicate", "firstOrNull_predicate",
        "last_predicate", "lastOrNull_predicate",
        "any", "all", "none",
        "contains", "isEmpty", "firstOrNull", "lastOrNull", "count", "sum",
        "reversed", "sorted", "toList",
    ]

    /// Members with bundled `RangeHOF.kt` definitions on `UIntProgression` /
    /// `ULongProgression`.
    private static let unsignedProgressionSourceBackedHOFs: Set<String> = [
        "first", "firstOrNull", "last", "lastOrNull",
        "iterator", "chunked", "windowed", "take", "drop",
        "map", "mapIndexed", "mapNotNull",
        "filter", "filterIndexed", "filterNot",
        "contains", "isEmpty", "count", "sum", "reversed", "toList",
    ]

    /// `Progression.first` / `last` properties (never throw).
    static func rangeFirstLastPropertyLinkName(kind: MemberDispatchReceiverKind, wantLast: Bool) -> String {
        rangeFirstLastLinkName(kind: kind, wantLast: wantLast, orThrow: false)
    }

    /// `Progression.first()` / `last()` (0-arg functions). Distinct from the
    /// `first`/`last` properties, which keep the non-throwing getters.
    static func rangeFirstLastOrThrowLinkName(kind: MemberDispatchReceiverKind, wantLast: Bool) -> String {
        rangeFirstLastLinkName(kind: kind, wantLast: wantLast, orThrow: true)
    }

    private static func rangeFirstLastLinkName(
        kind: MemberDispatchReceiverKind,
        wantLast: Bool,
        orThrow: Bool
    ) -> String {
        let member = wantLast ? "last" : "first"
        if orThrow {
            if kind.isULongRangeLike {
                return "kk_ulong_range_\(member)_orThrow"
            }
            if kind.isUIntRangeLike {
                return "kk_uint_range_\(member)_orThrow"
            }
            return "__kk_range_\(member)_orThrow"
        }
        // KSP-1523/KSP-1524: the non-throwing property getter has no
        // dedicated `kk_uint_range_first`/`kk_ulong_range_first` (or `_last`)
        // entry point — both UInt and ULong share the common `__kk_range_*`
        // bridge with signed ranges. The raw bits stored in the box are
        // reinterpreted by the caller, so no unsigned-specific comparison is
        // needed for a plain getter (unlike `contains`, which does need one).
        return "__kk_range_\(member)"
    }

    private static func rangeRuntimeName(
        kind: MemberDispatchReceiverKind,
        member: String,
        longMember: String? = nil,
        charMember: String? = nil,
        charProgressionUsesChar: Bool = false
    ) -> String? {
        if kind == .charRange || (kind == .charProgression && charProgressionUsesChar), let charMember {
            return "__kk_char_range_\(charMember)"
        }
        if kind == .ulongRange && Self.unsignedRangeSourceBackedHOFs.contains(member) {
            return nil
        }
        if (kind == .ulongProgression || kind == .uintProgression)
            && Self.unsignedProgressionSourceBackedHOFs.contains(member)
        {
            return nil
        }
        if kind.isULongRangeLike, member == "first" || member == "last" {
            return "__kk_range_\(member)"
        }
        if kind.isULongRangeLike {
            if member == "average" { return nil }
            return "kk_ulong_range_\(member)"
        }
        if kind == .uintRange {
            let sourceBacked = Self.unsignedRangeSourceBackedHOFs.union([
                // KSP-1523: none of these should ever reach the interpolated
                // fallback below — the isSourceBackedSymbol short-circuit in
                // CallLowerer+MemberCallDefaultsAndResolution.swift always
                // fires first. `isEmpty`/`count`/`toList`/`sorted`/`reversed`
                // are bundled RangeHOF.kt declarations; `first`/`last` are
                // synthetic property-shell members resolved earlier via
                // CallLowerer+LegacyMemberLikeCalls.swift; `average` has no
                // bundled declaration at all — real kotlinc rejects
                // `UIntRange.average()` (see RangeHOF.kt), so it's simply
                // unresolved at TypeCheck and never lowered. Listed here
                // anyway so the interpolated `"kk_uint_range_\(member)"`
                // below can never reconstruct a name for a symbol that no
                // longer exists in Runtime, even in that unreachable case.
                "first", "last", "firstOrNull", "lastOrNull",
                "isEmpty", "count", "toList", "average", "sorted", "reversed",
            ])
            if sourceBacked.contains(member) {
                return nil
            }
        }
        if kind.isUIntRangeLike {
            return "kk_uint_range_\(member)"
        }

        // KSP-453: IntRange/IntProgression HOFs are now implemented in bundled
        // Kotlin source (RangeHOF.kt) and must not be routed to the legacy
        // kk_range_* runtime entry points.
        if kind == .intRange || kind == .intProgression {
            let sourceBacked: Set<String> = [
                "toList", "forEach", "map", "mapIndexed", "mapNotNull",
                "filter", "filterIndexed", "filterNot",
                "reduce", "reduceIndexed", "fold", "foldIndexed",
                "find", "findLast",
                "first_predicate", "firstOrNull", "firstOrNull_predicate",
                "last_predicate", "lastOrNull", "lastOrNull_predicate",
                "any", "all", "none",
                "chunked", "windowed",
                "take", "drop", "average", "sorted",
            ]
            if sourceBacked.contains(member) {
                return nil
            }
        }

        if kind == .longProgression {
            let sourceBacked: Set<String> = ["first", "firstOrNull", "last", "lastOrNull"]
            if sourceBacked.contains(member) {
                return nil
            }
        }

        let migratedRangeMembers: Set<String> = ["first", "last", "count", "isEmpty", "reversed"]
        if migratedRangeMembers.contains(member) && !kind.isULongRangeLike && !kind.isUIntRangeLike {
            return "__kk_range_\(member)"
        }
        if kind.isLongRangeLike, let longMember {
            return "__kk_long_range_\(longMember)"
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
