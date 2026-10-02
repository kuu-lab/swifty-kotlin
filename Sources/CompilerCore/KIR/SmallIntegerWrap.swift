/// Width restoration for Byte / Short / UByte / UShort read-modify-write arithmetic.
///
/// All runtime integers live in uniform 64-bit slots, and Sema types `x++` on these
/// widths as a plain `.binary(add)`, so the result would otherwise escape the type's
/// range (`Byte.MAX_VALUE++` -> 128). `IntegerNarrowingPass` deliberately does not
/// narrow these result types generically: Sema types `UByte + UByte` as `UByte`
/// (Kotlin: `UInt`), so a pass-level wrap would corrupt `200u.toUByte() + 200u.toUByte()`.
/// Increment / decrement / compound-assign lowering therefore wraps at the source.
enum SmallIntegerWrap {
    /// Returns the wrapped temporary, or nil when `type` is not Byte/Short/UByte/UShort.
    static func append(
        _ value: KIRExprID,
        type: TypeID,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard case let .primitive(primitive, .nonNull) = sema.types.kind(of: type) else { return nil }
        let calleeName: String
        switch primitive {
        case .byte: calleeName = "kk_int_to_byte"
        case .short: calleeName = "kk_int_to_short"
        case .ubyte: calleeName = "kk_int_to_ubyte"
        case .ushort: calleeName = "kk_int_to_ushort"
        default: return nil
        }
        let wrapped = arena.appendTemporary(type: type)
        instructions.append(.call(
            symbol: nil, callee: interner.intern(calleeName), arguments: [value], result: wrapped,
            canThrow: false, thrownResult: nil
        ))
        return wrapped
    }
}
