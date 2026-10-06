import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

import CompilerCore

enum LLVMEntryPointObjectEmitterError: Error, CustomStringConvertible {
    case bindingsUnavailable
    case invalidIR(String)
    case emissionFailed(String)

    var description: String {
        switch self {
        case .bindingsUnavailable:
            "LLVM backend is unavailable while emitting the entry wrapper object."
        case let .invalidIR(reason):
            reason
        case let .emissionFailed(reason):
            reason
        }
    }
}

private struct LLVMEntryPointPrimitiveTypes {
    let int64Type: LLVMCAPIBindings.LLVMTypeRef
    let int32Type: LLVMCAPIBindings.LLVMTypeRef
    let thrownPointerType: LLVMCAPIBindings.LLVMTypeRef
    let cStringPointerType: LLVMCAPIBindings.LLVMTypeRef
}

private struct LLVMEntryPointFunctionTypes {
    let entryType: LLVMCAPIBindings.LLVMTypeRef
    let writeType: LLVMCAPIBindings.LLVMTypeRef
    let mainType: LLVMCAPIBindings.LLVMTypeRef
}

private struct LLVMEntryPointFunctions {
    let entryFunction: LLVMCAPIBindings.LLVMValueRef
    let writeFunction: LLVMCAPIBindings.LLVMValueRef
    let mainFunction: LLVMCAPIBindings.LLVMValueRef
}

private struct LLVMEntryPointBlocks {
    let entryBlock: LLVMCAPIBindings.LLVMBasicBlockRef
    let successBlock: LLVMCAPIBindings.LLVMBasicBlockRef
    let failureBlock: LLVMCAPIBindings.LLVMBasicBlockRef
}

private struct LLVMEntryPointConstants {
    let thrownSlot: LLVMCAPIBindings.LLVMValueRef
    let zero: LLVMCAPIBindings.LLVMValueRef
    let zero32: LLVMCAPIBindings.LLVMValueRef
    let one32: LLVMCAPIBindings.LLVMValueRef
    let stderrFD: LLVMCAPIBindings.LLVMValueRef
    let panicMessageLength: LLVMCAPIBindings.LLVMValueRef
}

struct LLVMEntryPointObjectEmitter {
    private let bindings: LLVMCAPIBindings
    private let target: TargetTriple
    private let panicMessageText = "KSwiftK panic [KSWIFTK-LINK-0003]: Unhandled top-level exception\n"

    init(target: TargetTriple) throws {
        guard let bindings = LLVMCAPIBindings.loadUsable() else {
            throw LLVMEntryPointObjectEmitterError.bindingsUnavailable
        }
        self.bindings = bindings
        self.target = target
    }

    func emit(entrySymbol: String, outputPath: String) throws -> String {
        // Emit into a per-invocation directory created with mkdtemp (mode 0700, unpredictable
        // name). This avoids the previous shared, predictable path under the world-writable temp
        // directory: an attacker cannot pre-plant a symlink at the destination nor replace the
        // emitted `.o` before the linker consumes it, since the containing directory is private to
        // the compiling user and not guessable.
        let objectURL = try makePrivateObjectURL()
        do {
            // Keep the target machine alive inside the same Linux critical
            // section as its creation, IR construction, emission, and
            // disposal. LLVM target machines retain process-global target
            // state, so splitting those operations across separate lock
            // scopes still permits another worker to mutate that state while
            // this wrapper is using it.
            try CodegenCriticalSection.withLinuxLLVMProcessLock(target: target) {
                try emitObject(entrySymbol: entrySymbol, objectURL: objectURL)
            }
        } catch {
            // On success the caller owns the directory and removes it after linking; on failure it
            // never receives the path, so drop the private directory here to avoid leaking it.
            try? FileManager.default.removeItem(at: objectURL.deletingLastPathComponent())
            throw error
        }
        return objectURL.path
    }

