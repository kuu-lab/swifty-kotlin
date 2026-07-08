struct BoxingCalleeTable {
    private struct PrimitiveCalleeNames {
        let box: String
        let unbox: String
    }

    private struct PrimitiveCalleeRule {
        let primitives: [PrimitiveType]
        let names: PrimitiveCalleeNames
    }

    private struct InternedPrimitiveCallees {
        let box: InternedString
        let unbox: InternedString
    }

    private static let primitiveCalleeRules: [PrimitiveCalleeRule] = [
        PrimitiveCalleeRule(
            primitives: [.int, .uint, .ubyte, .ushort],
            names: PrimitiveCalleeNames(box: "kk_box_int", unbox: "kk_unbox_int")
        ),
        PrimitiveCalleeRule(
            primitives: [.long],
            names: PrimitiveCalleeNames(box: "kk_box_long", unbox: "kk_unbox_long")
        ),
        PrimitiveCalleeRule(
            primitives: [.ulong],
            names: PrimitiveCalleeNames(box: "kk_box_ulong", unbox: "kk_unbox_ulong")
        ),
        PrimitiveCalleeRule(
            primitives: [.boolean],
            names: PrimitiveCalleeNames(box: "kk_box_bool", unbox: "kk_unbox_bool")
        ),
        PrimitiveCalleeRule(
            primitives: [.float],
            names: PrimitiveCalleeNames(box: "kk_box_float", unbox: "kk_unbox_float")
        ),
        PrimitiveCalleeRule(
            primitives: [.double],
            names: PrimitiveCalleeNames(box: "kk_box_double", unbox: "kk_unbox_double")
        ),
        PrimitiveCalleeRule(
            primitives: [.char],
            names: PrimitiveCalleeNames(box: "kk_box_char", unbox: "kk_unbox_char")
        ),
    ]

    static let primitiveBoxingCalleeNamesByPrimitive: [PrimitiveType: String] = {
        var result: [PrimitiveType: String] = [:]
        for rule in primitiveCalleeRules {
            for primitive in rule.primitives {
                precondition(result[primitive] == nil, "Duplicate boxing callee rule for \(primitive)")
                result[primitive] = rule.names.box
            }
        }
        return result
    }()

    static let primitiveUnboxingCalleeNamesByPrimitive: [PrimitiveType: String] = {
        var result: [PrimitiveType: String] = [:]
        for rule in primitiveCalleeRules {
            for primitive in rule.primitives {
                precondition(result[primitive] == nil, "Duplicate unboxing callee rule for \(primitive)")
                result[primitive] = rule.names.unbox
            }
        }
        return result
    }()

    static let primitiveBoxingCalleeNames: Set<String> = Set(primitiveBoxingCalleeNamesByPrimitive.values)
    static let primitiveUnboxingCalleeNames: Set<String> = Set(primitiveUnboxingCalleeNamesByPrimitive.values)

    /// Box callees used in place of the default one when the source's static
    /// type is provably non-null (TypeKind nullability `.nonNull`).
    ///
    /// Only `.long`/`.ulong` need this: `runtimeNullSentinelInt` (Int64.min)
    /// collides bit-for-bit with a legitimate value of those two 64-bit types
    /// (Long.MIN_VALUE / ULong 2^63), so the default box callees must keep
    /// treating that bit pattern as null for callers whose source might
    /// genuinely be null (e.g. a nullable Long? argument). When the source
    /// is statically known non-null, that ambiguity can't arise, so the
    /// `_nonnull` variant boxes the value unconditionally instead of
    /// misreporting it as null. Every other primitive's box callee already
    /// handles non-null values correctly (no bit-pattern collision), so no
    /// override is needed for them.
    private static let nonNullOnlyBoxCalleeOverridesByPrimitive: [PrimitiveType: String] = [
        .long: "kk_box_long_nonnull",
        .ulong: "kk_box_ulong_nonnull",
    ]

    private let calleesByPrimitive: [PrimitiveType: InternedPrimitiveCallees]
    private let nonNullOnlyBoxOverridesByPrimitive: [PrimitiveType: InternedString]

    init(interner: StringInterner) {
        var internedByName: [String: InternedString] = [:]
        func intern(_ name: String) -> InternedString {
            if let existing = internedByName[name] {
                return existing
            }
            let interned = interner.intern(name)
            internedByName[name] = interned
            return interned
        }

        var callees: [PrimitiveType: InternedPrimitiveCallees] = [:]
        for rule in Self.primitiveCalleeRules {
            let internedCallees = InternedPrimitiveCallees(
                box: intern(rule.names.box),
                unbox: intern(rule.names.unbox)
            )
            for primitive in rule.primitives {
                precondition(callees[primitive] == nil, "Duplicate primitive boxing rule for \(primitive)")
                callees[primitive] = internedCallees
            }
        }
        calleesByPrimitive = callees

        var nonNullOverrides: [PrimitiveType: InternedString] = [:]
        for (primitive, name) in Self.nonNullOnlyBoxCalleeOverridesByPrimitive {
            nonNullOverrides[primitive] = intern(name)
        }
        nonNullOnlyBoxOverridesByPrimitive = nonNullOverrides
    }

    static func boxCalleeName(for primitive: PrimitiveType) -> String? {
        primitiveBoxingCalleeNamesByPrimitive[primitive]
    }

    static func unboxCalleeName(for primitive: PrimitiveType) -> String? {
        primitiveUnboxingCalleeNamesByPrimitive[primitive]
    }

    static func boxCalleeName(for kind: TypeKind, requireNonNull: Bool = false) -> String? {
        guard let primitive = primitive(for: kind, requireNonNull: requireNonNull) else {
            return nil
        }
        if isProvablyNonNull(kind), let override = nonNullOnlyBoxCalleeOverridesByPrimitive[primitive] {
            return override
        }
        return boxCalleeName(for: primitive)
    }

    static func unboxCalleeName(for kind: TypeKind, requireNonNull: Bool = false) -> String? {
        guard let primitive = primitive(for: kind, requireNonNull: requireNonNull) else {
            return nil
        }
        return unboxCalleeName(for: primitive)
    }

    func boxCallee(for primitive: PrimitiveType) -> InternedString? {
        calleesByPrimitive[primitive]?.box
    }

    func unboxCallee(for primitive: PrimitiveType) -> InternedString? {
        calleesByPrimitive[primitive]?.unbox
    }

    func boxCallee(for kind: TypeKind, requireNonNull: Bool) -> InternedString? {
        guard let primitive = Self.primitive(for: kind, requireNonNull: requireNonNull) else {
            return nil
        }
        if Self.isProvablyNonNull(kind), let override = nonNullOnlyBoxOverridesByPrimitive[primitive] {
            return override
        }
        return boxCallee(for: primitive)
    }

    func unboxCallee(for kind: TypeKind, requireNonNull: Bool) -> InternedString? {
        guard let primitive = Self.primitive(for: kind, requireNonNull: requireNonNull) else {
            return nil
        }
        return unboxCallee(for: primitive)
    }

    func boxCallee(for type: TypeID, types: TypeSystem, requireNonNull: Bool) -> InternedString? {
        boxCallee(for: types.kind(of: type), requireNonNull: requireNonNull)
    }

    func unboxCallee(for type: TypeID, types: TypeSystem, requireNonNull: Bool) -> InternedString? {
        unboxCallee(for: types.kind(of: type), requireNonNull: requireNonNull)
    }

    private static func isProvablyNonNull(_ kind: TypeKind) -> Bool {
        guard case let .primitive(_, nullability) = kind else {
            return false
        }
        return nullability == .nonNull
    }

    private static func primitive(
        for kind: TypeKind,
        requireNonNull: Bool
    ) -> PrimitiveType? {
        guard case let .primitive(primitive, nullability) = kind else {
            return nil
        }
        if requireNonNull, nullability != .nonNull {
            return nil
        }
        guard primitiveBoxingCalleeNamesByPrimitive[primitive] != nil else {
            return nil
        }
        return primitive
    }
}
