import CompilerCore

extension NativeEmitter.FunctionEmissionContext {
    func emitGCGlobalStore(
        symbol: SymbolID,
        pointer: LLVMCAPIBindings.LLVMValueRef,
        value: LLVMCAPIBindings.LLVMValueRef
    ) {
        let isThreadLocal = emitter.threadLocalGCGlobalSymbols.contains(symbol)
            || symbols?.annotations(for: symbol).contains(where: {
                KnownCompilerAnnotation.nativeThreadLocal.matches($0.annotationFQName)
            }) == true
        let calleeName = isThreadLocal ? "kk_gc_store_thread_local_global" : "kk_gc_store_global"
        guard let callee = declareExternalFunction(
            named: calleeName, argumentCount: 2, appendThrownChannel: false
        )
        else {
            _ = bindings.buildStore(builder, value: value, pointer: pointer)
            return
        }
        _ = bindings.buildCall(
            builder, functionType: callee.type, callee: callee.value,
            arguments: [pointer, value], name: "gc_global_store"
        )
    }

    // Shadow roots currently preserve scalar handles. Flat String aggregates,
    // native callbacks and safepoint publication still need explicit
    // treatment before retained runtime boxes can be swept.
    func emitGCShadowPush() {
        guard let callee = declareExternalFunction(
            named: "kk_gc_shadow_push", argumentCount: 0, appendThrownChannel: false
        ) else { return }
        _ = bindings.buildCall(builder, functionType: callee.type, callee: callee.value, arguments: [], name: "gc_frame_push")
        for (index, parameter) in function.params.enumerated() {
            guard isPotentialGCReference(parameter.type),
                  let value = bindings.getParam(function: llvmFunction.value, index: UInt32(index))
            else { continue }
            emitGCShadowSet(slot: index, value: value)
        }
    }

    func emitGCShadowSet(_ result: KIRExprID?, value: LLVMCAPIBindings.LLVMValueRef?) {
        guard let result, result.rawValue >= 0,
              isPotentialGCReference(module.arena.exprType(result))
        else { return }
        emitGCShadowSet(slot: function.params.count + Int(result.rawValue), value: value)
    }

    func gcShadowSlot(for result: KIRExprID) -> LLVMCAPIBindings.LLVMValueRef? {
        guard result.rawValue >= 0,
              isPotentialGCReference(module.arena.exprType(result)),
              !stringAggregateBridge.isStringAggregateType(module.arena.exprType(result))
        else { return nil }
        return bindings.constInt(int64Type, value: UInt64(function.params.count + Int(result.rawValue)))
    }

    private func emitGCShadowSet(slot: Int, value: LLVMCAPIBindings.LLVMValueRef?) {
        guard let value, !bindings.isAggregateStructValue(value),
              let index = bindings.constInt(int64Type, value: UInt64(slot)),
              let callee = declareExternalFunction(
                  named: "kk_gc_shadow_set", argumentCount: 2, appendThrownChannel: false
              )
        else { return }
        _ = bindings.buildCall(builder, functionType: callee.type, callee: callee.value, arguments: [index, value], name: "gc_root_set")
    }

    func emitGCShadowPop(result: LLVMCAPIBindings.LLVMValueRef? = nil, thrown: LLVMCAPIBindings.LLVMValueRef? = nil) {
        guard let callee = declareExternalFunction(
            named: "kk_gc_shadow_pop", argumentCount: 2, appendThrownChannel: false
        ) else { return }
        let returned = result.map { bindings.isAggregateStructValue($0) ? zeroValue! : $0 } ?? zeroValue!
        let exception = thrown.map { bindings.isAggregateStructValue($0) ? zeroValue! : $0 } ?? zeroValue!
        _ = bindings.buildCall(builder, functionType: callee.type, callee: callee.value, arguments: [returned, exception], name: "gc_frame_pop")
    }

    private func isPotentialGCReference(_ type: TypeID?) -> Bool {
        guard let type, let typeSystem else { return true }
        switch typeSystem.kind(of: type) {
        case .primitive(_, .nonNull), .unit, .nullableUnit, .platformUnit, .nothing:
            return false
        default:
            return true
        }
    }
}
