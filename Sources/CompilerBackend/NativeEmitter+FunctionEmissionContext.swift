import CompilerCore

extension NativeEmitter {
    /// Shared per-function emission state. `emitFunctionBody` used to carry this
    /// state as locals captured by ~30 nested local funcs; the refactor turns
    /// each captured local into a property and each local func into a method so
    /// the code could be split across the `NativeEmitter+*Emission*` sibling
    /// files. Optionals marked `!` are populated by `emitBody`'s prologue before
    /// any helper runs (same ordering as the original single function).
    final class FunctionEmissionContext {
        let emitter: NativeEmitter

        let function: KIRFunction
        let llvmFunction: LLVMFunction
        let llvmModule: LLVMCAPIBindings.LLVMModuleRef
        let context: LLVMCAPIBindings.LLVMContextRef
        let int64Type: LLVMCAPIBindings.LLVMTypeRef
        let typeLowering: LLVMTypeLowering?
        let outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef
        let internalFunctions: [SymbolID: LLVMFunction]
        let internalSignatures: [SymbolID: (parameters: [TypeID], returnType: TypeID)]
        let internalFunctionsByLookupKey: [FunctionLookupKey: [KIRFunction]]
        let globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef]
        let runtimeCallbackRawReturnSymbols: Set<SymbolID>
        let usesRuntimeCallbackRawABI: Bool
        let returnsRawStringRuntimeCallback: Bool
        let nameCounter: GeneratedNameCounter
        let diContext: DebugInfoContext?

