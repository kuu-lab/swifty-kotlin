#if canImport(Testing)
@testable import CompilerCore
import RuntimeABI
import Testing

/// Operations identify ABI entries independently of their canonical link names.
enum BuildKIRRuntimeOperation: String {
    case arrayGet = "array_get"
    case arrayGetInbounds = "array_get_inbounds"
    case arrayNew = "array_new"
    case arrayNewChecked = "array_new_checked"
    case arrayOf = "array_of"
    case arraySet = "array_set"
    case arrayTagType = "array_tag_type"
    case arrayToList = "array_toList"
    case boxChar = "box_char"
    case boxInt = "box_int"
    case callableRefTagKfunction = "callable_ref_tag_kfunction"
    case coroutineCurrentScope = "coroutine_current_scope"
    case coroutineSuspended = "coroutine_suspended"
    case cpointerToKStringFromUtf16 = "cpointer_toKStringFromUtf16"
    case cpointerToKStringFromUtf32 = "cpointer_toKStringFromUtf32"
    case durationTimesInt = "duration_times_int"
    case enumMakeEntriesListCached = "enum_make_entries_list_cached"
    case enumMakeValuesArray = "enum_make_values_array"
    case exceptionNewCause = "exception_new_cause"
    case exceptionNewMessage = "exception_new_message"
    case functionCreate1 = "function_create_1"
    case intRangeInductionLe = "int_range_induction_le"
    case iterableIterator = "iterable_iterator"
    case iteratorBuilderBuild = "iterator_builder_build"
    case iteratorHasNext = "iterator_hasNext"
    case iteratorNext = "iterator_next"
    case kxminiDelay = "kxmini_delay"
    case listIterator = "list_iterator"
    case listIteratorHasNext = "list_iterator_hasNext"
    case listIteratorNext = "list_iterator_next"
    case mapMinus = "map_minus"
    case nativeByteArrayGetByteAt = "native_byteArray_getByteAt"
    case nativeByteArrayGetCharAt = "native_byteArray_getCharAt"
    case nativeByteArrayGetDoubleAt = "native_byteArray_getDoubleAt"
    case nativeByteArrayGetFloatAt = "native_byteArray_getFloatAt"
    case nativeByteArrayGetIntAt = "native_byteArray_getIntAt"
    case nativeByteArrayGetLongAt = "native_byteArray_getLongAt"
    case nativeByteArrayGetShortAt = "native_byteArray_getShortAt"
    case nativeByteArrayGetUByteAt = "native_byteArray_getUByteAt"
    case nativeByteArrayGetUIntAt = "native_byteArray_getUIntAt"
    case nativeByteArrayGetULongAt = "native_byteArray_getULongAt"
    case nativeByteArrayGetUShortAt = "native_byteArray_getUShortAt"
    case nativeByteArraySetByteAt = "native_byteArray_setByteAt"
    case nativeByteArraySetCharAt = "native_byteArray_setCharAt"
    case nativeByteArraySetDoubleAt = "native_byteArray_setDoubleAt"
    case nativeByteArraySetFloatAt = "native_byteArray_setFloatAt"
    case nativeByteArraySetIntAt = "native_byteArray_setIntAt"
    case nativeByteArraySetLongAt = "native_byteArray_setLongAt"
    case nativeByteArraySetShortAt = "native_byteArray_setShortAt"
    case nativeByteArraySetUByteAt = "native_byteArray_setUByteAt"
    case nativeByteArraySetUIntAt = "native_byteArray_setUIntAt"
    case nativeByteArraySetULongAt = "native_byteArray_setULongAt"
    case nativeByteArraySetUShortAt = "native_byteArray_setUShortAt"
    case nativeConcurrentAttachObjectGraph = "native_concurrent_attach_object_graph"
    case nativeConcurrentConsumeFuture = "native_concurrent_consume_future"
    case nativeConcurrentDetachObjectGraph = "native_concurrent_detach_object_graph"
    case nativeConcurrentExecuteImpl = "native_concurrent_execute_impl"
    case nativeConcurrentStartWorker = "native_concurrent_start_worker"
    case nativeConcurrentTerminateWorker = "native_concurrent_terminate_worker"
    case nativeConcurrentWaitForMultipleFutures = "native_concurrent_wait_for_multiple_futures"
    case nativeConcurrentWaitWorkerTermination = "native_concurrent_wait_worker_termination"
    case nativeGetStackTraceAddresses = "native_getStackTraceAddresses"
    case nativeGetUnhandledExceptionHook = "native_getUnhandledExceptionHook"
    case nativeIdentityHashCode = "native_identityHashCode"
    case nativeProcessUnhandledException = "native_processUnhandledException"
    case nativeSetUnhandledExceptionHook = "native_setUnhandledExceptionHook"
    case nativeTerminateWithUnhandledException = "native_terminateWithUnhandledException"
    case objectRegisterEqualsOverride = "object_register_equals_override"
    case opAdd = "op_add"
    case opContains = "op_contains"
    case opMul = "op_mul"
    case opRangeTo = "op_rangeTo"
    case opSub = "op_sub"
    case platformCanAccessUnaligned = "platform_canAccessUnaligned"
    case platformCpuArchitecture = "platform_cpuArchitecture"
    case platformGetAvailableProcessors = "platform_getAvailableProcessors"
    case platformGetAvailableProcessorsEnv = "platform_getAvailableProcessorsEnv"
    case platformIsDebugBinary = "platform_isDebugBinary"
    case platformIsLittleEndian = "platform_isLittleEndian"
    case platformIsMemoryLeakCheckerActiveLoad = "platform_isMemoryLeakCheckerActive_load"
    case platformIsMemoryLeakCheckerActiveStore = "platform_isMemoryLeakCheckerActive_store"
    case platformMemoryModel = "platform_memoryModel"
    case platformOsFamily = "platform_osFamily"
    case platformProgramName = "platform_programName"
    case rangeContains = "range_contains"
    case rangeFirst = "range_first"
    case rangeForInHasNext = "range_for_in_hasNext"
    case rangeForInIterator = "range_for_in_iterator"
    case rangeForInNext = "range_for_in_next"
    case rangeHasNext = "range_hasNext"
    case rangeIterator = "range_iterator"
    case rangeLast = "range_last"
    case rangeNext = "range_next"
    case sequenceBuilderBuild = "sequence_builder_build"
    case sequenceBuilderYield = "sequence_builder_yield"
    case sequenceContains = "sequence_contains"
    case sequenceNone = "sequence_none"
    case stringCodePointCount = "string_codePointCount"
    case stringCodePointCountFrom = "string_codePointCount_from"
    case stringCodePointCountRange = "string_codePointCount_range"
    case stringConcatFlat = "string_concat_flat"
    case stringEqualsFlat = "string_equals_flat"
    case stringIsNormalizedFlat = "string_isNormalized_flat"
    case stringNormalizeFlat = "string_normalize_flat"
    case suspendFunctionInvoke = "suspend_function_invoke"
    case systemCurrentTimeMillis = "system_currentTimeMillis"
    case systemGetTimeMicros = "system_getTimeMicros"
    case systemGetTimeNanos = "system_getTimeNanos"
    case systemNanoTime = "system_nanoTime"
    case systemProcessStartNanos = "system_process_start_nanos"
    case throwableCaptureStackTrace = "throwable_captureStackTrace"
    case throwableSetCause = "throwable_setCause"
    case throwableSetMessage = "throwable_setMessage"
    case timeSourceMarkNow = "time_source_mark_now"
    case uuidFromLongs = "uuid_fromLongs"
    case uuidLexicalOrder = "uuid_lexicalOrder"
    case uuidRandom = "uuid_random"
    case uuidToKotlinUuid = "uuid_toKotlinUuid"
}