    private func makePrivateObjectURL() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let template = tempDirectory.appendingPathComponent("kswiftk-entry.XXXXXX").path
        var templateBytes = template.utf8CString
        let privateDirectoryPath = try templateBytes.withUnsafeMutableBufferPointer { buffer -> String in
            guard let baseAddress = buffer.baseAddress, mkdtemp(baseAddress) != nil else {
                throw LLVMEntryPointObjectEmitterError.emissionFailed(
                    "failed to create a private temporary directory for the entry wrapper object"
                )
            }
            return String(cString: baseAddress)
        }
        return URL(fileURLWithPath: privateDirectoryPath, isDirectory: true)
            .appendingPathComponent("entry.o", isDirectory: false)
    }

    private func emitObject(entrySymbol: String, objectURL: URL) throws {
        guard let context = bindings.createContext() else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMContextCreate returned null")
        }
        defer { bindings.disposeContext(context) }

        guard let module = bindings.createModule(name: "kswiftk_entry_wrapper", context: context) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMModuleCreateWithNameInContext returned null")
        }
        defer { bindings.disposeModule(module) }

        let triple = CodegenRuntimeSupport.targetTripleString(target)
        bindings.setTarget(module, triple: triple)

        guard let targetMachine = bindings.createTargetMachine(triple: triple, optLevel: .O0) else {
            throw LLVMEntryPointObjectEmitterError.emissionFailed("failed to create LLVM target machine for entry wrapper")
        }
        defer {
            bindings.disposeTargetMachine(targetMachine)
        }

        guard bindings.applyTargetMachine(targetMachine, to: module) else {
            throw LLVMEntryPointObjectEmitterError.emissionFailed("failed to apply target data layout to entry wrapper")
        }

        let primitiveTypes = try makePrimitiveTypes(context: context)
        let functionTypes = try makeFunctionTypes(primitiveTypes)
        let functions = try declareFunctions(module: module, entrySymbol: entrySymbol, functionTypes: functionTypes)

        guard let builder = bindings.createBuilder(context: context) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMCreateBuilderInContext returned null")
        }
        defer { bindings.disposeBuilder(builder) }

        try emitMainWrapper(
            builder: builder,
            context: context,
            primitiveTypes: primitiveTypes,
            functionTypes: functionTypes,
            functions: functions
        )

        if let errorMessage = bindings.emitObject(
            targetMachine: targetMachine,
            module: module,
            outputPath: objectURL.path
        ) {
            throw LLVMEntryPointObjectEmitterError.emissionFailed(errorMessage)
        }
    }

    private func makePrimitiveTypes(context: LLVMCAPIBindings.LLVMContextRef) throws -> LLVMEntryPointPrimitiveTypes {
        guard let int64Type = bindings.int64Type(context: context) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMInt64TypeInContext returned null")
        }
        guard let int32Type = bindings.int32Type(context: context) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMInt32TypeInContext returned null")
        }
        guard let int8Type = bindings.int8Type(context: context) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMInt8TypeInContext returned null")
        }
        guard let thrownPointerType = bindings.pointerType(int64Type) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMPointerType returned null for thrown channel")
        }
        guard let cStringPointerType = bindings.pointerType(int8Type) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("LLVMPointerType returned null for panic message")
        }
        return LLVMEntryPointPrimitiveTypes(
            int64Type: int64Type,
            int32Type: int32Type,
            thrownPointerType: thrownPointerType,
            cStringPointerType: cStringPointerType
        )
    }

    private func makeFunctionTypes(_ primitiveTypes: LLVMEntryPointPrimitiveTypes) throws -> LLVMEntryPointFunctionTypes {
        guard let entryType = bindings.functionType(
            returnType: primitiveTypes.int64Type,
            parameters: [primitiveTypes.thrownPointerType],
            isVarArg: false
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create entry function type")
        }
        guard let writeType = bindings.functionType(
            returnType: primitiveTypes.int64Type,
            parameters: [
                primitiveTypes.int64Type,
                primitiveTypes.cStringPointerType,
                primitiveTypes.int64Type,
            ],
            isVarArg: false
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create stderr write function type")
        }
        guard let mainType = bindings.functionType(
            returnType: primitiveTypes.int32Type,
            parameters: [],
            isVarArg: false
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create main wrapper type")
        }
        return LLVMEntryPointFunctionTypes(entryType: entryType, writeType: writeType, mainType: mainType)
    }

    private func declareFunctions(
        module: LLVMCAPIBindings.LLVMModuleRef,
        entrySymbol: String,
        functionTypes: LLVMEntryPointFunctionTypes
    ) throws -> LLVMEntryPointFunctions {
        guard let entryFunction = bindings.getNamedFunction(module: module, name: entrySymbol)
            ?? bindings.addFunction(module: module, name: entrySymbol, functionType: functionTypes.entryType)
        else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to declare entry function '\(entrySymbol)'")
        }
        guard let writeFunction = bindings.getNamedFunction(module: module, name: "write")
            ?? bindings.addFunction(module: module, name: "write", functionType: functionTypes.writeType)
        else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to declare stderr write function")
        }
        guard let mainFunction = bindings.addFunction(module: module, name: "main", functionType: functionTypes.mainType) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to declare main wrapper function")
        }
        return LLVMEntryPointFunctions(
            entryFunction: entryFunction,
            writeFunction: writeFunction,
            mainFunction: mainFunction
        )
    }

    private func emitMainWrapper(
        builder: LLVMCAPIBindings.LLVMBuilderRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        primitiveTypes: LLVMEntryPointPrimitiveTypes,
        functionTypes: LLVMEntryPointFunctionTypes,
        functions: LLVMEntryPointFunctions
    ) throws {
        let blocks = try makeMainBlocks(context: context, mainFunction: functions.mainFunction)
        bindings.positionBuilder(builder, at: blocks.entryBlock)

        let constants = try makeMainConstants(builder: builder, primitiveTypes: primitiveTypes)
        try emitEntryDispatch(
            builder: builder,
            blocks: blocks,
            primitiveTypes: primitiveTypes,
            functionTypes: functionTypes,
            functions: functions,
            constants: constants
        )

        bindings.positionBuilder(builder, at: blocks.failureBlock)
        try emitFailurePath(
            builder: builder,
            functionTypes: functionTypes,
            functions: functions,
            constants: constants
        )

        bindings.positionBuilder(builder, at: blocks.successBlock)
        try emitSuccessPath(builder: builder, constants: constants)
    }

    private func makeMainBlocks(
        context: LLVMCAPIBindings.LLVMContextRef,
        mainFunction: LLVMCAPIBindings.LLVMValueRef
    ) throws -> LLVMEntryPointBlocks {
        guard let entryBlock = bindings.appendBasicBlock(context: context, function: mainFunction, name: "entry"),
              let successBlock = bindings.appendBasicBlock(context: context, function: mainFunction, name: "success"),
              let failureBlock = bindings.appendBasicBlock(context: context, function: mainFunction, name: "failure")
        else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create entry wrapper basic blocks")
        }
        return LLVMEntryPointBlocks(entryBlock: entryBlock, successBlock: successBlock, failureBlock: failureBlock)
    }

    private func makeMainConstants(
        builder: LLVMCAPIBindings.LLVMBuilderRef,
        primitiveTypes: LLVMEntryPointPrimitiveTypes
    ) throws -> LLVMEntryPointConstants {
        guard let thrownSlot = bindings.buildAlloca(builder, type: primitiveTypes.int64Type, name: "thrown.slot"),
              let zero = bindings.constInt(primitiveTypes.int64Type, value: 0),
              let zero32 = bindings.constInt(primitiveTypes.int32Type, value: 0),
              let one32 = bindings.constInt(primitiveTypes.int32Type, value: 1),
              let stderrFD = bindings.constInt(primitiveTypes.int64Type, value: 2),
              let panicMessageLength = bindings.constInt(
                  primitiveTypes.int64Type,
                  value: UInt64(panicMessageText.utf8.count)
              )
        else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create entry wrapper constants")
        }
        guard bindings.buildStore(builder, value: zero, pointer: thrownSlot) != nil else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to initialize thrown channel")
        }
        return LLVMEntryPointConstants(
            thrownSlot: thrownSlot,
            zero: zero,
            zero32: zero32,
            one32: one32,
            stderrFD: stderrFD,
            panicMessageLength: panicMessageLength
        )
    }

    private func emitEntryDispatch(
        builder: LLVMCAPIBindings.LLVMBuilderRef,
        blocks: LLVMEntryPointBlocks,
        primitiveTypes: LLVMEntryPointPrimitiveTypes,
        functionTypes: LLVMEntryPointFunctionTypes,
        functions: LLVMEntryPointFunctions,
        constants: LLVMEntryPointConstants
    ) throws {
        // `main`'s own result is deliberately discarded: only the call's side
        // effects and the thrown channel matter to the process status.
        _ = try emitEntryResult(
            builder: builder,
            functionTypes: functionTypes,
            functions: functions,
            constants: constants
        )
        guard let thrownValue = bindings.buildLoad(
            builder,
            type: primitiveTypes.int64Type,
            pointer: constants.thrownSlot,
            name: "thrown.value"
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to load thrown channel")
        }
        guard let hasThrown = bindings.buildICmpNotEqual(
            builder,
            lhs: thrownValue,
            rhs: constants.zero,
            name: "has.thrown"
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to compare thrown channel")
        }
        guard bindings.buildCondBr(
            builder,
            condition: hasThrown,
            thenBlock: blocks.failureBlock,
            elseBlock: blocks.successBlock
        ) != nil else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to emit entry wrapper branch")
        }
    }

    private func emitEntryResult(
        builder: LLVMCAPIBindings.LLVMBuilderRef,
        functionTypes: LLVMEntryPointFunctionTypes,
        functions: LLVMEntryPointFunctions,
        constants: LLVMEntryPointConstants
    ) throws -> LLVMCAPIBindings.LLVMValueRef {
        guard let entryResult = bindings.buildCall(
            builder,
            functionType: functionTypes.entryType,
            callee: functions.entryFunction,
            arguments: [constants.thrownSlot],
            name: "entry.result"
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to emit entry function call")
        }
        return entryResult
    }

    private func emitFailurePath(
        builder: LLVMCAPIBindings.LLVMBuilderRef,
        functionTypes: LLVMEntryPointFunctionTypes,
        functions: LLVMEntryPointFunctions,
        constants: LLVMEntryPointConstants
    ) throws {
        guard let panicMessage = bindings.buildGlobalStringPtr(
            builder,
            value: panicMessageText,
            name: "panic.message"
        ) else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to create panic message literal")
        }
        guard bindings.buildCall(
            builder,
            functionType: functionTypes.writeType,
            callee: functions.writeFunction,
            arguments: [constants.stderrFD, panicMessage, constants.panicMessageLength],
            name: "stderr.write"
        ) != nil else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to emit stderr write")
        }
        guard bindings.buildRet(builder, value: constants.one32) != nil else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to emit failure return")
        }
    }

    /// Returns `0` for every normal completion of `main`.
    ///
    /// Kotlin never uses the value of `main` as the process status: a valid
    /// entry point returns `Unit`, and a program chooses a non-zero status
    /// through `kotlin.system.exitProcess`, which terminates the process
    /// directly (`__kk_system_exitProcess` returns `Never`) without ever
    /// reaching this wrapper. Earlier this path truncated the entry
    /// function's `i64` result into the `main` ABI's `i32`, so any `main`
    /// whose inferred type was not `Unit` leaked its return value — or, when
    /// that value was a boxed object, the low bits of a heap pointer — into
    /// the exit status. `fun main() = runBlocking { 42 }` exited 42, and
    /// shapes whose type widened to `Any` (`coroutineScope`/`await` are
    /// modelled as returning `Any`) exited with a different garbage status on
    /// each run of the same binary.
    private func emitSuccessPath(
        builder: LLVMCAPIBindings.LLVMBuilderRef,
        constants: LLVMEntryPointConstants
    ) throws {
        guard bindings.buildRet(builder, value: constants.zero32) != nil else {
            throw LLVMEntryPointObjectEmitterError.invalidIR("failed to emit success return")
        }
    }
}
