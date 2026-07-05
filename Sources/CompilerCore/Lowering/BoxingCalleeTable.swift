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
            primitives: [.long, .ulong],
            names: PrimitiveCalleeNames(box: "kk_box_long", unbox: "kk_unbox_long")
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

    private let calleesByPrimitive: [PrimitiveType: InternedPrimitiveCallees]

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
