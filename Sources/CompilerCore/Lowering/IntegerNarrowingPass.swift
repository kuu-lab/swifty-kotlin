
/// All runtime values in KSwiftK are stored in uniform 64-bit slots, so the
/// integer arithmetic / bitwise / shift builtins lowered by earlier passes
/// (`kk_op_add`, `kk_op_shl`, …) compute in 64 bits and never wrap at the
/// 32-bit boundary. Kotlin specifies that `Int` operations overflow using
/// two's-complement wraparound (e.g. `Int.MAX_VALUE + 1 == Int.MIN_VALUE`)
/// and that the shift operators use only the low five bits of the shift
/// distance (`1 shl 32 == 1`).
///
/// `UInt` shifts reuse the 32-bit `Int` variants (with `shr` mapped to the
/// logical `iushr`) followed by `kk_uint_narrow`, and `ULong` reuses the
/// 64-bit `Long` variants (again with `shr` mapped to `lushr`), because Kotlin
/// defines unsigned `shr` as a logical shift.
final class IntegerNarrowingPass: LoweringPass, ParallelLoweringPass {
    static let name = "IntegerNarrowing"
    static let requiredStage: KIRStage = .propertyLowered
    static let producedStage: KIRStage = .integerNarrowed

    /// `Long` variants (`kk_op_lmod`, `kk_op_lfloor_div`, …) are intentionally
    /// excluded because their result type is `Long` and they are already
    /// correct in 64 bits.
    private static let narrowingCalleeNames: Set<String> = [
        "kk_op_add", "kk_op_sub", "kk_op_mul", "kk_op_div",
        "kk_op_mod", "kk_op_floor_div", "kk_op_floor_mod",
        "kk_bitwise_and", "kk_bitwise_or", "kk_bitwise_xor",
        "kk_op_inv", "kk_op_uminus",
    ]

    /// `Int` results use 32-bit variants (mask 5 bits + narrow); `Long` results
    /// use 64-bit variants (mask 6 bits) so that distances >= 64 are well defined.
    private static let intShiftRenameNames: [String: String] = [
        "kk_op_shl": "kk_op_ishl",
        "kk_op_shr": "kk_op_ishr",
        "kk_op_ushr": "kk_op_iushr",
    ]

    private static let longShiftRenameNames: [String: String] = [
        "kk_op_shl": "kk_op_lshl",
        "kk_op_shr": "kk_op_lshr",
        "kk_op_ushr": "kk_op_lushr",
    ]

    /// `UInt`/`ULong` only declare `shl`/`shr`, and their `shr` is logical.
    private static let uintShiftRenameNames: [String: String] = [
        "kk_op_shl": "kk_op_ishl",
        "kk_op_shr": "kk_op_iushr",
    ]

    private static let ulongShiftRenameNames: [String: String] = [
        "kk_op_shl": "kk_op_lshl",
        "kk_op_shr": "kk_op_lushr",
    ]

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        guard ctx.sema != nil else { return false }
        module.ensureFeaturesScanned()
        if !module.features.isDisjoint(with: [.hasBinaryOp, .hasUnaryOp]) {
            return true
        }
        let narrowingIDs = Set(Self.narrowingCalleeNames.map { ctx.interner.intern($0) })
        let shiftIDs = Set(Self.intShiftRenameNames.keys.map { ctx.interner.intern($0) })
        return !narrowingIDs.isDisjoint(with: module.usedCallees)
            || !shiftIDs.isDisjoint(with: module.usedCallees)
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        guard let types = ctx.sema?.types else {
            module.recordLowering(Self.name)
            return
        }
        let interner = ctx.interner
        let arena = module.arena
        let narrowCallee = interner.intern("kk_int_narrow")
        let unarrowCallee = interner.intern("kk_uint_narrow")
        let invCallee = interner.intern("kk_op_inv")
        let smallUnsignedInvNarrowCallees: [PrimitiveType: InternedString] = [
            .ubyte: interner.intern("kk_int_to_ubyte"),
            .ushort: interner.intern("kk_int_to_ushort"),
        ]
        let charArithmeticAdd = interner.intern("kk_op_add")
        let charArithmeticSub = interner.intern("kk_op_sub")
        let charWrapCallee = interner.intern("kk_int_to_char")
        let narrowingIDs = Set(Self.narrowingCalleeNames.map { interner.intern($0) })
        let intShiftRenameIDs: [InternedString: InternedString] = Dictionary(
            uniqueKeysWithValues: Self.intShiftRenameNames.map { (interner.intern($0.key), interner.intern($0.value)) }
        )
        let longShiftRenameIDs: [InternedString: InternedString] = Dictionary(
            uniqueKeysWithValues: Self.longShiftRenameNames.map { (interner.intern($0.key), interner.intern($0.value)) }
        )
        let uintShiftRenameIDs: [InternedString: InternedString] = Dictionary(
            uniqueKeysWithValues: Self.uintShiftRenameNames.map { (interner.intern($0.key), interner.intern($0.value)) }
        )
        let ulongShiftRenameIDs: [InternedString: InternedString] = Dictionary(
            uniqueKeysWithValues: Self.ulongShiftRenameNames.map { (interner.intern($0.key), interner.intern($0.value)) }
        )
        let shiftRenameIDsByResultKind: [PrimitiveType: [InternedString: InternedString]] = [
            .int: intShiftRenameIDs,
            .long: longShiftRenameIDs,
            .ulong: ulongShiftRenameIDs,
        ]

