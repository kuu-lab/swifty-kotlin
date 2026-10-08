#if canImport(Testing)
@testable import CompilerCore
import Foundation
import RuntimeABI
import Testing

@Suite
struct LoweringPassRegressionTests {
    // Runtime expectations use declarations from the canonical ABI table.
    // Missing entries record a test failure even for negative expectations.
    enum RuntimeCall: String {
        case bufferedReaderForEachLine = "__kk_buffered_reader_forEachLine"
        case bufferedReaderUseLines = "__kk_buffered_reader_useLines"
        case enumEntriesGet = "__kk_enum_entries_get"
        case iteratorBuilderBuildCoro = "__kk_iterator_builder_build_coro"
        case listSize = "__kk_list_size"
        case lockWithLock = "__kk_lock_withLock"
        case produceLaunch = "__kk_produce_launch"
        case produceLaunchWithCont = "__kk_produce_launch_with_cont"
        case sequenceBuilderBuild = "__kk_sequence_builder_build"
        case sequenceBuilderBuildCoro = "__kk_sequence_builder_build_coro"
        case sequenceBuilderYield = "__kk_sequence_builder_yield"
        case sequenceBuilderYieldAllChecked = "__kk_sequence_builder_yieldAll_checked"
        case stringBuilderAppendObj = "__kk_string_builder_append_obj"
        case stringBuilderNewFromStringFlat = "__kk_string_builder_new_from_string_flat"
        case stringBuilderToString = "__kk_string_builder_toString"
        case stringConcatFlat = "__kk_string_concat_flat"
        case stringEqualsFlat = "__kk_string_equals_flat"
        case uintRangeIterator = "__kk_uint_range_iterator"
        case anyHashCode = "kk_any_hashCode"
        case anyMemberToString = "kk_any_member_to_string"
        case anyToString = "kk_any_to_string"
        case arrayGet = "kk_array_get"
        case arrayGetInbounds = "kk_array_get_inbounds"
        case arrayNew = "kk_array_new"
        case arrayNewChecked = "kk_array_new_checked"
        case arraySet = "kk_array_set"
        case boxLongNonnullStatic = "kk_box_long_nonnull_static"
        case coroutineCallDirectSuspend = "kk_coroutine_call_direct_suspend"
        case coroutineCallSuspendWrapper = "kk_coroutine_call_suspend_wrapper"
        case coroutineContinuationNew = "kk_coroutine_continuation_new"
        case coroutineContinuationResume = "kk_coroutine_continuation_resume"
        case coroutineLauncherArgGet = "kk_coroutine_launcher_arg_get"
        case coroutineLauncherArgSet = "kk_coroutine_launcher_arg_set"
        case coroutineStateEnter = "kk_coroutine_state_enter"
        case coroutineStateExit = "kk_coroutine_state_exit"
        case coroutineStateGetCompletion = "kk_coroutine_state_get_completion"
        case coroutineStateGetSpill = "kk_coroutine_state_get_spill"
        case coroutineStateGetThrownException = "kk_coroutine_state_get_thrown_exception"
        case coroutineStateSetCompletion = "kk_coroutine_state_set_completion"
        case coroutineStateSetLabel = "kk_coroutine_state_set_label"
        case coroutineStateSetSpill = "kk_coroutine_state_set_spill"
        case coroutineSuspended = "kk_coroutine_suspended"
        case createCoroutineUnintercepted = "kk_create_coroutine_unintercepted"
        case durationInWholeMilliseconds = "kk_duration_inWholeMilliseconds"
        case enumMakeEntriesListCached = "kk_enum_make_entries_list_cached"
        case enumMakeValuesArray = "kk_enum_make_values_array"
        case enumValueOfThrow = "kk_enum_valueOf_throw"
        case flowEmit = "kk_flow_emit"
        case functionInvoke = "kk_function_invoke"
        case functionValueClosureRaw = "kk_function_value_closure_raw"
        case functionValueFnPtr = "kk_function_value_fn_ptr"
        case jobJoin = "kk_job_join"
        case kxminiAsyncAwait = "kk_kxmini_async_await"
        case kxminiDelay = "kk_kxmini_delay"
        case kxminiLaunchWithCont = "kk_kxmini_launch_with_cont"
        case kxminiRunBlocking = "kk_kxmini_run_blocking"
        case kxminiRunBlockingWithCont = "kk_kxmini_run_blocking_with_cont"
        case listForEach = "kk_list_forEach"
        case nullablePrimitiveEq = "kk_nullable_primitive_eq"
        case nullablePrimitiveNe = "kk_nullable_primitive_ne"
        case objectNew = "kk_object_new"
        case objectRegisterItableMethod = "kk_object_register_itable_method"
        case opDne = "kk_op_dne"
        case opElvis = "kk_op_elvis"
        case opEq = "kk_op_eq"
        case opIs = "kk_op_is"
        case opNe = "kk_op_ne"
        case opSafeCast = "kk_op_safe_cast"
        case rangeForInHasNext = "kk_range_for_in_hasNext"
        case rangeForInIterator = "kk_range_for_in_iterator"
        case rangeForInNext = "kk_range_for_in_next"
        case rangeHasNext = "kk_range_hasNext"
        case rangeIterator = "kk_range_iterator"
        case rangeNext = "kk_range_next"
        case startCoroutineUninterceptedOrReturn = "kk_start_coroutine_unintercepted_or_return"
        case structuralEq = "kk_structural_eq"
        case structuralNe = "kk_structural_ne"
        case suspendCoroutine = "kk_suspend_coroutine"
        case suspendFunctionInvoke = "kk_suspend_function_invoke"
        case suspendFunctionInvoke0 = "kk_suspend_function_invoke_0"
        case tagValueClassBox = "kk_tag_value_class_box"
        case typeRegisterIface = "kk_type_register_iface"
        case unboxInt = "kk_unbox_int"
        case unboxIntStatic = "kk_unbox_int_static"
        case unboxLongStatic = "kk_unbox_long_static"
        case withTimeout = "kk_with_timeout"
        case withTimeoutOrNull = "kk_with_timeout_or_null"
        case withTimeoutOrNullThrowing = "kk_with_timeout_or_null_throwing"

