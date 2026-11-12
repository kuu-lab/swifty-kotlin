import Foundation

import CompilerCore

extension NativeEmitter {

    /// One partition worker's emitted LLVM module plus the context that owns it.
    typealias PartitionModule = (
        context: LLVMCAPIBindings.LLVMContextRef,
        module: LLVMCAPIBindings.LLVMModuleRef
    )

    /// Whether function bodies may be emitted into per-partition LLVM modules
    /// and merged afterwards. Parallel emission requires the LLVMLinkModules2
    /// binding, more than one worker and function, and a fully materialized
    /// symbol table — lazy imported-metadata loads mutate TypeSystem without
    /// synchronization, so queries during emission are only safe serially.
    /// Debug info keeps the serial path: DIBuilder and DI metadata are
    /// per-module state that cannot be split across worker contexts.
    func canEmitFunctionBodiesInParallel(emittableCount: Int) -> Bool {
        parallelJobs > 1
            && emittableCount > 1
            && !debugInfo
            && bindings.linkModules2Fn != nil
            && symbols?.hasLazySymbolMaterialization != true
    }

    /// Emits function bodies in contiguous partitions of the symbol-sorted
    /// emittable list. Each partition builds a private LLVM context + module
    /// (LLVM contexts must not be shared between threads), emits its chunk,
    /// then the partition modules merge into `llvmModule` in partition order
    /// via LLVMLinkModules2.
    ///
    /// Per-partition private globals (e.g. `str_lit_*` string literals) can
    /// collide by name; LLVM renames them when modules merge. Because the
    /// merge order is fixed, the resulting module — and therefore the object
    /// file — is deterministic.
    ///
    /// Returns the worker contexts, which the caller must keep alive until the
    /// merged module is disposed: cross-context value remapping can retain
    /// references into a source context's type state even after the merge
    /// call returns.
    func emitFunctionBodiesInParallel(
        emittableFunctions: [(KIRFunction, String)],
        runtimeCallbackRawABISymbols: Set<SymbolID>,
        into llvmModule: LLVMCAPIBindings.LLVMModuleRef
    ) throws -> [LLVMCAPIBindings.LLVMContextRef] {
        let partitionCount = min(parallelJobs, emittableFunctions.count)
        let chunkSize = (emittableFunctions.count + partitionCount - 1) / partitionCount
        let workerCount = (emittableFunctions.count + chunkSize - 1) / chunkSize
        let input = PartitionedEmissionInput(
            emitter: self,
            functions: emittableFunctions,
            runtimeCallbackRawABISymbols: runtimeCallbackRawABISymbols,
            chunkSize: chunkSize,
            workerCount: workerCount
        )
        PhaseTimer.measureSubPhase("IR/partition bodies", timer: phaseTimer) {
            DispatchQueue.concurrentPerform(iterations: workerCount) { index in
                input.runWorker(at: index)
            }
        }
        var retainedContexts: [LLVMCAPIBindings.LLVMContextRef] = []
        do {
            try input.rethrowFirstError()
            try PhaseTimer.measureSubPhase("IR/partition merge", timer: phaseTimer) {
                for index in 0 ..< workerCount {
                    let partition = try input.partition(at: index)
                    guard bindings.linkModules(destination: llvmModule, source: partition.module) else {
                        // LLVMLinkModules2 takes ownership of the source module
                        // unconditionally — even on failure — so only the slot
                        // and context are cleaned up here.
                        input.clearPartition(at: index)
                        bindings.disposeContext(partition.context)
                        throw LLVMBackendError.nativeEmissionFailed(
                            "LLVMLinkModules2 failed while merging codegen partition \(index)"
                        )
                    }
                    // The linked module is consumed; its context is retained so
                    // the merged module can keep referencing its type state.
                    input.clearPartition(at: index)
                    retainedContexts.append(partition.context)
                }
            }
        } catch {
            // Dispose partitions that were never merged; merged contexts are
            // retained above and freed here since the module stays unreturned.
            input.disposeUnmergedPartitions(using: bindings)
            for partitionContext in retainedContexts {
                bindings.disposeContext(partitionContext)
            }
            throw error
        }
        return retainedContexts
    }

