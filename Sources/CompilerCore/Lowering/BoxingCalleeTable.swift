struct BoxingCalleeTable {
    let boxInt: InternedString
    let boxBool: InternedString
    let boxLong: InternedString
    let boxFloat: InternedString
    let boxDouble: InternedString
    let boxChar: InternedString

    let unboxInt: InternedString
    let unboxBool: InternedString
    let unboxLong: InternedString
    let unboxFloat: InternedString
    let unboxDouble: InternedString
    let unboxChar: InternedString

    init(interner: StringInterner) {
        boxInt = interner.intern("kk_box_int")
        boxBool = interner.intern("kk_box_bool")
        boxLong = interner.intern("kk_box_long")
        boxFloat = interner.intern("kk_box_float")
        boxDouble = interner.intern("kk_box_double")
        boxChar = interner.intern("kk_box_char")

        unboxInt = interner.intern("kk_unbox_int")
        unboxBool = interner.intern("kk_unbox_bool")
        unboxLong = interner.intern("kk_unbox_long")
        unboxFloat = interner.intern("kk_unbox_float")
        unboxDouble = interner.intern("kk_unbox_double")
        unboxChar = interner.intern("kk_unbox_char")
    }

    func boxCallee(for kind: TypeKind, requireNonNull: Bool) -> InternedString? {
        guard let primitive = primitiveCalleeKind(for: kind, requireNonNull: requireNonNull) else {
            return nil
        }
        switch primitive {
        case .int:
            return boxInt
        case .long:
            return boxLong
        case .boolean:
            return boxBool
        case .float:
            return boxFloat
        case .double:
            return boxDouble
        case .char:
            return boxChar
        }
    }

    func unboxCallee(for kind: TypeKind, requireNonNull: Bool) -> InternedString? {
        guard let primitive = primitiveCalleeKind(for: kind, requireNonNull: requireNonNull) else {
            return nil
        }
        switch primitive {
        case .int:
            return unboxInt
        case .long:
            return unboxLong
        case .boolean:
            return unboxBool
        case .float:
            return unboxFloat
        case .double:
            return unboxDouble
        case .char:
            return unboxChar
        }
    }

    private enum PrimitiveCalleeKind {
        case int
        case long
        case boolean
        case float
        case double
        case char
    }

    private func primitiveCalleeKind(
        for kind: TypeKind,
        requireNonNull: Bool
    ) -> PrimitiveCalleeKind? {
        guard case let .primitive(primitive, nullability) = kind else {
            return nil
        }
        if requireNonNull, nullability != .nonNull {
            return nil
        }
        switch primitive {
        case .int, .uint, .ubyte, .ushort:
            return .int
        case .long, .ulong:
            return .long
        case .boolean:
            return .boolean
        case .float:
            return .float
        case .double:
            return .double
        case .char:
            return .char
        case .string:
            return nil
        }
    }
}
