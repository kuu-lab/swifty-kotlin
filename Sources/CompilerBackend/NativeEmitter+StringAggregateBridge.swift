import CompilerCore

extension NativeEmitter {
    func isStringAggregateType(
        _ type: TypeID?,
        typeSystem: TypeSystem?,
        hasStringLowering: Bool
    ) -> Bool {
        guard let type,
              let typeSystem,
              case .stringStruct = typeSystem.kind(of: type)
        else {
            return false
        }
        return hasStringLowering
    }

    struct StringAggregateBridgeContext {
        typealias ExternalFunctionDeclaration = (
            String,
            [LLVMCAPIBindings.LLVMTypeRef?],
            LLVMCAPIBindings.LLVMTypeRef?
        ) -> LLVMFunction?

        let emitter: NativeEmitter
        let state: EmissionBuilderState
        let typeSystem: TypeSystem?
        let outParameterPointerType: LLVMCAPIBindings.LLVMTypeRef?
        let declareTypedExternalFunction: ExternalFunctionDeclaration?

        init(
            emitter: NativeEmitter,
            state: EmissionBuilderState,
            typeSystem: TypeSystem?,
            outParameterPointerType: LLVMCAPIBindings.LLVMTypeRef? = nil,
            declareTypedExternalFunction: ExternalFunctionDeclaration? = nil
        ) {
            self.emitter = emitter
            self.state = state
            self.typeSystem = typeSystem
            self.outParameterPointerType = outParameterPointerType
            self.declareTypedExternalFunction = declareTypedExternalFunction
        }

        func isStringAggregateType(_ type: TypeID?) -> Bool {
            emitter.isStringAggregateType(
                type,
                typeSystem: typeSystem,
                hasStringLowering: state.typeLowering != nil
            )
        }

        func buildEntrySlot(
            name: String,
            type: LLVMCAPIBindings.LLVMTypeRef? = nil
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            emitter.bindings.buildEntryAlloca(
                type: type ?? state.int64Type,
                name: name,
                entryBlock: state.entryBlock,
                allocaBuilder: state.allocaBuilder,
                fallbackBuilder: state.builder
            )
        }

        func stringAggregateFields(
            _ value: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) -> [LLVMCAPIBindings.LLVMValueRef]? {
            // A KIR expression typed as String may still be materialized as a raw handle.
            // Bridge it before extracting fields so LLVM never sees an invalid extract.
            let aggregate: LLVMCAPIBindings.LLVMValueRef
            if emitter.bindings.isAggregateStructValue(value) {
                aggregate = value
            } else if let bridged = bridgeRuntimeRawToStringAggregate(value, suffix: "\(suffix)_from_raw") {
                aggregate = bridged
            } else {
                return nil
            }
            guard let data = emitter.bindings.buildExtractValue(state.builder, aggregate: aggregate, index: 0, name: "str_data_\(suffix)"),
                  let length = emitter.bindings.buildExtractValue(state.builder, aggregate: aggregate, index: 1, name: "str_length_\(suffix)"),
                  let byteCount = emitter.bindings.buildExtractValue(state.builder, aggregate: aggregate, index: 2, name: "str_bytes_\(suffix)"),
                  let hash = emitter.bindings.buildExtractValue(state.builder, aggregate: aggregate, index: 3, name: "str_hash_\(suffix)")
            else {
                return nil
            }
            return [data, length, byteCount, hash]
        }

        func bridgeStringAggregateToRuntimeRaw(
            _ value: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let typeLowering = state.typeLowering,
                  let fields = stringAggregateFields(value, suffix: "\(suffix)_to_raw"),
                  let bridgeFunction = declareExternalFunction(
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
            return emitter.bindings.buildCall(
                state.builder,
                functionType: bridgeFunction.type,
                callee: bridgeFunction.value,
                arguments: fields,
                name: "string_raw_\(suffix)"
            ).flatMap { raw in
                // String? uses null data in aggregate form and the runtime null sentinel at raw boundaries.
                guard let nullData = emitter.bindings.constPointerNull(typeLowering.dataPointerType),
                      let isNull = emitter.bindings.buildICmpEqual(
                          state.builder,
                          lhs: fields[0],
                          rhs: nullData,
                          name: "string_raw_isnull_\(suffix)"
                      ),
                      let sentinel = emitter.bindings.constInt(
                          state.int64Type,
                          value: UInt64(bitPattern: Int64.min),
                          signExtend: true
                      )
                else {
                    return raw
                }
                return emitter.bindings.buildSelect(
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
                  let pointerType = outParameterPointerType ?? emitter.bindings.pointerType(state.int64Type, addressSpace: 0),
                  let lengthSlot = buildEntrySlot(name: "string_bridge_length_\(suffix)"),
                  let byteCountSlot = buildEntrySlot(name: "string_bridge_bytes_\(suffix)"),
                  let hashSlot = buildEntrySlot(name: "string_bridge_hash_\(suffix)")
            else {
                return nil
            }
            _ = emitter.bindings.buildStore(state.builder, value: state.zeroValue, pointer: lengthSlot)
            _ = emitter.bindings.buildStore(state.builder, value: state.zeroValue, pointer: byteCountSlot)
            _ = emitter.bindings.buildStore(state.builder, value: state.zeroValue, pointer: hashSlot)
            guard let bridgeFunction = declareExternalFunction(
                    named: "kk_string_to_flat",
                    parameterTypes: [
                        state.int64Type,
                        pointerType,
                        pointerType,
                        pointerType,
                    ],
                    returnType: typeLowering.dataPointerType
                ),
                  let data = emitter.bindings.buildCall(
                      state.builder,
                      functionType: bridgeFunction.type,
                      callee: bridgeFunction.value,
                      arguments: [raw, lengthSlot, byteCountSlot, hashSlot],
                      name: "string_bridge_data_\(suffix)"
                  ),
                  let length = emitter.bindings.buildLoad(
                      state.builder,
                      type: state.int64Type,
                      pointer: lengthSlot,
                      name: "string_bridge_length_val_\(suffix)"
                  ),
                  let byteCount = emitter.bindings.buildLoad(
                      state.builder,
                      type: state.int64Type,
                      pointer: byteCountSlot,
                      name: "string_bridge_bytes_val_\(suffix)"
                  ),
                  let hash = emitter.bindings.buildLoad(
                      state.builder,
                      type: state.int64Type,
                      pointer: hashSlot,
                      name: "string_bridge_hash_val_\(suffix)"
                  )
            else {
                return nil
            }
            return emitter.buildStringAggregate(
                builder: state.builder,
                lowering: typeLowering,
                data: data,
                length: length,
                byteCount: byteCount,
                hash: hash,
                name: "string_bridge_\(suffix)"
            )
        }

        func declareExternalFunction(
            named name: String,
            parameterTypes: [LLVMCAPIBindings.LLVMTypeRef?],
            returnType: LLVMCAPIBindings.LLVMTypeRef?
        ) -> LLVMFunction? {
            if let declareTypedExternalFunction {
                return declareTypedExternalFunction(name, parameterTypes, returnType)
            }
            guard let externalType = emitter.bindings.functionType(
                returnType: returnType,
                parameters: parameterTypes,
                isVarArg: false
            ) else {
                return nil
            }
            let externalValue = emitter.bindings.getNamedFunction(module: state.module, name: name)
                ?? emitter.bindings.addFunction(module: state.module, name: name, functionType: externalType)
            guard let externalValue else {
                return nil
            }
            return LLVMFunction(value: externalValue, type: externalType)
        }
    }
}