        var builder: LLVMCAPIBindings.LLVMBuilderRef!
        var currentBlock: LLVMCAPIBindings.LLVMBasicBlockRef!
        var labelBlocks: [Int32: LLVMCAPIBindings.LLVMBasicBlockRef] = [:]
        var parameterValues: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:]
        var outThrownParameter: LLVMCAPIBindings.LLVMValueRef!
        var zeroValue: LLVMCAPIBindings.LLVMValueRef!
        var zeroReturnValue: LLVMCAPIBindings.LLVMValueRef!
        var nullThrownPointer: LLVMCAPIBindings.LLVMValueRef!
        var values: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        var rawResultValues: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        var externalFunctions: [String: LLVMFunction] = [:]
        let maxKIRArgumentCountByExternalCallee: [String: Int]
        var builderState: NativeEmitter.EmissionBuilderState!
        var copyTargetAllocas: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        var stringAggregateBridge: NativeEmitter.StringAggregateBridgeContext!
        var coroutineRegisterRootFunction: LLVMFunction?
        var coroutineUnregisterRootFunction: LLVMFunction?
        var gcRootStoreFunction: LLVMFunction?
        var gcFrameLeaveFunction: LLVMFunction?
        var gcRootFrameActive = false
        var gcRootSlotsByExpression: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        var gcRootSlotsByParameter: [Int: LLVMCAPIBindings.LLVMValueRef] = [:]

        init(
            emitter: NativeEmitter,
            function: KIRFunction,
            llvmFunction: LLVMFunction,
            llvmModule: LLVMCAPIBindings.LLVMModuleRef,
            context: LLVMCAPIBindings.LLVMContextRef,
            int64Type: LLVMCAPIBindings.LLVMTypeRef,
            typeLowering: LLVMTypeLowering?,
            outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef,
            internalFunctions: [SymbolID: LLVMFunction],
            internalSignatures: [SymbolID: (parameters: [TypeID], returnType: TypeID)],
            internalFunctionsByLookupKey: [FunctionLookupKey: [KIRFunction]],
            globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:],
            runtimeCallbackRawReturnSymbols: Set<SymbolID> = [],
            usesRuntimeCallbackRawABI: Bool = false,
            returnsRawStringRuntimeCallback: Bool = false,
            nameCounter: GeneratedNameCounter,
            diContext: DebugInfoContext? = nil
        ) {
            self.emitter = emitter
            self.function = function
            self.llvmFunction = llvmFunction
            self.llvmModule = llvmModule
            self.context = context
            self.int64Type = int64Type
            self.typeLowering = typeLowering
            self.outThrownPointerType = outThrownPointerType
            self.internalFunctions = internalFunctions
            self.internalSignatures = internalSignatures
            self.internalFunctionsByLookupKey = internalFunctionsByLookupKey
            self.globalVariables = globalVariables
            self.runtimeCallbackRawReturnSymbols = runtimeCallbackRawReturnSymbols
            self.usesRuntimeCallbackRawABI = usesRuntimeCallbackRawABI
            self.returnsRawStringRuntimeCallback = returnsRawStringRuntimeCallback
            self.nameCounter = nameCounter
            self.diContext = diContext
            self.maxKIRArgumentCountByExternalCallee = NativeEmitter.maxKIRArgumentCountByExternalCallee(
                body: function.body,
                interner: emitter.interner
            )
        }

        // The moved code was written against `self` (the emitter). These
        // forwards keep the extracted bodies verbatim instead of rewriting
        // every member reference to go through `emitter`.

        var bindings: LLVMCAPIBindings { emitter.bindings }
        var module: KIRModule { emitter.module }
        var interner: StringInterner { emitter.interner }
        var typeSystem: TypeSystem? { emitter.typeSystem }
        var symbols: SymbolTable? { emitter.symbols }
        var sourceManager: SourceManager? { emitter.sourceManager }
        var externalFunctionSymbolsByLinkName: [String: SymbolID] {
            emitter.externalFunctionSymbolsByLinkName
        }

        func loweredLLVMType(
            for type: TypeID?,
            lowering: LLVMTypeLowering?,
            defaultType: LLVMCAPIBindings.LLVMTypeRef
        ) -> LLVMCAPIBindings.LLVMTypeRef {
            emitter.loweredLLVMType(for: type, lowering: lowering, defaultType: defaultType)
        }

        func zeroLLVMValue(
            for type: TypeID?,
            lowering: LLVMTypeLowering?,
            int64Type: LLVMCAPIBindings.LLVMTypeRef,
            context: LLVMCAPIBindings.LLVMContextRef? = nil
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            emitter.zeroLLVMValue(
                for: type,
                lowering: lowering,
                int64Type: int64Type,
                context: context
            )
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
            emitter.buildStringAggregate(
                builder: builder,
                lowering: lowering,
                data: data,
                length: length,
                byteCount: byteCount,
                hash: hash,
                name: name
            )
        }

        func buildNullStringAggregate(
            builder: LLVMCAPIBindings.LLVMBuilderRef?,
            lowering: LLVMTypeLowering,
            name: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            emitter.buildNullStringAggregate(builder: builder, lowering: lowering, name: name)
        }

        func emitConstantValue(
            _ expression: KIRExprKind,
            expectedType: TypeID? = nil,
            state: NativeEmitter.EmissionBuilderState,
            parameterValues: [SymbolID: LLVMCAPIBindings.LLVMValueRef],
            internalFunctions: [SymbolID: LLVMFunction],
            globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:],
            nameCounter: GeneratedNameCounter,
            declareExternalFunction: (String, Int, Bool) -> LLVMFunction?,
            declareExternalSymbolFunction: (SymbolID) -> LLVMFunction?,
            interner: StringInterner
        ) -> LLVMCAPIBindings.LLVMValueRef {
            emitter.emitConstantValue(
                expression,
                expectedType: expectedType,
                state: state,
                parameterValues: parameterValues,
                internalFunctions: internalFunctions,
                globalVariables: globalVariables,
                nameCounter: nameCounter,
                declareExternalFunction: declareExternalFunction,
                declareExternalSymbolFunction: declareExternalSymbolFunction,
                interner: interner
            )
        }

        func lowerBuiltinCall(
            calleeName: String,
            argumentValues: [LLVMCAPIBindings.LLVMValueRef],
            argumentTypes: [TypeID?] = [],
            resultType: TypeID? = nil,
            state: NativeEmitter.EmissionBuilderState,
            instructionIndex: Int
        ) -> (handled: Bool, value: LLVMCAPIBindings.LLVMValueRef?) {
            emitter.lowerBuiltinCall(
                calleeName: calleeName,
                argumentValues: argumentValues,
                argumentTypes: argumentTypes,
                resultType: resultType,
                state: state,
                instructionIndex: instructionIndex
            )
        }
    }
}
