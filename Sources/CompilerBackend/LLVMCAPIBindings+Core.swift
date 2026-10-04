import CompilerCore

extension LLVMCAPIBindings {
    func smokeTestContextLifecycle() -> Bool {
        guard let context = contextCreateFn() else {
            return false
        }
        contextDisposeFn(context)
        return true
    }

    func createContext() -> LLVMContextRef? {
        contextCreateFn()
    }

    func disposeContext(_ context: LLVMContextRef?) {
        contextDisposeFn(context)
    }

    func createModule(name: String, context: LLVMContextRef?) -> LLVMModuleRef? {
        name.withCString { moduleCreateFn($0, context) }
    }

    func disposeModule(_ module: LLVMModuleRef?) {
        disposeModuleFn(module)
    }

    func printModule(_ module: LLVMModuleRef?) -> String? {
        guard let raw = printModuleToStringFn(module) else {
            return nil
        }
        defer { disposeMessageFn(raw) }
        return String(cString: raw)
    }

    func setTarget(_ module: LLVMModuleRef?, triple: String) {
        triple.withCString { setTargetFn(module, $0) }
    }

    func setWeakAnyLinkage(_ value: LLVMValueRef?) {
        setLinkageFn(value, 5)
    }

    func setExternalLinkage(_ value: LLVMValueRef?) {
        setLinkageFn(value, 0)
    }

    func setInternalLinkage(_ value: LLVMValueRef?) {
        setLinkageFn(value, 8)
    }

    func setLinkOnceODRLinkage(_ value: LLVMValueRef?) {
        setLinkageFn(value, 3)
    }

    func int8Type(context: LLVMContextRef?) -> LLVMTypeRef? {
        int8TypeInContextFn(context)
    }

    func int64Type(context: LLVMContextRef?) -> LLVMTypeRef? {
        int64TypeFn(context)
    }

    func structType(context: LLVMContextRef?, elements: [LLVMTypeRef?], packed: Bool = false) -> LLVMTypeRef? {
        guard let structTypeInContextFn else {
            return nil
        }
        var mutable = elements
        return structTypeInContextFn(context, &mutable, UInt32(mutable.count), packed ? 1 : 0)
    }

    func pointerType(_ pointee: LLVMTypeRef?, addressSpace: UInt32 = 0) -> LLVMTypeRef? {
        pointerTypeFn(pointee, addressSpace)
    }

    func functionType(returnType: LLVMTypeRef?, parameters: [LLVMTypeRef?], isVarArg: Bool) -> LLVMTypeRef? {
        var mutable = parameters
        return functionTypeFn(returnType, &mutable, UInt32(mutable.count), isVarArg ? 1 : 0)
    }

    func addFunction(module: LLVMModuleRef?, name: String, functionType: LLVMTypeRef?) -> LLVMValueRef? {
        name.withCString { addFunctionFn(module, $0, functionType) }
    }

    func getNamedFunction(module: LLVMModuleRef?, name: String) -> LLVMValueRef? {
        name.withCString { getNamedFunctionFn(module, $0) }
    }

    func getParam(function: LLVMValueRef?, index: UInt32) -> LLVMValueRef? {
        getParamFn(function, index)
    }

    func getUndef(type: LLVMTypeRef?) -> LLVMValueRef? {
        getUndefFn(type)
    }

    func appendBasicBlock(context: LLVMContextRef?, function: LLVMValueRef?, name: String) -> LLVMBasicBlockRef? {
        name.withCString { appendBasicBlockFn(context, function, $0) }
    }

    func createBuilder(context: LLVMContextRef?) -> LLVMBuilderRef? {
        createBuilderFn(context)
    }

    func disposeBuilder(_ builder: LLVMBuilderRef?) {
        disposeBuilderFn(builder)
    }

    func positionBuilder(_ builder: LLVMBuilderRef?, at block: LLVMBasicBlockRef?) {
        positionBuilderFn(builder, block)
    }

    /// Positions the builder immediately before `instruction`. Returns false when
    /// the underlying `LLVMPositionBuilderBefore` symbol is unavailable.
    func positionBuilder(_ builder: LLVMBuilderRef?, before instruction: LLVMValueRef?) -> Bool {
        guard let positionBuilderBeforeFn else { return false }
        positionBuilderBeforeFn(builder, instruction)
        return true
    }

    func firstInstruction(of block: LLVMBasicBlockRef?) -> LLVMValueRef? {
        getFirstInstructionFn?(block)
    }

    /// Emits an `alloca` at the top of `entryBlock` through a dedicated builder.
    /// Slots emitted while a loop body is being lowered must not live in the loop
    /// block: a non-entry `alloca` is a dynamic stack allocation that grows the
    /// frame on every iteration and overflows the stack in long-running loops.
    /// Falls back to `fallbackBuilder` when the positioning symbols are missing.
    func buildEntryAlloca(
        type: LLVMTypeRef?,
        name: String,
        entryBlock: LLVMBasicBlockRef?,
        allocaBuilder: LLVMBuilderRef?,
        fallbackBuilder: LLVMBuilderRef?
    ) -> LLVMValueRef? {
        guard let allocaBuilder, let entryBlock, getFirstInstructionFn != nil, positionBuilderBeforeFn != nil else {
            return buildAlloca(fallbackBuilder, type: type, name: name)
        }
        if let firstInstruction = firstInstruction(of: entryBlock) {
            guard positionBuilder(allocaBuilder, before: firstInstruction) else {
                return buildAlloca(fallbackBuilder, type: type, name: name)
            }
        } else {
            positionBuilder(allocaBuilder, at: entryBlock)
        }
        return buildAlloca(allocaBuilder, type: type, name: name)
    }

    func hasTerminator(_ block: LLVMBasicBlockRef?) -> Bool {
        getBasicBlockTerminatorFn(block) != nil
    }

    func addGlobal(module: LLVMModuleRef?, type: LLVMTypeRef?, name: String) -> LLVMValueRef? {
        guard let fn = addGlobalFn else { return nil }
        return name.withCString { fn(module, type, $0) }
    }

    func setInitializer(_ global: LLVMValueRef?, value: LLVMValueRef?) {
        setInitializerFn?(global, value)
    }

}