        var name: String {
            guard let declaration = RuntimeABIExterns.externDecl(named: rawValue) else {
                Issue.record("Missing runtime ABI declaration: \(rawValue)")
                return "<missing runtime ABI: \(rawValue)>"
            }
            return declaration.name
        }
    }

    // Compiler intrinsics are registered separately from external ABI functions.
    enum CompilerCall: String {
        case intRangeInductionAdd = "__kk_int_range_induction_add"
        case intRangeInductionLe = "__kk_int_range_induction_le"
        case forLowered = "kk_for_lowered"
        case lambdaInvoke = "kk_lambda_invoke"
        case opAdd = "kk_op_add"
        case opMul = "kk_op_mul"

        var name: String {
            guard let name = RuntimeABISpec.compilerInternalNonThrowingCalleeNames.first(where: { $0 == rawValue }) else {
                Issue.record("Missing compiler intrinsic declaration: \(rawValue)")
                return "<missing compiler intrinsic: \(rawValue)>"
            }
            return name
        }
    }

    /// Follow the continuation factory's function ID instead of a generated name.
    func loweredSuspendFunction(
        originalNamed name: String,
        in module: KIRModule,
        interner: StringInterner
    ) throws -> KIRFunction {
        let wrapper = try findKIRFunction(named: name, in: module, interner: interner)
        return try loweredSuspendFunction(for: wrapper, in: module, interner: interner)
    }

