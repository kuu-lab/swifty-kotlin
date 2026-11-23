import Foundation
import RuntimeABI

import CompilerCore

final class GeneratedNameCounter {
    private var value: Int32 = 0

    func next() -> Int32 {
        let current = value
        value += 1
        return current
    }

    func nextName(_ prefix: String) -> String {
        "\(prefix)\(next())"
    }
}

struct NativeEmitter {
    static let dwarfLangC99: UInt32 = 11
    static let dwarfATESigned: UInt32 = 5

    static let knownVoidNoArgCallees: Set<String> = []

    static let functionValueInvokeCallees: Set<String> = Set([
        "kk_function_invoke", "kk_function_invoke_0",
        "kk_function_invoke_2", "kk_function_invoke_3", "kk_function_invoke_4",
        "kk_function_invoke_5", "kk_function_invoke_6",
        "kk_suspend_function_invoke", "kk_suspend_function_invoke_0", "kk_suspend_function_invoke_2",
        "kk_suspend_function_invoke_3", "kk_suspend_function_invoke_4", "kk_suspend_function_invoke_5",
        "kk_suspend_function_invoke_6",
    ] + (7...22).map { "kk_function_invoke_\($0)" })

    static let runtimeABIFunctionByName: [String: RuntimeABIFunctionSpec] = {
        Dictionary(uniqueKeysWithValues: RuntimeABISpec.allFunctions.map { ($0.name, $0) })
    }()

    struct LLVMFunction {
        let value: LLVMCAPIBindings.LLVMValueRef
        let type: LLVMCAPIBindings.LLVMTypeRef
    }

    struct FunctionLookupKey: Hashable {
        let name: String
        let parameterCount: Int
    }

    struct DebugInfoContext {
        let diBuilder: LLVMCAPIBindings.LLVMDIBuilderRef
        let file: LLVMCAPIBindings.LLVMMetadataRef
        let subprograms: [SymbolID: LLVMCAPIBindings.LLVMMetadataRef]
        let diFiles: [FileID: LLVMCAPIBindings.LLVMMetadataRef]
        let int64DIType: LLVMCAPIBindings.LLVMMetadataRef?
    }

    let phaseTimer: PhaseTimer?
    let target: TargetTriple
    let optLevel: OptimizationLevel
    let debugInfo: Bool
    let bindings: LLVMCAPIBindings
    let reusableContext: LLVMCAPIBindings.LLVMContextRef?
    let module: KIRModule
    let threadLocalGCGlobalSymbols: Set<SymbolID>
    let interner: StringInterner
    let moduleName: String
    let typeSystem: TypeSystem?
    let symbols: SymbolTable?
    let externalFunctionSymbolsByLinkName: [String: SymbolID]
    let sourceManager: SourceManager?
    let fileFacadeNamesByFileID: [Int32: String]
    let reflectionMetadataRecords: [MetadataRecord]
    let reflectionMetadataSymbolPrefix: String?
    let linkOnceODRSymbols: Set<SymbolID>
    let parallelJobs: Int

    init(
        target: TargetTriple,
        optLevel: OptimizationLevel,
        debugInfo: Bool,
        bindings: LLVMCAPIBindings,
        reusableContext: LLVMCAPIBindings.LLVMContextRef? = nil,
        module: KIRModule,
        interner: StringInterner,
        moduleName: String = "main",
        typeSystem: TypeSystem? = nil,
        symbols: SymbolTable? = nil,
        sourceManager: SourceManager? = nil,
        fileFacadeNamesByFileID: [Int32: String] = [:],
        reflectionMetadataRecords: [MetadataRecord] = [],
        reflectionMetadataSymbolPrefix: String? = nil,
        linkOnceODRSymbols: Set<SymbolID> = [],
        parallelJobs: Int = 1,
        phaseTimer: PhaseTimer? = nil
    ) {
        self.phaseTimer = phaseTimer
        self.target = target
        self.optLevel = optLevel
        self.debugInfo = debugInfo
        self.bindings = bindings
        self.reusableContext = reusableContext
        self.module = module
        self.threadLocalGCGlobalSymbols = Set(module.arena.declarations.compactMap { declaration in
            guard case let .global(global) = declaration, global.isThreadLocal else { return nil }
            return global.symbol
        })
        self.interner = interner
        self.moduleName = moduleName
        self.typeSystem = typeSystem
        self.symbols = symbols
        var externalFunctionSymbolsByLinkName: [String: SymbolID] = [:]
        var ambiguousLinkNames: Set<String> = []
        for symbol in symbols?.allSymbols() ?? [] where symbol.kind == .function {
            guard let linkName = symbols?.externalLinkNameIfKnown(for: symbol.id),
                  !linkName.isEmpty,
                  !ambiguousLinkNames.contains(linkName)
            else {
                continue
            }
            if externalFunctionSymbolsByLinkName[linkName] != nil {
                externalFunctionSymbolsByLinkName.removeValue(forKey: linkName)
                ambiguousLinkNames.insert(linkName)
            } else {
                externalFunctionSymbolsByLinkName[linkName] = symbol.id
            }
        }
        self.externalFunctionSymbolsByLinkName = externalFunctionSymbolsByLinkName
        self.sourceManager = sourceManager
        self.fileFacadeNamesByFileID = fileFacadeNamesByFileID
        self.reflectionMetadataRecords = reflectionMetadataRecords
        self.reflectionMetadataSymbolPrefix = reflectionMetadataSymbolPrefix
        self.linkOnceODRSymbols = linkOnceODRSymbols
        self.parallelJobs = parallelJobs
    }