private let buildKIRCanonicalCallees = Set(RuntimeABIExterns.allExterns.map(\.name))
    .union(RuntimeABISpec.compilerInternalNonThrowingCalleeNames)
    .union(RuntimeABISpec.compilerInternalBuiltinCalleeNames)

private let buildKIRRuntimeNamesByOperation = Dictionary(grouping: buildKIRCanonicalCallees,
    by: { $0.split(separator: "_").dropFirst().joined(separator: "_") }
)

enum BuildKIRRuntimeFamily: String {
    case base64
    case iterator
    case platform
    case uuid
}

enum BuildKIRRuntimeTier {
    case publicBridge
    case privateBridge

    func contains(_ name: String) -> Bool {
        switch self {
        case .publicBridge:
            return name.first != "_"
        case .privateBridge:
            return name.first == "_"
        }
    }
}

func runtimeCallees(in family: BuildKIRRuntimeFamily) -> Set<String> {
    Set(buildKIRRuntimeNamesByOperation.filter { operation, _ in
        if family == .uuid {
            return operation.lowercased().contains(family.rawValue)
        }
        return operation.hasPrefix(family.rawValue + "_")
    }.flatMap(\.value))
}

func registeredRuntimeCallees() -> Set<String> {
    buildKIRCanonicalCallees
}

