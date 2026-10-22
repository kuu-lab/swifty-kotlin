
import CompilerCore

final class LLVMBackend {
    let target: TargetTriple
    private let moduleName: String
    private let optLevel: OptimizationLevel
    private let debugInfo: Bool
    let diagnostics: DiagnosticEngine
    private let bindings: LLVMCAPIBindings
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
        linkOnceODRSymbols: Set<SymbolID> = []
    ) throws {
        try emitNative(
            context: "object",
            nativeEmit: { bindings in
                let emitter = withSubPhaseTiming("initEmitter", timer: phaseTimer) {
                    NativeEmitter(
                        target: target,
                        optLevel: optLevel,
                        debugInfo: debugInfo,
                        bindings: bindings,
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
                try emitter.emitObject(outputPath: outputObjectPath)
            }
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
