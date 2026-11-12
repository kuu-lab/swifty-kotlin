
import CompilerCore
import Foundation

final class LLVMBackend {
    let target: TargetTriple
    private let moduleName: String
    private let optLevel: OptimizationLevel
    private let debugInfo: Bool
    let diagnostics: DiagnosticEngine
    private let bindings: LLVMCAPIBindings
    private let reusableContext: LLVMCAPIBindings.LLVMContextRef?
    private let phaseTimer: PhaseTimer?
    private let parallelJobs: Int

    init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        diagnostics: DiagnosticEngine,
        moduleName: String = "main",
        phaseTimer: PhaseTimer? = nil,
        parallelJobs: Int = 1,
        session: LLVMBackendSession = LLVMBackendSession()
    ) throws {
        self.target = target
        self.moduleName = moduleName
        self.phaseTimer = phaseTimer
        self.parallelJobs = parallelJobs
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.diagnostics = diagnostics

        guard let bindings = session.loadBindings() else {
            diagnostics.error(
                "KSWIFTK-BACKEND-1007",
                "LLVM backend is unavailable because the LLVM C API bindings could not be loaded.",
                range: nil
            )
            throw LLVMBackendError.bindingsUnavailable
        }
        self.bindings = bindings
        self.reusableContext = session.reusableContext(for: bindings)
    }

    func emitObject(
        module: KIRModule,
        outputObjectPath: String,
        interner: StringInterner,
        typeSystem: TypeSystem? = nil,
        symbols: SymbolTable? = nil,
        sourceManager: SourceManager? = nil,
        fileFacadeNamesByFileID: [Int32: String] = [:],
        reflectionMetadataRecords: [MetadataRecord] = [],
        reflectionMetadataSymbolPrefix: String? = nil,
        linkOnceODRSymbols: Set<SymbolID> = [],
        bitcodeOutputPath: String? = nil
    ) throws {
        try emitNative(
            context: "object",
            nativeEmit: { bindings in
                let emitter = withSubPhaseTiming("initEmitter", timer: phaseTimer) {
                    makeEmitter(
                        bindings: bindings,
                        module: module,
                        interner: interner,
                        typeSystem: typeSystem,
                        symbols: symbols,
                        sourceManager: sourceManager,
                        fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                        reflectionMetadataRecords: reflectionMetadataRecords,
                        reflectionMetadataSymbolPrefix: reflectionMetadataSymbolPrefix,
                        linkOnceODRSymbols: linkOnceODRSymbols
                    )
                }
                try emitter.emitObject(outputPath: outputObjectPath, bitcodeOutputPath: bitcodeOutputPath)
            }
        )
    }

    func emitExecutableObjects(
        module: KIRModule,
        outputObjectPath: String,
        outputObjectsDir: String,
        interner: StringInterner,
        typeSystem: TypeSystem? = nil,
        symbols: SymbolTable? = nil,
        sourceManager: SourceManager? = nil,
        fileFacadeNamesByFileID: [Int32: String] = [:],
        reflectionMetadataRecords: [MetadataRecord] = [],
        reflectionMetadataSymbolPrefix: String? = nil,
        linkOnceODRSymbols: Set<SymbolID> = []
    ) throws -> [String] {
        guard parallelJobs > 1, !debugInfo else {
            try emitObject(
                module: module,
                outputObjectPath: outputObjectPath,
                interner: interner,
                typeSystem: typeSystem,
                symbols: symbols,
                sourceManager: sourceManager,
                fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                reflectionMetadataRecords: reflectionMetadataRecords,
                reflectionMetadataSymbolPrefix: reflectionMetadataSymbolPrefix,
                linkOnceODRSymbols: linkOnceODRSymbols
            )
            return [outputObjectPath]
        }
        try FileManager.default.createDirectory(atPath: outputObjectsDir, withIntermediateDirectories: true)
        var relativePaths: [String] = []
        try emitNative(
            context: "partitioned executable objects",
            nativeEmit: { bindings in
                let emitter = withSubPhaseTiming("initEmitter", timer: phaseTimer) {
                    makeEmitter(
                        bindings: bindings,
                        module: module,
                        interner: interner,
                        typeSystem: typeSystem,
                        symbols: symbols,
                        sourceManager: sourceManager,
                        fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                        reflectionMetadataRecords: reflectionMetadataRecords,
                        reflectionMetadataSymbolPrefix: reflectionMetadataSymbolPrefix,
                        linkOnceODRSymbols: linkOnceODRSymbols
                    )
                }
                relativePaths = try emitter.emitPartitionedObjects(
                    outputObjectsDir: outputObjectsDir,
                    moduleName: moduleName
                )
            }
        )
        return relativePaths.map { outputObjectsDir + "/" + ($0 as NSString).lastPathComponent }
    }

    func emitLibraryObjects(
        module: KIRModule,
        outputObjectsDir: String,
        interner: StringInterner,
        typeSystem: TypeSystem? = nil,
        symbols: SymbolTable? = nil,
        sourceManager: SourceManager? = nil,
        fileFacadeNamesByFileID: [Int32: String] = [:],
        reflectionMetadataRecords: [MetadataRecord] = [],
        reflectionMetadataSymbolPrefix: String? = nil,
        linkOnceODRSymbols: Set<SymbolID> = [],
        bitcodeOutputPath: String? = nil
    ) throws -> [String] {
        var relativeObjectPaths: [String] = []
        try emitNative(
            context: "library objects",
            nativeEmit: { bindings in
                let emitter = withSubPhaseTiming("initEmitter", timer: phaseTimer) {
                    makeEmitter(
                        bindings: bindings,
                        module: module,
                        interner: interner,
                        typeSystem: typeSystem,
                        symbols: symbols,
                        sourceManager: sourceManager,
                        fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                        reflectionMetadataRecords: reflectionMetadataRecords,
                        reflectionMetadataSymbolPrefix: reflectionMetadataSymbolPrefix,
                        linkOnceODRSymbols: linkOnceODRSymbols
                    )
                }
                if parallelJobs > 1, bitcodeOutputPath == nil {
                    relativeObjectPaths = try emitter.emitPartitionedObjects(
                        outputObjectsDir: outputObjectsDir,
                        moduleName: moduleName
                    )
                } else {
                    let objectPath = outputObjectsDir + "/\(moduleName)_0.o"
                    try emitter.emitObject(outputPath: objectPath, bitcodeOutputPath: bitcodeOutputPath)
                    relativeObjectPaths = ["objects/\(moduleName)_0.o"]
                }
            }
        )
        return relativeObjectPaths
    }

    private func makeEmitter(
        bindings: LLVMCAPIBindings,
        module: KIRModule,
        interner: StringInterner,
        typeSystem: TypeSystem?,
        symbols: SymbolTable?,
        sourceManager: SourceManager?,
        fileFacadeNamesByFileID: [Int32: String],
        reflectionMetadataRecords: [MetadataRecord],
        reflectionMetadataSymbolPrefix: String?,
        linkOnceODRSymbols: Set<SymbolID>
    ) -> NativeEmitter {
        NativeEmitter(
            target: target,
            optLevel: optLevel,
            debugInfo: debugInfo,
            bindings: bindings,
            reusableContext: reusableContext,
            module: module,
            interner: interner,
            moduleName: moduleName,
            typeSystem: typeSystem,
            symbols: symbols,
            sourceManager: sourceManager,
            fileFacadeNamesByFileID: fileFacadeNamesByFileID,
            reflectionMetadataRecords: reflectionMetadataRecords,
            reflectionMetadataSymbolPrefix: reflectionMetadataSymbolPrefix,
            linkOnceODRSymbols: linkOnceODRSymbols,
            parallelJobs: parallelJobs,
            phaseTimer: phaseTimer
        )
    }

    func emitLLVMIR(
        module: KIRModule,
        outputIRPath: String,
        interner: StringInterner,
        typeSystem: TypeSystem? = nil,
        symbols: SymbolTable? = nil,
        sourceManager: SourceManager? = nil,
        fileFacadeNamesByFileID: [Int32: String] = [:],
        reflectionMetadataRecords: [MetadataRecord] = [],
        reflectionMetadataSymbolPrefix: String? = nil
    ) throws {
        try emitNative(
            context: "LLVM IR",
            nativeEmit: { bindings in
                let emitter = withSubPhaseTiming("initEmitter", timer: phaseTimer) {
                    NativeEmitter(
                        target: target,
                        optLevel: optLevel,
                        debugInfo: debugInfo,
                        bindings: bindings,
                        reusableContext: reusableContext,
                        module: module,
                        interner: interner,
                        moduleName: moduleName,
                        typeSystem: typeSystem,
                        symbols: symbols,
                        sourceManager: sourceManager,
                        fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                        reflectionMetadataRecords: reflectionMetadataRecords,
                        reflectionMetadataSymbolPrefix: reflectionMetadataSymbolPrefix,
                        parallelJobs: parallelJobs,
                        phaseTimer: phaseTimer
                    )
                }
                try emitter.emitLLVMIR(outputPath: outputIRPath)
            }
        )
    }

    private func emitNative(
        context: String,
        nativeEmit: (LLVMCAPIBindings) throws -> Void
    ) throws {
        do {
            try nativeEmit(bindings)
        } catch {
            let reason = describe(error: error)
            diagnostics.error(
                "KSWIFTK-BACKEND-1006",
                "LLVM backend failed to emit \(context): \(reason)",
                range: nil
            )
            throw LLVMBackendError.nativeEmissionFailed(reason)
        }
    }

    private func describe(error: Error) -> String {
        if let backendError = error as? LLVMBackendError {
            switch backendError {
            case .bindingsUnavailable:
                return "backend unavailable"
            case let .nativeEmissionFailed(reason):
                return reason
            }
        }
        return String(describing: error)
    }

}

enum LLVMBackendError: Error {
    case bindingsUnavailable
    case nativeEmissionFailed(String)
}
