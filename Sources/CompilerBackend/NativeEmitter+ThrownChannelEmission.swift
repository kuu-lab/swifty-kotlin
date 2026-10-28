import CompilerCore

extension NativeEmitter.FunctionEmissionContext {

    func storeThrownResultZero(_ thrownResult: KIRExprID?) {
        guard let thrownResult else {
            return
        }
        if let alloca = copyTargetAllocas[thrownResult.rawValue] {
            _ = bindings.buildStore(builder, value: zeroValue, pointer: alloca)
            emitGCShadowSet(thrownResult, value: zeroValue)
        } else {
            storeResult(thrownResult, zeroValue)
        }
    }

    @discardableResult
    func handleThrownSlot(
        _ thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?,
        thrownResult: KIRExprID?,
        instructionIndex: Int,
        namePrefix: String = ""
    ) -> Bool {
        guard let thrownSlotPointer,
              let thrownValue = bindings.buildLoad(
                  builder,
                  type: int64Type,
                  pointer: thrownSlotPointer,
                  name: "\(namePrefix)thrown_val_\(instructionIndex)"
              )
        else {
            return false
        }
        if let thrownResult {
            if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                _ = bindings.buildStore(builder, value: thrownValue, pointer: alloca)
                emitGCShadowSet(thrownResult, value: thrownValue)
            } else {
                storeResult(thrownResult, thrownValue)
            }
        } else if let hasThrown = buildThrownSlotCondition(
            from: thrownValue,
            name: "\(namePrefix)has_thrown_\(instructionIndex)"
        ),
            let thrownBlock = bindings.appendBasicBlock(
                context: context,
                function: llvmFunction.value,
                name: "\(namePrefix)thrown_\(instructionIndex)"
            ),
            let continueBlock = bindings.appendBasicBlock(
                context: context,
                function: llvmFunction.value,
                name: "\(namePrefix)call_cont_\(instructionIndex)"
            )
        {
            _ = bindings.buildCondBr(
                builder,
                condition: hasThrown,
                thenBlock: thrownBlock,
                elseBlock: continueBlock
            )

            bindings.positionBuilder(builder, at: thrownBlock)
            storeOutThrownIfNonNull(thrownValue, suffix: "\(namePrefix)throw_\(instructionIndex)")
            emitGCShadowPop(thrown: thrownValue)
            _ = bindings.buildRet(builder, value: zeroReturnValue)

            currentBlock = continueBlock
            bindings.positionBuilder(builder, at: continueBlock)
        }
        return true
    }

    /// Does NOT call kk_unbox_bool;
    /// thrown slots hold raw integers (0 = no exception, non-zero = exception).
    func buildThrownSlotCondition(
        from value: LLVMCAPIBindings.LLVMValueRef,
        name: String
    ) -> LLVMCAPIBindings.LLVMValueRef? {
        bindings.buildICmpNotEqual(builder, lhs: value, rhs: zeroValue, name: name)
    }

    func storeOutThrownIfNonNull(
        _ value: LLVMCAPIBindings.LLVMValueRef,
        suffix: String
    ) {
        guard let outThrownParameter,
              let pointerIsNonNull = bindings.buildICmpNotEqual(
                  builder,
                  lhs: outThrownParameter,
                  rhs: nullThrownPointer,
                  name: "out_nonnull_\(suffix)"
              ),
              let storeBlock = bindings.appendBasicBlock(
                  context: context,
                  function: llvmFunction.value,
                  name: "out_store_\(suffix)"
              ),
              let continueBlock = bindings.appendBasicBlock(
                  context: context,
                  function: llvmFunction.value,
                  name: "out_cont_\(suffix)"
              )
        else {
            return
        }

        _ = bindings.buildCondBr(
            builder,
            condition: pointerIsNonNull,
            thenBlock: storeBlock,
            elseBlock: continueBlock
        )

        bindings.positionBuilder(builder, at: storeBlock)
        _ = bindings.buildStore(builder, value: value, pointer: outThrownParameter)
        _ = bindings.buildBr(builder, destination: continueBlock)

        currentBlock = continueBlock
        bindings.positionBuilder(builder, at: continueBlock)
    }

    // Per-frame stack guard (KUU-1384): every emitted function prologue
    // passes a marker address inside its own frame to
    // `kk_stack_overflow_check`. Once the current thread's stack drops
    // below the runtime's overflow bound the call returns a
    // StackOverflowError handle which this prologue propagates through the
    // ordinary outThrown channel, so deep recursion becomes a catchable
    // exception instead of a SIGSEGV.
    func emitStackOverflowGuard() {
        guard let checkFunction = declareExternalFunction(
            named: "kk_stack_overflow_check",
            argumentCount: 1,
            appendThrownChannel: false
        ),
              let markerSlot = stringAggregateBridge.buildEntrySlot(name: "soe_marker"),
              let markerValue = bindings.buildPtrToInt(
                  builder,
                  value: markerSlot,
                  type: int64Type,
                  name: "soe_marker"
              ),
              let throwBlock = bindings.appendBasicBlock(
                  context: context,
                  function: llvmFunction.value,
                  name: "soe_throw"
              ),
              let okBlock = bindings.appendBasicBlock(
                  context: context,
                  function: llvmFunction.value,
                  name: "soe_ok"
              ),
              let errorHandle = bindings.buildCall(
                  builder,
                  functionType: checkFunction.type,
                  callee: checkFunction.value,
                  arguments: [markerValue],
                  name: "soe_handle"
              ),
              let overflowed = buildThrownSlotCondition(from: errorHandle, name: "soe_threw")
        else {
            return
        }

        _ = bindings.buildCondBr(
            builder,
            condition: overflowed,
            thenBlock: throwBlock,
            elseBlock: okBlock
        )

        bindings.positionBuilder(builder, at: throwBlock)
        storeOutThrownIfNonNull(errorHandle, suffix: "soe")
        _ = bindings.buildRet(builder, value: zeroReturnValue)

        currentBlock = okBlock
        bindings.positionBuilder(builder, at: okBlock)
    }

}