    /// Emits a library as a primary globals/metadata object plus one
    /// independently compiled object file per function partition, running both
    /// IR construction and LLVM machine-code emission in parallel across cores.
    func emitPartitionedObjects(
        outputObjectsDir: String,
        moduleName: String
    ) throws -> [String] {
        let runtimeCallbackRawABISymbols = Self.collectRuntimeCallbackRawABISymbols(
            module: module,
            interner: interner,
            symbols: symbols
        )
        let emittableFunctions = try collectEmittableFunctionsForPartitioning(
            runtimeCallbackRawABISymbols: runtimeCallbackRawABISymbols
        )
        guard canEmitFunctionBodiesInParallel(emittableCount: emittableFunctions.count) else {
            let relPath = "objects/\(moduleName)_0.o"
            try emitObject(outputPath: outputObjectsDir + "/\(moduleName)_0.o", bitcodeOutputPath: nil)
            return [relPath]
        }

        let workerCount = min(parallelJobs, emittableFunctions.count)
        var buckets: [[(KIRFunction, String)]] = Array(repeating: [], count: workerCount)
        for (index, item) in emittableFunctions.enumerated() {
            buckets[index % workerCount].append(item)
        }

        let primaryRelPath = "objects/\(moduleName)_0.o"
        let primaryOutPath = outputObjectsDir + "/\(moduleName)_0.o"
        let partitionRelPaths = (0 ..< workerCount).map { "objects/\(moduleName)_\($0 + 1).o" }
        let partitionOutPaths = (0 ..< workerCount).map { "\(outputObjectsDir)/\(moduleName)_\($0 + 1).o" }

        let driver = PartitionedObjectEmissionDriver(
            emitter: self,
            buckets: buckets,
            outputPaths: partitionOutPaths,
            runtimeCallbackRawABISymbols: runtimeCallbackRawABISymbols
        )

        PhaseTimer.measureSubPhase("IR+obj/partition parallel", timer: phaseTimer) {
            DispatchQueue.concurrentPerform(iterations: workerCount + 1) { taskIndex in
                if taskIndex == workerCount {
                    driver.runPrimaryGlobalsWorker(outputPath: primaryOutPath)
                } else {
                    driver.runPartitionWorker(at: taskIndex)
                }
            }
        }
        try driver.rethrowFirstError()
        return [primaryRelPath] + partitionRelPaths
    }

    private func collectEmittableFunctionsForPartitioning(
        runtimeCallbackRawABISymbols: Set<SymbolID>
    ) throws -> [(KIRFunction, String)] {
        guard let probeContext = bindings.createContext(),
              let probeModule = bindings.createModule(name: "kswiftk_probe", context: probeContext),
              let int64Type = bindings.int64Type(context: probeContext),
              let outThrownPointerType = bindings.pointerType(int64Type, addressSpace: 0)
        else {
            throw LLVMBackendError.nativeEmissionFailed("failed to probe emittable functions")
        }
        defer {
            bindings.disposeModule(probeModule)
            bindings.disposeContext(probeContext)
        }
        let typeLowering = makeLLVMTypeLowering(context: probeContext, int64Type: int64Type)
        let declared = try declareFunctions(
            llvmModule: probeModule,
            int64Type: int64Type,
            outThrownPointerType: outThrownPointerType,
            typeLowering: typeLowering,
            runtimeCallbackRawABISymbols: runtimeCallbackRawABISymbols,
            definedSymbols: []
        )
        return declared.emittableFunctions
    }

