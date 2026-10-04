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
            primitives: [.int, .byte, .short],
            names: PrimitiveCalleeNames(box: "kk_box_int", unbox: "kk_unbox_int")
        ),
        PrimitiveCalleeRule(
            primitives: [.uint],
            names: PrimitiveCalleeNames(box: "kk_box_uint", unbox: "kk_unbox_int")
        ),
        PrimitiveCalleeRule(
            primitives: [.ubyte],
            names: PrimitiveCalleeNames(box: "kk_box_ubyte", unbox: "kk_unbox_int")
        ),
        PrimitiveCalleeRule(
            primitives: [.ushort],
            names: PrimitiveCalleeNames(box: "kk_box_ushort", unbox: "kk_unbox_int")
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

    /// Box callees used in place of the default one when the source's static
    /// type is provably non-null (TypeKind nullability `.nonNull`).
    ///
    /// Only `.long`/`.ulong`/`.double` need this: `runtimeNullSentinelInt`
    /// (Int64.min) collides bit-for-bit with a legitimate value of those
    /// 64-bit types (Long.MIN_VALUE / ULong 2^63 / Double -0.0), so the
    /// default box callees must keep treating that bit pattern as null for
    /// callers whose source might genuinely be null (e.g. a nullable Long?
    /// argument). When the source is statically known non-null, that
    /// ambiguity can't arise, so the `_nonnull` variant boxes the value
    /// unconditionally instead of misreporting it as null. Every other
    /// primitive's box callee already handles non-null values correctly
    /// (Float's bit pattern occupies only the low 32 bits), so no override
    /// is needed for them.
    private static let nonNullOnlyBoxCalleeOverridesByPrimitive: [PrimitiveType: String] = [
        .long: "kk_box_long_nonnull",
        .ulong: "kk_box_ulong_nonnull",
        .double: "kk_box_double_nonnull",
    ]

    /// ABI entry points for values whose primitive representation is known at
    /// the compiler boxing boundary. These retain the canonical Swift object
    /// box but use the tagged-handle fast path; ambiguous runtime values keep
    /// the legacy callees above.
    private static let staticPrimitiveBoxCalleeNamesByPrimitive: [PrimitiveType: String] = [
        .int: "kk_box_int_static",
        .uint: "kk_box_uint_static",
        .ubyte: "kk_box_ubyte_static",
        .ushort: "kk_box_ushort_static",
        .long: "kk_box_long_static",
        .ulong: "kk_box_ulong_static",
        .boolean: "kk_box_bool_static",
        .float: "kk_box_float_static",
        .double: "kk_box_double_static",
        .char: "kk_box_char_static",
    ]

    private static let staticPrimitiveUnboxCalleeNamesByPrimitive: [PrimitiveType: String] = [
        .int: "kk_unbox_int_static",
        .uint: "kk_unbox_int_static",
        .ubyte: "kk_unbox_int_static",
        .ushort: "kk_unbox_int_static",
        .long: "kk_unbox_long_static",
        .ulong: "kk_unbox_ulong_static",
        .boolean: "kk_unbox_bool_static",
        .float: "kk_unbox_float_static",
        .double: "kk_unbox_double_static",
        .char: "kk_unbox_char_static",
    ]

    private static let staticNonNullOnlyBoxCalleeOverridesByPrimitive: [PrimitiveType: String] = [
        .long: "kk_box_long_nonnull_static",
        .ulong: "kk_box_ulong_nonnull_static",
        .double: "kk_box_double_nonnull_static",
    ]

    private let calleesByPrimitive: [PrimitiveType: InternedPrimitiveCallees]
    private let nonNullOnlyBoxOverridesByPrimitive: [PrimitiveType: InternedString]
    private let staticBoxCalleesByPrimitive: [PrimitiveType: InternedString]
    private let staticUnboxCalleesByPrimitive: [PrimitiveType: InternedString]
    private let staticNonNullOnlyBoxOverridesByPrimitive: [PrimitiveType: InternedString]
    private let stringCallees: InternedPrimitiveCallees
    private let unitCallee: InternedString

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
        stringCallees = InternedPrimitiveCallees(
            box: intern("kk_string_from_flat"),
            unbox: intern("kk_string_to_flat")
        )
        unitCallee = intern("kk_box_unit")

        var nonNullOverrides: [PrimitiveType: InternedString] = [:]
        for (primitive, name) in Self.nonNullOnlyBoxCalleeOverridesByPrimitive {
            nonNullOverrides[primitive] = intern(name)
        }
        nonNullOnlyBoxOverridesByPrimitive = nonNullOverrides

        var staticBoxCallees: [PrimitiveType: InternedString] = [:]
        for (primitive, name) in Self.staticPrimitiveBoxCalleeNamesByPrimitive {
            staticBoxCallees[primitive] = intern(name)
        }
        staticBoxCalleesByPrimitive = staticBoxCallees

        var staticUnboxCallees: [PrimitiveType: InternedString] = [:]
        for (primitive, name) in Self.staticPrimitiveUnboxCalleeNamesByPrimitive {
            staticUnboxCallees[primitive] = intern(name)
        }
        staticUnboxCalleesByPrimitive = staticUnboxCallees

        var staticNonNullOverrides: [PrimitiveType: InternedString] = [:]
        for (primitive, name) in Self.staticNonNullOnlyBoxCalleeOverridesByPrimitive {
            staticNonNullOverrides[primitive] = intern(name)
        }
        staticNonNullOnlyBoxOverridesByPrimitive = staticNonNullOverrides
    }

    static func boxCalleeName(for primitive: PrimitiveType) -> String? {
        primitiveBoxingCalleeNamesByPrimitive[primitive]
    }

    static func unboxCalleeName(for primitive: PrimitiveType) -> String? {
        primitiveUnboxingCalleeNamesByPrimitive[primitive]
    }

    func boxCallee(for primitive: PrimitiveType) -> InternedString? {
        calleesByPrimitive[primitive]?.box
    }

    func unboxCallee(for primitive: PrimitiveType) -> InternedString? {
        calleesByPrimitive[primitive]?.unbox
    }

    func boxCallee(
        for kind: TypeKind,
        requireNonNull: Bool,
        preferStaticPrimitive: Bool = false
    ) -> InternedString? {
        if case .unit = kind {
            return unitCallee
        }
        if requireNonNull, Self.isNonNullableStringStruct(kind) {
            return stringCallees.box
        }
        guard let primitive = Self.primitive(for: kind, requireNonNull: requireNonNull) else {
            return nil
        }
        if preferStaticPrimitive {
            if Self.isProvablyNonNull(kind),
               let override = staticNonNullOnlyBoxOverridesByPrimitive[primitive]
            {
                return override
            }
            return staticBoxCalleesByPrimitive[primitive]
        }
        if Self.isProvablyNonNull(kind), let override = nonNullOnlyBoxOverridesByPrimitive[primitive] {
            return override
        }
        return boxCallee(for: primitive)
    }

    func unboxCallee(
        for kind: TypeKind,
        requireNonNull: Bool,
        preferStaticPrimitive: Bool = false
    ) -> InternedString? {
        if requireNonNull, Self.isNonNullableStringStruct(kind) {
            return stringCallees.unbox
        }
        guard let primitive = Self.primitive(for: kind, requireNonNull: requireNonNull) else {
            return nil
        }
        if preferStaticPrimitive {
            return staticUnboxCalleesByPrimitive[primitive]
        }
        return unboxCallee(for: primitive)
    }

    func boxCallee(
        for type: TypeID,
        types: TypeSystem,
        requireNonNull: Bool,
        preferStaticPrimitive: Bool = false
    ) -> InternedString? {
        boxCallee(
            for: types.kind(of: type),
            requireNonNull: requireNonNull,
            preferStaticPrimitive: preferStaticPrimitive
        )
    }

    func unboxCallee(
        for type: TypeID,
        types: TypeSystem,
        requireNonNull: Bool,
        preferStaticPrimitive: Bool = false
    ) -> InternedString? {
        unboxCallee(
            for: types.kind(of: type),
            requireNonNull: requireNonNull,
            preferStaticPrimitive: preferStaticPrimitive
        )
    }

    private static func isProvablyNonNull(_ kind: TypeKind) -> Bool {
        guard case let .primitive(_, nullability) = kind else {
            return false
        }
        return nullability == .nonNull
    }

    private static func isNonNullableStringStruct(_ kind: TypeKind) -> Bool {
        guard case let .stringStruct(nullability) = kind else {
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
