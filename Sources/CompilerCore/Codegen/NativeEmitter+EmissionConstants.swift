#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

extension NativeEmitter {
    struct EmissionBuilderState {
        let builder: LLVMCAPIBindings.LLVMBuilderRef
        let int64Type: LLVMCAPIBindings.LLVMTypeRef
        let zeroValue: LLVMCAPIBindings.LLVMValueRef
        let context: LLVMCAPIBindings.LLVMContextRef?
        let module: LLVMCAPIBindings.LLVMModuleRef?
        let typeLowering: LLVMTypeLowering?

        init(
            builder: LLVMCAPIBindings.LLVMBuilderRef,
            int64Type: LLVMCAPIBindings.LLVMTypeRef,
            zeroValue: LLVMCAPIBindings.LLVMValueRef,
            context: LLVMCAPIBindings.LLVMContextRef? = nil,
            module: LLVMCAPIBindings.LLVMModuleRef? = nil,
            typeLowering: LLVMTypeLowering? = nil
        ) {
            self.builder = builder
            self.int64Type = int64Type
            self.zeroValue = zeroValue
            self.context = context
            self.module = module
            self.typeLowering = typeLowering
        }
    }

    // swiftlint:disable cyclomatic_complexity
    func lowerBuiltinCall(
        calleeName: String,
        argumentValues: [LLVMCAPIBindings.LLVMValueRef],
        argumentTypes: [TypeID?] = [],
        resultType: TypeID? = nil,
        state: EmissionBuilderState,
        instructionIndex: Int
    ) -> (handled: Bool, value: LLVMCAPIBindings.LLVMValueRef?) {
        let lhs = argumentValues.count > 0 ? argumentValues[0] : state.zeroValue
        let rhs = argumentValues.count > 1 ? argumentValues[1] : state.zeroValue

        func isStringAggregateType(_ type: TypeID?) -> Bool {
            guard let type,
                  let typeSystem,
                  case .stringStruct = typeSystem.kind(of: type)
            else {
                return false
            }
            return state.typeLowering != nil
        }

        func stringAggregateFields(
            _ value: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) -> [LLVMCAPIBindings.LLVMValueRef]? {
            guard let data = bindings.buildExtractValue(state.builder, aggregate: value, index: 0, name: "str_data_\(suffix)"),
                  let length = bindings.buildExtractValue(state.builder, aggregate: value, index: 1, name: "str_length_\(suffix)"),
                  let byteCount = bindings.buildExtractValue(state.builder, aggregate: value, index: 2, name: "str_bytes_\(suffix)"),
                  let hash = bindings.buildExtractValue(state.builder, aggregate: value, index: 3, name: "str_hash_\(suffix)")
            else {
                return nil
            }
            return [data, length, byteCount, hash]
        }

        func declareTypedExternalFunction(
            named name: String,
            parameterTypes: [LLVMCAPIBindings.LLVMTypeRef?],
            returnType: LLVMCAPIBindings.LLVMTypeRef?
        ) -> LLVMFunction? {
            guard let externalType = bindings.functionType(
                returnType: returnType,
                parameters: parameterTypes,
                isVarArg: false
            ) else {
                return nil
            }
            let externalValue = bindings.getNamedFunction(module: state.module, name: name)
                ?? bindings.addFunction(module: state.module, name: name, functionType: externalType)
            guard let externalValue else {
                return nil
            }
            return LLVMFunction(value: externalValue, type: externalType)
        }

        func bridgeStringAggregateToRuntimeRaw(
            _ value: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let typeLowering = state.typeLowering,
                  let fields = stringAggregateFields(value, suffix: "\(suffix)_to_raw"),
                  let bridgeFunction = declareTypedExternalFunction(
                      named: "kk_string_from_flat",
                      parameterTypes: [
                          typeLowering.dataPointerType,
                          state.int64Type,
                          state.int64Type,
                          state.int64Type,
                      ],
                      returnType: state.int64Type
                  )
            else {
                return nil
            }
            return bindings.buildCall(
                state.builder,
                functionType: bridgeFunction.type,
                callee: bridgeFunction.value,
                arguments: fields,
                name: "string_raw_\(suffix)"
            ).flatMap { raw in
                // String? uses null data in aggregate form and the runtime null
                // sentinel at erased/raw boundaries.
                guard let nullData = bindings.constPointerNull(typeLowering.dataPointerType),
                      let isNull = bindings.buildICmpEqual(
                          state.builder,
                          lhs: fields[0],
                          rhs: nullData,
                          name: "string_raw_isnull_\(suffix)"
                      ),
                      let sentinel = bindings.constInt(state.int64Type, value: UInt64(bitPattern: Int64.min), signExtend: true)
                else {
                    return raw
                }
                return bindings.buildSelect(
                    state.builder,
                    condition: isNull,
                    thenValue: sentinel,
                    elseValue: raw,
                    name: "string_raw_nullable_\(suffix)"
                ) ?? raw
            }
        }

        func bridgeRuntimeRawToStringAggregate(
            _ raw: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let typeLowering = state.typeLowering,
                  let pointerType = bindings.pointerType(state.int64Type, addressSpace: 0),
                  let lengthSlot = bindings.buildAlloca(state.builder, type: state.int64Type, name: "string_bridge_length_\(suffix)"),
                  let byteCountSlot = bindings.buildAlloca(state.builder, type: state.int64Type, name: "string_bridge_bytes_\(suffix)"),
                  let hashSlot = bindings.buildAlloca(state.builder, type: state.int64Type, name: "string_bridge_hash_\(suffix)")
            else {
                return nil
            }
            _ = bindings.buildStore(state.builder, value: state.zeroValue, pointer: lengthSlot)
            _ = bindings.buildStore(state.builder, value: state.zeroValue, pointer: byteCountSlot)
            _ = bindings.buildStore(state.builder, value: state.zeroValue, pointer: hashSlot)
            guard let bridgeFunction = declareTypedExternalFunction(
                named: "kk_string_to_flat",
                parameterTypes: [
                    state.int64Type,
                    pointerType,
                    pointerType,
                    pointerType,
                ],
                returnType: typeLowering.dataPointerType
            ),
                let data = bindings.buildCall(
                    state.builder,
                    functionType: bridgeFunction.type,
                    callee: bridgeFunction.value,
                    arguments: [raw, lengthSlot, byteCountSlot, hashSlot],
                    name: "string_bridge_data_\(suffix)"
                ),
                let length = bindings.buildLoad(
                    state.builder,
                    type: state.int64Type,
                    pointer: lengthSlot,
                    name: "string_bridge_length_val_\(suffix)"
                ),
                let byteCount = bindings.buildLoad(
                    state.builder,
                    type: state.int64Type,
                    pointer: byteCountSlot,
                    name: "string_bridge_bytes_val_\(suffix)"
                ),
                let hash = bindings.buildLoad(
                    state.builder,
                    type: state.int64Type,
                    pointer: hashSlot,
                    name: "string_bridge_hash_val_\(suffix)"
                )
            else {
                return nil
            }
            return buildStringAggregate(
                builder: state.builder,
                lowering: typeLowering,
                data: data,
                length: length,
                byteCount: byteCount,
                hash: hash,
                name: "string_bridge_\(suffix)"
            )
        }

        func boolCondition(
            from value: LLVMCAPIBindings.LLVMValueRef,
            name: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            bindings.buildICmpNotEqual(state.builder, lhs: value, rhs: state.zeroValue, name: name)
        }

        func buildSignedFloorMod(name: String) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let quotient = bindings.buildSDiv(state.builder, lhs: lhs, rhs: rhs, name: "\(name)_q_\(instructionIndex)"),
                  let product = bindings.buildMul(state.builder, lhs: quotient, rhs: rhs, name: "\(name)_p_\(instructionIndex)"),
                  let remainder = bindings.buildSub(state.builder, lhs: lhs, rhs: product, name: "\(name)_rem_\(instructionIndex)"),
                  let remainderIsNonZero = bindings.buildICmpNotEqual(state.builder, lhs: remainder, rhs: state.zeroValue, name: "\(name)_nonzero_\(instructionIndex)"),
                  let lhsIsNegative = bindings.buildICmpSignedLessThan(state.builder, lhs: lhs, rhs: state.zeroValue, name: "\(name)_lhs_neg_\(instructionIndex)"),
                  let rhsIsNegative = bindings.buildICmpSignedLessThan(state.builder, lhs: rhs, rhs: state.zeroValue, name: "\(name)_rhs_neg_\(instructionIndex)"),
                  let signsDiffer = bindings.buildXor(state.builder, lhs: lhsIsNegative, rhs: rhsIsNegative, name: "\(name)_signs_\(instructionIndex)"),
                  let shouldAdjust = bindings.buildAnd(state.builder, lhs: remainderIsNonZero, rhs: signsDiffer, name: "\(name)_adjust_\(instructionIndex)"),
                  let adjusted = bindings.buildAdd(state.builder, lhs: remainder, rhs: rhs, name: "\(name)_adjusted_\(instructionIndex)")
            else {
                return nil
            }
            return bindings.buildSelect(
                state.builder,
                condition: shouldAdjust,
                thenValue: adjusted,
                elseValue: remainder,
                name: "\(name)_\(instructionIndex)"
            )
        }

