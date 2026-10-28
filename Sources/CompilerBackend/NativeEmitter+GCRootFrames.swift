import CompilerCore

extension NativeEmitter.FunctionEmissionContext {
    func prepareGCRootFrame(allocaBuilder: LLVMCAPIBindings.LLVMBuilderRef?) {
        let parameterIndices = function.params.indices.filter {
            isGCRootReferenceType(function.params[$0].type)
        }
        let expressionIDs = Set(function.body.flatMap(gcExpressionIDs(in:)))
            .filter { isGCRootReferenceType(module.arena.exprType($0)) }
            .sorted { $0.rawValue < $1.rawValue }
        let rootCount = parameterIndices.count + expressionIDs.count
        guard rootCount > 0,
              let pointerType = typeLowering?.dataPointerType,
              let arrayType = bindings.arrayType(element: int64Type, count: rootCount),
              let arrayPointer = bindings.buildEntryAlloca(
                  type: arrayType,
                  name: "gc_root_slots",
                  entryBlock: builderState.entryBlock,
                  allocaBuilder: allocaBuilder,
                  fallbackBuilder: builder
              ),
              let pushFunction = declareExternalFunction(
                  named: "kk_gc_push_root_frame",
                  parameterTypes: [pointerType, int64Type],
                  returnType: int64Type
              ),
              let storeFunction = declareExternalFunction(
                  named: "kk_gc_root_store",
                  parameterTypes: [pointerType, int64Type],
                  returnType: int64Type
              ),
              let leaveFunction = declareExternalFunction(
                  named: "kk_gc_frame_leave",
                  parameterTypes: [int64Type, int64Type],
                  returnType: int64Type
              )
        else {
            return
        }

        gcRootArrayType = arrayType
        gcRootArrayPointer = arrayPointer
        gcRootFrameActive = true
        gcFramePushFunction = pushFunction
        gcRootStoreFunction = storeFunction
        gcFrameLeaveFunction = leaveFunction

        var slotIndex = 0
        for parameterIndex in parameterIndices {
            guard let slot = bindings.buildArrayElementPointer(
                builder,
                context: context,
                arrayType: arrayType,
                arrayPointer: arrayPointer,
                index: slotIndex,
                name: "gc_param_root_\(parameterIndex)"
            ) else {
                continue
            }
            gcRootSlotsByParameter[parameterIndex] = slot
            slotIndex += 1
        }
        for expressionID in expressionIDs {
            guard let slot = bindings.buildArrayElementPointer(
                builder,
                context: context,
                arrayType: arrayType,
                arrayPointer: arrayPointer,
                index: slotIndex,
                name: "gc_expr_root_\(expressionID.rawValue)"
            ) else {
                continue
            }
            gcRootSlotsByExpression[expressionID.rawValue] = slot
            slotIndex += 1
        }

        for slot in Array(gcRootSlotsByParameter.values) + Array(gcRootSlotsByExpression.values) {
            _ = bindings.buildStore(builder, value: zeroValue, pointer: slot)
        }
        guard let countValue = bindings.constInt(int64Type, value: UInt64(rootCount)) else {
            gcRootFrameActive = false
            return
        }
        let pushResult = bindings.buildCall(
            builder,
            functionType: pushFunction.type,
            callee: pushFunction.value,
            arguments: [arrayPointer, countValue],
            name: nameCounter.nextName("gc_push_frame_")
        )
        _ = pushResult

        for (parameterIndex, slot) in gcRootSlotsByParameter {
            guard let value = parameterValues[function.params[parameterIndex].symbol] else {
                continue
            }
            emitGCRootStore(slot: slot, value: value, name: "gc_param_store_\(parameterIndex)")
        }
    }

    func emitGCRootStore(
        slot: LLVMCAPIBindings.LLVMValueRef,
        value: LLVMCAPIBindings.LLVMValueRef,
        name: String
    ) {
        guard !bindings.isAggregateStructValue(value),
              let storeFunction = gcRootStoreFunction
        else {
            return
        }
        _ = bindings.buildCall(
            builder,
            functionType: storeFunction.type,
            callee: storeFunction.value,
            arguments: [slot, value],
            name: nameCounter.nextName(name)
        )
    }

    func storeGCRoot(for expressionID: KIRExprID, value: LLVMCAPIBindings.LLVMValueRef) {
        guard let slot = gcRootSlotsByExpression[expressionID.rawValue] else {
            return
        }
        emitGCRootStore(slot: slot, value: value, name: "gc_expr_store_\(expressionID.rawValue)")
    }