/// Missing or ambiguous canonical entries must fail even a negative assertion.
func runtimeCallee(
    _ operation: BuildKIRRuntimeOperation,
    tier: BuildKIRRuntimeTier? = nil,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    line: UInt = #line
) -> String {
    canonicalRuntimeCallee(operation.rawValue, tier: tier, fileID: fileID, file: file, line: line)
}

private func canonicalRuntimeCallee(
    _ operation: String,
    tier: BuildKIRRuntimeTier? = nil,
    fileID: StaticString,
    file: StaticString,
    line: UInt
) -> String {
    let names = buildKIRRuntimeNamesByOperation[operation, default: []].filter {
        tier?.contains($0) ?? true
    }
    guard names.count == 1, let name = names.first else {
        Issue.record(
            "Expected one canonical runtime callee for \(operation), found: \(names.sorted())",
            sourceLocation: SourceLocation(
                fileID: fileID.description, filePath: file.description,
                line: Int(line), column: 1
            )
        )
        return operation
    }
    return name
}

func runtimeFunctionCreateCallee(
    arity: Int,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    line: UInt = #line
) -> String {
    canonicalRuntimeCallee("function_create_\(arity)", fileID: fileID, file: file, line: line)
}

func runtimeFunctionCreateCallees() -> Set<String> {
    Set(RuntimeABIExterns.allExterns.map(\.name).filter {
        $0.split(separator: "_").dropFirst().joined(separator: "_").hasPrefix("function_create_")
    })
}

/// Match AST lambdas using the compiler's own generated-name scheme.
func findKIRLambdaFunctions(in context: CompilationContext) throws -> [KIRFunction] {
    let ast = try #require(context.ast)
    let module = try #require(context.kir)
    let fixture = makeKIRDirectLoweringFixture()
    let names = Set(ast.arena.exprs.indices.compactMap { index -> InternedString? in
        let exprID = ExprID(rawValue: Int32(index))
        guard case .lambdaLiteral = ast.arena.expr(exprID) else { return nil }
        return fixture.driver.lambdaLowerer.syntheticLambdaName(for: exprID, interner: context.interner)
    })
    return findAllKIRFunctions(in: module).filter { names.contains($0.name) }
}

func findKIRCoroutineBlockAdapters(in context: CompilationContext) throws -> [KIRFunction] {
    let module = try #require(context.kir)
    let lambdaSymbols = Set(try findKIRLambdaFunctions(in: context).map(\.symbol))
    let scopeCallee = context.interner.intern(runtimeCallee(.coroutineCurrentScope))
    return findAllKIRFunctions(in: module).filter { function in
        function.isSuspend && !lambdaSymbols.contains(function.symbol)
            && function.body.contains { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return callee == scopeCallee
            }
    }
}

func referencedKIRFunction(_ reference: KIRExprID, in module: KIRModule) throws -> KIRFunction {
    let symbol: SymbolID?
    if case let .symbolRef(value) = module.arena.expr(reference) {
        symbol = value
    } else {
        symbol = nil
    }
    let target = try #require(symbol, "Expected a function symbol reference")
    return try #require(findAllKIRFunctions(in: module).first { $0.symbol == target })
}

