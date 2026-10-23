import Foundation

import CompilerCore

public final class CodegenPhase: CompilerPhase {
    public static let name = "Codegen"

    private let session: LLVMBackendSession?

    public init() { session = nil }

    init(session: LLVMBackendSession) { self.session = session }

    public func run(_ ctx: CompilationContext) throws {
        if ctx.options.emit.isJVM {
            try JVMCodegenPhase().run(ctx)
            return
        }
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for codegen.")
        }
        let fileFacadeNamesByFileID = withSubPhaseTiming("fileFacades", timer: ctx.phaseTimer) {
            CodegenSymbolSupport.fileFacadeNames(from: ctx.ast)
        }
        let backend = try withSubPhaseTiming("init", timer: ctx.phaseTimer) {
            try makeBackend(ctx: ctx)
        }
        // Shared by the reflection records, inline-KIR artifacts, and library
        // metadata: the map is a pure function of module + interner + symbols.
        let functionLinkInfo = withSubPhaseTiming("linkInfo", timer: ctx.phaseTimer) {
            makeFunctionLinkInfo(module: kir, ctx: ctx, fileFacadeNamesByFileID: fileFacadeNamesByFileID)
        }
        let reflectionRecords = withSubPhaseTiming("reflectionRecords", timer: ctx.phaseTimer) {
            buildReflectionMetadataRecords(ctx: ctx, functionLinkInfo: functionLinkInfo)
        }

