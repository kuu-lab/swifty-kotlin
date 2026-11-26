import Foundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

import CompilerCore

extension LLVMCAPIBindings {
    static func loadUsable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        diagnose: (String) -> Void = writeStandardError
    ) -> LLVMCAPIBindings? {
        if case .rejected(let diagnostic) = libraryOverride(environment: environment) {
            diagnose(diagnostic)
        }
        return firstUsable(
            candidates: candidateLibraryPaths(environment: environment),
            bind: { load(candidates: [$0]) },
            isUsable: { $0.smokeTestContextLifecycle() },
            diagnose: diagnose
        )
    }

    static func firstUsable<Bindings>(
        candidates: [String],
        bind: (String) -> Bindings?,
        isUsable: (Bindings) -> Bool,
        diagnose: (String) -> Void
    ) -> Bindings? {
        for candidate in candidates {
            guard let bindings = bind(candidate) else {
                continue
            }
            if isUsable(bindings) {
                return bindings
            }
            diagnose(smokeTestFailedDiagnostic(libraryPath: candidate))
        }
        return nil
    }

    static func smokeTestFailedDiagnostic(libraryPath: String) -> String {
        "kswiftc: skipping LLVM library candidate \(libraryPath): LLVMContextCreate returned null\n"
    }

    static func writeStandardError(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }

    enum LibraryOverride: Equatable {
        case unset
        case accepted(path: String)
        case rejected(diagnostic: String)
    }

    static func libraryOverride(environment: [String: String]) -> LibraryOverride {
        guard let override = environment["KSWIFTK_LLVM_DYLIB"], !override.isEmpty else {
            return .unset
        }
        guard override.hasPrefix("/") else {
            return .rejected(diagnostic: overrideRejectedDiagnostic(override, reason: "path is not absolute"))
        }
        let resolved = URL(fileURLWithPath: override).standardized.path
        guard FileManager.default.fileExists(atPath: resolved) else {
            return .rejected(diagnostic: overrideRejectedDiagnostic(resolved, reason: "file does not exist"))
        }
        return .accepted(path: resolved)
    }

    private static func overrideRejectedDiagnostic(_ path: String, reason: String) -> String {
        "kswiftc: skipping LLVM library candidate \(path) from KSWIFTK_LLVM_DYLIB: \(reason)\n"
    }

    /// Every entry is a canonical absolute path inside a well-known install
    /// location; generic library-search variables (`LIBRARY_PATH`,
    /// `LD_LIBRARY_PATH`, `DYLD_LIBRARY_PATH`) are
    /// deliberately ignored because relative or group/other-writable entries
    /// in them would let another local user substitute a malicious library.
    /// The only environment-driven override is `KSWIFTK_LLVM_DYLIB`, which
    /// must name an absolute path and is still verified before `dlopen`.
    static func candidateLibraryPaths(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var candidates: [String] = []
        if case .accepted(let path) = libraryOverride(environment: environment) {
            candidates.append(path)
        }
        let commonLibraryNames = [
            "libLLVM.dylib",
            "libLLVM.so",
            "libLLVM-19.so",
            "libLLVM-18.so",
            "libLLVM-17.so",
            "libLLVM-16.so",
            "libLLVM-15.so",
            "libLLVM-14.so",
        ]
        for directory in candidateLibraryDirectories() {
            candidates.append(contentsOf: discoveredLibraryPaths(in: directory))
            candidates.append(contentsOf: commonLibraryNames.map {
                URL(fileURLWithPath: directory).appendingPathComponent($0).standardized.path
            })
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/opt/llvm/lib/libLLVM.dylib",
            "/usr/local/opt/llvm/lib/libLLVM.dylib",
            "/Library/Developer/CommandLineTools/usr/lib/libLLVM.dylib",
            "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/usr/lib/libLLVM.dylib",
            "/usr/lib/llvm-19/lib/libLLVM.so",
            "/usr/lib/llvm-18/lib/libLLVM.so",
            "/usr/lib/llvm-17/lib/libLLVM.so",
            "/usr/lib/llvm-16/lib/libLLVM.so",
            "/usr/lib/x86_64-linux-gnu/libLLVM-15.so",
            "/usr/lib/x86_64-linux-gnu/libLLVM.so",
            "/usr/lib/aarch64-linux-gnu/libLLVM.so",
        ])
        return deduplicated(candidates)
    }

    private static func candidateLibraryDirectories() -> [String] {
        deduplicated([
            "/opt/homebrew/opt/llvm/lib",
            "/usr/local/opt/llvm/lib",
            "/usr/lib",
            "/usr/local/lib",
            "/usr/lib/x86_64-linux-gnu",
            "/usr/lib/aarch64-linux-gnu",
            "/usr/lib/llvm-19/lib",
            "/usr/lib/llvm-18/lib",
            "/usr/lib/llvm-17/lib",
            "/usr/lib/llvm-16/lib",
            "/usr/lib/llvm-15/lib",
            "/usr/lib/llvm-14/lib",
        ].map { URL(fileURLWithPath: $0).standardized.path })
    }

    private static func discoveredLibraryPaths(in directory: String) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        return entries
            .filter { entry in
                if !entry.hasPrefix("libLLVM") {
                    return false
                }
                return entry.hasSuffix(".dylib")
                    || entry.contains(".so")
            }
            .sorted()
            .map { URL(fileURLWithPath: directory).appendingPathComponent($0).standardized.path }
    }

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) -> LLVMCAPIBindings? {
        load(candidates: candidateLibraryPaths(environment: environment))
    }

    static func load(candidates: [String]) -> LLVMCAPIBindings? {
        for candidate in candidates {
            let libraryPath: String
            switch TrustedFileSystem.inspectLoadableFile(candidate) {
            case .trusted(let resolvedPath):
                libraryPath = resolvedPath
            case .rejected(let component, let reason):
                if reason != .missing {
                    FileHandle.standardError.write(Data(
                        "kswiftc: skipping LLVM library candidate \(candidate): \(component) \(reason.diagnosticDetail)\n".utf8
                    ))
                }
                continue
            }
            guard let handle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
                let message = dlerror().map { String(cString: $0) } ?? "unknown dlopen error"
                FileHandle.standardError.write(Data(
                    "kswiftc: could not load LLVM library at \(libraryPath): \(message)\n".utf8
                ))
                continue
            }

            switch makeBindings(handle: handle, libraryPath: libraryPath, lookup: { dlsym(handle, $0) }) {
            case .success(let bindings):
                return bindings
            case .failure(let missing):
                FileHandle.standardError.write(Data(
                    missingRequiredSymbolsDiagnostic(libraryPath: libraryPath, missing: missing.names).utf8
                ))
                dlclose(handle)
                continue
            }
        }
        return nil
    }

    struct MissingRequiredSymbols: Error, Equatable {
        let names: [String]
    }

    static func missingRequiredSymbolsDiagnostic(libraryPath: String, missing: [String]) -> String {
        "kswiftc: skipping LLVM library candidate \(libraryPath): missing required symbols: \(missing.joined(separator: ", "))\n"
    }

    final class SymbolResolver {
        private let lookup: (String) -> UnsafeMutableRawPointer?
        private(set) var missingRequired: [String] = []

        init(lookup: @escaping (String) -> UnsafeMutableRawPointer?) {
            self.lookup = lookup
        }

        func required<T>(_ name: String, as type: T.Type) -> T? {
            guard let symbol = optional(name, as: type) else {
                missingRequired.append(name)
                return nil
            }
            return symbol
        }

        func optional<T>(_ name: String, as type: T.Type) -> T? {
            guard let symbol = lookup(name) else {
                return nil
            }
            return unsafeBitCast(symbol, to: type)
        }
    }

    static func makeBindings(
        handle: UnsafeMutableRawPointer,
        libraryPath: String,
        lookup: @escaping (String) -> UnsafeMutableRawPointer?
    ) -> Result<LLVMCAPIBindings, MissingRequiredSymbols> {
        let symbols = SymbolResolver(lookup: lookup)
        let contextCreate = symbols.required("LLVMContextCreate", as: LLVMContextCreateFn.self)
        let contextDispose = symbols.required("LLVMContextDispose", as: LLVMContextDisposeFn.self)
        let moduleCreate = symbols.required("LLVMModuleCreateWithNameInContext", as: LLVMModuleCreateWithNameInContextFn.self)
        let disposeModule = symbols.required("LLVMDisposeModule", as: LLVMDisposeModuleFn.self)
        let printModule = symbols.required("LLVMPrintModuleToString", as: LLVMPrintModuleToStringFn.self)
        let disposeMessage = symbols.required("LLVMDisposeMessage", as: LLVMDisposeMessageFn.self)
        let setTarget = symbols.required("LLVMSetTarget", as: LLVMSetTargetFn.self)
        let setDataLayout = symbols.required("LLVMSetDataLayout", as: LLVMSetDataLayoutFn.self)
        let setLinkage = symbols.required("LLVMSetLinkage", as: LLVMSetLinkageFn.self)
        let setThreadLocal = symbols.required("LLVMSetThreadLocal", as: LLVMSetThreadLocalFn.self)
        let int8Type = symbols.required("LLVMInt8TypeInContext", as: LLVMInt8TypeInContextFn.self)
        let int64Type = symbols.required("LLVMInt64TypeInContext", as: LLVMInt64TypeInContextFn.self)
        let pointerType = symbols.required("LLVMPointerType", as: LLVMPointerTypeFn.self)
        let functionType = symbols.required("LLVMFunctionType", as: LLVMFunctionTypeFn.self)
        let addFunction = symbols.required("LLVMAddFunction", as: LLVMAddFunctionFn.self)
        let getNamedFunction = symbols.required("LLVMGetNamedFunction", as: LLVMGetNamedFunctionFn.self)
        let getParam = symbols.required("LLVMGetParam", as: LLVMGetParamFn.self)
        let getUndef = symbols.required("LLVMGetUndef", as: LLVMGetUndefFn.self)
        let appendBasicBlock = symbols.required("LLVMAppendBasicBlockInContext", as: LLVMAppendBasicBlockInContextFn.self)
        let createBuilder = symbols.required("LLVMCreateBuilderInContext", as: LLVMCreateBuilderInContextFn.self)
        let disposeBuilder = symbols.required("LLVMDisposeBuilder", as: LLVMDisposeBuilderFn.self)
        let positionBuilder = symbols.required("LLVMPositionBuilderAtEnd", as: LLVMPositionBuilderAtEndFn.self)
        let getTerminator = symbols.required("LLVMGetBasicBlockTerminator", as: LLVMGetBasicBlockTerminatorFn.self)
        let buildRet = symbols.required("LLVMBuildRet", as: LLVMBuildRetFn.self)
        let buildBr = symbols.required("LLVMBuildBr", as: LLVMBuildBrFn.self)
        let buildCondBr = symbols.required("LLVMBuildCondBr", as: LLVMBuildCondBrFn.self)
        let buildUnreachable = symbols.required("LLVMBuildUnreachable", as: LLVMBuildUnreachableFn.self)
        let buildAdd = symbols.required("LLVMBuildAdd", as: LLVMBuildAddFn.self)
        let buildSub = symbols.required("LLVMBuildSub", as: LLVMBuildSubFn.self)
        let buildMul = symbols.required("LLVMBuildMul", as: LLVMBuildMulFn.self)
        let buildSDiv = symbols.required("LLVMBuildSDiv", as: LLVMBuildSDivFn.self)
        let buildICmp = symbols.required("LLVMBuildICmp", as: LLVMBuildICmpFn.self)
        let constInt = symbols.required("LLVMConstInt", as: LLVMConstIntFn.self)
        let getDefaultTargetTriple = symbols.required("LLVMGetDefaultTargetTriple", as: LLVMGetDefaultTargetTripleFn.self)
        let getTargetFromTriple = symbols.required("LLVMGetTargetFromTriple", as: LLVMGetTargetFromTripleFn.self)
        let createTargetMachine = symbols.required("LLVMCreateTargetMachine", as: LLVMCreateTargetMachineFn.self)
        let disposeTargetMachine = symbols.required("LLVMDisposeTargetMachine", as: LLVMDisposeTargetMachineFn.self)
        let emitToFile = symbols.required("LLVMTargetMachineEmitToFile", as: LLVMTargetMachineEmitToFileFn.self)
        let createTargetDataLayout = symbols.required("LLVMCreateTargetDataLayout", as: LLVMCreateTargetDataLayoutFn.self)
        let copyStringRepOfTargetData = symbols.required("LLVMCopyStringRepOfTargetData", as: LLVMCopyStringRepOfTargetDataFn.self)
        let disposeTargetData = symbols.required("LLVMDisposeTargetData", as: LLVMDisposeTargetDataFn.self)
        guard let contextCreate, let contextDispose, let moduleCreate, let disposeModule, let printModule,
              let disposeMessage, let setTarget, let setDataLayout, let setLinkage, let setThreadLocal, let int8Type,
              let int64Type, let pointerType, let functionType, let addFunction, let getNamedFunction, let getParam,
              let getUndef, let appendBasicBlock, let createBuilder, let disposeBuilder, let positionBuilder,
              let getTerminator, let buildRet, let buildBr, let buildCondBr, let buildUnreachable, let buildAdd,
              let buildSub, let buildMul, let buildSDiv, let buildICmp, let constInt, let getDefaultTargetTriple,
              let getTargetFromTriple, let createTargetMachine, let disposeTargetMachine, let emitToFile,
              let createTargetDataLayout, let copyStringRepOfTargetData, let disposeTargetData
        else {
            return .failure(MissingRequiredSymbols(names: symbols.missingRequired))
        }

        let buildCall2 = symbols.optional("LLVMBuildCall2", as: LLVMBuildCall2Fn.self)
        let buildCall = symbols.optional("LLVMBuildCall", as: LLVMBuildCallFn.self)

        return .success(LLVMCAPIBindings(
            handle: handle,
            libraryPath: libraryPath,
            runPassesFn: symbols.optional("LLVMRunPasses", as: LLVMRunPassesFn.self),
            createPassBuilderOptionsFn: symbols.optional("LLVMCreatePassBuilderOptions", as: LLVMCreatePassBuilderOptionsFn.self),
            disposePassBuilderOptionsFn: symbols.optional("LLVMDisposePassBuilderOptions", as: LLVMDisposePassBuilderOptionsFn.self),
            getErrorMessageFn: symbols.optional("LLVMGetErrorMessage", as: LLVMGetErrorMessageFn.self),
            disposeErrorMessageFn: symbols.optional("LLVMDisposeErrorMessage", as: LLVMDisposeErrorMessageFn.self),
            verifyModuleFn: symbols.optional("LLVMVerifyModule", as: LLVMVerifyModuleFn.self),
            contextCreateFn: contextCreate,
            contextDisposeFn: contextDispose,
            moduleCreateFn: moduleCreate,
            disposeModuleFn: disposeModule,
            linkModules2Fn: symbols.optional("LLVMLinkModules2", as: LLVMLinkModules2Fn.self),
            writeBitcodeToFileFn: symbols.optional("LLVMWriteBitcodeToFile", as: LLVMWriteBitcodeToFileFn.self),
            printModuleToStringFn: printModule,
            disposeMessageFn: disposeMessage,
            setTargetFn: setTarget,
            setDataLayoutFn: setDataLayout,
            setLinkageFn: setLinkage,
            setThreadLocalFn: setThreadLocal,
            voidTypeFn: symbols.optional("LLVMVoidTypeInContext", as: LLVMVoidTypeInContextFn.self),
            int8TypeInContextFn: int8Type,
            int64TypeFn: int64Type,
            structTypeInContextFn: symbols.optional("LLVMStructTypeInContext", as: LLVMStructTypeInContextFn.self),
            pointerTypeFn: pointerType,
            functionTypeFn: functionType,
            addFunctionFn: addFunction,
            getNamedFunctionFn: getNamedFunction,
            getParamFn: getParam,
            getUndefFn: getUndef,
            appendBasicBlockFn: appendBasicBlock,
            createBuilderFn: createBuilder,
            disposeBuilderFn: disposeBuilder,
            positionBuilderFn: positionBuilder,
            getBasicBlockTerminatorFn: getTerminator,
            buildRetFn: buildRet,
            buildBrFn: buildBr,
            buildCondBrFn: buildCondBr,
            buildUnreachableFn: buildUnreachable,
            buildAddFn: buildAdd,
            buildSubFn: buildSub,
            buildMulFn: buildMul,
            buildSDivFn: buildSDiv,
            buildAndFn: symbols.optional("LLVMBuildAnd", as: LLVMBuildAndFn.self),
            buildOrFn: symbols.optional("LLVMBuildOr", as: LLVMBuildOrFn.self),
            buildXorFn: symbols.optional("LLVMBuildXor", as: LLVMBuildXorFn.self),
            buildShlFn: symbols.optional("LLVMBuildShl", as: LLVMBuildShlFn.self),
            buildAShrFn: symbols.optional("LLVMBuildAShr", as: LLVMBuildAShrFn.self),
            buildLShrFn: symbols.optional("LLVMBuildLShr", as: LLVMBuildLShrFn.self),
            buildNotFn: symbols.optional("LLVMBuildNot", as: LLVMBuildNotFn.self),
            buildICmpFn: buildICmp,
            buildZExtFn: symbols.optional("LLVMBuildZExt", as: LLVMBuildZExtFn.self),
            buildAllocaFn: symbols.optional("LLVMBuildAlloca", as: LLVMBuildAllocaFn.self),
            buildStoreFn: symbols.optional("LLVMBuildStore", as: LLVMBuildStoreFn.self),
            buildLoad2Fn: symbols.optional("LLVMBuildLoad2", as: LLVMBuildLoad2Fn.self),
            buildLoadFn: symbols.optional("LLVMBuildLoad", as: LLVMBuildLoadFn.self),
            buildSelectFn: symbols.optional("LLVMBuildSelect", as: LLVMBuildSelectFn.self),
            buildExtractValueFn: symbols.optional("LLVMBuildExtractValue", as: LLVMBuildExtractValueFn.self),
            buildInsertValueFn: symbols.optional("LLVMBuildInsertValue", as: LLVMBuildInsertValueFn.self),
            typeOfFn: symbols.optional("LLVMTypeOf", as: LLVMTypeOfFn.self),
            getTypeKindFn: symbols.optional("LLVMGetTypeKind", as: LLVMGetTypeKindFn.self),
            buildGlobalStringPtrFn: symbols.optional("LLVMBuildGlobalStringPtr", as: LLVMBuildGlobalStringPtrFn.self),
            buildPtrToIntFn: symbols.optional("LLVMBuildPtrToInt", as: LLVMBuildPtrToIntFn.self),
            buildIntToPtrFn: symbols.optional("LLVMBuildIntToPtr", as: LLVMBuildIntToPtrFn.self),
            buildPointerCastFn: symbols.optional("LLVMBuildPointerCast", as: LLVMBuildPointerCastFn.self),
            buildCall2Fn: buildCall2,
            buildCallFn: buildCall,
            constIntFn: constInt,
            constPointerNullFn: symbols.optional("LLVMConstPointerNull", as: LLVMConstPointerNullFn.self),
            constStructInContextFn: symbols.optional("LLVMConstStructInContext", as: LLVMConstStructInContextFn.self),
            constStringInContextFn: symbols.optional("LLVMConstStringInContext", as: LLVMConstStringInContextFn.self),
            arrayTypeFn: symbols.optional("LLVMArrayType", as: LLVMArrayTypeFn.self),
            setGlobalConstantFn: symbols.optional("LLVMSetGlobalConstant", as: LLVMSetGlobalConstantFn.self),
            setUnnamedAddrFn: symbols.optional("LLVMSetUnnamedAddr", as: LLVMSetUnnamedAddrFn.self),
            buildInBoundsGEP2Fn: symbols.optional("LLVMBuildInBoundsGEP2", as: LLVMBuildInBoundsGEP2Fn.self),
            getDefaultTargetTripleFn: getDefaultTargetTriple,
            getTargetFromTripleFn: getTargetFromTriple,
            createTargetMachineFn: createTargetMachine,
            disposeTargetMachineFn: disposeTargetMachine,
            emitToFileFn: emitToFile,
            createTargetDataLayoutFn: createTargetDataLayout,
            copyStringRepOfTargetDataFn: copyStringRepOfTargetData,
            disposeTargetDataFn: disposeTargetData,
            initializeX86TargetInfoFn: symbols.optional("LLVMInitializeX86TargetInfo", as: LLVMInitializeX86TargetInfoFn.self),
            initializeX86TargetFn: symbols.optional("LLVMInitializeX86Target", as: LLVMInitializeX86TargetFn.self),
            initializeX86TargetMCFn: symbols.optional("LLVMInitializeX86TargetMC", as: LLVMInitializeX86TargetMCFn.self),
            initializeX86AsmPrinterFn: symbols.optional("LLVMInitializeX86AsmPrinter", as: LLVMInitializeX86AsmPrinterFn.self),
            initializeAArch64TargetInfoFn: symbols.optional("LLVMInitializeAArch64TargetInfo", as: LLVMInitializeAArch64TargetInfoFn.self),
            initializeAArch64TargetFn: symbols.optional("LLVMInitializeAArch64Target", as: LLVMInitializeAArch64TargetFn.self),
            initializeAArch64TargetMCFn: symbols.optional("LLVMInitializeAArch64TargetMC", as: LLVMInitializeAArch64TargetMCFn.self),
            initializeAArch64AsmPrinterFn: symbols.optional("LLVMInitializeAArch64AsmPrinter", as: LLVMInitializeAArch64AsmPrinterFn.self),
            initializeWebAssemblyTargetInfoFn: symbols.optional("LLVMInitializeWebAssemblyTargetInfo", as: LLVMInitializeWebAssemblyTargetInfoFn.self),
            initializeWebAssemblyTargetFn: symbols.optional("LLVMInitializeWebAssemblyTarget", as: LLVMInitializeWebAssemblyTargetFn.self),
            initializeWebAssemblyTargetMCFn: symbols.optional("LLVMInitializeWebAssemblyTargetMC", as: LLVMInitializeWebAssemblyTargetMCFn.self),
            initializeWebAssemblyAsmPrinterFn: symbols.optional("LLVMInitializeWebAssemblyAsmPrinter", as: LLVMInitializeWebAssemblyAsmPrinterFn.self),
            addGlobalFn: symbols.optional("LLVMAddGlobal", as: LLVMAddGlobalFn.self),
            setInitializerFn: symbols.optional("LLVMSetInitializer", as: LLVMSetInitializerFn.self),
            positionBuilderBeforeFn: symbols.optional("LLVMPositionBuilderBefore", as: LLVMPositionBuilderBeforeFn.self),
            getFirstInstructionFn: symbols.optional("LLVMGetFirstInstruction", as: LLVMGetFirstInstructionFn.self),
            createDIBuilderFn: symbols.optional("LLVMCreateDIBuilder", as: LLVMCreateDIBuilderFn.self),
            disposeDIBuilderFn: symbols.optional("LLVMDisposeDIBuilder", as: LLVMDisposeDIBuilderFn.self),
            diBuilderFinalizeFn: symbols.optional("LLVMDIBuilderFinalize", as: LLVMDIBuilderFinalizeFn.self),
            diBuilderCreateFileFn: symbols.optional("LLVMDIBuilderCreateFile", as: LLVMDIBuilderCreateFileFn.self),
            diBuilderCreateCompileUnitFn: symbols.optional("LLVMDIBuilderCreateCompileUnit", as: LLVMDIBuilderCreateCompileUnitFn.self),
            diBuilderCreateSubroutineTypeFn: symbols.optional("LLVMDIBuilderCreateSubroutineType", as: LLVMDIBuilderCreateSubroutineTypeFn.self),
            diBuilderCreateFunctionFn: symbols.optional("LLVMDIBuilderCreateFunction", as: LLVMDIBuilderCreateFunctionFn.self),
            setSubprogramFn: symbols.optional("LLVMSetSubprogram", as: LLVMSetSubprogramFn.self),
            addModuleFlagFn: symbols.optional("LLVMAddModuleFlag", as: LLVMAddModuleFlagFn.self),
            valueAsMetadataFn: symbols.optional("LLVMValueAsMetadata", as: LLVMValueAsMetadataFn.self),
            int32TypeFn: symbols.optional("LLVMInt32TypeInContext", as: LLVMInt32TypeInContextFn.self),
            setCurrentDebugLocation2Fn: symbols.optional("LLVMSetCurrentDebugLocation2", as: LLVMSetCurrentDebugLocation2Fn.self),
            diBuilderCreateDebugLocationFn: symbols.optional("LLVMDIBuilderCreateDebugLocation", as: LLVMDIBuilderCreateDebugLocationFn.self),
            diBuilderCreateBasicTypeFn: symbols.optional("LLVMDIBuilderCreateBasicType", as: LLVMDIBuilderCreateBasicTypeFn.self),
            diBuilderCreateParameterVariableFn: symbols.optional("LLVMDIBuilderCreateParameterVariable", as: LLVMDIBuilderCreateParameterVariableFn.self),
            diBuilderCreateAutoVariableFn: symbols.optional("LLVMDIBuilderCreateAutoVariable", as: LLVMDIBuilderCreateAutoVariableFn.self),
            diBuilderInsertDeclareAtEndFn: symbols.optional("LLVMDIBuilderInsertDeclareAtEnd", as: LLVMDIBuilderInsertDeclareAtEndFn.self),
            diBuilderCreateExpressionFn: symbols.optional("LLVMDIBuilderCreateExpression", as: LLVMDIBuilderCreateExpressionFn.self)
        ))
    }

    static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in values where seen.insert(value).inserted {
            ordered.append(value)
        }
        return ordered
    }
}
