extension NativeEmitter {
    struct LLVMTypeLowering {
        let int64Type: LLVMCAPIBindings.LLVMTypeRef
        let dataPointerType: LLVMCAPIBindings.LLVMTypeRef
        let stringStructType: LLVMCAPIBindings.LLVMTypeRef
        let kswiftValueType: LLVMCAPIBindings.LLVMTypeRef
    }

    func makeLLVMTypeLowering(
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef
    ) -> LLVMTypeLowering? {
        guard let int8Type = bindings.int8Type(context: context),
              let dataPointerType = bindings.pointerType(int8Type, addressSpace: 0),
              let stringStructType = bindings.structType(
                  context: context,
                  elements: [dataPointerType, int64Type, int64Type, int64Type]
              ),
              let kswiftValueType = bindings.structType(
                  context: context,
                  elements: [int64Type, int64Type, int64Type, int64Type, int64Type]
              )
        else {
            return nil
        }
        return LLVMTypeLowering(
            int64Type: int64Type,
            dataPointerType: dataPointerType,
            stringStructType: stringStructType,
            kswiftValueType: kswiftValueType
        )
    }

    func loweredLLVMType(
        for type: TypeID?,
        lowering: LLVMTypeLowering?,
        defaultType: LLVMCAPIBindings.LLVMTypeRef
    ) -> LLVMCAPIBindings.LLVMTypeRef {
        guard let type,
              let lowering,
              let typeSystem
        else {
            return defaultType
        }
        switch typeSystem.kind(of: type) {
        case .stringStruct:
            return lowering.stringStructType
        default:
            return lowering.int64Type
        }
    }

    func zeroLLVMValue(
        for type: TypeID?,
        lowering: LLVMTypeLowering?,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        context: LLVMCAPIBindings.LLVMContextRef? = nil
    ) -> LLVMCAPIBindings.LLVMValueRef? {
        guard let type,
              let lowering,
              let typeSystem,
              case .stringStruct = typeSystem.kind(of: type)
        else {
            return bindings.constInt(int64Type, value: 0)
        }
        return constNullStringAggregate(context: context, lowering: lowering)
    }

    func constNullStringAggregate(
        context: LLVMCAPIBindings.LLVMContextRef?,
        lowering: LLVMTypeLowering
    ) -> LLVMCAPIBindings.LLVMValueRef? {
        guard let nullData = bindings.constPointerNull(lowering.dataPointerType),
              let zero = bindings.constInt(lowering.int64Type, value: 0)
        else {
            return nil
        }
        return bindings.constStruct(context: context, values: [nullData, zero, zero, zero])
    }

    func buildStringAggregate(
        builder: LLVMCAPIBindings.LLVMBuilderRef?,
        lowering: LLVMTypeLowering,
        data: LLVMCAPIBindings.LLVMValueRef?,
        length: LLVMCAPIBindings.LLVMValueRef?,
        byteCount: LLVMCAPIBindings.LLVMValueRef?,
        hash: LLVMCAPIBindings.LLVMValueRef?,
        name: String
    ) -> LLVMCAPIBindings.LLVMValueRef? {
        guard var aggregate = bindings.getUndef(type: lowering.stringStructType) else {
            return nil
        }
        aggregate = bindings.buildInsertValue(builder, aggregate: aggregate, element: data, index: 0, name: "\(name)_data") ?? aggregate
        aggregate = bindings.buildInsertValue(builder, aggregate: aggregate, element: length, index: 1, name: "\(name)_length") ?? aggregate
        aggregate = bindings.buildInsertValue(builder, aggregate: aggregate, element: byteCount, index: 2, name: "\(name)_byte_count") ?? aggregate
        aggregate = bindings.buildInsertValue(builder, aggregate: aggregate, element: hash, index: 3, name: "\(name)_hash") ?? aggregate
        return aggregate
    }

    func buildNullStringAggregate(
        builder: LLVMCAPIBindings.LLVMBuilderRef?,
        lowering: LLVMTypeLowering,
        name: String
    ) -> LLVMCAPIBindings.LLVMValueRef? {
        guard let nullData = bindings.constPointerNull(lowering.dataPointerType),
              let zero = bindings.constInt(lowering.int64Type, value: 0)
        else {
            return nil
        }
        return buildStringAggregate(
            builder: builder,
            lowering: lowering,
            data: nullData,
            length: zero,
            byteCount: zero,
            hash: zero,
            name: name
        )
    }
}