    private func collectRuntimeCallbackRawABISymbols() -> Set<SymbolID> {
        Self.collectRuntimeCallbackRawABISymbols(module: module, interner: interner, symbols: symbols)
    }

    static func collectRuntimeCallbackRawStringReturnSymbols(
        module: KIRModule,
        interner: StringInterner,
        typeSystem: TypeSystem?,
        symbols: SymbolTable? = nil
    ) -> Set<SymbolID> {
        let rawSymbols = collectRuntimeCallbackRawABISymbols(module: module, interner: interner, symbols: symbols)
        guard let typeSystem else { return [] }
        return Set(module.arena.declarations.compactMap { declaration -> SymbolID? in
            guard case let .function(function) = declaration else { return nil }
            guard rawSymbols.contains(function.symbol) else { return nil }
            guard case .stringStruct = typeSystem.kind(of: function.returnType) else { return nil }
            return function.symbol
        })
    }

    static func collectRuntimeCallbackRawABISymbols(
        module: KIRModule,
        interner: StringInterner,
        symbols: SymbolTable? = nil
    ) -> Set<SymbolID> {
        let callbackArgumentPositionsByCallee = runtimeCallbackArgumentPositionsByCallee(interner: interner)
        guard !callbackArgumentPositionsByCallee.isEmpty else {
            return []
        }

        let notNullCallee = interner.intern("kk_op_notnull")
        let callableTagCallees: Set<InternedString> = [
            interner.intern("kk_callable_ref_tag_kfunction"),
            interner.intern("kk_callable_ref_tag_kproperty"),
        ]
        let packedValueCallees: Set<InternedString> = [
            interner.intern("kk_array_set"),
            interner.intern("kk_coroutine_launcher_arg_set"),
        ]
        let lambdaSymbols = Set(module.arena.declarations.compactMap { declaration -> SymbolID? in
            guard case let .function(function) = declaration else { return nil }
            guard interner.resolve(function.name).hasPrefix("kk_lambda_")
                || symbols?.isAnonymousFunction(function.symbol, interner: interner) == true
            else { return nil }
            return function.symbol
        })
        let globalSymbols = Set(module.arena.declarations.compactMap { declaration -> SymbolID? in
            guard case let .global(global) = declaration else { return nil }
            return global.symbol
        })
        let topLevelStringCallableRefThunkSymbols = Set(module.arena.declarations.compactMap { declaration -> SymbolID? in
            guard case let .function(function) = declaration,
                  interner.resolve(function.name).hasPrefix("kk_top_level_string_callable_ref_")
            else {
                return nil
            }
            return function.symbol
        })
        let anonymousFunctionSymbols = Set(module.arena.declarations.compactMap { declaration -> SymbolID? in
            guard case let .function(function) = declaration else { return nil }
            guard symbols?.isAnonymousFunction(function.symbol, interner: interner) == true
            else { return nil }
            return function.symbol
        })
        var rawSymbols: Set<SymbolID> = anonymousFunctionSymbols
        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration else {
                continue
            }
            let aliasSources = Self.valueAliasSources(
                in: function.body,
                notNullCallee: notNullCallee,
                callableTagCallees: callableTagCallees
            )
            func collectSymbolRefs(reaching root: KIRExprID, lambdaOnly: Bool) {
                var visited: Set<KIRExprID> = []
                var pending = [root]
                while let exprID = pending.popLast() {
                    guard visited.insert(exprID).inserted else { continue }
                    if case let .symbolRef(symbol)? = module.arena.expr(exprID),
                       !lambdaOnly || lambdaSymbols.contains(symbol)
                    {
                        rawSymbols.insert(symbol)
                    }
                    pending.append(contentsOf: aliasSources[exprID] ?? [])
                }
            }
            func collectTopLevelStringCallableRefThunks(reaching root: KIRExprID) {
                var visited: Set<KIRExprID> = []
                var pending = [root]
                while let exprID = pending.popLast() {
                    guard visited.insert(exprID).inserted else { continue }
                    if case let .symbolRef(symbol)? = module.arena.expr(exprID),
                       topLevelStringCallableRefThunkSymbols.contains(symbol)
                    {
                        rawSymbols.insert(symbol)
                    }
                    pending.append(contentsOf: aliasSources[exprID] ?? [])
                }
            }
            for instruction in function.body {
                switch instruction {
                case let .copy(from, to):
                    if case let .symbolRef(globalSymbol)? = module.arena.expr(to),
                       globalSymbols.contains(globalSymbol)
                    {
                        collectTopLevelStringCallableRefThunks(reaching: from)
                    }

                case let .storeGlobal(value, globalSymbol):
                    if globalSymbols.contains(globalSymbol) {
                        collectTopLevelStringCallableRefThunks(reaching: value)
                    }

                case let .call(_, callee, arguments, _, _, _, _, _):
                    if packedValueCallees.contains(callee), arguments.count == 3 {
                        collectSymbolRefs(reaching: arguments[2], lambdaOnly: true)
                    }
                    guard let callbackPositions = callbackArgumentPositionsByCallee[callee] else {
                        continue
                    }
                    for position in callbackPositions where arguments.indices.contains(position) {
                        collectSymbolRefs(reaching: arguments[position], lambdaOnly: false)
                    }

                case let .returnValue(value):
                    collectSymbolRefs(reaching: value, lambdaOnly: true)

                default:
                    continue
                }
            }
        }
        if !rawSymbols.isEmpty {
            struct FunctionABIKey: Hashable {
                let name: InternedString
                let parameterCount: Int
            }

            var rawCallbackKeys: Set<FunctionABIKey> = []
            for declaration in module.arena.declarations {
                guard case let .function(function) = declaration,
                      rawSymbols.contains(function.symbol),
                      Self.isSyntheticCallbackFunction(function, symbols: symbols)
                else {
                    continue
                }
                rawCallbackKeys.insert(FunctionABIKey(
                    name: function.name,
                    parameterCount: function.params.count
                ))
            }
            for declaration in module.arena.declarations {
                guard case let .function(function) = declaration else {
                    continue
                }
                let key = FunctionABIKey(name: function.name, parameterCount: function.params.count)
                if rawCallbackKeys.contains(key), Self.isSyntheticCallbackFunction(function, symbols: symbols) {
                    rawSymbols.insert(function.symbol)
                }
            }
        }

        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration,
                  isThrowableToStringFunction(function, interner: interner, symbols: symbols)
            else {
                continue
            }
            rawSymbols.insert(function.symbol)
        }

        return rawSymbols
    }

    private static func valueAliasSources(
        in body: [KIRInstruction],
        notNullCallee: InternedString,
        callableTagCallees: Set<InternedString>
    ) -> [KIRExprID: [KIRExprID]] {
        var sources: [KIRExprID: [KIRExprID]] = [:]
        for instruction in body {
            switch instruction {
            case let .copy(from, to):
                sources[to, default: []].append(from)
            case let .nullAssert(operand, result):
                sources[result, default: []].append(operand)
            case let .call(_, callee, arguments, result, _, _, _, _):
                if callee == notNullCallee, arguments.count == 1, let result {
                    sources[result, default: []].append(arguments[0])
                } else if callableTagCallees.contains(callee), let callable = arguments.first, let result {
                    sources[result, default: []].append(callable)
                }
            default:
                continue
            }
        }
        return sources
    }

    private static func isThrowableToStringFunction(
        _ function: KIRFunction,
        interner: StringInterner,
        symbols: SymbolTable?
    ) -> Bool {
        guard interner.resolve(function.name) == "toString",
              let symbols,
              isThrowableToStringSymbol(function.symbol, interner: interner, symbols: symbols)
        else {
            return false
        }
        return true
    }

    static func isThrowableToStringSymbol(
        _ symbol: SymbolID,
        interner: StringInterner,
        symbols: SymbolTable
    ) -> Bool {
        guard let owner = symbols.parentSymbol(for: symbol) else {
            return false
        }
        return isThrowableClassSymbol(owner, interner: interner, symbols: symbols)
    }

    static func isThrowableType(
        _ type: TypeID?,
        typeSystem: TypeSystem,
        interner: StringInterner,
        symbols: SymbolTable
    ) -> Bool {
        guard let type,
              case let .classType(classType) = typeSystem.kind(of: type)
        else {
            return false
        }
        return isThrowableClassSymbol(
            classType.classSymbol,
            interner: interner,
            symbols: symbols
        )
    }

    private static func isThrowableClassSymbol(
        _ symbol: SymbolID,
        interner: StringInterner,
        symbols: SymbolTable
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        var visited: Set<SymbolID> = []
        var pending = [symbol]
        while let candidate = pending.popLast() {
            guard visited.insert(candidate).inserted,
                  let symbolInfo = symbols.symbol(candidate)
            else {
                continue
            }
            if symbolInfo.fqName == knownNames.kotlinThrowableFQName {
                return true
            }
            pending.append(contentsOf: symbols.directSupertypes(for: candidate))
        }
        return false
    }

    private static func isSyntheticCallbackFunction(
        _ function: KIRFunction,
        symbols: SymbolTable?
    ) -> Bool {
        guard let symbols else { return true }
        guard let symbolInfo = symbols.symbol(function.symbol) else { return false }
        return symbolInfo.flags.contains(.synthetic)
    }

    private static func runtimeCallbackArgumentPositionsByCallee(
        interner: StringInterner
    ) -> [InternedString: [Int]] {
        var positionsByCallee: [InternedString: [Int]] = [:]
        for spec in RuntimeABISpec.allFunctions {
            if spec.name == "kk_object_register_itable_method"
                || spec.name == "kk_object_register_vtable_method"
                || spec.name == "kk_object_register_any_to_string"
                || spec.name.hasPrefix("__kk_kfunction_create")
                || spec.name == "__kk_kconstructor_create" {
                continue
            }
            var positions: [Int] = []
            var abiIndex = 0
            var kirIndex = 0
            while abiIndex < spec.parameters.count {
                let parameter = spec.parameters[abiIndex]
                let name = parameter.name.lowercased()
                if name.contains("fnptr") || name == "functionraw" || name == "bodyraw" || name.hasSuffix("fn") {
                    positions.append(kirIndex)
                }
                if abiIndex + 3 < spec.parameters.count,
                   name.hasSuffix("data")
                {
                    let prefix = String(name.dropLast("data".count))
                    let lengthName = spec.parameters[abiIndex + 1].name.lowercased()
                    let byteCountName = spec.parameters[abiIndex + 2].name.lowercased()
                    let hashName = spec.parameters[abiIndex + 3].name.lowercased()
                    if lengthName == "\(prefix)length",
                       byteCountName == "\(prefix)bytecount",
                       hashName == "\(prefix)hash"
                    {
                        kirIndex += 1
                        abiIndex += 4
                        continue
                    }
                }
                kirIndex += 1
                abiIndex += 1
            }
            if !positions.isEmpty {
                positionsByCallee[interner.intern(spec.name)] = positions
            }
        }
        return positionsByCallee
    }

    func emitLLVMIR(outputPath: String) throws {
        let built = try withSubPhaseTiming("emit", timer: phaseTimer) {
            try buildModule()
        }
        defer {
            bindings.disposeModule(built.module)
            for partitionContext in built.partitionContexts {
                bindings.disposeContext(partitionContext)
            }
            if built.ownsContext {
                bindings.disposeContext(built.context)
            }
        }

        let triple = targetTripleString()
        try CodegenCriticalSection.withLinuxLLVMProcessLock(target: target) {
            bindings.setTarget(built.module, triple: triple)

            if optLevel != .O0 {
                let targetMachine = try withSubPhaseTiming("initTarget", timer: phaseTimer) {
                    try configuredTargetMachine(for: built.module)
                }
                defer { bindings.disposeTargetMachine(targetMachine) }
                try withSubPhaseTiming("opt", timer: phaseTimer) {
                    if let error = bindings.optimizeModule(built.module, targetMachine: targetMachine, optLevel: optLevel) {
                        throw LLVMBackendError.nativeEmissionFailed(error)
                    }
                }
            }

            try withSubPhaseTiming("write", timer: phaseTimer) {
                guard let llvmIR = bindings.printModule(built.module) else {
                    throw LLVMBackendError.nativeEmissionFailed("LLVMPrintModuleToString returned null")
                }
                do {
                    try llvmIR.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
                } catch {
                    throw LLVMBackendError.nativeEmissionFailed("failed to write LLVM IR to '\(outputPath)'")
                }
            }
        }
    }

    func emitObject(outputPath: String, bitcodeOutputPath: String? = nil) throws {
        let built = try withSubPhaseTiming("emit", timer: phaseTimer) {
            try buildModule()
        }
        defer {
            bindings.disposeModule(built.module)
            for partitionContext in built.partitionContexts {
                bindings.disposeContext(partitionContext)
            }
            if built.ownsContext {
                bindings.disposeContext(built.context)
            }
        }

        try CodegenCriticalSection.withLinuxLLVMProcessLock(target: target) {
            let targetMachine = try withSubPhaseTiming("initTarget", timer: phaseTimer) {
                try configuredTargetMachine(for: built.module)
            }
            defer { bindings.disposeTargetMachine(targetMachine) }

            try withSubPhaseTiming("opt", timer: phaseTimer) {
                if let error = bindings.optimizeModule(built.module, targetMachine: targetMachine, optLevel: optLevel) {
                    throw LLVMBackendError.nativeEmissionFailed(error)
                }
            }
            if let bitcodeOutputPath {
                try withSubPhaseTiming("writeBitcode", timer: phaseTimer) {
                    if let errorMessage = bindings.writeBitcode(built.module, to: bitcodeOutputPath) {
                        throw LLVMBackendError.nativeEmissionFailed(errorMessage)
                    }
                }
            }
            try withSubPhaseTiming("write", timer: phaseTimer) {
                if let errorMessage = bindings.emitObject(targetMachine: targetMachine, module: built.module, outputPath: outputPath) {
                    throw LLVMBackendError.nativeEmissionFailed(errorMessage)
                }
            }
        }
    }

    func configuredTargetMachine(for llvmModule: LLVMCAPIBindings.LLVMModuleRef) throws -> LLVMCAPIBindings.LLVMTargetMachineRef {
        let triple = targetTripleString()
        bindings.setTarget(llvmModule, triple: triple)

        guard let targetMachine = bindings.createTargetMachine(triple: triple, optLevel: optLevel) else {
            throw LLVMBackendError.nativeEmissionFailed(
                "failed to create LLVM target machine for '\(triple)' (the loaded LLVM may lack this backend)"
            )
        }
        guard bindings.applyTargetMachine(targetMachine, to: llvmModule) else {
            bindings.disposeTargetMachine(targetMachine)
            throw LLVMBackendError.nativeEmissionFailed("failed to apply target data layout")
        }
        return targetMachine
    }

    fileprivate func stableGlobalSlotName(for symbol: SymbolID) -> String {
        if let sym = symbols?.symbol(symbol) {
            let fqn = sym.fqName.compactMap { interner.resolve($0) }.joined(separator: ".")
            if !fqn.isEmpty {
                let sanitized = fqn.map { c in
                    c.isLetter || c.isNumber || c == "_" ? String(c) : "_"
                }.joined()
                if sym.visibility == .private,
                   !sym.flags.contains(.importedLibrary),
                   let symbols,
                   symbols.lookupAll(fqName: sym.fqName).contains(where: { candidate in
                       candidate != symbol && symbols.symbol(candidate)?.kind == sym.kind
                   }) {
                    return "kk_global_root_slot_\(sanitized)_private_\(symbol.rawValue)"
                }
                return "kk_global_root_slot_\(sanitized)"
            }
        }
        return "kk_global_root_slot_\(max(0, Int(symbol.rawValue)))"
    }

    private func shouldEmitImportedGlobalReference(for symbol: SymbolID) -> Bool {
        guard let sym = symbols?.symbol(symbol),
              sym.flags.contains(.importedLibrary)
        else {
            return false
        }
        switch sym.kind {
        case .property, .field, .backingField:
            return true
        case .object:
            if let parentID = symbols?.parentSymbol(for: symbol),
               symbols?.companionObjectSymbol(for: parentID) == symbol {
                return symbols?.companionObjectInitializerSymbol(for: parentID) != nil
            }
            if symbols?.objectInitializerSymbol(for: symbol) == nil,
               symbols?.externalLinkName(for: symbol)?.isEmpty != false,
               symbols?.nominalLayout(for: symbol)?.instanceFieldCount == 0 {
                return false
            }
            return true
        case .class, .interface, .enumClass, .annotationClass, .typeAlias,
             .function, .constructor, .typeParameter, .valueParameter,
             .local, .label, .package:
            return false
        }
    }

    private func shouldUseWeakImportedGlobalReference(for symbol: SymbolID) -> Bool {
        guard let symbols else { return false }
        return Self.shouldUseWeakImportedObjectGlobalReference(for: symbol, symbols: symbols)
            || Self.shouldUseWeakImportedEnumEntryGlobalReference(for: symbol, symbols: symbols)
    }

    static func shouldUseWeakImportedEnumEntryGlobalReference(
        for symbol: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        guard let sym = symbols.symbol(symbol),
              sym.kind == .field,
              sym.flags.contains(.importedLibrary),
              let parentID = symbols.parentSymbol(for: symbol),
              symbols.symbol(parentID)?.kind == .enumClass
        else {
            return false
        }
        return symbols.enumStaticInitSymbol(for: parentID) == nil
    }

    static func shouldUseWeakImportedObjectGlobalReference(
        for symbol: SymbolID,
        symbols: SymbolTable
    ) -> Bool {
        guard let sym = symbols.symbol(symbol), sym.kind == .object else {
            return false
        }
        if let parentID = symbols.parentSymbol(for: symbol),
           symbols.companionObjectSymbol(for: parentID) == symbol
        {
            return symbols.companionObjectInitializerSymbol(for: parentID) == nil
        }
        return symbols.objectInitializerSymbol(for: symbol) == nil
    }

    func ensureImportedGlobalReferences(
        module: KIRModule,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        emitDefinitions: Bool,
        globalVariables: inout [SymbolID: LLVMCAPIBindings.LLVMValueRef]
    ) {
        var referencedSymbols: Set<SymbolID> = []
        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration else {
                continue
            }
            for instruction in function.body {
                switch instruction {
                case let .loadGlobal(_, symbol), let .storeGlobal(_, symbol):
                    referencedSymbols.insert(symbol)
                case let .constValue(_, .symbolRef(symbol)):
                    referencedSymbols.insert(symbol)
                default:
                    break
                }
            }
        }
        for expr in module.arena.expressions {
            if case let .symbolRef(symbol) = expr {
                referencedSymbols.insert(symbol)
            }
        }
        let sortedReferencedSymbols = referencedSymbols
            .map { (slotName: stableGlobalSlotName(for: $0), symbol: $0) }
            .sorted { $0.slotName < $1.slotName }
        for (slotName, symbol) in sortedReferencedSymbols {
            guard globalVariables[symbol] == nil,
                  shouldEmitImportedGlobalReference(for: symbol) || shouldUseWeakImportedGlobalReference(for: symbol)
            else {
                continue
            }
            if let llvmGlobal = bindings.addGlobal(module: llvmModule, type: int64Type, name: slotName) {
                if symbols?.annotations(for: symbol).contains(where: {
                    KnownCompilerAnnotation.nativeThreadLocal.matches($0.annotationFQName)
                }) == true {
                    bindings.setThreadLocal(llvmGlobal)
                }
                if emitDefinitions {
                    if shouldUseWeakImportedGlobalReference(for: symbol) {
                        bindings.setWeakAnyLinkage(llvmGlobal)
                        if let zero = bindings.constInt(int64Type, value: 0) {
                            bindings.setInitializer(llvmGlobal, value: zero)
                        }
                    } else {
                        bindings.setExternalLinkage(llvmGlobal)
                    }
                }
                globalVariables[symbol] = llvmGlobal
            }
        }
    }

    func buildModule() throws -> (
        context: LLVMCAPIBindings.LLVMContextRef,
        module: LLVMCAPIBindings.LLVMModuleRef,
        partitionContexts: [LLVMCAPIBindings.LLVMContextRef],
        ownsContext: Bool
    ) {
        let usesReusableContext = reusableContext != nil
        guard let context = reusableContext ?? bindings.createContext() else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMContextCreate returned null")
        }
        guard let llvmModule = bindings.createModule(name: "kswiftk_module", context: context) else {
            if !usesReusableContext { bindings.disposeContext(context) }
            throw LLVMBackendError.nativeEmissionFailed("LLVMModuleCreateWithNameInContext returned null")
        }

        guard let int64Type = bindings.int64Type(context: context) else {
            bindings.disposeModule(llvmModule)
            if !usesReusableContext { bindings.disposeContext(context) }
            throw LLVMBackendError.nativeEmissionFailed("LLVMInt64TypeInContext returned null")
        }
        guard let outThrownPointerType = bindings.pointerType(int64Type, addressSpace: 0) else {
            bindings.disposeModule(llvmModule)
            if !usesReusableContext { bindings.disposeContext(context) }
            throw LLVMBackendError.nativeEmissionFailed("LLVMPointerType returned null")
        }
        let typeLowering = makeLLVMTypeLowering(context: context, int64Type: int64Type)
        let runtimeCallbackRawABISymbols = collectRuntimeCallbackRawABISymbols()
        var partitionContexts: [LLVMCAPIBindings.LLVMContextRef] = []

        do {
            var llvmGlobalVariables = declareGlobals(
                llvmModule: llvmModule,
                int64Type: int64Type,
                emitDefinitions: true
            )

            ensureImportedGlobalReferences(
                module: module,
                llvmModule: llvmModule,
                int64Type: int64Type,
                emitDefinitions: true,
                globalVariables: &llvmGlobalVariables
            )

            let declared = try declareFunctions(
                llvmModule: llvmModule,
                int64Type: int64Type,
                outThrownPointerType: outThrownPointerType,
                typeLowering: typeLowering,
                runtimeCallbackRawABISymbols: runtimeCallbackRawABISymbols
            )

            let diContext: DebugInfoContext? = (debugInfo && bindings.debugLocationAvailable)
                ? createDebugInfoContext(
                    llvmModule: llvmModule,
                    context: context,
                    internalFunctions: declared.internalFunctions
                )
                : nil

            do {
                if canEmitFunctionBodiesInParallel(emittableCount: declared.emittableFunctions.count) {
                    partitionContexts = try emitFunctionBodiesInParallel(
                        emittableFunctions: declared.emittableFunctions,
                        runtimeCallbackRawABISymbols: runtimeCallbackRawABISymbols,
                        into: llvmModule
                    )
                } else {
                    let nameCounter = GeneratedNameCounter()
                    for (function, _) in declared.emittableFunctions {
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
                            globalVariables: llvmGlobalVariables,
                            runtimeCallbackRawReturnSymbols: runtimeCallbackRawABISymbols,
                            usesRuntimeCallbackRawABI: usesRuntimeCallbackRawABI,
                            returnsRawStringRuntimeCallback: returnsRawStringRuntimeCallback,
                            nameCounter: nameCounter,
                            diContext: diContext
                        )
                    }
                }
            } catch {
                if let diContext {
                    bindings.disposeDIBuilder(diContext.diBuilder)
                }
                throw error
            }

            if let diContext {
                finalizeDebugInfo(
                    diContext: diContext,
                    llvmModule: llvmModule,
                    context: context
                )
            }
        } catch {
            bindings.disposeModule(llvmModule)
            for partitionContext in partitionContexts {
                bindings.disposeContext(partitionContext)
            }
            if !usesReusableContext { bindings.disposeContext(context) }
            throw error
        }

        PhaseTimer.measureSubPhase("IR/reflection globals", timer: phaseTimer) {
            RuntimeReflectionMetadataEmitter.emitGlobals(
                records: reflectionMetadataRecords,
                bindings: bindings,
                module: llvmModule,
                context: context,
                int64Type: int64Type,
                symbolPrefix: reflectionMetadataSymbolPrefix
            )
        }

        return (
            context: context,
            module: llvmModule,
            partitionContexts: partitionContexts,
            ownsContext: !usesReusableContext
        )
    }

    func declareGlobals(
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        emitDefinitions: Bool,
        definitionsUsedOnlyByOtherObjects: Bool = false
    ) -> [SymbolID: LLVMCAPIBindings.LLVMValueRef] {
        var llvmGlobalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:]
        let globalDecls = module.arena.declarations.compactMap { decl -> (slotName: String, global: KIRGlobal)? in
            guard case let .global(global) = decl else { return nil }
            return (stableGlobalSlotName(for: global.symbol), global)
        }.sorted { lhs, rhs in
            if lhs.slotName != rhs.slotName { return lhs.slotName < rhs.slotName }
            return lhs.global.symbol.rawValue < rhs.global.symbol.rawValue
        }
        for (slotName, global) in globalDecls {
            let isImported = symbols?.symbol(global.symbol)?.flags.contains(.importedLibrary) == true
                && symbols?.isKlibDefinedGlobal(global.symbol) != true
            if let llvmGlobal = bindings.addGlobal(module: llvmModule, type: int64Type, name: slotName) {
                if global.isThreadLocal {
                    bindings.setThreadLocal(llvmGlobal)
                }
                if emitDefinitions {
                    if isImported {
                        if shouldUseWeakImportedGlobalReference(for: global.symbol) {
                            bindings.setWeakAnyLinkage(llvmGlobal)
                            if let zero = bindings.constInt(int64Type, value: 0) {
                                bindings.setInitializer(llvmGlobal, value: zero)
                            }
                        } else {
                            bindings.setExternalLinkage(llvmGlobal)
                        }
                    } else {
                        if definitionsUsedOnlyByOtherObjects {
                            bindings.setWeakODRLinkage(llvmGlobal)
                        } else {
                            bindings.setLinkOnceODRLinkage(llvmGlobal)
                        }
                        if let zero = bindings.constInt(int64Type, value: 0) {
                            bindings.setInitializer(llvmGlobal, value: zero)
                        }
                    }
                }
                llvmGlobalVariables[global.symbol] = llvmGlobal
            }
        }
        return llvmGlobalVariables
    }

    struct DeclaredFunctions {
        var internalFunctions: [SymbolID: LLVMFunction] = [:]
        var internalSignatures: [SymbolID: (parameters: [TypeID], returnType: TypeID)] = [:]
        var internalFunctionsByLookupKey: [FunctionLookupKey: [KIRFunction]] = [:]
        var emittableFunctions: [(KIRFunction, String)] = []
    }

    func declareFunctions(
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef,
        typeLowering: LLVMTypeLowering?,
        runtimeCallbackRawABISymbols: Set<SymbolID>,
        definedSymbols: Set<SymbolID>? = nil
    ) throws -> DeclaredFunctions {
        var declared = DeclaredFunctions()

        for declaration in module.arena.declarations {
            guard case let .function(function) = declaration,
                  !function.isInlineOnly
            else {
                continue
            }
            let functionName = CodegenSymbolSupport.cFunctionSymbol(
                for: function,
                interner: interner,
                moduleName: moduleName,
                symbols: symbols,
                fileFacadeNamesByFileID: fileFacadeNamesByFileID
            )
            let usesRuntimeCallbackRawABI = runtimeCallbackRawABISymbols.contains(function.symbol)
            var parameterTypes = function.params.map {
                if usesRuntimeCallbackRawABI {
                    return int64Type
                }
                return loweredLLVMType(
                    for: $0.type,
                    lowering: typeLowering,
                    defaultType: int64Type
                )
            }
            parameterTypes.append(outThrownPointerType)
            let returnsRawStringRuntimeCallback = usesRuntimeCallbackRawABI
                && isStringAggregateType(
                    function.returnType,
                    typeSystem: typeSystem,
                    hasStringLowering: typeLowering != nil
                )
            let returnType = if returnsRawStringRuntimeCallback {
                int64Type
            } else {
                loweredLLVMType(
                    for: function.returnType,
                    lowering: typeLowering,
                    defaultType: int64Type
                )
            }

            guard let functionType = bindings.functionType(returnType: returnType, parameters: parameterTypes, isVarArg: false),
                  let functionValue = bindings.addFunction(module: llvmModule, name: functionName, functionType: functionType)
            else {
                throw LLVMBackendError.nativeEmissionFailed("failed to declare function '\(functionName)'")
            }
            let isDefinedHere = definedSymbols?.contains(function.symbol) ?? true
            if isDefinedHere && linkOnceODRSymbols.contains(function.symbol) {
                bindings.setLinkOnceODRLinkage(functionValue)
            }
            declared.internalFunctions[function.symbol] = LLVMFunction(value: functionValue, type: functionType)
            declared.internalSignatures[function.symbol] = (function.params.map(\.type), function.returnType)
            let functionLookupKey = FunctionLookupKey(name: interner.resolve(function.name), parameterCount: function.params.count)
            let cSymbolLookupKey = FunctionLookupKey(name: functionName, parameterCount: function.params.count)
            declared.internalFunctionsByLookupKey[functionLookupKey, default: []].append(function)
            declared.internalFunctionsByLookupKey[cSymbolLookupKey, default: []].append(function)
            declared.emittableFunctions.append((function, functionName))
        }

        declared.emittableFunctions.sort { $0.1 < $1.1 }
        return declared
    }

    func createDebugInfoContext(
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context _: LLVMCAPIBindings.LLVMContextRef,
        internalFunctions: [SymbolID: LLVMFunction]
    ) -> DebugInfoContext? {
        guard bindings.debugInfoAvailable else {
            return nil
        }

        guard let diBuilder = bindings.createDIBuilder(module: llvmModule) else {
            return nil
        }

        let primaryFilename: String
        let primaryDirectory: String
        if let sourceManager, sourceManager.fileCount > 0 {
            let firstFileID = FileID(rawValue: 0)
            let fullPath = sourceManager.path(of: firstFileID)
            let url = URL(fileURLWithPath: fullPath)
            primaryFilename = url.lastPathComponent
            let directoryPath = url.deletingLastPathComponent().path
            primaryDirectory = directoryPath.isEmpty ? "." : directoryPath
        } else {
            primaryFilename = "kswiftk_module.kt"
            primaryDirectory = "."
        }

        guard let diFile = bindings.diBuilderCreateFile(
            diBuilder,
            filename: primaryFilename,
            directory: primaryDirectory
        ) else {
            bindings.disposeDIBuilder(diBuilder)
            return nil
        }

        let isOptimized = optLevel != .O0
        guard bindings.diBuilderCreateCompileUnit(
            diBuilder,
            lang: Self.dwarfLangC99,
            file: diFile,
            producer: "kswiftk",
            isOptimized: isOptimized
        ) != nil else {
            bindings.disposeDIBuilder(diBuilder)
            return nil
        }

        let subroutineType = bindings.diBuilderCreateSubroutineType(
            diBuilder,
            file: diFile,
            parameterTypes: []
        )

        let diFiles = buildDIFiles(diBuilder: diBuilder, defaultFile: diFile)
        let int64DIType = bindings.diBuilderCreateBasicType(
            diBuilder, name: "Int", sizeInBits: 64, encoding: Self.dwarfATESigned
        )
        let subprograms = buildSubprograms(
            diBuilder: diBuilder, diFile: diFile, diFiles: diFiles,
            subroutineType: subroutineType, isOptimized: isOptimized,
            internalFunctions: internalFunctions
        )

        return DebugInfoContext(
            diBuilder: diBuilder,
            file: diFile,
            subprograms: subprograms,
            diFiles: diFiles,
            int64DIType: int64DIType
        )
    }

    private func buildDIFiles(
        diBuilder: LLVMCAPIBindings.LLVMDIBuilderRef,
        defaultFile _: LLVMCAPIBindings.LLVMMetadataRef
    ) -> [FileID: LLVMCAPIBindings.LLVMMetadataRef] {
        var diFiles: [FileID: LLVMCAPIBindings.LLVMMetadataRef] = [:]
        guard let sourceManager else { return diFiles }
        for fileID in sourceManager.fileIDs() {
            let fullPath = sourceManager.path(of: fileID)
            let url = URL(fileURLWithPath: fullPath)
            let fname = url.lastPathComponent
            let dir = url.deletingLastPathComponent().path
            if let f = bindings.diBuilderCreateFile(diBuilder, filename: fname, directory: dir) {
                diFiles[fileID] = f
            }
        }
        return diFiles
    }

    private func buildSubprograms(
        diBuilder: LLVMCAPIBindings.LLVMDIBuilderRef,
        diFile: LLVMCAPIBindings.LLVMMetadataRef,
        diFiles: [FileID: LLVMCAPIBindings.LLVMMetadataRef],
        subroutineType: LLVMCAPIBindings.LLVMMetadataRef?,
        isOptimized: Bool,
        internalFunctions: [SymbolID: LLVMFunction]
    ) -> [SymbolID: LLVMCAPIBindings.LLVMMetadataRef] {
        var subprograms: [SymbolID: LLVMCAPIBindings.LLVMMetadataRef] = [:]
        let functions = module.arena.declarations.compactMap { decl -> (name: String, function: KIRFunction)? in
            guard case let .function(function) = decl,
                  internalFunctions[function.symbol] != nil
            else { return nil }
            let name = CodegenSymbolSupport.cFunctionSymbol(
                for: function,
                interner: interner,
                moduleName: moduleName,
                symbols: symbols,
                fileFacadeNamesByFileID: fileFacadeNamesByFileID
            )
            return (name, function)
        }.sorted { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.function.symbol.rawValue < rhs.function.symbol.rawValue
        }
        for (functionName, function) in functions {
            guard let llvmFunction = internalFunctions[function.symbol] else { continue }
            var lineNo: UInt32 = 0
            var funcDIFile = diFile
            if let sourceRange = function.sourceRange, let sourceManager {
                let lc = sourceManager.lineColumn(of: sourceRange.start)
                lineNo = UInt32(lc.line)
                if let perFileDI = diFiles[sourceRange.start.file] { funcDIFile = perFileDI }
            }
            guard let subprogram = bindings.diBuilderCreateFunction(
                diBuilder, scope: funcDIFile,
                name: interner.resolve(function.name), linkageName: functionName,
                file: funcDIFile, lineNo: lineNo, type: subroutineType,
                isLocalToUnit: false, isDefinition: true, scopeLine: lineNo, isOptimized: isOptimized
            ) else { continue }
            bindings.setSubprogram(llvmFunction.value, subprogram: subprogram)
            subprograms[function.symbol] = subprogram
        }
        return subprograms
    }

    func finalizeDebugInfo(
        diContext: DebugInfoContext,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef
    ) {
        bindings.finalizeDIBuilder(diContext.diBuilder)
        bindings.disposeDIBuilder(diContext.diBuilder)

        if let int32Type = bindings.int32Type(context: context),
           let debugVersionConst = bindings.constInt(int32Type, value: 3),
           let debugVersionMD = bindings.valueAsMetadata(debugVersionConst)
        {
            bindings.addModuleFlag(llvmModule, behavior: 1, key: "Debug Info Version", value: debugVersionMD)
        }

        if let int32Type = bindings.int32Type(context: context),
           let dwarfVersionConst = bindings.constInt(int32Type, value: 5),
           let dwarfVersionMD = bindings.valueAsMetadata(dwarfVersionConst)
        {
            bindings.addModuleFlag(llvmModule, behavior: 1, key: "Dwarf Version", value: dwarfVersionMD)
        }
    }

    func targetTripleString() -> String {
        CodegenRuntimeSupport.targetTripleString(target)
    }
}