    func registerGCRootForGlobal(_ symbol: SymbolID, slot: LLVMCAPIBindings.LLVMValueRef) {
        guard isGCRootGlobal(symbol),
              let slotAddress = bindings.buildPtrToInt(
                  builder,
                  value: slot,
                  type: int64Type,
                  name: nameCounter.nextName("gc_global_slot_")
              ),
              let registerFunction = declareExternalFunction(
                  named: "kk_register_global_root",
                  argumentCount: 1,
                  appendThrownChannel: false
              )
        else {
            return
        }
        _ = bindings.buildCall(
            builder,
            functionType: registerFunction.type,
            callee: registerFunction.value,
            arguments: [slotAddress],
            name: nameCounter.nextName("gc_register_global_")
        )
    }

    func emitGCFrameLeave(returning value: LLVMCAPIBindings.LLVMValueRef?) {
        guard let leaveFunction = gcFrameLeaveFunction else {
            return
        }
        let rawValue = value.flatMap { bindings.isAggregateStructValue($0) ? nil : $0 } ?? zeroValue
        let hasRootFrame = bindings.constInt(int64Type, value: gcRootFrameActive ? 1 : 0) ?? zeroValue
        _ = bindings.buildCall(
            builder,
            functionType: leaveFunction.type,
            callee: leaveFunction.value,
            arguments: [rawValue, hasRootFrame],
            name: nameCounter.nextName("gc_leave_frame_")
        )
    }

    private func isGCRootReferenceType(_ type: TypeID?) -> Bool {
        guard let type, let typeSystem else {
            return false
        }
        switch typeSystem.kind(of: type) {
        case .any, .classType, .typeParam, .functionType, .intersection, .kClassType:
            return true
        case .error, .unit, .nullableUnit, .platformUnit, .nothing, .stringStruct, .primitive:
            return false
        }
    }

    private func isGCRootGlobal(_ symbol: SymbolID) -> Bool {
        let declaredGlobal = module.arena.declarations.compactMap { declaration -> KIRGlobal? in
            guard case let .global(global) = declaration, global.symbol == symbol else {
                return nil
            }
            return global
        }.first
        if let declaredGlobal {
            return !declaredGlobal.isThreadLocal && isGCRootReferenceType(declaredGlobal.type)
        }
        if symbols?.annotations(for: symbol).contains(where: {
            KnownCompilerAnnotation.nativeThreadLocal.matches($0.annotationFQName)
        }) == true {
            return false
        }
        switch symbols?.symbol(symbol)?.kind {
        case .object, .property, .field, .backingField:
            // Some imported globals have a linker slot but no KIRGlobal entry.
            // Their serialized type is unavailable here, so retain their slot
            // conservatively; non-reference integer values are ignored by the
            // collector unless their bits match a registered object handle.
            return true
        default:
            return false
        }
    }

    private func gcExpressionIDs(in instruction: KIRInstruction) -> [KIRExprID] {
        switch instruction {
        case let .constValue(result, _):
            return [result]
        case let .binary(_, lhs, rhs, result):
            return [lhs, rhs, result]
        case let .jumpIfEqual(lhs, rhs, _), let .returnIfEqual(lhs, rhs):
            return [lhs, rhs]
        case let .unary(_, operand, result), let .nullAssert(operand, result):
            return [operand, result]
        case let .call(_, _, arguments, result, _, thrownResult, _, _):
            return arguments + [result, thrownResult].compactMap { $0 }
        case let .virtualCall(_, _, receiver, arguments, result, _, thrownResult, _):
            return [receiver] + arguments + [result, thrownResult].compactMap { $0 }
        case let .jumpIfNotNull(value, _), let .rethrow(value), let .returnValue(value), let .resumeNonLocalReturn(value):
            return [value]
        case let .copy(from, to):
            return [from, to]
        case let .storeGlobal(value, _):
            return [value]
        case let .loadGlobal(result, _):
            return [result]
        case let .nonLocalReturn(value, _):
            return value.map { [$0] } ?? []
        case let .beginNonLocalReturnScope(value, _, _):
            return [value]
        case .nop, .beginBlock, .endBlock, .label, .jump, .returnUnit,
             .endNonLocalReturnScope, .beginFinallyGuard, .endFinallyGuard,
             .beginFinallyCleanup, .endFinallyCleanup:
            return []
        }
    }

}