        func resultPrimitive(_ result: KIRExprID?) -> PrimitiveType? {
            guard let result, let typeID = arena.exprType(result),
                  case let .primitive(primitive, _) = types.kind(of: typeID)
            else {
                return nil
            }
            return primitive
        }

        module.arena.transformFunctions { function in
            var updated = function
            var newBody = KIRLoweringEmitContext()
            newBody.instructions.reserveCapacity(function.body.count)
            for (index, instruction) in function.body.enumerated() {
                newBody.currentSourceRange = index < function.instructionLocations.count
                    ? function.instructionLocations[index]
                    : nil
                guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType) = instruction else {
                    newBody.append(instruction)
                    continue
                }

                let resultKind = resultPrimitive(result)

                func appendCall(callee newCallee: InternedString, result newResult: KIRExprID?) {
                    newBody.append(.call(
                        symbol: symbol, callee: newCallee, arguments: arguments, result: newResult,
                        canThrow: canThrow, thrownResult: thrownResult,
                        isSuperCall: isSuperCall, qualifiedSuperType: qualifiedSuperType
                    ))
                }

                func appendWrappedCall(opCallee: InternedString, wrapCallee: InternedString, result: KIRExprID, fallbackType: TypeID? = nil) {
                    let rawResult = arena.appendTemporary(type: arena.exprType(result) ?? fallbackType)
                    appendCall(callee: opCallee, result: rawResult)
                    newBody.append(.call(
                        callee: wrapCallee, arguments: [rawResult], result: result,
                        canThrow: false
                    ))
                }

                if callee == invCallee, let result, let resultKind,
                   let wrapCallee = smallUnsignedInvNarrowCallees[resultKind]
                {
                    appendWrappedCall(opCallee: callee, wrapCallee: wrapCallee, result: result)
                    continue
                }

                if let resultKind, let renamed = shiftRenameIDsByResultKind[resultKind]?[callee] {
                    appendCall(callee: renamed, result: result)
                    continue
                }
                // The 32-bit variants sign-extend their result; masking the low
                // 32 bits afterwards yields the zero-extended `UInt` slot value.
                if resultKind == .uint, let result, let renamed = uintShiftRenameIDs[callee] {
                    appendWrappedCall(opCallee: renamed, wrapCallee: unarrowCallee, result: result, fallbackType: types.uintType)
                    continue
                }

                if narrowingIDs.contains(callee), let result, resultKind == .int {
                    appendWrappedCall(opCallee: callee, wrapCallee: narrowCallee, result: result, fallbackType: types.intType)
                    continue
                }

                if callee == charArithmeticAdd || callee == charArithmeticSub, let result, resultKind == .char {
                    appendWrappedCall(opCallee: callee, wrapCallee: charWrapCallee, result: result, fallbackType: types.charType)
                    continue
                }

                if narrowingIDs.contains(callee), let result, resultKind == .uint {
                    appendWrappedCall(opCallee: callee, wrapCallee: unarrowCallee, result: result, fallbackType: types.uintType)
                    continue
                }

                newBody.append(instruction)
            }
            updated.replaceBody(newBody)
            return updated
        }
        module.recordLowering(Self.name)
    }
}
