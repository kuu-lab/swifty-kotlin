import Foundation

import CompilerCore

extension NativeEmitter {

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
            input.disposeUnmergedPartitions(using: bindings)
            for partitionContext in retainedContexts {
                bindings.disposeContext(partitionContext)
            }
            throw error
        }
        return retainedContexts
    }

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
        let startupIndices = optLevel == .O0 ? [] : emittableFunctions.indices.filter {
            Self.isStartupReflectionInitializer(interner.resolve(emittableFunctions[$0].0.name))
        }
        let startupSet = Set(startupIndices)
        let optimizedIndices = emittableFunctions.indices.filter { !startupSet.contains($0) }
        func partitions(of indices: [Int], workers: Int) -> [[Int]] {
            Self.planObjectPartitions(
                weights: indices.map { emittableFunctions[$0].0.body.count },
                workerCount: workers,
                maxWeightPerPartition: maxInstructionsPerObjectPartition
            ).map { partition in partition.map { indices[$0] } }
        }
        let plan = partitions(of: optimizedIndices, workers: workerCount).map { ($0, optLevel) }
            + partitions(of: startupIndices, workers: 1).map { ($0, OptimizationLevel.O0) }
        let buckets = plan.map { partition in partition.0.map { emittableFunctions[$0] } }
        let partitionCount = buckets.count
        if ProcessInfo.processInfo.environment["KSWIFTK_DEBUG_PARTITION_TIMING"] == "1" {
            let weights = emittableFunctions.map { (max($0.0.body.count, 1), $0.1) }
            let total = weights.reduce(0) { $0 + $1.0 }
            let top = weights.sorted { $0.0 > $1.0 }.prefix(8).map { "\($0.0):\($0.1.prefix(60))" }
            FileHandle.standardError.write(Data(
                "KSWIFTK_PARTITION_PLAN functions=\(emittableFunctions.count) startup=\(startupIndices.count) weight=\(total) partitions=\(partitionCount) workers=\(workerCount) top=\(top)\n".utf8
            ))
        }

        let primaryRelPath = "objects/\(moduleName)_0.o"
        let primaryOutPath = outputObjectsDir + "/\(moduleName)_0.o"
        let partitionRelPaths = (0 ..< partitionCount).map { "objects/\(moduleName)_\($0 + 1).o" }
        let partitionOutPaths = (0 ..< partitionCount).map { "\(outputObjectsDir)/\(moduleName)_\($0 + 1).o" }

        let driver = PartitionedObjectEmissionDriver(
            emitter: self,
            buckets: buckets,
            optimizationLevels: plan.map(\.1),
            outputPaths: partitionOutPaths,
            runtimeCallbackRawABISymbols: runtimeCallbackRawABISymbols
        )

        PhaseTimer.measureSubPhase("IR+obj/partition parallel", timer: phaseTimer) {
            DispatchQueue.concurrentPerform(iterations: workerCount + 1) { taskIndex in
                if taskIndex == workerCount {
                    driver.runPrimaryGlobalsWorker(outputPath: primaryOutPath)
                } else {
                    while let partitionIndex = driver.claimNextPartition() {
                        driver.runPartitionWorker(at: partitionIndex)
                    }
                }
            }
        }
        try driver.rethrowFirstError()
        return [primaryRelPath] + partitionRelPaths
    }

    static func isStartupReflectionInitializer(_ name: String) -> Bool {
        name.hasPrefix("__ctor_reflect_init_")
    }

    static func planObjectPartitions(weights: [Int], workerCount: Int, maxWeightPerPartition: Int) -> [[Int]] {
        guard !weights.isEmpty, workerCount > 0 else { return [] }
        let costs = weights.map { max($0, 1) }
        let totalCost = costs.reduce(0, +)
        let budget = max(maxWeightPerPartition, 1)
        let partitionCount = min(costs.count, max(workerCount, (totalCost + budget - 1) / budget))
        let heaviestFirst = costs.indices.sorted { lhs, rhs in
            costs[lhs] != costs[rhs] ? costs[lhs] > costs[rhs] : lhs < rhs
        }
        var partitions = Array(repeating: [Int](), count: partitionCount)
        var loads = Array(repeating: 0, count: partitionCount)
        for function in heaviestFirst {
            var target = 0
            for candidate in 1 ..< partitionCount where loads[candidate] < loads[target] {
                target = candidate
            }
            partitions[target].append(function)
            loads[target] += costs[function]
        }
        let claimOrder = partitions.indices.sorted { lhs, rhs in
            loads[lhs] != loads[rhs] ? loads[lhs] > loads[rhs] : lhs < rhs
        }
        return claimOrder.map { partitions[$0].sorted() }
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
            emitDefinitions: true,
            definitionsUsedOnlyByOtherObjects: true
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
        outputPath: String,
        optLevel moduleOptLevel: OptimizationLevel? = nil
    ) throws {
        let level = moduleOptLevel ?? optLevel
        try CodegenCriticalSection.withLinuxLLVMProcessLock(target: target) {
            let targetMachine = try configuredTargetMachine(for: llvmModule, optLevel: level)
            defer { bindings.disposeTargetMachine(targetMachine) }
            if let error = bindings.optimizeModule(llvmModule, targetMachine: targetMachine, optLevel: level) {
                throw LLVMBackendError.nativeEmissionFailed(error)
            }
            if let errorMessage = bindings.emitObject(targetMachine: targetMachine, module: llvmModule, outputPath: outputPath) {
                throw LLVMBackendError.nativeEmissionFailed(errorMessage)
            }
        }
    }

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

        func clearPartition(at index: Int) {
            lock.lock()
            slots[index] = nil
            lock.unlock()
        }

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
        let optimizationLevels: [OptimizationLevel]
        let outputPaths: [String]
        let runtimeCallbackRawABISymbols: Set<SymbolID>
        private let lock = NSLock()
        private var errors: [any Error] = []
        private var nextPartitionIndex = 0

        init(
            emitter: NativeEmitter,
            buckets: [[(KIRFunction, String)]],
            optimizationLevels: [OptimizationLevel],
            outputPaths: [String],
            runtimeCallbackRawABISymbols: Set<SymbolID>
        ) {
            self.emitter = emitter
            self.buckets = buckets
            self.optimizationLevels = optimizationLevels
            self.outputPaths = outputPaths
            self.runtimeCallbackRawABISymbols = runtimeCallbackRawABISymbols
        }

        func claimNextPartition() -> Int? {
            lock.lock()
            defer { lock.unlock() }
            guard errors.isEmpty, nextPartitionIndex < buckets.count else { return nil }
            let index = nextPartitionIndex
            nextPartitionIndex += 1
            return index
        }

        func runPrimaryGlobalsWorker(outputPath: String) {
            do {
                try emitter.emitPrimaryGlobalsObject(outputPath: outputPath)
            } catch {
                recordError(error)
            }
        }

        func runPartitionWorker(at index: Int) {
            let debugStart = Date()
            var debugIRSeconds = 0.0
            do {
                let partition = try emitter.emitFunctionPartitionModule(
                    functions: ArraySlice(buckets[index]),
                    runtimeCallbackRawABISymbols: runtimeCallbackRawABISymbols
                )
                debugIRSeconds = Date().timeIntervalSince(debugStart)
                defer {
                    emitter.bindings.disposeModule(partition.module)
                    emitter.bindings.disposeContext(partition.context)
                }
                try emitter.emitModuleToObjectFile(
                    llvmModule: partition.module,
                    outputPath: outputPaths[index],
                    optLevel: optimizationLevels[index]
                )
            } catch {
                recordError(error)
            }
            if ProcessInfo.processInfo.environment["KSWIFTK_DEBUG_PARTITION_TIMING"] == "1" {
                let weight = buckets[index].reduce(0) { $0 + max($1.0.body.count, 1) }
                let line = String(
                    format: "KSWIFTK_PARTITION index=%d opt=%d functions=%d weight=%d ir=%.1fs total=%.1fs\n",
                    index, optimizationLevels[index].rawValue, buckets[index].count, weight, debugIRSeconds, Date().timeIntervalSince(debugStart)
                )
                FileHandle.standardError.write(Data(line.utf8))
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