    func loweredSuspendFunction(
        for wrapper: KIRFunction,
        in module: KIRModule,
        interner: StringInterner
    ) throws -> KIRFunction {
        let functionID = try #require(wrapper.body.compactMap { instruction -> Int64? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  callee == interner.intern(RuntimeCall.coroutineContinuationNew.name),
                  let argument = arguments.first,
                  case let .intLiteral(rawValue) = module.arena.expr(argument)
            else { return nil }
            return rawValue
        }.first, "Expected a continuation factory carrying the lowered function ID")
        return try #require(findAllKIRFunctions(in: module).first {
            Int64($0.symbol.rawValue) == functionID
        }, "Expected the continuation factory to reference a declared function")
    }

    /// A closure wrapper forwards to the original lambda's symbol.
    func closureWrapper(for lambda: SymbolID, in module: KIRModule) throws -> KIRFunction {
        let wrappers = findAllKIRFunctions(in: module).filter { function in
            function.symbol != lambda && function.body.contains { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == lambda
            }
        }
        #expect(wrappers.count == 1, "Expected exactly one forwarding closure wrapper")
        return try #require(wrappers.first)
    }

    func launcherThunks(in module: KIRModule, interner: StringInterner) -> [KIRFunction] {
        let argumentGetter = interner.intern(RuntimeCall.coroutineLauncherArgGet.name)
        // Receiver-only builder adapters share the getter but are not launcher values.
        return functionValueTargets(in: module).filter { function in
            function.body.contains { instruction in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return false }
                return callee == argumentGetter
            }
        }
    }

    /// Select function values from expressions and loaded symbol constants.
    func functionValueTargets(in module: KIRModule) -> [KIRFunction] {
        let functions = findAllKIRFunctions(in: module)
        let symbols = Set(module.arena.expressions.compactMap { expression -> SymbolID? in
            guard case let .symbolRef(symbol) = expression else { return nil }
            return symbol
        }).union(functions.flatMap { function in
            function.body.compactMap { instruction -> SymbolID? in
                guard case let .constValue(_, .symbolRef(symbol)) = instruction else { return nil }
                return symbol
            }
        })
        return functions.filter { symbols.contains($0.symbol) }
    }

    // MARK: - Shared lowering fixture

    struct LoweringRewriteFixture {
        let interner: StringInterner
        let module: KIRModule
        let mainID: KIRDeclID
        let emptyID: KIRDeclID
    }

    func makeLoweringRewriteFixture() throws -> LoweringRewriteFixture {
        let interner = StringInterner()
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 10)
        let inlineSym = SymbolID(rawValue: 11)
        let suspendSym = SymbolID(rawValue: 12)
        let emptySym = SymbolID(rawValue: 13)

        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))
        let v2 = arena.appendExpr(.temporary(2))
        let v3 = arena.appendExpr(.temporary(3))
        let vFalse = arena.appendExpr(.boolLiteral(false))

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: nil, callee: interner.intern(RuntimeCall.rangeIterator.name), arguments: [v0], result: v3, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern(CompilerCall.forLowered.name), arguments: [v3], result: v1, canThrow: false, thrownResult: nil),
                .constValue(result: vFalse, value: .boolLiteral(false)),
                .jumpIfEqual(lhs: v0, rhs: vFalse, target: 800),
                .jump(801),
                .label(800),
                .copy(from: v2, to: v1),
                .label(801),
                .call(symbol: nil, callee: interner.intern("get"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("set"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("<lambda>"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("inlineTarget"), arguments: [], result: v1, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("suspendTarget"), arguments: [v0], result: v1, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("inlineTarget"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: true
        )
        let suspendFn = KIRFunction(
            symbol: suspendSym,
            name: interner.intern("suspendTarget"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [
                .call(symbol: suspendSym, callee: interner.intern("suspendTarget"), arguments: [], result: v2, canThrow: false, thrownResult: nil),
                .returnValue(v2),
            ],
            isSuspend: true,
            isInline: false
        )
        let emptyFn = KIRFunction(
            symbol: emptySym,
            name: interner.intern("empty"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(inlineFn))
        _ = arena.appendDecl(.function(suspendFn))
        let emptyID = arena.appendDecl(.function(emptyFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID, emptyID])], arena: arena)

        try runLowering(module: module, interner: interner, moduleName: "Lowering")

        return LoweringRewriteFixture(interner: interner, module: module, mainID: mainID, emptyID: emptyID)
    }

    @Test
    func testLoweringRewritesMainCallSites() throws {
        let fixture = try makeLoweringRewriteFixture()

        let loweredMain = try requireTestValue(fixture.module.arena.decl(fixture.mainID)?.function, "expected lowered main function")

        let callees = extractCallees(from: loweredMain.body, interner: fixture.interner)
        #expect(callees.contains(RuntimeCall.uintRangeIterator.name), "Callees: \(callees)")
        #expect(!callees.contains(RuntimeCall.rangeIterator.name), "Callees: \(callees)")
        #expect(callees.contains(RuntimeCall.rangeHasNext.name), "Callees: \(callees)")
        #expect(callees.contains(RuntimeCall.rangeNext.name), "Callees: \(callees)")
        #expect(!callees.contains(CompilerCall.forLowered.name), "Callees: \(callees)")
        // The test fixture uses symbol-less get/set calls, so they remain unchanged.
        #expect(callees.contains("get"), "Callees: \(callees)")
        #expect(callees.contains("set"), "Callees: \(callees)")
        #expect(loweredMain.body.contains { if case .jumpIfEqual = $0 { return true }; return false })
        #expect(loweredMain.body.contains { if case .copy = $0 { return true }; return false })
        #expect(callees.contains(CompilerCall.lambdaInvoke.name), "Callees: \(callees)")
        #expect(!callees.contains("inlineTarget"), "Callees: \(callees)")
        #expect(callees.contains(RuntimeCall.coroutineContinuationNew.name), "Callees: \(callees)")
        let loweredSuspend = try loweredSuspendFunction(originalNamed: "suspendTarget", in: fixture.module, interner: fixture.interner)
        let loweredSuspendName = fixture.interner.resolve(loweredSuspend.name)
        #expect(callees.contains(loweredSuspendName), "Callees: \(callees)")
        let declaredCallees = Set(RuntimeABIExterns.allExterns.map(\.name))
            .union(RuntimeABISpec.compilerInternalNonThrowingCalleeNames)
            .union(RuntimeABISpec.compilerInternalBuiltinCalleeNames)
            .union(findAllKIRFunctions(in: fixture.module).map { fixture.interner.resolve($0.name) })
            .union(["get", "set"])
        #expect(Set(callees).subtracting(declaredCallees).isEmpty, "Callees: \(callees)")

        let throwFlags = extractThrowFlags(from: loweredMain.body, interner: fixture.interner)
        #expect(throwFlags[RuntimeCall.coroutineContinuationNew.name]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags[loweredSuspendName]?.allSatisfy { $0 == true } == true)
    }

    @Test
    func testLoweringBuildsSuspendStateMachineAndThrowFlags() throws {
        let fixture = try makeLoweringRewriteFixture()
        let loweredSuspend = try loweredSuspendFunction(originalNamed: "suspendTarget", in: fixture.module, interner: fixture.interner)

        #expect(loweredSuspend.params.count == 1)
        #expect(loweredSuspend.isSuspend == false)

        let loweredSuspendCallees = extractCallees(from: loweredSuspend.body, interner: fixture.interner)
        #expect(loweredSuspendCallees.contains(RuntimeCall.coroutineStateEnter.name))
        #expect(loweredSuspendCallees.contains(RuntimeCall.coroutineStateSetLabel.name))
        #expect(loweredSuspendCallees.contains(RuntimeCall.coroutineStateSetCompletion.name))
        #expect(loweredSuspendCallees.contains(RuntimeCall.coroutineStateGetCompletion.name))
        #expect(loweredSuspendCallees.contains(RuntimeCall.coroutineStateExit.name))

        let dispatchJumpCount = loweredSuspend.body.filter { instruction in
            if case .jumpIfEqual = instruction {
                return true
            }
            return false
        }.count
        // A suspend function with one suspension point needs at least 2 dispatch jumps:
        // one for label 1000 (entry) and one for label 1001 (resume point)
        #expect(dispatchJumpCount >= 2)

        let dispatchLabels = loweredSuspend.body.compactMap { instruction -> Int32? in
            if case let .label(id) = instruction {
                return id
            }
            return nil
        }
        // Coroutine state machine dispatch labels start at coroutineDispatchLabelBase
        #expect(dispatchLabels.contains(coroutineDispatchLabelBase))
        #expect(dispatchLabels.contains(coroutineDispatchLabelBase + 1))

        let hasSuspendGuard = loweredSuspend.body.contains { instruction in
            if case .returnIfEqual = instruction {
                return true
            }
            return false
        }
        #expect(hasSuspendGuard)

        let throwFlags = extractThrowFlags(from: loweredSuspend.body, interner: fixture.interner)
        #expect(loweredSuspendCallees.contains(RuntimeCall.coroutineCallDirectSuspend.name))
        #expect(throwFlags[RuntimeCall.coroutineCallDirectSuspend.name]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags[RuntimeCall.coroutineSuspended.name]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags[RuntimeCall.coroutineStateSetLabel.name]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags[RuntimeCall.coroutineStateSetCompletion.name]?.allSatisfy { $0 == false } == true)
        #expect(throwFlags[RuntimeCall.coroutineStateGetCompletion.name]?.allSatisfy { $0 == false } == true)
    }

    @Test
    func testSuspendWrapperUsesCompletionRelayInsteadOfRunBlocking() throws {
        let fixture = try makeLoweringRewriteFixture()
        let wrapper = try findKIRFunction(named: "suspendTarget", in: fixture.module, interner: fixture.interner)
        let callees = extractCallees(from: wrapper.body, interner: fixture.interner)
        #expect(callees.contains(RuntimeCall.coroutineCallSuspendWrapper.name))
        #expect(!callees.contains(RuntimeCall.kxminiRunBlockingWithCont.name))
    }

    @Test
    func testImportedSuspendCallHasSuspendGuardAndResumeLabel() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()
        let diagnostics = DiagnosticEngine()
        let importedName = interner.intern("importedSuspend")
        let imported = symbols.define(
            kind: .function, name: importedName, fqName: [importedName],
            declSite: makeRange(), visibility: .public, flags: [.importedLibrary, .suspendFunction]
        )
        symbols.setFunctionSignature(FunctionSignature(parameterTypes: [], returnType: types.unitType, isSuspend: true), for: imported)
        let importedLinkName = "kk_fn_importedSuspend"
        symbols.setExternalLinkName(importedLinkName, for: imported)
        let result = arena.appendTemporary(type: types.unitType)
        let caller = KIRFunction(
            symbol: SymbolID(rawValue: 950), name: interner.intern("caller"), params: [], returnType: types.unitType,
            body: [
                .call(symbol: imported, callee: interner.intern(importedLinkName), arguments: [], result: result, canThrow: true, thrownResult: nil),
                .returnValue(result),
            ], isSuspend: true, isInline: false
        )
        let callerID = arena.appendDecl(.function(caller))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)
        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: diagnostics)
        try runLowering(module: module, interner: interner, moduleName: "ImportedSuspend", sema: sema.ctx, diagnostics: diagnostics)
        let lowered = try loweredSuspendFunction(originalNamed: "caller", in: module, interner: interner)
        #expect(lowered.body.contains { if case .returnIfEqual = $0 { return true }; return false })
        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains(RuntimeCall.coroutineStateGetThrownException.name))
        #expect(callees.contains(importedLinkName))
    }

    @Test
    func testLoweringNormalizesEmptyFunctionBody() throws {
        let fixture = try makeLoweringRewriteFixture()

        let loweredEmpty = try requireTestValue(fixture.module.arena.decl(fixture.emptyID)?.function, "expected lowered empty function")
        #expect(loweredEmpty.body.last == .returnUnit)
        #expect(!loweredEmpty.body.isEmpty)
    }

    @Test
    func testCoroutineLoweringRewritesOverloadedSuspendCallsByNameAndArity() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSymbol = SymbolID(rawValue: 950)
        let suspendNoArgSymbol = SymbolID(rawValue: 951)
        let suspendOneArgSymbol = SymbolID(rawValue: 952)
        let suspendOneArgParam = SymbolID(rawValue: 953)

        let argValue = arena.appendExpr(.temporary(0))
        let noArgResult = arena.appendExpr(.temporary(1))
        let oneArgResult = arena.appendExpr(.temporary(2))

        let caller = KIRFunction(
            symbol: callerSymbol,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: argValue, value: .intLiteral(42)),
                .call(symbol: nil, callee: interner.intern("susp"), arguments: [], result: noArgResult, canThrow: false, thrownResult: nil),
                .call(symbol: nil, callee: interner.intern("susp"), arguments: [argValue], result: oneArgResult, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let suspendNoArg = KIRFunction(
            symbol: suspendNoArgSymbol,
            name: interner.intern("susp"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )
        let suspendOneArg = KIRFunction(
            symbol: suspendOneArgSymbol,
            name: interner.intern("susp"),
            params: [KIRParameter(symbol: suspendOneArgParam, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: true,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(caller))
        _ = arena.appendDecl(.function(suspendNoArg))
        _ = arena.appendDecl(.function(suspendOneArg))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        try runLowering(module: module, interner: interner, moduleName: "CoroutineOverloadRewrite")

        let loweredCaller = try requireTestValue(module.arena.decl(callerID)?.function, "expected lowered caller function")

        let rawSuspendCalls = loweredCaller.body.contains { instruction in
            guard case let .call(_, callee, _, _, _, _, _, _) = instruction else {
                return false
            }
            return callee == interner.intern("susp")
        }
        #expect(!rawSuspendCalls)

        let loweredTargets = try [suspendNoArg, suspendOneArg].map { original in
            // Each original wrapper retains its symbol across coroutine lowering.
            let wrapper = try #require(findAllKIRFunctions(in: module).first { $0.symbol == original.symbol })
            return try loweredSuspendFunction(for: wrapper, in: module, interner: interner)
        }
        let rewrittenSuspendCalls = loweredCaller.body.compactMap { instruction -> (symbol: SymbolID, arity: Int, canThrow: Bool)? in
            guard case let .call(symbol, callee, arguments, _, canThrow, _, _, _) = instruction,
                  let symbol,
                  loweredTargets.contains(where: { $0.symbol == symbol && $0.name == callee })
            else {
                return nil
            }
            return (symbol: symbol, arity: arguments.count, canThrow: canThrow)
        }
        #expect(rewrittenSuspendCalls.count == 2)
        #expect(Set(rewrittenSuspendCalls.map(\.symbol)) == Set(loweredTargets.map(\.symbol)))
        #expect(Set(rewrittenSuspendCalls.map(\.arity)) == Set([1, 2]))
        let allCanThrow = rewrittenSuspendCalls.allSatisfy(\.canThrow)
        #expect(allCanThrow)
    }

    @Test
    func testCoroutineLoweringPreservesControlFlowAroundSuspendCalls() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let suspendSym = SymbolID(rawValue: 900)
        let lhs = arena.appendExpr(.temporary(0))
        let rhs = arena.appendExpr(.temporary(1))
        let callResult = arena.appendExpr(.temporary(2))

        let suspendFn = KIRFunction(
            symbol: suspendSym,
            name: interner.intern("suspendTarget"),
            params: [],
            returnType: types.unitType,
            body: [
                .label(10),
                .call(symbol: suspendSym, callee: interner.intern("suspendTarget"), arguments: [], result: callResult, canThrow: false, thrownResult: nil),
                .jumpIfEqual(lhs: lhs, rhs: rhs, target: 20),
                .returnValue(lhs),
                .label(20),
                .returnValue(rhs),
            ],
            isSuspend: true,
            isInline: false
        )

        let suspendID = arena.appendDecl(.function(suspendFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [suspendID])], arena: arena)
        try runLowering(module: module, interner: interner, moduleName: "CoroutineCFG")

        let loweredSuspend = try loweredSuspendFunction(originalNamed: "suspendTarget", in: module, interner: interner)

        let labels = loweredSuspend.body.compactMap { instruction -> Int32? in
            if case let .label(id) = instruction {
                return id
            }
            return nil
        }
        // Coroutine dispatch labels + original user label 20
        #expect(labels.contains(coroutineDispatchLabelBase))
        #expect(labels.contains(coroutineDispatchLabelBase + 1))
        #expect(labels.contains(20))

        let hasOriginalBranch = loweredSuspend.body.contains { instruction in
            if case let .jumpIfEqual(_, _, target) = instruction {
                return target == 20
            }
            return false
        }
        #expect(hasOriginalBranch)
    }

    @Test
    func testConsolidatedLoweringSourceScenarios() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.random.Random

            fun main_sample0() {
                val random = Random(7)
                val charValue = ('a'..'z').random(random)
                val intValue = (10..20).random(random)
                val longValue = (100L..110L).random(random)
                val uintValue = (10u..20u).random(random)
                val ulongValue = (100uL..110uL).random(random)
                println(charValue)
                println(intValue)
                println(longValue)
                println(uintValue)
                println(ulongValue)
            }
            """,
            """
            package sample1
            suspend fun delayedValue_1(): Int {
                delay(1)
                return 42
            }
            fun main_sample1(): Any? = runBlocking(delayedValue_1)
            """,
            """
            package sample2
            import kotlinx.coroutines.*

            suspend fun awaitAndJoin(d: Deferred<Int>, j: Job): Int {
                val value = d.await()
                j.join()
                return value
            }
            """,
            """
            package sample3
            suspend fun delayedValue_3(): Int {
                delay(1)
                return 42
            }
            fun main_sample3(): Any? = runBlocking { coroutineScope { delayedValue_3() } }
            """,
            """
            package sample4
            import kotlinx.coroutines.*
            import kotlinx.coroutines.sync.*

            fun main_sample4() = runBlocking {
                val mutex = Mutex()
                println(mutex.withLock { 1 })
            }
            """,
            """
            package sample5
            suspend fun delayedValue_5(v: Int): Int = v

            suspend fun outerSuspendHost(value: Int): Int {
                suspend fun localSuspendBridge(value: Int): Int = delayedValue_5(value)
                return localSuspendBridge(value)
            }

            fun main_sample5(): Any? = runBlocking(outerSuspendHost)
            """,
            """
            package sample6
            import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn

            suspend fun probe(): Any? {
                return suspendCoroutineUninterceptedOrReturn { cont ->
                    cont
                }
            }
            fun main_sample6(): Any? = runBlocking(probe)
            """,
            """
            package sample7
            fun myCompare(a: Int, b: Int): Int = a - b

            fun interface Stringify {
                fun render(value: Int): String
            }

            fun label(value: Int): String = "v=" + value

            fun main_sample7() {
                val comparator = Comparator<Int>(::myCompare)
                println(comparator.compare(3, 5))
                println(Stringify(::label).render(42))
            }
            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            // Scanned once and shared below: no scenario mutates `module`.
            let allFunctions = findAllKIRFunctions(in: module)
            let allCallees = allFunctions.flatMap { function in
                extractCallees(from: function.body, interner: ctx.interner)
            }

            // testRangeRandomCallsKeepRandomArgument
            do {
                let body = try findKIRFunctionBody(named: "main_sample0", in: module, interner: ctx.interner)
                let allCallees = extractCallees(from: body, interner: ctx.interner)

                let randomCalls = body.compactMap { instruction -> (String, Int, Bool)? in
                    guard case let .call(_, callee, arguments, _, canThrow, _, _, _) = instruction else {
                        return nil
                    }
                    let name = ctx.interner.resolve(callee)
                    guard name == "random"
                    else {
                        return nil
                    }
                    return (name, arguments.count, canThrow)
                }

                #expect(randomCalls.count == 5, "Expected five source-backed range.random calls, got: \(randomCalls); all callees: \(allCallees)")
                #expect(randomCalls.allSatisfy { _, argumentCount, canThrow in
                    argumentCount == 2 && canThrow
                }, "Expected source wrapper receiver + Random argument and canThrow=true, got: \(randomCalls); all callees: \(allCallees)")
                #expect(
                    allCallees.allSatisfy { name in
                        !name.contains("range_random") && !name.contains("randomOrNull")
                    },
                    "Legacy range random runtime links must not remain in user call lowering: \(allCallees)"
                )
            }
            // testCoroutineLoweringRewritesKxMiniLauncherAndDelayBuiltins
            do {
                let mainBody = try findKIRFunctionBody(named: "main_sample1", in: module, interner: ctx.interner)
                let suspendBody = try loweredSuspendFunction(originalNamed: "delayedValue_1", in: module, interner: ctx.interner).body

                let mainCalls = extractCallees(from: mainBody, interner: ctx.interner)
                #expect(mainCalls.contains(RuntimeCall.kxminiRunBlocking.name))
                #expect(!mainCalls.contains("runBlocking"))

                let delayCalls = extractCallees(from: suspendBody, interner: ctx.interner)
                #expect(delayCalls.contains(RuntimeCall.kxminiDelay.name))

                let throwFlags = extractThrowFlags(from: suspendBody, interner: ctx.interner)
                #expect(throwFlags[RuntimeCall.kxminiDelay.name]?.allSatisfy { $0 == false } == true)
            }
            // testCoroutineLoweringTreatsAwaitAndJoinAsSuspendPoints
            do {
                let suspendBody = try loweredSuspendFunction(originalNamed: "awaitAndJoin", in: module, interner: ctx.interner).body

                let callees = extractCallees(from: suspendBody, interner: ctx.interner)
                #expect(callees.contains(RuntimeCall.kxminiAsyncAwait.name), "await should lower to kk_kxmini_async_await")
                #expect(callees.contains(RuntimeCall.jobJoin.name), "join should lower to kk_job_join")
                #expect(
                    callees.contains(RuntimeCall.coroutineStateSetLabel.name),
                    "await/join must be treated as suspend points (resume label install)"
                )

                let throwFlags = extractThrowFlags(from: suspendBody, interner: ctx.interner)
                #expect(throwFlags[RuntimeCall.kxminiAsyncAwait.name]?.allSatisfy { $0 == false } == true)
                let joinABI = try #require(RuntimeABISpec.byName[RuntimeCall.jobJoin.name])
                #expect(throwFlags[RuntimeCall.jobJoin.name]?.allSatisfy { $0 == joinABI.isThrowing } == true)
            }
            // Source scopes and generated bodies must call declared targets.
            do {
                let sema = try #require(ctx.sema)
                let unresolvedCalls = KIRVerifier.verify(module: module, symbols: sema.symbols, interner: ctx.interner)
                    .filter { $0.kind == .unresolvableCallee }
                #expect(unresolvedCalls.isEmpty, "Unresolved lowering targets: \(unresolvedCalls)")
                // A valid bound symbol must not hide an obsolete runtime shim name.
                let symbols = sema.symbols.allSymbols()
                let declaredCallees = Set(RuntimeABIExterns.allExterns.map(\.name))
                    .union(RuntimeABISpec.compilerInternalNonThrowingCalleeNames)
                    .union(RuntimeABISpec.compilerInternalBuiltinCalleeNames)
                    .union(allFunctions.map { ctx.interner.resolve($0.name) })
                    .union(symbols.map { ctx.interner.resolve($0.name) })
                    .union(symbols.compactMap { sema.symbols.externalLinkName(for: $0.id) })
                let undeclaredRuntimeCallees = Set(allCallees.filter { name in
                    (name.hasPrefix("kk_") || name.hasPrefix("__kk_"))
                        && !name.hasPrefix(RuntimeABISpec.compilerGeneratedLinkNamePrefix)
                }).subtracting(declaredCallees)
                #expect(undeclaredRuntimeCallees.isEmpty, "Undeclared runtime lowering targets: \(undeclaredRuntimeCallees.sorted())")
            }
            // testNonInlineCallIsNotRedirectedToSameNamedInlineOverload
            do {
                #expect(
                    !allCallees.contains(RuntimeCall.lockWithLock.name),
                    "Mutex.withLock must not be inlined into the Lock.withLock bridge"
                )
            }
            // testCoroutineLoweringRewritesSuspendLocalFunctionCalls
            do {
                let loweredOuter = try loweredSuspendFunction(originalNamed: "outerSuspendHost", in: module, interner: ctx.interner)
                let loweredLocal = try loweredSuspendFunction(originalNamed: "localSuspendBridge", in: module, interner: ctx.interner)

                let outerCallees = extractCallees(from: loweredOuter.body, interner: ctx.interner)
                #expect(outerCallees.contains(RuntimeCall.coroutineCallDirectSuspend.name))
                #expect(!outerCallees.contains("localSuspendBridge"))

                let localCallees = extractCallees(from: loweredLocal.body, interner: ctx.interner)
                #expect(localCallees.contains(RuntimeCall.coroutineCallDirectSuspend.name))
                #expect(localCallees.contains(RuntimeCall.coroutineStateEnter.name))
                #expect(localCallees.contains(RuntimeCall.coroutineStateExit.name))
            }
            // testCoroutineLoweringRewritesSuspendCoroutineUninterceptedOrReturnFromImport
            do {
                let probeBody = try loweredSuspendFunction(originalNamed: "probe", in: module, interner: ctx.interner).body

                let callees = extractCallees(from: probeBody, interner: ctx.interner)
                #expect(callees.contains(RuntimeCall.coroutineSuspended.name), "callees: \(callees)")
                #expect(!callees.contains("suspendCoroutineUninterceptedOrReturn"), "callees: \(callees)")
            }
            // testSamConvertedCallableRefLowersToInterfaceWrapper
            do {
                let mainBody = try findKIRFunctionBody(named: "main_sample7", in: module, interner: ctx.interner)
                let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
                #expect(
                    mainCallees.filter { $0 == RuntimeCall.objectRegisterItableMethod.name }.count == 2,
                    "Callees: \(mainCallees)"
                )
                #expect(mainCallees.contains(RuntimeCall.typeRegisterIface.name), "Callees: \(mainCallees)")

                let targets = try ["myCompare", "label"].map {
                    try findKIRFunction(named: $0, in: module, interner: ctx.interner).symbol
                }
                let thunks = allFunctions.filter { function in
                    function.body.contains { instruction in
                        guard case let .call(symbol?, _, _, _, _, _, _, _) = instruction else { return false }
                        return targets.contains(symbol)
                    }
                }
                #expect(thunks.count == 2, "Expected a forwarding thunk for each callable reference")
                #expect(Set(thunks.map(\.params.count)) == [1, 2])
            }
        }
    }

    @Test
    func testConsolidatedKIRSourceScenarios() throws {
        let sources: [String] = [
            """
            package sample8
            import kotlinx.coroutines.*

            suspend fun invokeZero(block: suspend () -> Int): Int = block()

            suspend fun invokeOne(block: suspend (Int) -> Int): Int = block(41)

            fun main_sample8() = runBlocking {
                val zero = invokeZero { 7 }
                val one = invokeOne { value -> value + 1 }
                println(zero)
                println(one)
            }
            """
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)
            let module = try #require(ctx.kir)

            // testCoroutineLoweringRewritesSuspendFunctionTypeInvokeCalls
            do {
                let allCallees = findAllKIRFunctions(in: module).flatMap { function in
                    extractCallees(from: function.body, interner: ctx.interner)
                }
                let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.severity): \($0.message)" }

                #expect(allCallees.contains(RuntimeCall.suspendFunctionInvoke0.name), "Callees: \(allCallees)")
                #expect(allCallees.contains(RuntimeCall.suspendFunctionInvoke.name), "Callees: \(allCallees)")
                #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error }, "Diagnostics: \(diagnostics)")
            }
        }
    }

    @Test
    func testSafeCallInlineResultIsMaterializedBeforeMerge() throws {
        let source = """
        fun main() {
            val nullableInput: String? = null
            println(nullableInput?.let { it.uppercase() })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .object)
            try runToLowering(ctx)
            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)

            let printlnCallIndex = mainBody.firstIndex { instruction in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else {
                    return false
                }
                let calleeName = ctx.interner.resolve(callee)
                return calleeName == "println" && !arguments.isEmpty
            }
            let printlnCallInstruction = try #require(printlnCallIndex.map { mainBody[$0] }, "expected println call in main")
            guard case let .call(_, _, printlnArgs, _, _, _, _, _) = printlnCallInstruction else {
                return
            }
            let printlnArg = printlnArgs[0]

            // `String.uppercase()` is now bundled Kotlin source, so its body
            // no longer has to expose the old `kk_string_uppercase_flat`
            // runtime call here. The invariant under test is the safe-call
            // merge itself: the inline result must be copied into the value
            // consumed by `println` before the call is emitted.
            let hasMaterializedSafeCallResult = mainBody[..<printlnCallIndex!].contains { instruction in
                if case let .copy(_, to) = instruction {
                    return to == printlnArg
                }
                if case let .call(_, _, args, result, _, _, _, _) = instruction,
                   let result,
                   result == printlnArg
                {
                    return !args.isEmpty
                }
                return false
            }
            #expect(hasMaterializedSafeCallResult, "safe-call inline result must be materialized before println")
        }
    }
}


#endif