        do {
            switch ctx.options.emit {
            case .llvmIR:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "ll")
                try backend.emitLLVMIR(
                    module: kir,
                    outputIRPath: path,
                    interner: ctx.interner,
                    typeSystem: ctx.sema?.types,
                    symbols: ctx.sema?.symbols,
                    sourceManager: ctx.sourceManager,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                    reflectionMetadataRecords: reflectionRecords,
                    reflectionMetadataSymbolPrefix: ctx.options.moduleName
                )
                ctx.storeGeneratedLLVMIRPath(path)

            case .object:
                let path = outputPath(base: ctx.options.outputPath, defaultExtension: "o")
                try backend.emitObject(
                    module: kir,
                    outputObjectPath: path,
                    interner: ctx.interner,
                    typeSystem: ctx.sema?.types,
                    symbols: ctx.sema?.symbols,
                    sourceManager: ctx.sourceManager,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                    reflectionMetadataRecords: reflectionRecords,
                    reflectionMetadataSymbolPrefix: ctx.options.moduleName
                )
                ctx.storeGeneratedObjectPath(path)

            case .executable:
                if ctx.options.target.isWasm {
                    // WebAssembly executables are modules, not host objects:
                    // the wasm emitter writes the final .wasm directly and the
                    // Link phase is bypassed.
                    let path = outputPath(base: ctx.options.outputPath, defaultExtension: "wasm")
                    try emitWasmModule(module: kir, outputPath: path, ctx: ctx)
                    ctx.storeGeneratedWasmPath(path)
                    return
                }
                let path = executableObjectPath(base: ctx.options.outputPath)
                try backend.emitObject(
                    module: kir,
                    outputObjectPath: path,
                    interner: ctx.interner,
                    typeSystem: ctx.sema?.types,
                    symbols: ctx.sema?.symbols,
                    sourceManager: ctx.sourceManager,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                    reflectionMetadataRecords: reflectionRecords,
                    reflectionMetadataSymbolPrefix: ctx.options.moduleName
                )
                ctx.storeGeneratedObjectPath(path)

            case .library:
                try emitLibrary(
                    module: kir,
                    backend: backend,
                    ctx: ctx,
                    reflectionMetadataRecords: reflectionRecords,
                    reflectionMetadataSymbolPrefix: ctx.options.moduleName,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID,
                    functionLinkInfo: functionLinkInfo
                )

            case .kirDump, .jvmClass, .jvmJar:
                return
            }
        } catch {
            if !ctx.diagnostics.hasError {
                ctx.diagnostics.error(
                    "KSWIFTK-PIPELINE-0004",
                    "Codegen phase could not emit requested output: \(error)",
                    range: nil
                )
            }
            throw CompilerPipelineError.outputUnavailable
        }
    }

    private func outputPath(base: String, defaultExtension: String) -> String {
        let fileURL = URL(fileURLWithPath: base)
        if fileURL.pathExtension.isEmpty {
            return fileURL.appendingPathExtension(defaultExtension).path
        }
        return base
    }

    /// Runs the custom KIR→wasm emitter and writes the module. The entry
    /// symbol is resolved the same way Link does so `_start`/`main` wraps the
    /// real `main` function.
    private func emitWasmModule(module kir: KIRModule, outputPath: String, ctx: CompilationContext) throws {
        var entrySymbol: SymbolID?
        if let ast = ctx.ast, let sema = ctx.sema {
            entrySymbol = ExecutableEntryPointSelector.firstFileLevelSymbol(
                ast: ast,
                bindings: sema.bindings,
                arena: kir.arena,
                interner: ctx.interner,
                symbols: sema.symbols,
                entryPointFQName: ctx.options.entryPointFQName
            )
        }
        let result = try WasmEmitter().emitModule(
            module: kir,
            interner: ctx.interner,
            symbols: ctx.sema?.symbols,
            types: ctx.sema?.types,
            entrySymbol: entrySymbol,
            target: ctx.options.target,
            diagnostics: ctx.diagnostics
        )
        try Data(result.bytes).write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }

    private func executableObjectPath(base: String) -> String {
        // Keep the linker output path and the intermediate object path distinct,
        // even when the user passes an executable filename with an extension.
        let fileURL = URL(fileURLWithPath: base)
        if fileURL.pathExtension == "o" {
            return fileURL
                .deletingPathExtension()
                .appendingPathExtension("executable")
                .appendingPathExtension("o")
                .path
        }
        return fileURL.appendingPathExtension("o").path
    }

    private func emitLibrary(
        module: KIRModule,
        backend: LLVMBackend,
        ctx: CompilationContext,
        reflectionMetadataRecords: [MetadataRecord] = [],
        reflectionMetadataSymbolPrefix: String? = nil,
        fileFacadeNamesByFileID: [Int32: String] = [:],
        functionLinkInfo: FunctionLinkInfo = FunctionLinkInfo()
    ) throws {
        let fm = FileManager.default
        let outputDir = libraryOutputPath(base: ctx.options.outputPath)
        let objectsDir = outputDir + "/objects"
        let inlineDir = outputDir + "/inline-kir"

        if fm.fileExists(atPath: outputDir) {
            try fm.removeItem(atPath: outputDir)
        }
        try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: objectsDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: inlineDir, withIntermediateDirectories: true)

        let objectPath = objectsDir + "/\(ctx.options.moduleName)_0.o"
        // KUU-2814: `-Xfrontend stdlib-bitcode` also ships the optimized LLVM
        // module as bitcode (~2x the object size) for LTO experiments. Opt-in
        // because no consumer reads it: measured on hello.kt, importing the
        // needed stdlib bitcode and re-running codegen costs ~6s versus 0.42s
        // for the current prebuilt-object link.
        let bitcodeRelativePath = "bitcode/\(ctx.options.moduleName)_0.bc"
        let bitcodePath: String? = (ctx.options.stdlibOnly && ctx.options.frontendFlags.contains("stdlib-bitcode")) ? outputDir + "/" + bitcodeRelativePath : nil
        if bitcodePath != nil {
            try fm.createDirectory(atPath: outputDir + "/bitcode", withIntermediateDirectories: true)
        }
        // Bundled stdlib functions appear in every source-backed compilation unit. Use
        // linkonce_odr there so the linker can deduplicate them. A stdlib artifact is the
        // provider of those symbols, however; keeping its definitions externally visible
        // prevents an O2 global-DCE pass from removing entry points that only consumers call.
        let bundledFileIDs = Set(ctx.sourceManager.fileIDs()
            .filter { ctx.sourceManager.origin(of: $0)?.isBundledStdlib == true }
            .map(\.rawValue))
        let bundledSymbolIDs: Set<SymbolID> = ctx.sema.map { sema in
            Set(sema.symbols.allSymbols()
                .filter { sym in
                    guard let declSite = sym.declSite else { return false }
                    return bundledFileIDs.contains(declSite.start.file.rawValue)
                }
                .map(\.id))
        } ?? []
        try backend.emitObject(
            module: module,
            outputObjectPath: objectPath,
            interner: ctx.interner,
            typeSystem: ctx.sema?.types,
            symbols: ctx.sema?.symbols,
            sourceManager: ctx.sourceManager,
            fileFacadeNamesByFileID: fileFacadeNamesByFileID,
            reflectionMetadataRecords: reflectionMetadataRecords,
            reflectionMetadataSymbolPrefix: reflectionMetadataSymbolPrefix,
            linkOnceODRSymbols: ctx.options.stdlibOnly ? [] : bundledSymbolIDs,
            bitcodeOutputPath: bitcodePath
        )
        ctx.storeGeneratedObjectPath(objectPath)

        try withSubPhaseTiming("inlineKIRArtifacts", timer: ctx.phaseTimer) {
            try emitInlineKIRArtifacts(module: module, outputDir: inlineDir, ctx: ctx, functionLinkInfo: functionLinkInfo)
        }

        let manifestPath = outputDir + "/manifest.json"
        let metadataPath = outputDir + "/metadata.bin"

        let targetString = "\(ctx.options.target.arch)-\(ctx.options.target.vendor)-\(ctx.options.target.os)"
        var manifestDict: [String: Any] = [
            "formatVersion": 2,
            "moduleName": ctx.options.moduleName,
            "kotlinLanguageVersion": "2.4.20",
            "compilerVersion": CompilerBuildInfo.version,
            "sourceVarargStorageABI": "array-v1",
            "target": targetString,
            "objects": ["objects/\(ctx.options.moduleName)_0.o"],
            "metadata": "metadata.bin",
            "inlineKIRDir": "inline-kir",
            "runtimeReflectionMetadataScope": ctx.options.includeNonPublicReflectionMetadata || ctx.options.stdlibOnly
                ? "all"
                : "public",
            "precomputedReflectionRecords": true
        ]
        if ctx.options.stdlibOnly {
            manifestDict["libraryKind"] = "stdlib"
            if bitcodePath != nil {
                manifestDict["bitcode"] = [bitcodeRelativePath]
            }
            manifestDict["stdlibManifestHash"] = BundledStdlib.manifestHash(profile: ctx.options.stdlibProfile)
            if ctx.options.stdlibProfile != .full {
                manifestDict["stdlibProfile"] = ctx.options.stdlibProfile.rawValue
            }
            manifestDict["bundledMemberIndex"] = "bundled-members.bin"
            manifestDict["precomputedSyntheticStubs"] = true
        }
        if let topLevelInitializer = module.arena.declarations.compactMap({ declaration -> KIRFunction? in
            guard case let .function(function) = declaration,
                  ctx.interner.resolve(function.name).hasPrefix("__kk_library_top_level_init_")
            else { return nil }
            return function
        }).first,
           let linkName = functionLinkInfo.functionLinkNamesBySymbol[topLevelInitializer.symbol] {
            manifestDict["topLevelInitializerLinkName"] = linkName
        }
        let manifestData = try JSONSerialization.data(withJSONObject: manifestDict, options: [.sortedKeys, .prettyPrinted])
        var manifestString = String(data: manifestData, encoding: .utf8) ?? ""
        manifestString = manifestString.replacingOccurrences(of: "\" : \"", with: "\": \"")
        try manifestString.write(to: URL(fileURLWithPath: manifestPath), atomically: true, encoding: .utf8)

        try withSubPhaseTiming("libraryMetadata", timer: ctx.phaseTimer) {
            let metadata = makeMetadata(ctx: ctx, module: module, functionLinkInfo: functionLinkInfo)
            try metadata.data.write(to: URL(fileURLWithPath: metadataPath), options: .atomic)
            if let bundledMemberIndex = metadata.bundledMemberIndex {
                try bundledMemberIndex.write(
                    to: URL(fileURLWithPath: outputDir + "/bundled-members.bin"),
                    options: .atomic
                )
            }
        }
    }

    private func makeBackend(ctx: CompilationContext) throws -> LLVMBackend {
        // `-Xfrontend codegen-parallel` opts into partitioned function-body
        // emission; `-Xfrontend jobs=N` supplies the worker count (the same
        // knob BuildAST and parallel Sema already share).
        let parallelJobs = ctx.options.frontendFlags.contains("codegen-parallel")
            ? ctx.frontendJobs
            : 1
        return try LLVMBackend(
            target: ctx.options.target,
            optLevel: ctx.options.optLevel,
            debugInfo: ctx.options.debugInfo,
            diagnostics: ctx.diagnostics,
            moduleName: ctx.options.moduleName,
            phaseTimer: ctx.phaseTimer,
            parallelJobs: parallelJobs,
            session: session ?? LLVMBackendSession()
        )
    }

    private struct FunctionLinkInfo {
        var functionLinkNamesBySymbol: [SymbolID: String] = [:]
        var inlineFunctionSymbols: Set<SymbolID> = []
        /// `isInlineOnly` declarations (e.g. lambdas carrying a non-local
        /// return) are never emitted into an object file, so their link name
        /// would be a dangling extern reference for a consumer of serialized
        /// inline KIR. Codegen resolves references to them to `zeroValue`.
        var unemittedFunctionSymbols: Set<SymbolID> = []
    }

    private func makeFunctionLinkInfo(
        module: KIRModule,
        ctx: CompilationContext,
        fileFacadeNamesByFileID: [Int32: String]
    ) -> FunctionLinkInfo {
        var info = FunctionLinkInfo()
        guard let sema = ctx.sema else {
            return info
        }
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            info.functionLinkNamesBySymbol[function.symbol] = CodegenSymbolSupport.cFunctionSymbol(
                for: function,
                interner: ctx.interner,
                moduleName: ctx.options.moduleName,
                symbols: sema.symbols,
                fileFacadeNamesByFileID: fileFacadeNamesByFileID
            )
            if function.isInline {
                info.inlineFunctionSymbols.insert(function.symbol)
            }
            if function.isInlineOnly {
                info.unemittedFunctionSymbols.insert(function.symbol)
            }
        }
        return info
    }

    private func emitInlineKIRArtifacts(
        module: KIRModule,
        outputDir: String,
        ctx: CompilationContext,
        functionLinkInfo: FunctionLinkInfo
    ) throws {
        guard let sema = ctx.sema else {
            return
        }
        let mangler = NameMangler()
        let functionLinkNamesBySymbol = functionLinkInfo.functionLinkNamesBySymbol
        for decl in module.arena.declarations {
            guard case let .function(function) = decl, function.isInline else {
                continue
            }
            let mangled: String
            if let symbol = sema.symbols.symbol(function.symbol) {
                mangled = mangler.mangle(
                    moduleName: ctx.options.moduleName, symbol: symbol,
                    symbols: sema.symbols, types: sema.types,
                    nameResolver: { ctx.interner.resolve($0) }
                )
            } else if ctx.interner.resolve(function.name).hasSuffix("$default"),
                      let linkName = functionLinkNamesBySymbol[function.symbol] {
                // Inline default stubs also require call-site expansion. Their
                // existing metadata link name identifies the serialized body.
                mangled = linkName
            } else {
                continue
            }
            let fileName = MetadataEncoder.inlineKIRFileName(for: mangled)
            let filePath = outputDir + "/\(fileName)"
            let parameterSymbols = Set(function.params.map(\.symbol))
            let inlineBody = module.inlineBodiesBeforeFinallyLowering[function.symbol]
                ?? module.inlineBodiesBeforeCoroutineLowering[function.symbol]
                ?? function.body
            let referencedExpressions = Set(inlineBody.flatMap(inlineReferencedExpressions))
            let bodyLines = inlineBody.filter { instruction in
                // Expanded lambdas need no address, and their standalone bodies may not be exported.
                if case let .constValue(result, .symbolRef(_)) = instruction {
                    return referencedExpressions.contains(result)
                }
                return true
            }.map { instruction in
                serializeInlineInstruction(
                    instruction,
                    interner: ctx.interner,
                    functionLinkNames: functionLinkNamesBySymbol,
                    unemittedFunctionSymbols: functionLinkInfo.unemittedFunctionSymbols,
                    parameterSymbols: parameterSymbols,
                    symbols: sema.symbols
                )
            }.joined(separator: "\n")
            let paramSymbols = function.params.map { String($0.symbol.rawValue) }.joined(separator: ",")
            let content = """
            version=2
            nameB64=\(base64Encode(ctx.interner.resolve(function.name)))
            params=\(function.params.count)
            paramSymbols=\(paramSymbols)
            suspend=\(function.isSuspend)
            body:
            \(bodyLines)
            """
            try content.write(to: URL(fileURLWithPath: filePath), atomically: true, encoding: .utf8)
        }
    }

    private func inlineReferencedExpressions(_ instruction: KIRInstruction) -> [KIRExprID] {
        switch instruction {
        case let .jumpIfEqual(lhs, rhs, _), let .returnIfEqual(lhs, rhs), let .binary(_, lhs, rhs, _):
            [lhs, rhs]
        case let .unary(_, operand, _), let .nullAssert(operand, _):
            [operand]
        case let .call(_, _, arguments, _, _, _, _, _):
            arguments
        case let .virtualCall(_, _, receiver, arguments, _, _, _, _):
            [receiver] + arguments
        case let .copy(from, to):
            // Both operands can reference symbol-backed storage.
            [from, to]
        case let .jumpIfNotNull(value, _), let .storeGlobal(value, _),
             let .rethrow(value), let .returnValue(value), let .resumeNonLocalReturn(value):
            [value]
        case let .nonLocalReturn(value, _):
            value.map { [$0] } ?? []
        case .nop, .beginBlock, .endBlock, .label, .jump, .constValue, .loadGlobal, .returnUnit,
             .beginNonLocalReturnScope, .endNonLocalReturnScope, .beginFinallyCleanup, .endFinallyCleanup,
             .beginFinallyGuard, .endFinallyGuard:
            []
        }
    }

    private func serializeInlineInstruction(
        _ instruction: KIRInstruction,
        interner: StringInterner,
        functionLinkNames: [SymbolID: String],
        unemittedFunctionSymbols: Set<SymbolID>,
        parameterSymbols: Set<SymbolID>,
        symbols: SymbolTable?
    ) -> String {
        switch instruction {
        case .nop:
            return "nop"
        case .beginBlock:
            return "beginBlock"
        case .endBlock:
            return "endBlock"
        case let .label(id):
            return "label id=\(id)"
        case let .jump(target):
            return "jump target=\(target)"
        case let .jumpIfEqual(lhs, rhs, target):
            return "jumpIfEqual lhs=\(lhs.rawValue) rhs=\(rhs.rawValue) target=\(target)"
        case let .constValue(result, value):
            return "const result=\(result.rawValue) value=\(serializeInlineExprKind(value, interner: interner, functionLinkNames: functionLinkNames, unemittedFunctionSymbols: unemittedFunctionSymbols, parameterSymbols: parameterSymbols, symbols: symbols))"
        case let .binary(op, lhs, rhs, result):
            return "binary op=\(op) lhs=\(lhs.rawValue) rhs=\(rhs.rawValue) result=\(result.rawValue)"
        case .returnUnit:
            return "returnUnit"
        case let .returnValue(value):
            return "returnValue value=\(value.rawValue)"
        case let .returnIfEqual(lhs, rhs):
            return "returnIfEqual lhs=\(lhs.rawValue) rhs=\(rhs.rawValue)"
        case let .unary(op, operand, result):
            return "unary op=\(op) operand=\(operand.rawValue) result=\(result.rawValue)"
        case let .nullAssert(operand, result):
            return "nullAssert operand=\(operand.rawValue) result=\(result.rawValue)"
        case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
            let fields = serializeInlineCallFields(
                symbol: symbol,
                callee: callee,
                arguments: arguments,
                result: result,
                thrownResult: thrownResult,
                interner: interner,
                functionLinkNames: functionLinkNames,
                symbols: symbols
            )
            let qualifiedSuperValue = qualifiedSuperType.map { String($0.rawValue) } ?? "_"
            return "call symbol=\(fields.symbolValue) calleeB64=\(fields.calleeName) args=[\(fields.args)]"
                + " result=\(fields.resultValue) canThrow=\(canThrow ? 1 : 0)"
                + " thrownResult=\(fields.thrownResultValue) isSuperCall=\(isSuperCall ? 1 : 0)"
                + " qualifiedSuperType=\(qualifiedSuperValue)" + fields.linkField + fields.symbolFQNameField
        case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
            let fields = serializeInlineCallFields(
                symbol: symbol,
                callee: callee,
                arguments: arguments,
                result: result,
                thrownResult: thrownResult,
                interner: interner,
                functionLinkNames: functionLinkNames,
                symbols: symbols
            )
            let dispatchStr = switch dispatch {
            case let .vtable(slot):
                "vtable:\(slot)"
            case let .itable(interfaceSlot, methodSlot):
                "itable:\(interfaceSlot):\(methodSlot)"
            case let .itableDynamic(interfaceTypeID, methodSlot):
                "itableDynamic:\(interfaceTypeID):\(methodSlot)"
            }
            return "virtualCall symbol=\(fields.symbolValue) calleeB64=\(fields.calleeName)"
                + " receiver=\(receiver.rawValue) args=[\(fields.args)]"
                + " result=\(fields.resultValue) canThrow=\(canThrow ? 1 : 0)"
                + " thrownResult=\(fields.thrownResultValue) dispatch=\(dispatchStr)"
                + fields.linkField + fields.symbolFQNameField
        case let .jumpIfNotNull(value, target):
            return "jumpIfNotNull value=\(value.rawValue) target=\(target)"
        case let .copy(from, to):
            return "copy from=\(from.rawValue) to=\(to.rawValue)"
        case let .storeGlobal(value, symbol):
            return "storeGlobal value=\(value.rawValue) symbol=\(symbol.rawValue)"
                + inlineSymbolFQNameField(symbol, interner: interner, symbols: symbols)
        case let .loadGlobal(result, symbol):
            return "loadGlobal result=\(result.rawValue) symbol=\(symbol.rawValue)"
                + inlineSymbolFQNameField(symbol, interner: interner, symbols: symbols)
        case let .rethrow(value):
            return "rethrow value=\(value.rawValue)"
        case let .nonLocalReturn(value, target):
            let targetField = target.flatMap {
                inlineReturnTargetLink($0, interner: interner, functionLinkNames: functionLinkNames, symbols: symbols)
            }.map { " targetB64=\(base64Encode($0))" } ?? ""
            if let value {
                return "nonLocalReturn value=\(value.rawValue)" + targetField
            } else {
                return "nonLocalReturnUnit" + targetField
            }
        case .beginFinallyGuard:
            return "beginFinallyGuard"
        case let .beginNonLocalReturnScope(value, target, function):
            let functionField = function.flatMap {
                inlineReturnTargetLink($0, interner: interner, functionLinkNames: functionLinkNames, symbols: symbols)
            }.map { " functionB64=\(base64Encode($0))" } ?? ""
            return "beginNonLocalReturnScope value=\(value.rawValue) target=\(target)" + functionField
        case .endNonLocalReturnScope:
            return "endNonLocalReturnScope"
        case let .resumeNonLocalReturn(value):
            return "resumeNonLocalReturn value=\(value.rawValue)"
        case let .beginFinallyCleanup(skipping):
            return "beginFinallyCleanup skipping=\(skipping)"
        case .endFinallyCleanup:
            return "endFinallyCleanup"
        case .endFinallyGuard:
            return "endFinallyGuard"
        }
    }

    /// Serialized field columns shared by `.call` and `.virtualCall`: both
    /// record kinds lead with the same symbol/callee/args/result/throw/link
    /// fields before appending their kind-specific fields.
    private func serializeInlineCallFields(
        symbol: SymbolID?,
        callee: InternedString,
        arguments: [KIRExprID],
        result: KIRExprID?,
        thrownResult: KIRExprID?,
        interner: StringInterner,
        functionLinkNames: [SymbolID: String],
        symbols: SymbolTable?
    ) -> (args: String, symbolValue: String, resultValue: String, thrownResultValue: String, calleeName: String, linkField: String, symbolFQNameField: String) {
        let linkName = symbol.flatMap { functionLinkNames[$0] ?? symbols?.externalLinkName(for: $0) } ?? ""
        let linkField = linkName.isEmpty ? "" : " linkB64=\(base64Encode(linkName))"
        return (
            args: arguments.map { String($0.rawValue) }.joined(separator: ","),
            symbolValue: symbol.map { String($0.rawValue) } ?? "_",
            resultValue: result.map { String($0.rawValue) } ?? "_",
            thrownResultValue: thrownResult.map { String($0.rawValue) } ?? "_",
            calleeName: base64Encode(interner.resolve(callee)),
            linkField: linkField,
            symbolFQNameField: inlineSymbolFQNameField(symbol, interner: interner, symbols: symbols)
        )
    }

    private func inlineSymbolFQNameField(
        _ symbol: SymbolID?,
        interner: StringInterner,
        symbols: SymbolTable?
    ) -> String {
        symbol.flatMap { inlineSymbolFQName($0, interner: interner, symbols: symbols) }
            .map { " symbolFQNameB64=\(base64Encode($0))" } ?? ""
    }

    private func inlineReturnTargetLink(
        _ target: KIRReturnTarget,
        interner: StringInterner,
        functionLinkNames: [SymbolID: String],
        symbols: SymbolTable?
    ) -> String? {
        switch target {
        case let .function(symbol):
            functionLinkNames[symbol] ?? symbols?.externalLinkName(for: symbol)
        case let .importedFunction(link):
            interner.resolve(link)
        }
    }

    private func serializeInlineExprKind(
        _ value: KIRExprKind,
        interner: StringInterner,
        functionLinkNames: [SymbolID: String],
        unemittedFunctionSymbols: Set<SymbolID>,
        parameterSymbols: Set<SymbolID>,
        symbols: SymbolTable?
    ) -> String {
        switch value {
        case let .intLiteral(intValue):
            "int:\(intValue)"
        case let .longLiteral(longValue):
            "long:\(longValue)"
        case let .uintLiteral(uintValue):
            "uint:\(uintValue)"
        case let .ulongLiteral(ulongValue):
            "ulong:\(ulongValue)"
        case let .floatLiteral(floatValue):
            "float:\(floatValue)"
        case let .doubleLiteral(doubleValue):
            "double:\(doubleValue)"
        case let .charLiteral(charValue):
            "char:\(charValue)"
        case let .boolLiteral(boolValue):
            "bool:\(boolValue ? 1 : 0)"
        case let .stringLiteral(text):
            "stringB64:\(base64Encode(interner.resolve(text)))"
        case let .symbolRef(symbol):
            if parameterSymbols.contains(symbol) {
                "symbol:\(symbol.rawValue)"
            } else if unemittedFunctionSymbols.contains(symbol) {
                // Bodies of `isInlineOnly` functions never reach an object
                // file, so the link name would dangle in the consumer. Match
                // codegen, which resolves the same `.symbolRef` to zero.
                "temp:0"
            } else if let linkName = functionLinkNames[symbol] ?? symbols?.externalLinkName(for: symbol), !linkName.isEmpty {
                "externB64:\(base64Encode(linkName))"
            } else if let fQName = inlineSymbolFQName(symbol, interner: interner, symbols: symbols) {
                "symbolFQNameB64:\(base64Encode(fQName))"
            } else {
                "symbol:\(symbol.rawValue)"
            }
        case let .externSymbolAddress(name):
            "externB64:\(base64Encode(interner.resolve(name)))"
        case let .temporary(raw):
            "temp:\(raw)"
        case .null:
            "null"
        case .unit:
            "unit"
        }
    }

    private func base64Encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private func inlineSymbolFQName(
        _ symbol: SymbolID,
        interner: StringInterner,
        symbols: SymbolTable?
    ) -> String? {
        // Imported inline KIR is consumed by a different symbol table, so raw
        // positive IDs are not stable across library boundaries.
        guard let semanticSymbol = symbols?.symbol(symbol),
              !semanticSymbol.fqName.isEmpty
        else {
            return nil
        }
        return semanticSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
    }

    private func libraryOutputPath(base: String) -> String {
        if base.hasSuffix(".kklib") {
            return base
        }
        return base + ".kklib"
    }

    private func makeMetadata(
        ctx: CompilationContext,
        module: KIRModule,
        functionLinkInfo: FunctionLinkInfo
    ) -> (data: Data, bundledMemberIndex: Data?) {
        guard let sema = ctx.sema else {
            return (MetadataEncoder().serializeCompactIndexed([]), nil)
        }
        let functionLinkNamesBySymbol = functionLinkInfo.functionLinkNamesBySymbol
        let inlineFunctionSymbols = functionLinkInfo.inlineFunctionSymbols
        let bundledFileIDs = Set(ctx.sourceManager.fileIDs()
            .filter { ctx.sourceManager.origin(of: $0)?.isBundledStdlib == true }
            .map(\.rawValue))

        let excludeSourceFileIDs = ctx.options.stdlibOnly ? [] : bundledFileIDs

        let runtimeCallbackRawReturnSymbolIDs = NativeEmitter.collectRuntimeCallbackRawStringReturnSymbols(
            module: module,
            interner: ctx.interner,
            typeSystem: ctx.sema?.types,
            symbols: ctx.sema?.symbols
        )
        var objectInitializerLinkNames: [SymbolID: String] = [:]
        var companionInitializerLinkNames: [SymbolID: String] = [:]
        var objectLazyInitializerLinkNames: [SymbolID: String] = [:]
        var enumStaticInitLinkNames: [SymbolID: String] = [:]
        for decl in module.arena.declarations {
            guard case let .function(function) = decl,
                  let linkName = functionLinkNamesBySymbol[function.symbol]
            else {
                continue
            }
            let functionName = ctx.interner.resolve(function.name)
            if let ownerID = Self.objectInitializerOwnerSymbolID(from: functionName) {
                objectInitializerLinkNames[SymbolID(rawValue: ownerID)] = linkName
            } else if let ownerID = Self.companionInitializerOwnerSymbolID(from: functionName) {
                companionInitializerLinkNames[SymbolID(rawValue: ownerID)] = linkName
            } else if let objectID = Self.objectLazyInitializerOwnerSymbolID(from: functionName) {
                objectLazyInitializerLinkNames[SymbolID(rawValue: objectID)] = linkName
            } else if let ownerID = Self.enumStaticInitOwnerSymbolID(
                from: functionName,
                symbol: function.symbol,
                sema: sema
            ) {
                enumStaticInitLinkNames[ownerID] = linkName
            }
        }

        let encoder = MetadataEncoder()
        let requiredNonPublicSymbols = ctx.options.stdlibOnly ? []
            : InlineMetadataDependencies.collect(module: module, sema: sema)
        let records = encoder.buildRecords(
            symbols: sema.symbols,
            types: sema.types,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner,
            functionLinkNames: functionLinkNamesBySymbol,
            inlineFunctionSymbols: inlineFunctionSymbols,
            includeNonPublic: ctx.options.stdlibOnly,
            requiredNonPublicSymbols: requiredNonPublicSymbols,
            includeSynthetic: false,
            includeSyntheticNominalAnchors: ctx.options.stdlibOnly,
            includePrecomputedStdlibSynthesis: ctx.options.stdlibOnly,
            excludeSourceFileIDs: excludeSourceFileIDs,
            runtimeCallbackRawReturnSymbolIDs: runtimeCallbackRawReturnSymbolIDs,
            objectInitializerLinkNames: objectInitializerLinkNames,
            companionInitializerLinkNames: companionInitializerLinkNames,
            objectLazyInitializerLinkNames: objectLazyInitializerLinkNames,
            enumStaticInitLinkNames: enumStaticInitLinkNames
        )
        let memberIndex = ctx.options.stdlibOnly
            ? BundledDeclarationIndex.precomputedMemberIndexData(records: records, interner: ctx.interner)
            : nil
        return (encoder.serializeCompactIndexed(records), memberIndex)
    }
    private func buildReflectionMetadataRecords(
        ctx: CompilationContext,
        functionLinkInfo: FunctionLinkInfo
    ) -> [MetadataRecord] {
        guard let sema = ctx.sema else {
            return []
        }
        let encoder = MetadataEncoder()
        return encoder.buildRecords(
            symbols: sema.symbols,
            types: sema.types,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner,
            functionLinkNames: functionLinkInfo.functionLinkNamesBySymbol,
            inlineFunctionSymbols: functionLinkInfo.inlineFunctionSymbols,
            includeNonPublic: ctx.options.includeNonPublicReflectionMetadata || ctx.options.stdlibOnly,
            runtimeReflectionOnly: true
        )
    }

    private static func objectInitializerOwnerSymbolID(from name: String) -> Int32? {
        let prefix = "__object_init_"
        guard name.hasPrefix(prefix) else { return nil }
        let suffix = String(name.dropFirst(prefix.count))
        let parts = suffix.split(separator: "_").map(String.init)
        guard let first = parts.first else { return nil }
        return Int32(first)
    }

    private static func companionInitializerOwnerSymbolID(from name: String) -> Int32? {
        let prefix = "__companion_init_"
        guard name.hasPrefix(prefix) else { return nil }
        let suffix = String(name.dropFirst(prefix.count))
        let parts = suffix.split(separator: "_").map(String.init)
        guard parts.count >= 2, let ownerID = parts.first else { return nil }
        return Int32(ownerID)
    }

    private static func objectLazyInitializerOwnerSymbolID(from name: String) -> Int32? {
        for prefix in ["__object_lazy_init_", "__companion_lazy_init_"] where name.hasPrefix(prefix) {
            return Int32(name.dropFirst(prefix.count))
        }
        return nil
    }
    private static func enumStaticInitOwnerSymbolID(
        from name: String,
        symbol: SymbolID,
        sema: SemaModule
    ) -> SymbolID? {
        let prefix = "__enum_static_init_"
        guard name.hasPrefix(prefix) else { return nil }
        guard let functionSymbol = sema.symbols.symbol(symbol),
              functionSymbol.fqName.count >= 2
        else {
            return nil
        }
        let ownerFQName = Array(functionSymbol.fqName.dropLast())
        guard let ownerSymbol = sema.symbols.lookup(fqName: ownerFQName),
              sema.symbols.symbol(ownerSymbol)?.kind == .enumClass
        else {
            return nil
        }
        return ownerSymbol
    }
}