        // Sign-extend the low 32 bits of a 64-bit slot back into a canonical
        // 64-bit representation of a Kotlin `Int`. Implemented as
        // `(value << 32) >>a 32` so it needs no dedicated i32 type / SExt
        // binding. This enforces Kotlin's two's-complement `Int` wraparound.
        func narrowTo32(_ value: LLVMCAPIBindings.LLVMValueRef?, name: String) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let value,
                  let thirtyTwo = bindings.constInt(state.int64Type, value: 32),
                  let widened = bindings.buildShl(state.builder, lhs: value, rhs: thirtyTwo, name: "\(name)_w_\(instructionIndex)")
            else {
                return nil
            }
            return bindings.buildAShr(state.builder, lhs: widened, rhs: thirtyTwo, name: "\(name)_\(instructionIndex)")
        }

        let lowered: LLVMCAPIBindings.LLVMValueRef?
        switch calleeName {
        case "__string_struct_get_length", "length":
            guard argumentValues.count == 1,
                  let firstType = argumentTypes.first.flatMap({ $0 }),
                  state.typeLowering != nil,
                  let typeSystem,
                  case .stringStruct = typeSystem.kind(of: firstType)
            else {
                return (false, nil)
            }
            lowered = bindings.buildExtractValue(
                state.builder,
                aggregate: lhs,
                index: 1,
                name: "string_length_\(instructionIndex)"
            )
        case "kk_op_add":
            lowered = bindings.buildAdd(state.builder, lhs: lhs, rhs: rhs, name: "add_\(instructionIndex)")
        case "kk_op_sub":
            lowered = bindings.buildSub(state.builder, lhs: lhs, rhs: rhs, name: "sub_\(instructionIndex)")
        case "kk_op_mul":
            lowered = bindings.buildMul(state.builder, lhs: lhs, rhs: rhs, name: "mul_\(instructionIndex)")
        case "kk_op_floor_div", "kk_op_lfloor_div":
            if let quotient = bindings.buildSDiv(state.builder, lhs: lhs, rhs: rhs, name: "floordiv_q_\(instructionIndex)"),
               let product = bindings.buildMul(state.builder, lhs: quotient, rhs: rhs, name: "floordiv_p_\(instructionIndex)"),
               let remainder = bindings.buildSub(state.builder, lhs: lhs, rhs: product, name: "floordiv_r_\(instructionIndex)"),
               let remainderNonZero = bindings.buildICmpNotEqual(state.builder, lhs: remainder, rhs: state.zeroValue, name: "floordiv_rnz_\(instructionIndex)"),
               let lhsNegative = bindings.buildICmpSignedLessThan(state.builder, lhs: lhs, rhs: state.zeroValue, name: "floordiv_lneg_\(instructionIndex)"),
               let rhsNegative = bindings.buildICmpSignedLessThan(state.builder, lhs: rhs, rhs: state.zeroValue, name: "floordiv_rneg_\(instructionIndex)"),
               let signsDiffer = bindings.buildXor(state.builder, lhs: lhsNegative, rhs: rhsNegative, name: "floordiv_sdiff_\(instructionIndex)"),
               let shouldAdjust = bindings.buildAnd(state.builder, lhs: remainderNonZero, rhs: signsDiffer, name: "floordiv_adj_\(instructionIndex)"),
               let one = bindings.constInt(state.int64Type, value: 1),
               let adjustedQuotient = bindings.buildSub(state.builder, lhs: quotient, rhs: one, name: "floordiv_dec_\(instructionIndex)")
            {
                lowered = bindings.buildSelect(
                    state.builder,
                    condition: shouldAdjust,
                    thenValue: adjustedQuotient,
                    elseValue: quotient,
                    name: "floordiv_\(instructionIndex)"
                )
            } else {
                lowered = nil
            }
        case "kk_op_udiv":
            lowered = bindings.buildUDiv(state.builder, lhs: lhs, rhs: rhs, name: "udiv_\(instructionIndex)")
        case "kk_op_floor_mod":
            lowered = buildSignedFloorMod(name: "floor_mod")
        case "kk_op_lfloor_mod":
            lowered = buildSignedFloorMod(name: "lfloor_mod")
        case "kk_op_urem":
            lowered = bindings.buildURem(state.builder, lhs: lhs, rhs: rhs, name: "urem_\(instructionIndex)")
        case "kk_op_eq":
            if let compared = bindings.buildICmpEqual(state.builder, lhs: lhs, rhs: rhs, name: "eq_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "eq64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_ne":
            if let compared = bindings.buildICmpNotEqual(state.builder, lhs: lhs, rhs: rhs, name: "ne_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "ne64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_lt":
            if let compared = bindings.buildICmpSignedLessThan(state.builder, lhs: lhs, rhs: rhs, name: "lt_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "lt64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_le":
            if let compared = bindings.buildICmpSignedLessOrEqual(state.builder, lhs: lhs, rhs: rhs, name: "le_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "le64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_gt":
            if let compared = bindings.buildICmpSignedGreaterThan(state.builder, lhs: lhs, rhs: rhs, name: "gt_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "gt64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_ge":
            if let compared = bindings.buildICmpSignedGreaterOrEqual(state.builder, lhs: lhs, rhs: rhs, name: "ge_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "ge64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_ult":
            if let compared = bindings.buildICmpUnsignedLessThan(state.builder, lhs: lhs, rhs: rhs, name: "ult_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "ult64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_ule":
            if let compared = bindings.buildICmpUnsignedLessOrEqual(state.builder, lhs: lhs, rhs: rhs, name: "ule_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "ule64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_ugt":
            if let compared = bindings.buildICmpUnsignedGreaterThan(state.builder, lhs: lhs, rhs: rhs, name: "ugt_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "ugt64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_uge":
            if let compared = bindings.buildICmpUnsignedGreaterOrEqual(state.builder, lhs: lhs, rhs: rhs, name: "uge_\(instructionIndex)") {
                lowered = bindings.buildZExt(state.builder, value: compared, type: state.int64Type, name: "uge64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_and":
            if let lhsBool = boolCondition(from: lhs, name: "and_lhs_\(instructionIndex)"),
               let rhsBool = boolCondition(from: rhs, name: "and_rhs_\(instructionIndex)"),
               let lhsInt = bindings.buildZExt(state.builder, value: lhsBool, type: state.int64Type, name: "and_lhs64_\(instructionIndex)"),
               let rhsInt = bindings.buildZExt(state.builder, value: rhsBool, type: state.int64Type, name: "and_rhs64_\(instructionIndex)")
            {
                lowered = bindings.buildMul(state.builder, lhs: lhsInt, rhs: rhsInt, name: "and64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_or":
            if let lhsBool = boolCondition(from: lhs, name: "or_lhs_\(instructionIndex)"),
               let rhsBool = boolCondition(from: rhs, name: "or_rhs_\(instructionIndex)"),
               let lhsInt = bindings.buildZExt(state.builder, value: lhsBool, type: state.int64Type, name: "or_lhs64_\(instructionIndex)"),
               let rhsInt = bindings.buildZExt(state.builder, value: rhsBool, type: state.int64Type, name: "or_rhs64_\(instructionIndex)"),
               let sum = bindings.buildAdd(state.builder, lhs: lhsInt, rhs: rhsInt, name: "or_sum_\(instructionIndex)"),
               let nonZero = bindings.buildICmpNotEqual(state.builder, lhs: sum, rhs: state.zeroValue, name: "or_nonzero_\(instructionIndex)")
            {
                lowered = bindings.buildZExt(state.builder, value: nonZero, type: state.int64Type, name: "or64_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_bitwise_and":
            lowered = bindings.buildAnd(state.builder, lhs: lhs, rhs: rhs, name: "bitand_\(instructionIndex)")
        case "kk_bitwise_or":
            lowered = bindings.buildOr(state.builder, lhs: lhs, rhs: rhs, name: "bitor_\(instructionIndex)")
        case "kk_bitwise_xor":
            lowered = bindings.buildXor(state.builder, lhs: lhs, rhs: rhs, name: "bitxor_\(instructionIndex)")
        case "kk_op_shl":
            lowered = bindings.buildShl(state.builder, lhs: lhs, rhs: rhs, name: "shl_\(instructionIndex)")
        case "kk_op_shr":
            lowered = bindings.buildAShr(state.builder, lhs: lhs, rhs: rhs, name: "shr_\(instructionIndex)")
        case "kk_op_ushr":
            lowered = bindings.buildLShr(state.builder, lhs: lhs, rhs: rhs, name: "ushr_\(instructionIndex)")
        case "kk_int_narrow":
            // Wrap a 64-bit arithmetic result to Kotlin's 32-bit `Int`.
            lowered = narrowTo32(lhs, name: "narrow")
        case "kk_uint_narrow":
            // Mask a 64-bit arithmetic result to Kotlin's 32-bit `UInt` (zero-extend low 32 bits).
            if let mask = bindings.constInt(state.int64Type, value: 0xFFFF_FFFF) {
                lowered = bindings.buildAnd(state.builder, lhs: lhs, rhs: mask,
                                            name: "uint_narrow_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_ishl":
            // Kotlin `Int.shl`: shift distance is `rhs and 31`; result wraps to 32 bits.
            if let mask = bindings.constInt(state.int64Type, value: 31),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "ishl_amt_\(instructionIndex)"),
               let shifted = bindings.buildShl(state.builder, lhs: lhs, rhs: amount, name: "ishl_s_\(instructionIndex)")
            {
                lowered = narrowTo32(shifted, name: "ishl")
            } else {
                lowered = nil
            }
        case "kk_op_ishr":
            // Kotlin `Int.shr`: arithmetic (sign-propagating) shift by `rhs and 31`.
            if let mask = bindings.constInt(state.int64Type, value: 31),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "ishr_amt_\(instructionIndex)"),
               let signExtended = narrowTo32(lhs, name: "ishr_in")
            {
                lowered = bindings.buildAShr(state.builder, lhs: signExtended, rhs: amount, name: "ishr_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_iushr":
            // Kotlin `Int.ushr`: logical shift of the 32-bit value by `rhs and 31`.
            if let mask = bindings.constInt(state.int64Type, value: 31),
               let lowMask = bindings.constInt(state.int64Type, value: 0xFFFF_FFFF),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "iushr_amt_\(instructionIndex)"),
               let zeroExtended = bindings.buildAnd(state.builder, lhs: lhs, rhs: lowMask, name: "iushr_in_\(instructionIndex)"),
               let shifted = bindings.buildLShr(state.builder, lhs: zeroExtended, rhs: amount, name: "iushr_s_\(instructionIndex)")
            {
                lowered = narrowTo32(shifted, name: "iushr")
            } else {
                lowered = nil
            }
        case "kk_op_lshl":
            // Kotlin `Long.shl`: shift distance is `rhs and 63` (64-bit result).
            if let mask = bindings.constInt(state.int64Type, value: 63),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "lshl_amt_\(instructionIndex)")
            {
                lowered = bindings.buildShl(state.builder, lhs: lhs, rhs: amount, name: "lshl_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_lshr":
            // Kotlin `Long.shr`: arithmetic shift by `rhs and 63`.
            if let mask = bindings.constInt(state.int64Type, value: 63),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "lshr_amt_\(instructionIndex)")
            {
                lowered = bindings.buildAShr(state.builder, lhs: lhs, rhs: amount, name: "lshr_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_lushr":
            // Kotlin `Long.ushr`: logical shift by `rhs and 63`.
            if let mask = bindings.constInt(state.int64Type, value: 63),
               let amount = bindings.buildAnd(state.builder, lhs: rhs, rhs: mask, name: "lushr_amt_\(instructionIndex)")
            {
                lowered = bindings.buildLShr(state.builder, lhs: lhs, rhs: amount, name: "lushr_\(instructionIndex)")
            } else {
                lowered = nil
            }
        case "kk_op_inv":
            lowered = bindings.buildNot(state.builder, value: lhs, name: "inv_\(instructionIndex)")
        case "kk_op_elvis":
            let lhsType = argumentTypes.indices.contains(0) ? argumentTypes[0] : nil
            let rhsType = argumentTypes.indices.contains(1) ? argumentTypes[1] : nil
            let lhsIsString = isStringAggregateType(lhsType)
            let rhsIsString = isStringAggregateType(rhsType)
            let resultIsString = isStringAggregateType(resultType)
            if resultIsString {
                let lhsValue: LLVMCAPIBindings.LLVMValueRef?
                if lhsIsString {
                    lhsValue = lhs
                } else {
                    lhsValue = bridgeRuntimeRawToStringAggregate(lhs, suffix: "elvis_\(instructionIndex)_lhs")
                }
                guard let typeLowering = state.typeLowering,
                      let lhsValue,
                      let lhsData = bindings.buildExtractValue(
                          state.builder,
                          aggregate: lhsValue,
                          index: 0,
                          name: "elvis_str_data_\(instructionIndex)"
                      ),
                      let nullData = bindings.constPointerNull(typeLowering.dataPointerType),
                      let isNull = bindings.buildICmpEqual(
                          state.builder,
                          lhs: lhsData,
                          rhs: nullData,
                          name: "elvis_string_isnull_\(instructionIndex)"
                      )
                else {
                    lowered = nil
                    break
                }
                let rhsValue: LLVMCAPIBindings.LLVMValueRef?
                if rhsIsString {
                    rhsValue = rhs
                } else {
                    rhsValue = bridgeRuntimeRawToStringAggregate(rhs, suffix: "elvis_\(instructionIndex)_rhs")
                }
                if let rhsValue {
                    lowered = bindings.buildSelect(
                        state.builder,
                        condition: isNull,
                        thenValue: rhsValue,
                        elseValue: lhsValue,
                        name: "elvis_\(instructionIndex)"
                    )
                } else {
                    lowered = nil
                }
            } else {
                let lhsValue: LLVMCAPIBindings.LLVMValueRef?
                if lhsIsString {
                    lhsValue = bridgeStringAggregateToRuntimeRaw(lhs, suffix: "elvis_\(instructionIndex)_lhs")
                } else {
                    lhsValue = lhs
                }
                let sentinel = bindings.constInt(state.int64Type, value: UInt64(bitPattern: Int64.min), signExtend: true) ?? state.zeroValue
                guard let lhsValue,
                      let isNull = bindings.buildICmpEqual(
                    state.builder,
                    lhs: lhsValue,
                    rhs: sentinel,
                    name: "elvis_isnull_\(instructionIndex)"
                ) else {
                    lowered = nil
                    break
                }
                let rhsValue: LLVMCAPIBindings.LLVMValueRef?
                if rhsIsString {
                    rhsValue = bridgeStringAggregateToRuntimeRaw(rhs, suffix: "elvis_\(instructionIndex)_rhs")
                } else {
                    rhsValue = rhs
                }
                if let rhsValue {
                    lowered = bindings.buildSelect(
                        state.builder,
                        condition: isNull,
                        thenValue: rhsValue,
                        elseValue: lhsValue,
                        name: "elvis_\(instructionIndex)"
                    )
                } else {
                    lowered = nil
                }
            }
        default:
            return (false, nil)
        }
        return (true, lowered)
    }

    // swiftlint:enable cyclomatic_complexity

    func emitConstantValue(
        _ expression: KIRExprKind,
        expressionRawID: Int32?,
        expectedType: TypeID? = nil,
        state: EmissionBuilderState,
        parameterValues: [SymbolID: LLVMCAPIBindings.LLVMValueRef],
        internalFunctions: [SymbolID: LLVMFunction],
        globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:],
        generatedStringLiteralCount: inout Int32,
        declareExternalFunction: (String, Int, Bool) -> LLVMFunction?,
        interner: StringInterner
    ) -> LLVMCAPIBindings.LLVMValueRef {
        func nullStringAggregateIfExpected() -> LLVMCAPIBindings.LLVMValueRef? {
            guard let expectedType,
                  let typeLowering = state.typeLowering,
                  let typeSystem,
                  case .stringStruct = typeSystem.kind(of: expectedType)
            else {
                return nil
            }
            return buildNullStringAggregate(
                builder: state.builder,
                lowering: typeLowering,
                name: "null_string_\(expressionRawID ?? 0)"
            )
        }

        switch expression {
        case let .intLiteral(number):
            if number == 0,
               let nullString = nullStringAggregateIfExpected()
            {
                return nullString
            }
            return bindings.constInt(state.int64Type, value: UInt64(bitPattern: number), signExtend: true) ?? state.zeroValue
        case let .longLiteral(number):
            return bindings.constInt(state.int64Type, value: UInt64(bitPattern: number), signExtend: true) ?? state.zeroValue
        case let .uintLiteral(number):
            return bindings.constInt(state.int64Type, value: number, signExtend: false) ?? state.zeroValue
        case let .ulongLiteral(number):
            return bindings.constInt(state.int64Type, value: number, signExtend: false) ?? state.zeroValue
        case let .floatLiteral(value):
            var f = Float(value)
            var bits: UInt32 = 0
            memcpy(&bits, &f, MemoryLayout<UInt32>.size)
            return bindings.constInt(state.int64Type, value: UInt64(bits)) ?? state.zeroValue
        case let .doubleLiteral(value):
            var d = value
            var bits: UInt64 = 0
            memcpy(&bits, &d, MemoryLayout<UInt64>.size)
            return bindings.constInt(state.int64Type, value: bits) ?? state.zeroValue
        case let .charLiteral(scalar):
            return bindings.constInt(state.int64Type, value: UInt64(scalar)) ?? state.zeroValue
        case let .boolLiteral(value):
            return bindings.constInt(state.int64Type, value: value ? 1 : 0) ?? state.zeroValue
        case let .stringLiteral(interned):
            let text = interner.resolve(interned)
            let literalID: Int32
            if let expressionRawID {
                literalID = expressionRawID
            } else {
                literalID = generatedStringLiteralCount
                generatedStringLiteralCount += 1
            }
            guard let globalStringPointer = bindings.buildGlobalStringPtrNullSafe(
                state.builder,
                context: state.context,
                module: state.module,
                value: text,
                name: "str_lit_\(literalID)"
            ) else {
                return state.zeroValue
            }
            if let expectedType,
               let typeLowering = state.typeLowering,
               let typeSystem,
               case .stringStruct = typeSystem.kind(of: expectedType)
            {
                let lengthValue = bindings.constInt(state.int64Type, value: UInt64(text.utf8.count)) ?? state.zeroValue
                let byteCountValue = bindings.constInt(state.int64Type, value: UInt64(text.utf8.count)) ?? state.zeroValue
                let hashValue = bindings.constInt(state.int64Type, value: 0) ?? state.zeroValue
                return buildStringAggregate(
                    builder: state.builder,
                    lowering: typeLowering,
                    data: globalStringPointer,
                    length: lengthValue,
                    byteCount: byteCountValue,
                    hash: hashValue,
                    name: "str_agg_\(literalID)"
                ) ?? state.zeroValue
            }
            guard let pointerAsInt = bindings.buildPtrToInt(
                state.builder,
                value: globalStringPointer,
                type: state.int64Type,
                name: "str_ptr_\(literalID)"
            ) else {
                return state.zeroValue
            }
            let lengthValue = bindings.constInt(state.int64Type, value: UInt64(text.utf8.count)) ?? state.zeroValue
            guard let stringFromUTF8 = declareExternalFunction(
                "kk_string_from_utf8",
                2,
                false
            ) else {
                return state.zeroValue
            }
            return bindings.buildCall(
                state.builder,
                functionType: stringFromUTF8.type,
                callee: stringFromUTF8.value,
                arguments: [pointerAsInt, lengthValue],
                name: "str_from_utf8_\(literalID)"
            ) ?? state.zeroValue
        case let .externSymbolAddress(symbolName):
            let symbolStr = interner.resolve(symbolName)
            if let externFn = declareExternalFunction(symbolStr, 4, false) {
                return bindings.buildPtrToInt(
                    state.builder,
                    value: externFn.value,
                    type: state.int64Type,
                    name: "extern_addr_\(symbolStr)"
                ) ?? state.zeroValue
            }
            return state.zeroValue
        case let .symbolRef(symbol):
            if let parameter = parameterValues[symbol] {
                return parameter
            }
            if let internalFunction = internalFunctions[symbol],
               let functionPointer = bindings.buildPtrToInt(
                   state.builder,
                   value: internalFunction.value,
                   type: state.int64Type,
                   name: "fn_ptr_\(symbol.rawValue)"
               )
            {
                return functionPointer
            }
            // Load from LLVM global variable if this symbol refers to a global.
            if let globalPtr = globalVariables[symbol] {
                let loadType = loweredLLVMType(
                    for: expectedType,
                    lowering: state.typeLowering,
                    defaultType: state.int64Type
                )
                return bindings.buildLoad(
                    state.builder,
                    type: loadType,
                    pointer: globalPtr,
                    name: "global_load_\(symbol.rawValue)"
                ) ?? state.zeroValue
            }
            return state.zeroValue
        case let .temporary(raw):
            return bindings.constInt(
                state.int64Type,
                value: UInt64(bitPattern: Int64(raw)),
                signExtend: true
            ) ?? state.zeroValue
        case .null:
            if let nullString = nullStringAggregateIfExpected() {
                return nullString
            }
            return bindings.constInt(
                state.int64Type,
                value: UInt64(bitPattern: Int64.min),
                signExtend: true
            ) ?? state.zeroValue
        case .unit:
            return state.zeroValue
        }
    }
}