/// Accessor symbols may precede their KIR definitions or retain a property's call name.
private func propertyOwnerForKIRAccessorCall(
    _ symbol: SymbolID,
    callee: InternedString,
    sema: SemaModule,
    knownNames: KnownCompilerNames
) -> SymbolID? {
    if let accessor = SyntheticSymbolScheme.decodedPropertyAccessor(symbol),
       let property = sema.symbols.symbol(accessor.property), property.kind == .property,
       sema.symbols.propertyType(for: property.id) != nil
    {
        switch accessor.kind {
        case .getter:
            return callee == knownNames.get ? property.id : nil
        case .setter:
            return callee == knownNames.sbSet && property.flags.contains(.mutable) ? property.id : nil
        }
    }
    let owner = sema.symbols.accessorOwnerProperty(for: symbol)
        ?? sema.symbols.parentSymbol(for: symbol)
    guard let owner, let property = sema.symbols.symbol(owner), property.kind == .property,
          property.name == callee,
          sema.symbols.extensionPropertyGetterAccessor(for: property.id) == symbol
    else { return nil }
    return property.id
}

/// An obsolete bridge must not pass merely because it vanished from the ABI registry.
func expectResolvedKIRCallTargets(in body: [KIRInstruction], context: CompilationContext) throws {
    let sema = try #require(context.sema)
    let module = try #require(context.kir)
    let functions = findAllKIRFunctions(in: module)
    let functionsBySymbol = Dictionary(grouping: functions, by: \.symbol)
    let functionNames = Set(functions.map(\.name))
    let knownNames = KnownCompilerNames(interner: context.interner)
    for instruction in body {
        let target: (SymbolID?, InternedString)
        switch instruction {
        case let .call(symbol, callee, _, _, _, _, _, _),
             let .virtualCall(symbol, callee, _, _, _, _, _, _):
            target = (symbol, callee)
        default:
            continue
        }
        if let symbol = target.0, symbol != .invalid {
            let semanticSymbol = sema.symbols.symbol(symbol)
            let functions = functionsBySymbol[symbol, default: []]
            let accessorProperty = propertyOwnerForKIRAccessorCall(
                symbol, callee: target.1, sema: sema, knownNames: knownNames
            )
            #expect(semanticSymbol != nil || !functions.isEmpty || accessorProperty != nil)
            let name = context.interner.resolve(target.1)
            let matchesSymbol = semanticSymbol?.name == target.1
                || functions.contains { $0.name == target.1 }
                || accessorProperty != nil
            let resolvedTarget = buildKIRCanonicalCallees.contains(name) || matchesSymbol
            #expect(
                resolvedTarget,
                "KIR callee \(name) does not match its symbol or a registered runtime operation"
            )
            if let link = sema.symbols.externalLinkName(for: symbol) {
                let registeredBridge = buildKIRCanonicalCallees.contains(link)
                #expect(registeredBridge, "Unregistered runtime bridge: \(link)")
            }
            if let property = accessorProperty, let link = sema.symbols.externalLinkName(for: property) {
                let registeredBridge = buildKIRCanonicalCallees.contains(link)
                #expect(registeredBridge, "Unregistered property bridge: \(link)")
            }
        } else {
            let name = context.interner.resolve(target.1)
            let resolvedTarget = buildKIRCanonicalCallees.contains(name) || functionNames.contains(target.1)
            #expect(resolvedTarget, "Unresolved KIR call target: \(name)")
        }
    }
}

/// Verify source ownership and absence of an external ABI link for each selected call.
func expectSourceBackedCalls(
    named name: InternedString,
    in body: [KIRInstruction],
    context: CompilationContext,
    count: Int? = nil
) throws {
    let sema = try #require(context.sema)
    let calls = body.filter { instruction in
        switch instruction {
        case let .call(_, callee, _, _, _, _, _, _),
             let .virtualCall(_, callee, _, _, _, _, _, _):
            return callee == name
        default:
            return false
        }
    }
    #expect(!calls.isEmpty, "Expected a source-backed call to \(context.interner.resolve(name))")
    if let count {
        #expect(calls.count == count)
    }
    for call in calls {
        let symbol: SymbolID?
        switch call {
        case let .call(calleeSymbol, _, _, _, _, _, _, _),
             let .virtualCall(calleeSymbol, _, _, _, _, _, _, _):
            symbol = calleeSymbol
        default:
            continue
        }
        let calleeSymbol = try #require(symbol)
        #expect(sema.symbols.isSourceBackedSymbol(calleeSymbol))
        #expect(sema.symbols.externalLinkName(for: calleeSymbol) == nil)
    }
}
#endif