    fileprivate func emitPrimaryGlobalsObject(outputPath: String) throws {
        guard let context = bindings.createContext() else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMContextCreate returned null")
        }
        guard let llvmModule = bindings.createModule(name: "kswiftk_globals", context: context) else {
            bindings.disposeContext(context)
            throw LLVMBackendError.nativeEmissionFailed("LLVMModuleCreateWithNameInContext returned null")
        }
        defer {
            bindings.disposeModule(llvmModule)
            bindings.disposeContext(context)
        }
        guard let int64Type = bindings.int64Type(context: context) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMInt64TypeInContext returned null")
        }
        var globalVariables = declareGlobals(
            llvmModule: llvmModule,
            int64Type: int64Type,
            emitDefinitions: true
        )
        ensureImportedGlobalReferences(
            module: module,
            llvmModule: llvmModule,
            int64Type: int64Type,
            emitDefinitions: true,
            globalVariables: &globalVariables
        )
        RuntimeReflectionMetadataEmitter.emitGlobals(
            records: reflectionMetadataRecords,
            bindings: bindings,
            module: llvmModule,
            context: context,
            int64Type: int64Type,
            symbolPrefix: reflectionMetadataSymbolPrefix
        )
        try emitModuleToObjectFile(llvmModule: llvmModule, outputPath: outputPath)
    }

    fileprivate func emitModuleToObjectFile(
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        outputPath: String
    ) throws {
        try CodegenCriticalSection.withLinuxLLVMProcessLock(target: target) {
            let targetMachine = try configuredTargetMachine(for: llvmModule)
            defer { bindings.disposeTargetMachine(targetMachine) }
            if let error = bindings.optimizeModule(llvmModule, targetMachine: targetMachine, optLevel: optLevel) {
                throw LLVMBackendError.nativeEmissionFailed(error)
            }
            if let errorMessage = bindings.emitObject(targetMachine: targetMachine, module: llvmModule, outputPath: outputPath) {
                throw LLVMBackendError.nativeEmissionFailed(errorMessage)
            }
        }
    }

    /// Emits one partition's functions into a private context/module. The
    /// module gets extern declarations for every global and function (matching
    /// the primary module's declarations) plus definitions for the chunk's own
    /// functions; merging upgrades those declarations in the primary module.
    private func emitFunctionPartitionModule(
        functions: ArraySlice<(KIRFunction, String)>,
        runtimeCallbackRawABISymbols: Set<SymbolID>
    ) throws -> PartitionModule {
        guard let context = bindings.createContext() else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMContextCreate returned null")
        }
        guard let llvmModule = bindings.createModule(name: "kswiftk_module_partition", context: context) else {
            bindings.disposeContext(context)
            throw LLVMBackendError.nativeEmissionFailed("LLVMModuleCreateWithNameInContext returned null")
        }
        do {
            guard let int64Type = bindings.int64Type(context: context),
                  let outThrownPointerType = bindings.pointerType(int64Type, addressSpace: 0)
            else {
                throw LLVMBackendError.nativeEmissionFailed("partition LLVM type creation returned null")
            }
            let typeLowering = makeLLVMTypeLowering(context: context, int64Type: int64Type)
            var globalVariables = declareGlobals(
                llvmModule: llvmModule,
                int64Type: int64Type,
                emitDefinitions: false
            )
            ensureImportedGlobalReferences(
                module: module,
                llvmModule: llvmModule,
                int64Type: int64Type,
                emitDefinitions: false,
                globalVariables: &globalVariables
            )
            let declared = try declareFunctions(
                llvmModule: llvmModule,
                int64Type: int64Type,
                outThrownPointerType: outThrownPointerType,
                typeLowering: typeLowering,
                runtimeCallbackRawABISymbols: runtimeCallbackRawABISymbols,
                definedSymbols: Set(functions.map { $0.0.symbol })
            )
            let nameCounter = GeneratedNameCounter()
            for (function, _) in functions {
                guard let llvmFunction = declared.internalFunctions[function.symbol] else { continue }
                let usesRuntimeCallbackRawABI = runtimeCallbackRawABISymbols.contains(function.symbol)
                let returnsRawStringRuntimeCallback = usesRuntimeCallbackRawABI
                    && isStringAggregateType(
                        function.returnType,
                        typeSystem: typeSystem,
                        hasStringLowering: typeLowering != nil
                    )
                try emitFunctionBody(
                    function: function,
                    llvmFunction: llvmFunction,
                    llvmModule: llvmModule,
                    context: context,
                    int64Type: int64Type,
                    typeLowering: typeLowering,
                    outThrownPointerType: outThrownPointerType,
                    internalFunctions: declared.internalFunctions,
                    internalSignatures: declared.internalSignatures,
                    internalFunctionsByLookupKey: declared.internalFunctionsByLookupKey,
                    globalVariables: globalVariables,
                    runtimeCallbackRawReturnSymbols: runtimeCallbackRawABISymbols,
                    usesRuntimeCallbackRawABI: usesRuntimeCallbackRawABI,
                    returnsRawStringRuntimeCallback: returnsRawStringRuntimeCallback,
                    nameCounter: nameCounter,
                    diContext: nil
                )
            }
            return (context: context, module: llvmModule)
        } catch {
            bindings.disposeModule(llvmModule)
            bindings.disposeContext(context)
            throw error
        }
    }

    /// Shared inputs and ordered result slots for the emission workers.
    /// `@unchecked Sendable`: each worker mutates only its private LLVM
    /// context/module and its own result slot under `lock`. Every shared
    /// reference is read-only during body emission (KIR arena, emitter fields)
    /// or internally synchronized (SymbolTable, StringInterner); TypeSystem is
    /// read-only here because `canEmitFunctionBodiesInParallel` requires the
    /// lazy imported-state machinery to be absent.
    private final class PartitionedEmissionInput: @unchecked Sendable {
        let emitter: NativeEmitter
        let functions: [(KIRFunction, String)]
        let runtimeCallbackRawABISymbols: Set<SymbolID>
        let chunkSize: Int
        private let lock = NSLock()
        private var slots: [Result<PartitionModule, any Error>?]

        init(
            emitter: NativeEmitter,
            functions: [(KIRFunction, String)],
            runtimeCallbackRawABISymbols: Set<SymbolID>,
            chunkSize: Int,
            workerCount: Int
        ) {
            self.emitter = emitter
            self.functions = functions
            self.runtimeCallbackRawABISymbols = runtimeCallbackRawABISymbols
            self.chunkSize = chunkSize
            slots = Array(repeating: nil, count: workerCount)
        }

        func runWorker(at index: Int) {
            let start = index * chunkSize
            let end = min(start + chunkSize, functions.count)
            let result: Result<PartitionModule, any Error>
            do {
                result = .success(try emitter.emitFunctionPartitionModule(
                    functions: functions[start ..< end],
                    runtimeCallbackRawABISymbols: runtimeCallbackRawABISymbols
                ))
            } catch {
                result = .failure(error)
            }
            lock.lock()
            slots[index] = result
            lock.unlock()
        }

        func rethrowFirstError() throws {
            lock.lock()
            defer { lock.unlock() }
            for slot in slots {
                if case let .failure(error) = slot {
                    throw error
                }
            }
        }

        func partition(at index: Int) throws -> PartitionModule {
            lock.lock()
            defer { lock.unlock() }
            guard let slot = slots[index] else {
                throw LLVMBackendError.nativeEmissionFailed("codegen partition \(index) produced no module")
            }
            return try slot.get()
        }

        /// Marks a partition's module consumed by LLVMLinkModules2 so cleanup
        /// passes never dispose it a second time.
        func clearPartition(at index: Int) {
            lock.lock()
            slots[index] = nil
            lock.unlock()
        }

        /// Disposes module+context for every partition not consumed by a merge.
        func disposeUnmergedPartitions(using bindings: LLVMCAPIBindings) {
            lock.lock()
            let remaining = slots
            slots = Array(repeating: nil, count: slots.count)
            lock.unlock()
            for slot in remaining {
                guard case let .success(partition) = slot else { continue }
                bindings.disposeModule(partition.module)
                bindings.disposeContext(partition.context)
            }
        }
    }

    private final class PartitionedObjectEmissionDriver: @unchecked Sendable {
        let emitter: NativeEmitter
        let buckets: [[(KIRFunction, String)]]
        let outputPaths: [String]
        let runtimeCallbackRawABISymbols: Set<SymbolID>
        private let lock = NSLock()
        private var errors: [any Error] = []

        init(
            emitter: NativeEmitter,
            buckets: [[(KIRFunction, String)]],
            outputPaths: [String],
            runtimeCallbackRawABISymbols: Set<SymbolID>
        ) {
            self.emitter = emitter
            self.buckets = buckets
            self.outputPaths = outputPaths
            self.runtimeCallbackRawABISymbols = runtimeCallbackRawABISymbols
        }

        func runPrimaryGlobalsWorker(outputPath: String) {
            do {
                try emitter.emitPrimaryGlobalsObject(outputPath: outputPath)
            } catch {
                recordError(error)
            }
        }

        func runPartitionWorker(at index: Int) {
            do {
                let partition = try emitter.emitFunctionPartitionModule(
                    functions: ArraySlice(buckets[index]),
                    runtimeCallbackRawABISymbols: runtimeCallbackRawABISymbols
                )
                defer {
                    emitter.bindings.disposeModule(partition.module)
                    emitter.bindings.disposeContext(partition.context)
                }
                try emitter.emitModuleToObjectFile(
                    llvmModule: partition.module,
                    outputPath: outputPaths[index]
                )
            } catch {
                recordError(error)
            }
        }

        private func recordError(_ error: any Error) {
            lock.lock()
            errors.append(error)
            lock.unlock()
        }

        func rethrowFirstError() throws {
            lock.lock()
            let first = errors.first
            lock.unlock()
            if let first {
                throw first
            }
        }
    }
}
